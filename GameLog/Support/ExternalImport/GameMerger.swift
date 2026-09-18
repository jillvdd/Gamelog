import Foundation
import SwiftData

/// 外部记录与 `Game` 之间的**手动**绑定、解绑，以及「两个 Game 合成一个」。
///
/// 与 `GameLinker` 的分工是一条清晰的红线：
/// - **自动**匹配（`GameLinker`）只认强键，宁可不匹配 —— 它无人复核，错了不可逆。
/// - **手动**操作（本类型）由用户点了才发生，所以不设二次猜测：用户说这个记录属于那个游戏，
///   那就是。`suggestions` 提供弱键候选，但**它只产出一个列表**，不碰任何数据。
///
/// ⚠️ 这里的三个方法都是**就地改模型**的，调用方必须在持有这些对象的那个 `ModelContext`
/// 所属线程上调用（UI 走主线程 context），并在之后自己 `save()` + `ImageDecodeCache.bump()`。
/// 本类型刻意不碰 context 的保存 —— 与库里的编辑路径保持同一种「谁开的事务谁保存」的写法。
enum GameMerger {

    // MARK: - 绑定 / 解绑

    /// 把一条外部记录手动绑到某个 Game。
    ///
    /// 顺手清掉 `isIgnored`：用户既然亲手把它绑上了，「别再导入这条」这个意思就作废了，
    /// 两个状态同时挂着只会让界面自相矛盾（既显示「已关联」又显示「已忽略」）。
    static func bind(_ record: ExternalGameRecord, to game: Game) {
        record.link(to: game)
        record.isIgnored = false
    }

    /// 解绑。**可逆**：只摘关联，不置 `isIgnored`。
    ///
    /// 下次同步若这条记录又匹配上（同一个 titleId / conceptId / 归一化同名），它会被重新
    /// 自动关联 —— 这就是「解除关联」的字面含义，也是用户点它时的预期。
    /// 若用户的真实意图是「以后都别再导入」，那是另一个动作（`setIgnored(_:on:)`），
    /// 界面上和这个按钮分开摆（见 `ExternalRecordLinkSheet`）。
    static func unbind(_ record: ExternalGameRecord) {
        record.unlink()
    }

    /// 设置 / 撤销「别再自动导入这条」。
    ///
    /// 撤销之后如果 `game == nil`，这条记录会**重新参加**下一轮同步的匹配与建库 —— 这正是
    /// 「恢复导入」该有的效果。若它还绑着某个 Game，那它本来就不会被自动逻辑碰，撤销只影响
    /// 界面上的标签。
    static func setIgnored(_ ignored: Bool, on record: ExternalGameRecord) {
        record.isIgnored = ignored
    }

    // MARK: - 删除 Game 的收尾

    /// 删除一个 `Game` **之前**必须调用：把它名下的外部记录标成「别再自动导入」。
    ///
    /// 没有这一步，用户删掉一个导入建出来的游戏之后，每同步一次它就会被再建回来一次，
    /// 而用户完全不知道发生了什么（记录还在库里、还绑着那个已删的游戏）。这是「自动墓碑」
    /// 原本唯一正当的用途，现在由 `isIgnored` 显式承担 —— 好处是它能被看见、被筛选、被撤销，
    /// 而不是靠一个「曾经绑过而现在没绑」的隐式判据（那个判据把「解绑」也一并吞了）。
    ///
    /// 走 `FetchDescriptor` 全量取回再内存比对，而不是读 `game.externalRecords` 这个 inverse
    /// 数组 —— 与 `ImportCoordinator` 同一条纪律：inverse 在某些写入路径上要等 save 之后才一致，
    /// 而删除路径不该建立在「调用方刚刚 save 过」这个前提上。记录本身只有几十字节，代价可忽略。
    ///
    /// - Returns: 被标记的记录数（给调用方做回执/断言用）。
    @discardableResult
    static func ignoreRecords(linkedTo game: Game, in context: ModelContext) -> Int {
        let targetID = game.persistentModelID
        guard let records = try? context.fetch(FetchDescriptor<ExternalGameRecord>()) else { return 0 }
        var marked = 0
        for record in records
        where record.game?.persistentModelID == targetID && !record.isIgnored {
            record.isIgnored = true
            marked += 1
        }
        return marked
    }

