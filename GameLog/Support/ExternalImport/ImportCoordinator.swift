import Foundation
import SwiftData

/// 一次导入的落库结果摘要（**只给 UI 看，不落库**）。
///
/// 为什么不落库：库里要保留的是「上次同步的结果」（`LinkedAccount.lastSyncAt` /
/// `lastSyncRecordCount` / `lastSyncError`），那是**状态**；而本类型描述的是「这一轮
/// 具体干了什么」（新建了几条、自动建了几个库、有几条进了墓碑）。两者口径不同 ——
/// 把「这一轮的增量」写进库里，下次读出来就必然是错的。
struct ImportSummary: Equatable {
    /// 新建的外部记录数。
    var createdRecords = 0
    /// 已存在、字段被刷新的记录数。
    var updatedRecords = 0
    /// 自动匹配到现有 Game 的记录数。
    var autoLinked = 0
    /// 自动建库数。
    var createdGames = 0
    /// 已经绑着 Game、这次原样保留的记录数（含用户手动绑定的）。
    var alreadyLinked = 0
    /// 被用户标了「已忽略」而跳过自动处理的记录数。
    var ignored = 0
    /// 库里存在**同一 (provider, account, titleId) 的重复记录**的条数。
    ///
    /// 只统计、不清理：beta 3.1 的幂等 bug 在库里留下的重复记录，用户已经决定走
    /// 「清空该账号导入数据再重新同步」这条路（见 `ExternalAccountBinder.purgeImportedData`）。
    /// 自动删数据太危险，但**必须让它可见** —— 否则用户只会觉得「怎么又多了几十个游戏」。
    var duplicateRecords = 0
    /// 体验版/试玩版：照常入库但不进游戏库的记录数。
    var excludedByVersion = 0
    /// 来源侧这次没再返回、被标成 `presentInLastSync = false` 的记录数（**不删**）。
    var absent = 0
    /// 单条处理失败而被跳过的记录数 —— **不影响其余记录**。
    var failed = 0
    /// 成功落到 Game 封面槽的图片数 / 尝试了但没拿到的次数 / 强制刷新覆盖掉的张数。
    var artworkFetched = 0
    var artworkFailed = 0
    var artworkRefreshed = 0

    /// 这一轮真正读到的记录条数（新建 + 刷新）。
    var processed: Int { createdRecords + updatedRecords }
    var isEmpty: Bool { processed == 0 }
}

