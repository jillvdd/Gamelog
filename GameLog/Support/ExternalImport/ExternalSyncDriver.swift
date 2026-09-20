import Foundation
import SwiftData

/// 一个账号一次同步的结果。
///
/// **刻意不落库**：库里保留的是「上次同步的结果」（`LinkedAccount.lastSyncAt` /
/// `lastSyncError` …），那是**状态**；本类型描述的是「刚刚这一次怎么样」，
/// 包括这一轮新建/刷新/忽略各多少条 —— 那是**事件**。两者混为一谈的话，
/// 第二次读出来的「本轮增量」必然是错的。
struct ExternalSyncResult: Equatable {
    var summary = ImportSummary()
    /// nil = 成功。**只留分类与动作信息**，UI 一律走 `errorKind` 查 L10n，
    /// 绝不展示 `ExternalAPIError` 的描述（那里面可能有字段路径等诊断细节）。
    var error: ExternalAPIError?
    /// true = 这次调用**根本没跑**：同一个账号已经有一次同步在进行中。
    ///
    /// 这不是失败，也不代表数据有问题 —— 它是一条**防线**。UI 的三条触发路径
    /// （账号列表、账号详情、绑定成功回调）各自都加了在飞判断，但那只防住「用户手快点了两下」；
    /// 真正需要防的是「同一个账号的两份导入同时写库」—— 那正是 beta 3.1 里每个游戏被加进库
    /// 两次的直接原因。放在驱动层，是因为只要有一条 UI 路径漏了加锁就等于没加。
    var skippedBecauseInFlight = false
    /// true = 同步本身成功了，但**奖杯 / PS3·Vita 那一路补充数据没取到**。
    /// 与 `error` 互斥（有 `error` 时整次同步就没成，谈不上「只有补充数据没取到」）。
    /// 界面上要把它说出来 —— 否则「PS3 游戏一条都没有」看起来就是功能没做（见 `FetchedRecords`）。
    var trophyUnavailable = false
    /// true = 同步本身成功了，但**游玩时长那一路补充数据没取到**（只有 Xbox 会为非）。
    ///
    /// 与 `trophyUnavailable` 分开两个字段而不是合成一个「补充数据没取到」：两家 provider
    /// 各自只会置其中一个，而用户要做的动作完全不同 —— 奖杯那条是「过会儿再同步一次」，
    /// 时长这条常见原因是**限流**（免费档 150 次/小时）。合成一个的话文案只能写得含混。
    var playtimeUnavailable = false
    /// 这一轮收尾时清掉的**空壳条目**数（导入自动建、已无记录指向、用户没碰过）。
    ///
    /// ⚠️ 是**全库口径**，不是「这个账号清了 N 条」—— `pruneOrphanImportGames` 扫的是整个库
    ///（另一条路径造出的空壳也被它收走）。界面上的措辞必须照这个口径写，不做成「该账号清了 N 条」。
    var prunedGames = 0
    /// 这一轮清掉的**已被游玩记录覆盖的奖杯记录**数（本账号口径）。
    ///
    /// 见 `ExternalAccountBinder.removeSupersededRecords`：跨世代奖杯套（`PS3,PS4` 共用）
    /// 曾经会被当成一个 PS3 游戏建一条记录，而同一套奖杯本来就有 PS4/PS5 记录在承载。
    /// 界面要如实报出来 —— 这个动作**会删掉用户手工绑过的记录**（他 2026-09-18 明确选了
    /// 「全清」），不声不响地删是这里最不该有的行为。
    var supersededRecords = 0

    var isSuccess: Bool { error == nil }
    /// 落库用的粗分类（nil = 成功）。
    var errorKind: AccountSyncErrorKind? { error?.syncErrorKind }
    /// 是否值得让用户点「再试一次」—— 只有网络抖动 / 5xx / 限流这三类。
    /// 凭证失效与接口变了重发一万次也是同样的结果。
    var isRetryable: Bool { error?.isRetryable ?? false }
}