    // MARK: - 合并

    /// 一次合并搬了多少东西（给 UI 回执用）。
    struct MergeReport: Equatable {
        var completions = 0
        var copies = 0
        var groups = 0
        var records = 0
        var artworks = 0
        /// 是否**继承**了 source 的状态（见下面 `status` 那一段）。
        var adoptedStatus = false
    }

    /// 把 `source` 整个并进 `target`，然后**删掉** `source`。
    ///
    /// 不用「先删再建」那类写法：`Game` 上挂的三组关系有级联（`completions` / `copies`），
    /// 顺序一错就会把用户写的通关记录和持有记录一起删掉。所以这里严格两步 ——
    /// **① 把所有子对象改挂到 target，② 最后才 `delete(source)`**。此刻 source 上已经
    /// 什么都不剩，级联无对象可删。
    ///
    /// 合并的取舍只有一条：**target 优先，source 补空**。
    /// - 标量字段：target 有值就不动，target 为空才从 source 取。
    /// - 图片：target 那一类有图就不动，没有才从 source 搬。
    /// - 通关记录 / 持有 / 分组 / 外部记录：**全部搬过去**（它们是多条事实，不存在覆盖问题）。
    ///
    /// `status` 的原则上是「不搬」（它是用户对进度的判断，两个条目各有一份，没有依据说哪个对），
    /// **但有一条例外**：source 有通关记录、target 一条都没有、且 target 现在不是
    /// 已通关/长线游玩 —— 那就继承 source 的状态。
    ///
    /// 例外是为了修一个**记录凭空消失**的坑：详情页只在 `isCompletedOrLongRunning` 时才渲染
    /// 记录区（`GameDetailView`），而合并会把 source 的通关记录全部搬过来。不继承状态的话，
    /// 「把一个已通关的游戏并进一个未分类的游戏」的结果是：记录确实在库里，但详情页不显示，
    /// 用户看到的是一个刚搬过去的游戏显示「一条记录都没有」—— 只能靠手动改状态去把它找回来。
    ///
    /// 为什么评价是「搬」而不是「并」：把两段文字拼起来会造出一段**谁都没写过**的话。
    ///
    /// ⚠️ **顺序前提**：本方法读 `source.completions` / `source.copies` / `source.groups` /
    /// `source.externalRecords` 这四个 **inverse 数组**，而 `ImportCoordinator` 里写明了
    /// 「inverse 在 save 之前不保证一致」。这里的调用点全部满足前提 —— 被合并的两个 Game
    /// 都是用户从界面上选中、早已落盘的对象，且本方法是「先搬子对象、最后删 source」，
    /// 中途不涉及新建关系的写入。**若将来出现「刚插入还没 save 就直接合并」的调用点，
    /// 必须先把这里改成 FetchDescriptor 查询。**
    ///
    /// - Returns: 搬运数量摘要；`source === target` 时原样返回空摘要（不删任何东西）。
    @discardableResult
    static func merge(_ source: Game, into target: Game, in context: ModelContext,
                      now: Date = .now) -> MergeReport {
        guard source.persistentModelID != target.persistentModelID else { return MergeReport() }
        var report = MergeReport()

        // ① 先搬子对象。
        //    遍历的是数组的值拷贝，所以边搬边改不会打断循环。
        for completion in source.completions {
            completion.game = target
            report.completions += 1
        }
        for copy in source.copies {
            copy.game = target
            report.copies += 1
        }
        for group in source.groups
        where !target.groups.contains(where: { $0.persistentModelID == group.persistentModelID }) {
            target.groups.append(group)   // 多对多：`group.games` 由 inverse 自动更新
            report.groups += 1
        }
        for record in source.externalRecords {
            record.link(to: target)
            report.records += 1
        }

        // ② 标量字段：只补空。
        if Self.isBlank(target.nameZh) { target.nameZh = Self.nonBlank(source.nameZh) }
        if Self.isBlank(target.nameJa) { target.nameJa = Self.nonBlank(source.nameJa) }
        if target.releaseDate == nil { target.releaseDate = source.releaseDate }
        if Self.isBlank(target.developer) { target.developer = Self.nonBlank(source.developer) }
        if Self.isBlank(target.publisher) { target.publisher = Self.nonBlank(source.publisher) }
        if Self.isBlank(target.genre) { target.genre = Self.nonBlank(source.genre) }
        if target.platform.isEmpty { target.platform = source.platform }
        if target.reviewTitle.isEmpty { target.reviewTitle = source.reviewTitle }
        if target.reviewBody.isEmpty { target.reviewBody = source.reviewBody }
        target.isFavorite = target.isFavorite || source.isFavorite
        // 来源标记：并进来的东西可能是同步建的，删掉「由导入创建」这个来路会让
        // 「清空该账号导入数据」漏掉它（它现在是 target 的一部分了，见 purgeImportedData）。
        target.isAutoCreated = target.isAutoCreated && source.isAutoCreated

        // ②' 状态：只在这一个方向上继承（见上面「例外」那一段）。
        if report.completions > 0, !target.statusValue.isCompletedOrLongRunning,
           source.statusValue.isCompletedOrLongRunning {
            target.statusValue = source.statusValue
            report.adoptedStatus = true
        }

        // ③ 别名：取并集，并把 source 的名字也收进去 —— 合并之后原来那个名字仍然搜得到，
        //    否则「我明明记得库里叫这个名」会变成搜不到。
        var aliases = target.aliases
        // 两边的名字都走 `allNames`（已滤掉空值 —— 主名可以是空的，见 `Game.name`）。
        let known = target.allNames
        for candidate in source.allNames {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !known.contains(trimmed), !aliases.contains(trimmed) else { continue }
            aliases.append(trimmed)
        }
        target.aliases = aliases

        // ④ 图：只补缺的那几类。
        for kind in ArtworkKind.allCases where target.artwork(kind) == nil {
            if let data = source.artwork(kind) {
                target.setArtwork(kind, data)
                report.artworks += 1
            }
        }

        target.updatedAt = now

        // ⑤ 最后才删。此刻 source 已空，级联无对象可删。
        //    ⚠️ 删掉 source 后**不要**再碰它 —— SwiftData 里已删对象上的属性访问是未定义的。
        context.delete(source)
        return report
    }