/// 把一批来源记录落进库里：**幂等 upsert → 自动匹配/建库 → 忽略 → 封面**。
///
/// 职责边界：本层只认 `ExternalGameRecordDTO`，**不认识 Nintendo / PSN 的任何协议细节**
/// （取数据、换 token 在各自的 Service 里）。反过来 Service 层也不碰 SwiftData。
/// 中间这条缝就是 `ExternalGameRecordDTO`。
///
/// 跑在独立 actor 上，理由与 `BackupImporter` 相同：一次导入可能是几百条记录 + 几百次
/// 封面下载，绝不能占着主线程。线程红线也一样 —— 用宏生成的 `modelContext`，
/// **绝不**把主线程的 context 传进来，也绝不在后台碰 `container.mainContext`。
///
/// ⚠️ 三条纪律：
/// 1. **单条记录出错不拖垮整批**（见 `failed`）。
/// 2. **没有来源依据的字段绝不写**：不编评分、不编通关记录、不编时长。
/// 3. **去重键必须先于封面下载落盘** —— 见 `importRecords` 里那次提前的 `save()`。
///    这条是 beta 3.1「每个游戏被加进库两次」的根因修复，别再把它挪回函数末尾。
@ModelActor
actor ImportCoordinator {

    /// 把一批来源记录落库。
    ///
    /// - Parameters:
    ///   - dtos: 来源侧解析出来的记录（各 Service 的 `records(from:)` 产物）。
    ///   - localId: 目标账号的 `LinkedAccount.localId`。
    ///   - sourceLocale: 来源标题的语言标签（Nintendo 用账号的 `sourceLocale`，
    ///     PSN 用请求时带 `Accept-Language` 的那个值）。只影响自动建库时标题落在哪个语言槽。
    ///   - autoCreateGames: 匹配不上时是否自动建库。false 时记录照常入库，只是留在「待关联」。
    ///   - artworkFetcher: 传 nil = **不抓封面**。刻意让「抓图」是显式选择而不是默认行为 ——
    ///     它会打网络（可能几百次），不该因为调用方忘了传参数就悄悄发生。
    ///   - forceArtworkRefresh: 覆盖**已有**封面（默认 false = 只填空白）。
    ///     用户改了标题语言后要「重新同步并刷新标题与封面」时才传 true —— 那一次的目的
    ///     就是换图；平时绝不能开，否则每次同步都会把用户自己挑的封面冲掉。
    ///     即便如此也只覆盖**没被用户经手过**的（见 `fetchArtwork`）。
    ///   - now: 注入时间，便于测试断言 `lastSeenAt`。
    /// - Returns: 本轮摘要。
    /// - Throws: 只在「账号找不到」或「最终落盘失败」时抛 —— 单条记录的问题不抛。
    @discardableResult
    func importRecords(_ dtos: [ExternalGameRecordDTO],
                       intoAccount localId: UUID,
                       sourceLocale: String = "",
                       autoCreateGames: Bool = true,
                       artworkFetcher: ArtworkFetcher? = nil,
                       forceArtworkRefresh: Bool = false,
                       now: Date = .now) async throws -> ImportSummary {
        let account = try linkedAccount(localId: localId)
        var summary = ImportSummary()

        let provider = account.provider
        let externalAccountId = account.externalAccountId

        // ⚠️ 记录与线索都走 `FetchDescriptor` + 内存过滤，**不读 `account.records` /
        // `game.externalRecords` 这两个反向数组**：SwiftData 的 inverse 在某些写入路径上
        // 要等到 save 之后才一致，而协调器必须在「刚插入、还没 save」的同一次调用里也能正确
        // 去重与匹配（同一次导入里的第二条记录就得看到第一条刚建好的 Game）。
        // 全量取回是廉价的：图片是 `.externalStorage` 懒加载，记录本身只有几十字节。
        let allRecords = try modelContext.fetch(FetchDescriptor<ExternalGameRecord>())

        // 本账号现有的记录，按 titleId 索引 —— 幂等就靠它。
        //
        // ⚠️ **同一个 titleId 出现多条 = 库里已经有脏数据**（beta 3.1 的双重导入留下的，
        // 那次的写入在整个导入期间不落盘，第二次同步看不见第一次的成果）。这里不静默取
        // 「最后一条」：优先保留**有账号归属**的那条（孤儿记录在界面上完全不可见，
        // 用它当幂等基准等于把新数据也拖进不可见状态），并把冲突数记进摘要让用户看得见。
        var existing: [String: ExternalGameRecord] = [:]
        for record in allRecords
        where record.providerRaw == provider.rawValue
            && record.externalAccountId == externalAccountId {
            guard let kept = existing[record.titleId] else {
                existing[record.titleId] = record
                continue
            }
            summary.duplicateRecords += 1
            if kept.account == nil && record.account != nil {
                existing[record.titleId] = record
            }
        }

        // 线索 = 「已经绑到某个 Game」的记录给出的键。正向读 `record.game`（to-one，写入即生效）。
        var cluesByGame: [PersistentIdentifier: [GameLinker.Clue]] = [:]
        for record in allRecords {
            guard let game = record.game else { continue }
            cluesByGame[game.persistentModelID, default: []].append(
                GameLinker.Clue(titleId: record.titleId, conceptId: record.conceptId))
        }

        // 匹配候选 = 库里**全部** Game 的快照（不止本账号关联的那些：同一个游戏可能先由
        // 另一个 Nintendo 账号建了库，这次要并过去）。候选数组与 `candidateGames` 同序，
        // 引擎返回的下标直接用来取对象。
        var candidateGames = try modelContext.fetch(FetchDescriptor<Game>())
        var candidates = candidateGames.map { game in
            GameLinker.LinkCandidate(names: Self.matchNames(of: game),
                                     clues: cluesByGame[game.persistentModelID] ?? [])
        }

        // 本轮的封面目标（(Game, 图片 URL)），顺序即记录顺序。
        // 第 3 段 = 「来源侧这一轮改了名字」，见 `fetchArtwork` 的 `sourceChanged`。
        var artworkTargets: [(game: Game, urlString: String?, sourceChanged: Bool)] = []

        for dto in dtos {
            // 唯一的「单条失败」：来源侧给了一条连 titleId 都空掉的记录。
            // 服务层的 `usableTitleId` 已经滤过一道，这里是本层不信任调用方的兜底 ——
            // titleId 是唯一键的第 3 段，空值会让所有这类记录在库里互相覆盖。
            let titleId = dto.titleId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !titleId.isEmpty else {
                summary.failed += 1
                continue
            }

            let record: ExternalGameRecord
            // 来源侧这一轮的名字变了没有 —— 换语言（`Gentry-Locale`）之后必然如此。
            // 为什么要关心：**任天堂的图标是按语言发的**（实测：日文名的游戏拿回的就是日文版
            // 商品图，简体中文名的拿回简体中文图）。所以名字变了就等于图也换了，那些「同步替我
            // 建的、用户没碰过」的条目该重抓一次（见 `fetchArtwork` 的 `sourceChanged`）。
            let sourceTitleChanged: Bool
            if let found = existing[titleId] {
                sourceTitleChanged = found.titleName != dto.titleName
                Self.refresh(found, with: dto, account: account,
                             sourceLocale: sourceLocale, now: now)
                summary.updatedRecords += 1
                record = found
            } else {
                sourceTitleChanged = false
                let created = Self.makeRecord(dto, titleId: titleId,
                                              provider: provider,
                                              externalAccountId: externalAccountId,
                                              now: now)
                created.account = account
                modelContext.insert(created)
                existing[titleId] = created
                summary.createdRecords += 1
                record = created
            }

            // 关联决策。顺序即优先级，每一步都有它挡的东西：
            if let game = record.game {
                // ① 已经绑着 —— **一律不动**。用户手动绑的固然不能动，自动绑的也不该被
                //    这一轮的运气改写（比如标题名变了导致这次匹配到别的 Game）。
                summary.alreadyLinked += 1
                artworkTargets.append((game, dto.imageURLString, sourceTitleChanged))
            } else if record.isIgnored {
                // ② 用户说了「这条别再进我的库」，或者这条当时绑着的那个游戏被用户删了
                //    （删除路径会把记录标成忽略）。不重建 —— 否则用户每同步一次就得删一次。
                //
                //    ⚠️ 这一档是**可撤销**的：用户在记录面板点「恢复导入」会把标记清掉，
                //    下一轮同步它就会重新走 ④⑤⑥。以前这个状态由「曾经绑过而现在没绑」隐式
                //    推出来，于是用户点「解除关联」也会掉进这里、且永远出不来 —— 那正是
                //    「关联 / 解除关联 / 不再导入」三件事糊成一团的根源。
                summary.ignored += 1
            } else if !GameLinker.allowsAutoMatching(record.versionType) {
                // ③ 体验版/试玩版：入库留档，但不进游戏库。
                summary.excludedByVersion += 1
            } else if let (index, _) = GameLinker.match(dto, among: candidates) {
                // ④ 强键命中现有 Game。
                let game = candidateGames[index]
                Self.link(record, to: game, titleId: titleId, conceptId: dto.conceptId,
                          candidates: &candidates, index: index)
                summary.autoLinked += 1
                artworkTargets.append((game, dto.imageURLString, sourceTitleChanged))
            } else if autoCreateGames {
                // ⑤ 都不命中 → 建库。字段只填来源真的知道的那几个（见 `makeGame`）。
                let game = Self.makeGame(from: dto, sourceLocale: sourceLocale, now: now)
                modelContext.insert(game)
                candidateGames.append(game)
                candidates.append(GameLinker.LinkCandidate(names: Self.matchNames(of: game)))
                Self.link(record, to: game, titleId: titleId, conceptId: dto.conceptId,
                          candidates: &candidates, index: candidates.count - 1)
                summary.createdGames += 1
                artworkTargets.append((game, dto.imageURLString, sourceTitleChanged))
            }
            // ⑥ 都不成立且不自动建库 → 记录入库、留在「待关联」，本轮摘要也不额外计。
        }

        // 来源侧这次没再返回的记录：只标 `presentInLastSync = false`，**绝不删** ——
        // 删掉等于把「这条记录曾经存在」也抹了，而它可能正是某次手动绑定的依据。
        //
        // ⚠️ 整批为空时不动这个标记：那更可能是服务端换了响应形状返回了空列表，
        //    而不是用户一夜之间清空了账号。误标一次会让整个库都显示「来源已无此记录」，
        //    代价远大于偶尔漏标一次。
        if !dtos.isEmpty {
            var seen = Set<String>()
            for dto in dtos { seen.insert(dto.titleId.trimmingCharacters(in: .whitespacesAndNewlines)) }
            for record in existing.values where !seen.contains(record.titleId) {
                record.presentInLastSync = false
                summary.absent += 1
            }
        }

        // ⚠️⚠️ **这次 save 必须在这里，不能挪到封面下载之后** —— 这是 beta 3.1
        // 「每个游戏被同步加进库两次」的根因。那时的唯一一次 save 在函数最末尾，而前面是
        // 上百次封面下载（几十秒），于是整个导入期间 `(provider, accountId, titleId)`
        // 这个去重键都**没有落盘**：第二次同步（不管是并发触发还是紧接着点）在库里
        // 什么都查不到，187 条记录与 143 个 Game 全部重建一遍，而两个 `ImportCoordinator`
        // 各持一个 ModelContext，彼此看不见对方的未提交写入。
        //
        // 现在去重键在第一段落盘，任何后来的导入都能看见它；封面下载是纯附加的打磨，
        // 失败也不影响数据的正确性（第二次 save 只是把图写下去）。
        try modelContext.save()

        if let artworkFetcher {
            await fetchArtwork(into: artworkTargets, using: artworkFetcher,
                               forceRefresh: forceArtworkRefresh, summary: &summary)
            try modelContext.save()
        }
        return summary
    }

    // MARK: - 封面

    /// 给目标 Game 补图。规则见 `ArtworkFetcher` 头部：失败静默。
    ///
    /// ## 落哪个槽由**图片自己的宽高比**决定
    ///
    /// 方图（1:1 附近）→ `.square`；其余 → `.poster`。
    ///
    /// 为什么不能让调用方指定：两家来源给的都不是「封面」而是**图标**。任天堂的
    /// `imageUrl` 实测是 512×512 的官方图标，PSN 有时给竖图 —— 一律塞进 2:3 的竖版槽，
    /// 方图就会被左右各裁一截（用户 2026-09-16 的原始反馈），或者被当成竖版封面在
    /// 详情页/分享卡里按 0.75 的框摆。用户的要求是「抓回来的图放在方形封面这一栏」，
    /// 所以槽位判据是 `AppImage.isSquareArtwork`（**只此一处**，导入层与显示层不各写一套阈值）。
    ///
    /// ⚠️ 显示层现在**不读**这个判据了（2026-09-17 改读 `AppImage.letterboxes(inBoxAspect:)`）：
    /// 「什么算方形」回答得了"进哪个槽"，回答不了"放进这个框会不会被裁"。两者共用同一个容差
    /// （`AppImage.aspectTolerance`），所以不会出现导入说方、显示说不方。
    ///
    /// ## 只填空白，并且顺手把上一版放错槽的图搬回去
    ///
    /// **任意一个槽**有图就跳过下载（封面是装饰，重复下载纯属浪费）。**目标槽有内容时也跳过**
    /// —— 用户自己挑的图，自动流程不能覆盖。两个例外都要再满足 `isUntouchedAutoArtwork`
    /// （同步建的、用户没经手过）：`forceRefresh`（用户点了「重新同步并刷新标题与封面」），
    /// 或者**来源侧这一轮给这条记录换了名字**（换语言 → 图标也跟着换语言，见 `sourceChanged`）。
    ///
    /// 动手之前先做一次**本地校正**：竖版槽里躺着一张 1:1 图（= 上一版把官方图标塞错了槽）
    /// 且方形槽空着，就把它搬进方形槽。这一步不发请求、只在本地解码判宽高比，所以老数据
    /// 在下一轮普通同步里就归位了；用户挑过的真竖版封面也搬不动（不是 1:1）。
    ///
    /// 调用方在主线程拿到摘要后要调 `ImageDecodeCache.bump()` —— 本层在后台 actor 上，
    /// **不发通知、不碰 UI 缓存**（与 `BackupImporter` 同一条红线）。
    ///
    /// - Parameter forceRefresh: 覆盖已有图。**只对「还没被用户经手过」的游戏生效** ——
    ///   判据是 `isAutoCreated` 且**另外三类图**（横向 / 背景 / Logo）全空。用户一旦用过
    ///   SteamGridDB、自己导入过横向图 / 背景图 / Logo，这个游戏就不再是「同步替我建的」，
    ///   他的选择必须留着。宁可少换几张（用户重新同步完还能自己再换），也不能把用户挑的图冲掉。
    private func fetchArtwork(into targets: [(game: Game, urlString: String?, sourceChanged: Bool)],
                              using fetcher: ArtworkFetcher,
                              forceRefresh: Bool,
                              summary: inout ImportSummary) async {
        // 同一个 Game 可能被多条记录指向（Nintendo + PSN 是同一个游戏）：取第一条有 URL 的。
        // 记录顺序已经是「最近游玩优先」（各 Service 的 `records(from:)` 都做了这个排序），
        // 所以「第一条」= 最近在玩的那些来源里的第一条。
        // 「这一轮要不要覆盖」按同一条 Game **取或**：只要有**任意一条**记录说来源侧换了名字，
        // 这张图就旧了。
        var indexByGame: [PersistentIdentifier: Int] = [:]
        var queue: [(game: Game, urlString: String, sourceChanged: Bool)] = []
        for target in targets {
            guard let urlString = target.urlString, !urlString.isEmpty else { continue }
            let id = target.game.persistentModelID
            if let index = indexByGame[id] {
                queue[index].sourceChanged = queue[index].sourceChanged || target.sourceChanged
                continue
            }
            indexByGame[id] = queue.count
            queue.append((target.game, urlString, target.sourceChanged))
        }

        for item in queue {
            // 允许覆盖的两种情形：用户主动要求（`forceRefresh`），或者**来源侧这一轮换了名字**
            // —— 任天堂的图标跟着名字的语言走，名字变了图就旧了（用户 2026-09-16 的反馈：
            // 「标题已经是繁體中文了，封面还是英文的」）。两种都要再满足
            // `isUntouchedAutoArtwork`：用户碰过的图一律不动。
            let overwritable = (forceRefresh || item.sourceChanged)
                && Self.isUntouchedAutoArtwork(item.game)

            // ① 本地校正：旧版把官方方形图标写进了竖版槽。**不解码就认不出来**，但解码在
            //    本地、不花流量 —— 于是 127 个已导入条目原地归位，不用等用户清空重同步。
            //    判据是图自己 1:1，用户挑的真竖版封面（≥3:4）不会被搬走。
            if item.game.artwork(.square) == nil,
               let poster = item.game.artwork(.poster),
               Self.looksSquare(poster) {
                item.game.setArtwork(.square, poster)
                item.game.setArtwork(.poster, nil)
            }

            // ② 「已经有图」= **任意一个槽**非空。按①之后的状态判没问题：①只会把竖版槽清空、
            //    同时填上方形槽，所以「搬动前有图」与「搬动后有图」等价。
            let hasArtwork = item.game.artwork(.poster) != nil || item.game.artwork(.square) != nil
            // 已经有图就不下载 —— 封面是装饰，重复下载是纯浪费。唯一例外见 `overwritable`。
            if hasArtwork, !overwritable { continue }

            guard let data = await fetcher.artworkData(from: item.urlString) else {
                summary.artworkFailed += 1
                continue
            }
            let slot: ArtworkKind = Self.looksSquare(data) ? .square : .poster
            // 目标槽已经有内容（用户挑的、或上一轮填的）就不动它 —— 上面那个判据只说明
            // 「两个槽都是空的」，落到具体槽上还要再确认一次（方图撞上已填的方形槽）。
            let replacing = item.game.artwork(.poster) != nil || item.game.artwork(.square) != nil
            guard !replacing || overwritable else { continue }

            // 覆盖 = **换掉**这张来源图，而不是「在另一个槽里再堆一张」：旧语言那张留着的话，
            // 同一个游戏会同时有中英两版图（网格卡读竖版槽、宽卡读方形槽，看起来像两个人拼的）。
            // 只有 `overwritable`（用户点了刷新，或来源侧换了名字）才会走到这里，而那两个前提
            // 都保证这个条目的图是同步自己抓的、用户没经手过。
            if overwritable {
                item.game.setArtwork(.poster, nil)
                item.game.setArtwork(.square, nil)
            }
            item.game.setArtwork(slot, data)
            if replacing { summary.artworkRefreshed += 1 } else { summary.artworkFetched += 1 }
        }
    }

    /// 这张刚下载的图是不是 1:1 附近（该进方形槽）。
    ///
    /// 解不出来一律返回 false → 落竖版槽（历史行为）。与显示层同一条纪律：
    /// 「尺寸不可读时不假装它是方形」（见 `AppImage.isSquareArtwork`；显示层那道闸在
    /// `AppImage.letterboxes(inBoxAspect:)`，两边都是「答不出来就按老行为走」）。
    /// 解码在后台 actor 上做：`AppImage(data:)` 只是读文件头，两家平台都不要求主线程。
    static func looksSquare(_ data: Data) -> Bool {
        AppImage(data: data)?.isSquareArtwork ?? false
    }

    /// 这个游戏的图是不是「同步建库时抓的、用户还没经手过」。
    ///
    /// ⚠️ **不含方形/竖版两个槽** —— 那两个正是这一步自己会写的槽。要求它们为空会让
    /// `forceRefresh` 永远不生效（上一轮同步刚填过，这一轮就"已经脏了"）。
    /// 判据落在**另外三类图**上：用户只要动过横向 / 背景 / Logo 中的任何一个，
    /// 就说明他进过图库界面，这个条目不再是"同步替我建的"。
    private static func isUntouchedAutoArtwork(_ game: Game) -> Bool {
        game.isAutoCreated
            && game.artwork(.landscape) == nil
            && game.artwork(.hero) == nil
            && game.artwork(.logo) == nil
    }

    // MARK: - 构造

    private func linkedAccount(localId: UUID) throws -> LinkedAccount {
        // 在内存里找而不是用 `#Predicate`：能绑的账号最多几条，全量取回的代价可以忽略，
        // 而不值得为这点性能押上「谓词在某个 SwiftData 版本上不支持 UUID 等值比较」的风险。
        guard let account = try modelContext.fetch(FetchDescriptor<LinkedAccount>())
            .first(where: { $0.localId == localId }) else {
            throw ExternalAPIError.internalFailure("linked account not found for import")
        }
        return account
    }

    /// 一个 Game 参与同名匹配的全部名字（主名 / 中文名 / 日文名 / 别名，去掉空的）。
    /// 按 Game 分组传入引擎，摊平会数错（见 `GameLinker.LinkCandidate`）。
    private static func matchNames(of game: Game) -> [String] {
        game.allNames
    }

    private static func link(_ record: ExternalGameRecord, to game: Game,
                             titleId: String, conceptId: String?,
                             candidates: inout [GameLinker.LinkCandidate], index: Int) {
        record.link(to: game)
        // 把新绑上的这条也变成线索：同一批里的下一条记录（比如 PSN 的 PS5 版跟着 PS4 版）
        // 就能靠 titleId/conceptId 直接命中，而不必再走名字启发式。
        candidates[index].clues.append(GameLinker.Clue(titleId: titleId, conceptId: conceptId))
    }

    private static func makeRecord(_ dto: ExternalGameRecordDTO, titleId: String,
                                   provider: AccountProvider, externalAccountId: String,
                                   now: Date) -> ExternalGameRecord {
        ExternalGameRecord(
            provider: provider,
            externalAccountId: externalAccountId,
            titleId: titleId,
            conceptId: dto.conceptId,
            titleName: dto.titleName,
            platform: dto.platform,
            platformRaw: dto.platformRaw,
            versionType: dto.versionType,
            firstPlayedAt: dto.firstPlayedAt,
            lastPlayedAt: dto.lastPlayedAt,
            playedSeconds: dto.playedSeconds,
            playCount: dto.playCount,
            trophies: dto.trophies,
            achievements: dto.achievements,
            imageURLString: dto.imageURLString,
            firstSeenAt: now)
    }

    /// 自动建库。
    ///
    /// 只填**来源真的知道**的字段：名字、平台、创建时间。评分/评价/通关记录一概不编 ——
    /// 用户打开详情页看到的空记录区，正是「这里还没有你的东西」的正确表达。
    ///
    /// 状态**显式**给 `.unclassified`（不靠 `Game.init` 的默认值）：导入进来的游戏是
    /// 「同步替我建的，我还没表过态」，而 `Game.init` 的默认值是「已通关」——
    /// 那是给用户自己新建条目时的语义。beta 3.1 因为没传这个参数，297 个导入游戏全成了
    /// 「已通关」，还带着空的通关记录区。
    ///
    /// `isAutoCreated = true` 是给「清空该账号导入数据」用的来路标记（见 `purgeImportedData`）。
    private static func makeGame(from dto: ExternalGameRecordDTO,
                                 sourceLocale: String, now: Date) -> Game {
        // 主名先留空：来源标题该落在哪个名字槽由 `applyTitleLanguage` 决定，
        // 中日文标题不该在 `name` 里也留一份（见那个函数的注释）。
        let game = Game(name: "", platform: dto.platform,
                        createdAt: now, status: .unclassified, isAutoCreated: true)
        applyTitleLanguage(game, title: dto.titleName, sourceLocale: sourceLocale)
        return game
    }

    /// 把来源标题写进**它该在的那个名字槽**。
    ///
    /// 为什么不能只写 `name`：来源标题是按请求语言本地化过的（Nintendo 的 `Gentry-Locale` /
    /// PSN 的 `Accept-Language`）。日本账号同步下来的标题是日文的，若只落在 `name` 上，
    /// 中文界面走语言槽兜底会显示日文名 —— 看着"能用"，但用户一旦在编辑页补上真正的中文名，
    /// 两个字段就各说各话。写进正确的槽位，编辑页打开时是「已经填好了，改不改随你」。
    ///
    /// ⚠️ **槽位由标题自己的文字种类决定，不由「请求了什么语言」决定** —— 服务端会在没有
    /// 目标语言时静默回落到别的语言，而请求本身是成功的。改这一版之前这里是
    /// 「请求了 `zh-*` 就写 `nameZh`」，于是真账号上 89 条英文/日文标题（共 151 条）被写进了
    /// 中文名槽，库里从此谎称这些游戏有中文名。判定与取证见 `TitleScript`。
    ///
    /// ⚠️ **中日文标题只落语言槽，不落 `name`**（2026-09-16 用户要求）：此前 `name` 无条件
    /// 也写一份，于是编辑页里「英文名」那一栏躺着一串中文，用户的原话是「把英文选项也填上中文」。
    /// 由此确立的新不变量：**`name` 只装非中日文的标题**，而「至少要有一个名字」由本函数
    /// 自身保证 —— 槽位非 nil 就填了槽，槽位 nil（拉丁/西里尔/韩文/正体不明）就填 `name`。
    ///
    /// 认不出来的语言（`TitleScript.other`）走 `name` 而不是另开一个槽：库里只有三个名字槽，
    /// 给韩文名临时造第四个字段是过度设计，而 `name` 本来的语义就是「不是中日文的那一个」。
    private static func applyTitleLanguage(_ game: Game, title: String, sourceLocale: String) {
        switch TitleScript.of(title).languageSlot(requestedLocale: sourceLocale) {
        case "ja": game.nameJa = title
        case "zh": game.nameZh = title
        default: game.name = title
        }
    }

    /// 语言标签 → 库里的语言槽（**在不知道标题文字时的旧判据**）。
    ///
    /// 只在没有标题可判的地方用（目前没有调用点，保留是因为 `propagateTitle` 的旧实现走过它）。
    /// 有新代码要落语言槽时请用 `TitleScript.languageSlot(requestedLocale:)` —— 只看 locale
    /// 的版本无法发现「请求了中文但拿回英文」这种服务端静默回落。
    ///
    /// **认不出来就不写**：把英文标题塞进日文槽，用户切到日文界面看到的是一个英文名，
    /// 比留空更糟 —— 留空至少会走 `name` 兜底，显示的仍然是同一个名字。
    static func languageSlot(for localeCode: String) -> String? {
        let lower = localeCode.lowercased()
        if lower.hasPrefix("ja") { return "ja" }
        if lower.hasPrefix("zh") { return "zh" }
        return nil
    }

    // MARK: - 刷新已有记录

    /// 用来源侧的新值刷新一条已有记录。
    ///
    /// 规则：**有值才覆盖，没值不清空**。理由是不对称的 ——
    /// 来源侧真的会偶尔少给字段（PSN 对 PS3/Vita 常常不给 `playDuration`，地区变体也会缺
    /// 首次游玩时间）。清空一次，用户库里的时长就凭空消失且无从恢复；保留一次，最坏是留下
    /// 一个略旧的正确值。两边的代价差一个数量级，所以选保留。
    ///
    /// `firstPlayedAt` 取更早、`lastPlayedAt` 取更晚：这两个是**单调事实**
    /// （第一次玩过就不会变晚，最近玩过不会更早），取极值天然抗抖动。
    ///
    /// - Parameter account: 目标账号。仅用于**认领孤儿**：`record.account == nil` 的记录
    ///   （beta 3.1 那批脏数据的另一半，界面上按 `account?.localId` 过滤，所以它在 UI 里
    ///   完全不可见、解绑时也不随级联删除）在这里被挂回账号，从此可见、可删、可清理。
    private static func refresh(_ record: ExternalGameRecord, with dto: ExternalGameRecordDTO,
                                account: LinkedAccount,
                                sourceLocale: String,
                                now: Date) {
        if record.account == nil { record.account = account }

        let previousTitle = record.titleName
        record.titleName = dto.titleName
        record.platform = dto.platform
        record.platformRaw = dto.platformRaw ?? record.platformRaw
        record.versionType = dto.versionType
        // conceptId 同理不清空：它是 PS4/PS5 双版本唯一的官方合并键，丢一次就再也拿不回来
        // （除非这条记录再出现在响应里），而它是后续合并的依据。
        record.conceptId = dto.conceptId ?? record.conceptId
        record.firstPlayedAt = earliest(record.firstPlayedAt, dto.firstPlayedAt)
        record.lastPlayedAt = latest(record.lastPlayedAt, dto.lastPlayedAt)
        record.playedSeconds = dto.playedSeconds ?? record.playedSeconds
        record.playCount = dto.playCount ?? record.playCount
        // 奖杯与 `playedSeconds` 同一条「nil 不清空」纪律：奖杯来自另一个端点
        //（`PSNTrophyService`），这一轮没取到 / 没匹配上时 dto 里就是 nil，
        // 那意味着「这次没新数据」，不是「奖杯没了」。清一次就再也拿不回来
        //（除非再同步一次），而保留最坏只是留一个略旧的正确值。
        record.trophies = dto.trophies ?? record.trophies
        // 成就走同一条「nil 不清空」纪律。Xbox 的成就就在 titles 那同一条响应里、
        // 实测 330/330 条都有，所以 dto 里为 nil 基本只可能是「这次 titles 少给了字段」——
        // 那同样意味着「这次没新数据」，不是「成就没了」。
        record.achievements = dto.achievements ?? record.achievements
        record.imageURLString = dto.imageURLString ?? record.imageURLString
        record.lastSeenAt = now
        record.presentInLastSync = true
        propagateTitle(to: record.game, from: previousTitle, to: dto.titleName,
                       sourceLocale: sourceLocale)
    }

    /// 把来源标题同步到 Game 的语言槽上。
    ///
    /// 三件事，顺序即优先级：
    ///
    /// 1. **修上一版的污染。** 某个语言槽里的值**正是我们上一轮写进去的来源标题**（`== old`），
    ///    而它按文字种类根本不属于那个槽（`nameZh` 里躺着英文或日文标题）→ 清空它。
    ///    这是 2026-09-16 那版「请求了中文就写 `nameZh`」留下的 89 条脏数据的修复路径 ——
    ///    没有这一步，那些游戏在**不改语言**的普通重新同步里永远不会被修正：下面的改名逻辑
    ///    在 `old == new` 时什么都不做，而语言的锅不该让用户靠「清空重同步」来背。
    /// 2. **改名**，且**只在用户没改过那个字段时**：`game.name` / `nameZh` / `nameJa` 里任何一个
    ///    **仍等于上一轮的来源标题**，就说明那个字段是我们写的、没人动过，可以跟着换；一旦用户
    ///    改成了别的名字，我们就再也不知道源标题该落在哪个字段上了，宁可不改 —— 把用户起的名字
    ///    冲掉是不可逆的，而少改一次只是名字旧了一轮（下次同步还会再试）。
    /// 3. **把新标题落到它该在的槽**（那槽还空着、或还是我们上一轮写的那个值）—— 与自动建库
    ///    同一套 `TitleScript` 规则。⚠️ 这一步**不受 `old == new` 影响**：那 13 条日文标题
    ///    上一版被丢掉了（请求的是中文，旧判据只写中文槽），现在正好在这一步补进 `nameJa`。
    ///
    /// 第 2 步（2026-09-16 扩充）还多管一件事：**`name` 里躺着的来源标题若是中日文，一并搬走** ——
    /// 旧的 `applyTitleLanguage` 无条件往 `name` 也写一份，于是在「英文名」栏留下了中文。
    /// 判据与第 1 步同款（`name` 里必须正是上一轮的来源标题），所以普通的一次重新同步就能
    /// 把已经导入的库洗干净，不必靠「清空重同步」。
    ///
    /// 不动 `updatedAt`：这是同步带来的改名，不是用户的编辑，不该把它顶到「最近编辑」的最前面。
    private static func propagateTitle(to game: Game?, from old: String, to new: String,
                                       sourceLocale: String) {
        guard let game else { return }
        let slot = TitleScript.of(new).languageSlot(requestedLocale: sourceLocale)

        // 1. 清掉上一版写错槽位的值（只清「还是我们写的那个来源标题」的，用户改过的一律不动）。
        if let zh = game.nameZh, zh == old, TitleScript.of(zh) != .han { game.nameZh = nil }
        if let ja = game.nameJa, ja == old, TitleScript.of(ja) == .other { game.nameJa = nil }

        // 2. **主名**。新标题的家是 `name`（非中日文）时才写它；那一格还空着、或还是我们
        //    上一轮写的旧值才动 —— 用户自己起的名字不碰（同第 1 步的纪律）。
        //
        //    ⚠️ 新标题若是中日文，**这一格一个字都不改**：里面那份旧值可能是**真的英文名**
        //    （上一轮用英文同步下来的），那是有用信息，不该被中文盖掉。两条信息各归各位，
        //    正是这套分工存在的意义（用户 2026-09-16 的要求：选了繁體中文就只填中文）。
        if slot == nil, game.name.isEmpty || game.name == old { game.name = new }

        // 2b. **`name` 里的中日文标题要搬走**（同一天的另一半：`name` 只装非中日文标题，
        //     见 `applyTitleLanguage`）。旧版无条件往 `name` 也写一份，于是「英文名」那一栏
        //     躺着一串中文 —— 这一段就是那条脏数据的修复路径，普通的一次重新同步就能洗掉。
        //     判据看**旧标题**的文字种类（不是新标题的槽）：只有当 `name` 里躺的正是上一轮的
        //     来源标题、而那个标题本来就不属于 `name` 时才清；用户自己敲进去的中文名一般
        //     不等于来源标题，不会被动。
        if game.name == old, TitleScript.of(old).languageSlot(requestedLocale: sourceLocale) != nil {
            game.name = ""
        }

        // 3. 落到正确的槽。
        switch slot {
        case "zh" where game.nameZh == nil || game.nameZh == old: game.nameZh = new
        case "ja" where game.nameJa == nil || game.nameJa == old: game.nameJa = new
        default: break
        }
    }

    static func earliest(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case (nil, nil): nil
        case (let value?, nil), (nil, let value?): value
        case (let a?, let b?): Swift.min(a, b)
        }
    }

    static func latest(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case (nil, nil): nil
        case (let value?, nil), (nil, let value?): value
        case (let a?, let b?): Swift.max(a, b)
        }
    }
}