/// 同步编排：**分派 provider → 取数据 → 交给 `ImportCoordinator` 落库 → 回写同步状态**。
///
/// 这一层的全部意义是把「两个 provider 的差异」收进一个 `switch`：UI 只需要说
/// 「同步这个账号」，不该知道 Nintendo 必带 `Gentry-Locale`、PSN 要先解析 accountId。
///
/// **凭证的进出全在这里接**：两个 provider 的 auth 服务都由闭包注入 Keychain 读写，
/// 于是 token / NPSSO 只在本层与 Keychain 之间存在 —— 不进 SwiftData、不进 UI、不进日志。
///
/// ⚠️ 本层还是**同账号导入的唯一闸门**（见 `ImportGate` 与 `ExternalSyncResult.skippedBecauseInFlight`）。
@MainActor
enum ExternalSyncDriver {

    /// 同步一个账号。
    ///
    /// - Parameters:
    ///   - account: 已保存的账号（本方法会改它的同步状态字段）。
    ///   - container: 主 ModelContainer。落库交给独立 actor 上的 `ImportCoordinator`，
    ///     所以这里要的是 container 而不是某个 ModelContext —— 后台绝不能用主线程的 context。
    ///   - language: 当前界面语言。决定 Nintendo 在「跟随 App 语言」档下的 `Gentry-Locale`，
    ///     以及 PSN 的 `Accept-Language`。
    ///   - refreshArtwork: 覆盖已有封面（只对同步建的、用户没经手过的游戏生效）。
    ///     只有「改了标题语言之后点重新同步」这一条路径传 true。
    @discardableResult
    static func sync(_ account: LinkedAccount, container: ModelContainer,
                     language: AppLanguage, autoCreateGames: Bool = true,
                     refreshArtwork: Bool = false) async -> ExternalSyncResult {
        let localId = account.localId

        // 同账号串行化：拿不到闸门就直接回「已在同步」，绝不并发跑第二遍导入。
        guard await ImportGate.shared.acquire(localId) else {
            var busy = ExternalSyncResult()
            busy.skippedBecauseInFlight = true
            return busy
        }
        // 同步期间让自动备份别写盘：这一路会**批量改写封面**，而封面是 `@Attribute(.externalStorage)`
        // 外置存储 —— 备份并发去读会读到已经被删掉的旧文件，CoreData 抛的是 Swift 接不住的
        // NSException，整个 app 当场 abort（2026-09-18 两份崩溃报告，已离线复现）。
        // 详见 `AutoBackup.backupSuppression`。**必须包住 `performSync` 全程**：
        // 写图发生在它内部的 `ImportCoordinator.importRecords` 里。
        // 放在闸门之后而不是之前：拿不到闸门就说明有另一份同步在跑，那时候让路由那一份去管，
        // 两次 begin/end 会把计数算成 2→1，最后归不了零。
        AutoBackup.shared.beginBackupSuppression()
        defer { AutoBackup.shared.endBackupSuppression() }

        let result = await performSync(account, container: container, language: language,
                                       autoCreateGames: autoCreateGames, refreshArtwork: refreshArtwork)
        // 闸门必须释放。**放在唯一的出口上**（`performSync` 把所有错误都吃进 `result`、
        // 不向外抛），所以这里不会漏 —— 将来若给它加上会抛的路径，必须改成 defer 语义。
        await ImportGate.shared.release(localId)
        return result
    }