    // MARK: - 手动绑定的候选（弱键）

    /// 手动绑定面板的候选列表。
    ///
    /// **这里可以用弱键**，与自动匹配的纪律不冲突：结果只是一个列表，用户看着挑，
    /// 挑错也不会有任何数据被改。自动匹配不能这么干，是因为它无人复核。
    ///
    /// 打分只有两档（归一化后**全等** > **互相包含**），没有前缀/编辑距离那一类 ——
    /// 档位越多，「为什么这条排在前面」越难解释，而用户一眼就能扫完这二十条。
    ///
    /// - Parameter limit: 上限。默认 20：再多用户也不会翻，而列表越长越难找。
    static func suggestions(for record: ExternalGameRecord, among games: [Game],
                            limit: Int = 20) -> [Game] {
        let target = GameLinker.normalizedTitle(record.titleName)
        guard target.count >= 2 else { return [] }

        var scored: [(score: Int, name: String, game: Game)] = []
        for game in games {
            var best = 0
            for name in game.allNames {
                let normalized = GameLinker.normalizedTitle(name)
                guard !normalized.isEmpty else { continue }
                if normalized == target {
                    best = max(best, 2)
                } else if normalized.count >= 2,
                          normalized.contains(target) || target.contains(normalized) {
                    best = max(best, 1)
                }
            }
            guard best > 0 else { continue }
            // 定序键：主名可能为空（导入的中日文标题只落语言槽），用解析后的名字。
            scored.append((best, game.primaryName, game))
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.name < rhs.name   // 同分按名字定序：结果稳定，测试可断言
            }
            .prefix(limit)
            .map(\.game)
    }

    // MARK: - 小工具

    private static func isBlank(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }

    /// 空白字符串一律当「没有」，别把 `" "` 搬过去。
    private static func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