    /// 真正干活的那一半。**只有 `sync` 会调它**，且只在拿到导入闸门之后。
    private static func performSync(_ account: LinkedAccount, container: ModelContainer,
                                    language: AppLanguage, autoCreateGames: Bool,
                                    refreshArtwork: Bool) async -> ExternalSyncResult {
        let provider = account.provider
        let localId = account.localId
        // 在**任何 await 之前**抄下来：收尾清理发生在几十秒之后，那时用户完全可能已经解绑了
        // 这个账号（`context.delete` + `save`），再去读已销毁模型的属性就是 SwiftData fatal。
        let externalAccountId = account.externalAccountId

        // 先按 Keychain 实况校正一次状态：换机、抹掉设备、从备份恢复出来的账号，库里还写着
        // `active`，直接同步只会得到一个莫名其妙的失败，而真正的原因是「凭证根本不在了」。
        AccountCredentialStore.refreshCredentialState(of: account)

        var result = ExternalSyncResult()
        // 落库结果先攒在局部变量里，**最后一次性回写** —— 这样「账号中途被解绑」只需要在
        // 回写处挡一道（见下），不必在每个分支里各挡一次。
        var summary: ImportSummary?
        var appliedLocale = ""
        var fallbackFrom: String?
        var failure: ExternalAPIError?

        do {
            let fetched = try await fetchRecords(provider: provider, localId: localId,
                                                 account: account, language: language)
            let coordinator = ImportCoordinator(modelContainer: container)
            summary = try await coordinator.importRecords(
                fetched.records,
                intoAccount: localId,
                sourceLocale: fetched.usedLocale,
                autoCreateGames: autoCreateGames,
                artworkFetcher: ArtworkFetcher(),
                forceArtworkRefresh: refreshArtwork)

            // 后台导入往库里写了图片，主线程的解码缓存必须清掉（否则同 ID 的旧图残留）。
            // 通知与缓存清理都由**主线程**做，不在后台 actor 里 —— 与 `BackupImporter` 同一条纪律。
            ImageDecodeCache.bump()

            // 收尾一：清掉「已经被游玩记录覆盖」的奖杯记录。
            //
            // 起因是用户 2026-09-18 报的「个别游戏读到的不是 title id `CUSA01174` 而是奖杯套
            // id `NPWR07319`」：跨世代共用的奖杯套（`PS3,PS4`）在名字匹配失败时会被当成
            // 「一个 PS3 游戏」建一条记录，而同一套奖杯本来就有 PS4/PS5 记录在承载。
            // 建记录的那条规则已经改了（`PSNTrophyService.finish` 的规则 ④），这里收走旧账。
            //
            // 判据是**服务端事实**（本次按 id 取奖杯时回报的归属），不是名字像不像 —— 所以
            // 取数失败时集合为空、什么也不删，而不是拿一个猜出来的集合去删。
            let superseded = (try? ExternalAccountBinder.removeSupersededRecords(
                titleIds: fetched.claimedTrophySets, provider: provider,
                externalAccountId: externalAccountId, in: container.mainContext)) ?? 0

            // 收尾二：替导入把地上的碎屑捡掉。
            //
            // 同步的**自动匹配**会把记录改指到库里已有的条目上（第 1 次同步建了 A，用户随后
            // 手工建了同名条目，第 2 次同步把记录改指到用户条目 → A 从此没有任何记录指向
            // 它）。A 若还是「导入自动建、用户没碰过」的，就只是一个空壳，界面上却仍然是一
            // 条游戏（用户 2026-09-17 报的「合并了但库里还是两条」的同一族现象）。
            //
            // 顺序必须在收尾一**之后**：上面刚删掉的那批记录，如果正是某个自动建条目的唯一
            // 依据，那个条目现在才成为空壳，正好被这一遍收走。
            //
            // 判据完全复用用户已认可的那一套（`purgeImportedData` 的 `isPristineImportGame`）：
            // 「导入自动建 + 用户没碰过 + 已无任何记录指向」三条同时成立才删，**用户自己建的
            // 条目连考虑都不考虑**。
            //
            // 用 `container.mainContext` 而不是新开一个 context：删掉的东西必须**立刻**对界面
            // 可见（视图里的 `@Query` 读的就是 mainContext），否则库页会多渲染一帧已删条目。
            let pruned = (try? ExternalAccountBinder.pruneOrphanImportGames(in: container.mainContext)) ?? 0
            if superseded > 0 || pruned > 0 {
                // 真删到了东西才收尾 —— 与 `purge()` 同一套（`ImageDecodeCache.bump()` +
                // 广播整库替换）。用户完全可能正停在那个空壳的详情页上，不广播就是一次
                // SwiftData fatal（§54.14）。
                ImageDecodeCache.bump()
                NotificationCenter.default.post(name: UserCustomization.libraryReplacedNotification,
                                                object: nil)
            }
            result.supersededRecords = superseded
            result.prunedGames = pruned

            appliedLocale = fetched.usedLocale
            fallbackFrom = fetched.didFallBackLocale ? fetched.requestedLocale : nil
            result.summary = summary ?? ImportSummary()
            result.trophyUnavailable = fetched.trophyUnavailable
            result.playtimeUnavailable = fetched.playtimeUnavailable
        } catch let error as ExternalAPIError {
            failure = error
            result.error = error
        } catch {
            // 兜底：不把任意 Error 的 description 写进库里（可能带响应体或 URL）。
            failure = .internalFailure("unexpected sync failure")
            result.error = failure
        }

        // ⚠️ 到这里可能已经过了几十秒，用户完全可能在这期间解绑了这个账号（`account` 已被
        // `context.delete` + `save`）。已销毁的对象读一下属性就是 SwiftData fatal，所以
        // **回写同步状态前必须挡一道 `isLive`**（判据见 `Game.isLive`）。
        // 导入本身已经在一个独立 context 的 actor 上落库完了，跳过回写不影响数据正确性 ——
        // 账号都没了，「上次同步时间」也就没有意义了。
        guard account.isLive else { return result }

        if let failure {
            account.lastSyncError = failure.syncErrorKind
            // 凭证失效要写进账号状态：界面据此显示「需要重新登录」而不是干巴巴一句「同步失败」。
            if failure.syncErrorKind == .authExpired { account.credentialState = .expired }
        } else {
            account.lastSyncAt = .now
            account.lastSyncRecordCount = summary?.processed ?? 0
            account.lastSyncError = nil
            account.credentialState = .active
            // 语言回退要写进账号：用户选了繁體中文却拿回英文标题时，界面必须说清是
            // 「接口不接受这个取值，本次回退到 English」—— 而不是让用户以为功能坏了。
            // 只记「从哪个取值退下来的」，不记任何响应内容。
            account.sourceLocale = appliedLocale
            account.localeFallbackFrom = fallbackFrom
        }
        // 上面写回的全是 `account` 上的状态字段，落盘由本层负责（调用方只管展示结果）。
        // 失败也没关系：状态没存下来只是「界面显示的还是上一次的结果」，不影响数据正确性。
        try? account.modelContext?.save()
        return result
    }

    /// 依次同步多个账号，返回 `localId → 结果`。
    ///
    /// **串行**而不是并发：这些请求打的是同一家（或两家）官方接口，一次同步本来就有几十上百个
    /// 请求，并发只会更容易被限流，而用户看不出「快了一点」和「被封了」的关系。
    ///
    /// ⚠️ 先把手上的 `localId` 抄成数组再用：每一轮 `await` 期间用户都可能解绑**下一个**
    /// 账号（`context.delete` + `save()`），回到循环里再读 `account.localId` 就是读已销毁模型
    ///（SwiftData fatal，判据见 `Game.isLive`）。抄过 ID 之后本循环不再碰 `account`。
    static func syncAll(_ accounts: [LinkedAccount], container: ModelContainer,
                        language: AppLanguage) async -> [UUID: ExternalSyncResult] {
        let targets = accounts.filter(\.isLive).map { (id: $0.localId, account: $0) }
        var results: [UUID: ExternalSyncResult] = [:]
        for target in targets {
            // 每一轮开始前确认账号还在（上一轮 await 期间可能已被解绑）——
            // 不在了就跳过，而不是去碰那个死对象。
            guard target.account.isLive else { continue }
            results[target.id] = await sync(target.account, container: container, language: language)
        }
        return results
    }

    // MARK: - provider 分派

    /// 一次取数的产物：记录 + 实际用的语言。
    struct FetchedRecords {
        var records: [ExternalGameRecordDTO]
        /// 实际用于取数的语言标签（Nintendo = `Gentry-Locale` 的取值；PSN = `Accept-Language`）。
        /// 它决定标题落在哪个语言槽（`ImportCoordinator.applyTitleLanguage`）。
        var usedLocale: String
        /// 原本想用的语言标签。与 `usedLocale` 不同 = 发生了回退。
        var requestedLocale: String
        /// true = 这一轮的**奖杯/PS3·Vita 补充数据没取到**（只有 PSN 会为非）。
        ///
        /// 它不是失败：游玩记录已经正常拿回来了，整次同步不该为一条辅助端点回滚。
        /// 但它也**不能静默** —— 用户正是为了「PS3/Vita 一条都没有」来提的这条需求，
        /// 如果补充取数失败了却什么都不说，界面上看起来就是「功能没做」。
        /// 所以如实带出去，由界面说一句「本次没取到奖杯数据」。
        var trophyUnavailable = false

        /// true = 这一轮的**游玩时长没取到**（只有 Xbox 会为非）。
        ///
        /// 与 `trophyUnavailable` 同一条理由：游玩记录已经拿回来了，不该为一条辅助数据
        /// 把整批丢掉；但也**不能静默** —— 用户看到满屏「—」会以为 Xbox 根本不提供时长，
        /// 而实际只是这次没取到（限流是常见原因）。
        var playtimeUnavailable = false

        /// 这一轮被**某条游玩记录认领**的奖杯套 id（只有 PSN 会为非空）。
        ///
        /// 用途只有一个：同步收尾时把历史上「跨世代奖杯套被当成 PS3 游戏建出来」的那些来源
        /// 记录清掉（`ExternalAccountBinder.removeSupersededRecords`）。取数失败时它是空集 ——
        /// 那时**不清理**，而不是按空集去猜。
        var claimedTrophySets: Set<String> = []

        var didFallBackLocale: Bool { usedLocale != requestedLocale }
    }

    /// 按 provider 取记录。**两个分支的凭证闭包是这一层唯一碰 Keychain 的地方。**
    private static func fetchRecords(provider: AccountProvider, localId: UUID,
                                     account: LinkedAccount,
                                     language: AppLanguage) async throws -> FetchedRecords {
        switch provider {
        case .nintendo:
            let auth = NintendoAuthService(sessionTokenProvider: {
                try AccountCredentialStore.get(kind: .nintendoSessionToken,
                                               provider: .nintendo, localId: localId)
            })
            let locale = requestedNintendoLocale(account: account, language: language)
            let fetched = try await NintendoPlayHistoryClient(auth: auth, locale: locale).fetchRecords()
            return FetchedRecords(records: fetched.records,
                                  usedLocale: fetched.usedLocale,
                                  requestedLocale: fetched.requestedLocale)

        case .playstation:
            let auth = PSNAuthService(
                npssoProvider: {
                    try AccountCredentialStore.get(kind: .psnNPSSO,
                                                   provider: .playstation, localId: localId)
                },
                refreshTokenProvider: {
                    try AccountCredentialStore.get(kind: .psnRefreshToken,
                                                   provider: .playstation, localId: localId)
                },
                refreshTokenSink: { token in
                    // refresh_token 实测不轮换，通常写的还是同一个值。仍然写，是因为
                    // 「万一哪天开始轮换而我们没存」的后果是会话在某天毫无征兆地失效。
                    try AccountCredentialStore.set(token, kind: .psnRefreshToken,
                                                   provider: .playstation, localId: localId)
                })
            // PSN 的语言走标准的 `Accept-Language` 头。用户在账号上选的那一档优先
            //（`acceptLanguage` 是一条降级阶梯，形如 `zh-Hant-TW,zh-Hant,zh-TW`）；
            // 选「跟随 App 语言」时拿**当前**界面语言的 BCP-47 标签现算 —— 与 Nintendo
            // 侧同一条「跟随是逐次生效的，不是绑定那天定死」的纪律。
            //
            // ⚠️ 与 Nintendo 的关键差异：`Accept-Language` 是标准头，不被接受的取值只会被
            // **忽略**、不会报错，服务端也**不回报**实际用了哪个语言。所以这里
            // `usedLocale == requestedLocale` 是**如实陈述「我们发了什么」**，
            // 不是「我们检测到服务端用了什么」—— PSN 侧的 `localeFallbackFrom` 因此恒为空，
            // 不假装能检测（见 `ExternalTitleLocale` 的说明）。
            let locale = requestedAcceptLanguageLocale(account: account, language: language)
            let records = try await PSNGameService(auth: auth,
                                                   accountId: account.externalAccountId,
                                                   acceptLanguage: locale).fetchRecords()

            // 奖杯标题端点**同时**是 PS3 / PS Vita 的唯一来源（`gamelist/v2` 是
            // PS4/PS5/PC 专用的，见 `PSNTrophyService` 头部），所以这一步不是「锦上添花」——
            // 不做的话用户明确说过的 PS3/Vita 游戏永远进不来。
            //
            // 失败**不牵连整次同步**：上面的游玩记录已经拿到了，为一条辅助端点把 101 条
            // PS4/PS5 记录一起丢掉是更糟的结果。失败如实记进 `trophyUnavailable`。
            var merged = records
            var trophyUnavailable = false
            var claimedTrophySets: Set<String> = []
            do {
                let trophies = PSNTrophyService(
                    auth: auth, accountId: account.externalAccountId,
                    acceptLanguage: locale)
                let titles = try await trophies.fetchTrophyTitles()
                // 第一遍（免费）：按名字 + 平台贴，顺带算出「哪些套已经有主」与「谁还没认下」。
                let namePass = PSNTrophyService.attachByName(gamelist: records, trophies: titles)

                // 名字匹配认不下的，改用 `titleId` 精确对号（每 5 个 id 一次请求）。
                //
                // 这不是「多一层保险」，是**主力**：`gamelist` 的 `name` 是**商店商品名**
                //（实测见过「双人成行 PS4™ 和 PS5™」这种同捆包名、「Devil May Cry 5 Series」
                // 这种合集名），与奖杯套名 `trophyTitleName` 常常根本不同；同名同平台多条
                // （《The Last of Us Part II》在库里三条）又会被上面「不唯一就不贴」保守掉。
                // 用户真库实测：101 条 PS4/PS5 记录里纯名字匹配只认下 31 条。
                //
                // 只问**没认下的**，认下的不再问 —— 请求数因此从 21 批降到约 14 批。
                // 靠名字认下的那些不是白认：它们给出的「这个套有主」随 `NamePass.claimed`
                // 进入收尾的认领集合，所以「只问没认下的」不影响规则 ④ 判定的完整性。
                var byTitleId: [String: PSNTrophyService.TitleTrophies] = [:]
                if !namePass.unresolved.isEmpty {
                    byTitleId = try await trophies.fetchTrophies(forTitleIds: namePass.unresolved)
                }
                let outcome = PSNTrophyService.finish(namePass, trophies: titles,
                                                      byTitleId: byTitleId)
                merged = outcome.records
                claimedTrophySets = outcome.claimedTrophySets
            } catch {
                // 不问是哪种错误：`PSNTrophyService` 内部已经做过一次凭证失效重取，
                // 到这里就是「这一轮拿不到」，分类对用户没有更多信息量。
                //
                // ⚠️ 走到这里时 `merged` 可能**已经带上了**名字匹配那一步的结果（精确对号
                // 那一半失败）。所以对应的文案是「没取全」而不是「一条都没有」——
                // 见 `account.detail.trophyUnavailable`。
                trophyUnavailable = true
            }

            return FetchedRecords(records: merged, usedLocale: locale, requestedLocale: locale,
                                  trophyUnavailable: trophyUnavailable,
                                  claimedTrophySets: claimedTrophySets)

        case .xbox:
            // Xbox 侧没有 `invalidate()` 可调：那一个 API key 长期有效、不轮换，
            // 401 就是「这个 key 不被接受」，重取一次读到的还是同一个值。
            // 所以这里**没有** PSN 那样的失效重试 —— 重试是确定性的无用功。
            let auth = XboxAuthService(apiKeyProvider: {
                try AccountCredentialStore.get(kind: .xboxAPIKey,
                                               provider: .xbox, localId: localId)
            })
            // 与 PSN 同一条头、同一条规矩（见上面那段 `Accept-Language` 说明）：
            // `usedLocale == requestedLocale` 是如实陈述「我们发了什么」，不是检测到服务端用了什么。
            // Xbox 侧另有一个实测事实值得记下来：这个头**确实生效**（同一批 330 条标题里
            // zh-CN 与 en-US 有 115 条不同，见 §63），但仍然没有办法知道服务端最终采纳了哪个。
            let locale = requestedAcceptLanguageLocale(account: account, language: language)
            let fetched = try await XboxGameService(auth: auth,
                                                    xuid: account.externalAccountId,
                                                    acceptLanguage: locale).fetch()

            // 时长那一路的失败已经被 `XboxGameService` 吃进 `playtimeUnavailable`
            //（不是抛出）—— 两次调用是同一个服务里的编排，「怎么分批问」是它的实现细节，
            // 不该漏到这里来。这里只负责把那个标志如实传出去。
            return FetchedRecords(records: fetched.records, usedLocale: locale, requestedLocale: locale,
                                  playtimeUnavailable: fetched.playtimeUnavailable)
        }
    }

    // MARK: - 标题语言

    /// 本次请求该用哪个语言标签（各 provider 各按各的规矩算）。
    /// 界面问「改了语言要不要重新同步」时走这个 —— 它问的是「发出去的会是什么」，
    /// 与到底是 `Gentry-Locale` 还是 `Accept-Language` 无关。
    static func requestedLocale(account: LinkedAccount, language: AppLanguage) -> String {
        switch account.provider {
        case .nintendo: requestedNintendoLocale(account: account, language: language)
        case .playstation, .xbox: requestedAcceptLanguageLocale(account: account, language: language)
        }
    }

    /// 本次请求该用哪个 `Gentry-Locale`。
    ///
    /// 用户的**选择**（`LinkedAccount.titleLocale`）优先；选了「跟随 App 语言」就按**当前**
    /// 界面语言现算 —— 所以跟随是逐次生效的，而不是绑定那天定死。
    ///
    /// ⚠️ 这里不再读 `account.sourceLocale`：那个字段现在的含义是「上次实际用了什么」
    /// （诊断与展示），拿它当输入会让「跟随 App 语言」退化成「跟随绑定那天的语言」。
    static func requestedNintendoLocale(account: LinkedAccount, language: AppLanguage) -> String {
        NintendoAuthService.gentryLocale(for: account.titleLocale,
                                         appLocaleCode: language.localeCode)
    }

    /// 本次请求该用哪个 `Accept-Language`（**PSN 与 Xbox 共用**）。同一条「选择优先、
    /// 跟随 App 语言则现算」的纪律。
    ///
    /// ⚠️ 「跟随 App 语言」档拿到的是 `language.localeCode`，即 `zh-Hans` / `ja` / `en`——
    /// 单标签，不是阶梯。这是**如实**的：用户说「跟随界面语言」，那就发界面语言本身，
    /// 不为他挑一个更可能命中的区域写法（那是替他做决定，而他随手改成某一档就能得到阶梯）。
    static func requestedAcceptLanguageLocale(account: LinkedAccount, language: AppLanguage) -> String {
        account.titleLocale.acceptLanguage ?? language.localeCode
    }
}

/// 同账号导入的闸门：保证**同一个 `localId` 同一时刻只有一次导入在跑**。
///
/// 为什么必须存在（而不是靠 UI 的按钮置灰）：一次导入要几十秒（几百条记录 + 封面下载），
/// 期间它有**三条**触发路径 —— 账号列表的「同步」、账号详情的「同步」、绑定成功后的自动同步。
/// 只要有一条漏了加锁，两次导入就会各持一个 `ImportCoordinator`（各自一个 ModelContext）
/// 同时写库，而 SwiftData 的两个 context 之间看不见对方的未提交写入 —— 于是同一批记录
/// 被建两遍，用户库里凭空多出一整套游戏。beta 3.1 真账号实测就是这个后果。
///
/// `ImportCoordinator` 内部的 `save()` 时机修复（去重键先落盘）让「先后两次」变得安全，
/// 但「同时两次」仍然需要这一层的互斥。
private actor ImportGate {
    static let shared = ImportGate()

    private var inFlight: Set<UUID> = []

    /// 尝试进入。true = 拿到了闸门（用完必须 `release`）；false = 已有一次在跑。
    func acquire(_ id: UUID) -> Bool {
        inFlight.insert(id).inserted
    }

    func release(_ id: UUID) {
        inFlight.remove(id)
    }
}
