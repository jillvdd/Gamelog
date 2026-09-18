import Foundation
import SwiftData

/// 绑定流程的错误分类。
///
/// 与 `ExternalAPIError` 分开，是因为这里多了一类**只有用户能修好的**错误：
/// 粘贴的链接里没有 code、NPSSO 长度不对。混进 `ExternalAPIError` 的话，
/// UI 只能给出「同步失败，请重试」—— 而用户该做的是「重新复制一次」。
enum AccountLinkError: Error, Equatable {
    /// 用户提供的那段东西格式就不对。**只有这一类用户能自己改好。**
    case invalidInput
    /// 回调不属于本次登录（多半是粘了上一次的旧链接）。
    case staleCallback
    /// 绑定本身失败（网络 / 服务端 / 凭证被拒 / 接口变了）。
    case service(ExternalAPIError)

    /// 展示用文案 key。**原始错误一概不进 UI**（诊断细节走 `diagnosticDetail`）。
    var messageKey: String {
        switch self {
        case .invalidInput: "account.linkError.invalidInput"
        case .staleCallback: "account.linkError.staleCallback"
        case .service(let error): error.messageKey
        }
    }

    /// 是否值得让用户直接重试（网络抖动 / 5xx / 限流）。
    var isRetryable: Bool {
        if case .service(let error) = self { return error.isRetryable }
        return false
    }
}

/// 绑定一个外部账号：**登录 → 换凭证 → 解析身份 → 落 Keychain + 建账号行**。
///
/// 三条纪律，每条都是为了不留下「半成品状态」：
///
/// 1. **凭证最后才写 Keychain**。身份解析用闭包把内存里的凭证直接递给 auth 服务，
///    等确定要落到哪个 `localId` 之后再写。这样永远不会出现「钥匙串里有一条没有归属的
///    凭证」——那种凭证解绑时删不掉（没有账号行就没有 `localId`），会一直躺在那儿。
/// 2. **重复绑定同一个外部账号 = 刷新凭证，不是建第二行**。唯一键是
///    `provider + externalAccountId`；建第二行会让两份记录各有各的 titleId 命名空间，
///    同步时互相看不见，库里凭空多出一整份，而且用户无从分辨该删哪个。
/// 3. **不要求用户把密码交给我们**。Nintendo 走系统登录会话（浏览器里登的是任天堂自己的
///    页面），PSN 走用户从 Sony 自己页面复制的 NPSSO —— 两条路都拿不到、也不需要用户的密码。
@MainActor
enum ExternalAccountBinder {

    /// 绑定（或重新绑定）的结果。`isNew == false` 表示刷新了一个已存在的账号的凭证。
    struct LinkOutcome {
        let account: LinkedAccount
        let isNew: Bool
    }

    // MARK: - Nintendo：系统登录会话 + 手工粘贴兜底

    /// ① 起一个登录请求。UI 拿 `url` 去开 `ASWebAuthenticationSession`，
    ///    `codeVerifier` 必须留在内存里直到回调回来（**不落盘、不进日志**）。
    static func makeNintendoLoginRequest() throws -> NintendoLoginRequest {
        try NintendoAuthService.makeLoginRequest()
    }

    /// ② 用回调完成绑定。
    ///
    /// - Parameter callback: 回调的**原文**（浏览器回跳的完整 URL，或用户手工粘贴的那一串）。
    ///   两条路都走这里 —— 手工粘贴不是「另一套流程」，只是同一个解析器的另一种输入。
    /// - Parameter titleLocale: 用户在添加页选的「标题与封面语言」。**在这里定下来**，
    ///   所以绑定后的第一次同步拿到的就是用户要的语言（而不是先拿一次 App 语言的、再改）。
    static func completeNintendoLogin(callback: String,
                                      request: NintendoLoginRequest,
                                      in context: ModelContext,
                                      language: AppLanguage,
                                      titleLocale: ExternalTitleLocale = .followApp) async throws -> LinkOutcome {
        guard let parsed = NintendoAPI.parseCallback(callback) else {
            throw AccountLinkError.invalidInput
        }
        guard NintendoAuthService.callbackMatches(parsed, request: request) else {
            throw AccountLinkError.staleCallback
        }

        do {
            // 身份解析阶段用一个「拿不到已知会话令牌」的 auth 服务 —— 这一步只做换取，
            // 不读 Keychain（纪律 1）。
            let exchanger = NintendoAuthService(sessionTokenProvider: { nil })
            let sessionToken = try await exchanger.exchangeSessionTokenCode(
                parsed.code, codeVerifier: request.codeVerifier)

            let authorized = NintendoAuthService(sessionTokenProvider: { sessionToken })
            let identity = try await NintendoAccountService(auth: authorized).resolveIdentity()

            let outcome = try resolveAccount(
                provider: .nintendo,
                externalAccountId: identity.externalAccountId,
                displayName: identity.displayName,
                avatarURLString: nil,
                country: identity.country,
                birthday: identity.birthday,
                // 新建账号时先按「用户的选择 + 当前 App 语言」算一个初始值；
                // 之后每次同步都会用**实际成功的那个取值**覆盖它（含回退）。
                sourceLocale: NintendoAuthService.gentryLocale(for: titleLocale,
                                                               appLocaleCode: language.localeCode),
                titleLocale: titleLocale,
                in: context)

            try AccountCredentialStore.set(sessionToken, kind: .nintendoSessionToken,
                                           provider: .nintendo, localId: outcome.account.localId)
            outcome.account.credentialState = .active
            outcome.account.credentialExpiresAt = nil   // 会话 token 无明确到期字段，不编
            try context.save()
            return outcome
        } catch let error as ExternalAPIError {
            throw AccountLinkError.service(error)
        }
    }

    // MARK: - PlayStation：粘贴 NPSSO

    /// 用用户粘贴的 NPSSO 绑定。
    static func linkPlayStation(npsso raw: String, in context: ModelContext,
                                language: AppLanguage,
                                titleLocale: ExternalTitleLocale = .followApp) async throws -> LinkOutcome {
        let npsso = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // 先在当地挡一道：NPSSO 是 64 个 URL-safe 字符。挡在这里的意义不是"校验"，而是
        // 别拿一段明显不是 NPSSO 的东西（比如用户误粘的密码）去撞 Sony 的接口。
        guard npsso.count == 64,
              npsso.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else {
            throw AccountLinkError.invalidInput
        }

        // refresh_token 是在换 access token 的**同一个响应**里给的，而那时身份还没解析出来。
        // 先攒在内存里，等 localId 定了再一次性写（纪律 1）。
        let captured = TokenBox()
        let auth = PSNAuthService(
            npssoProvider: { npsso },
            refreshTokenProvider: { nil },          // 绑定阶段一律走 NPSSO，不去猜已有的 refresh token
            refreshTokenSink: { captured.value = $0 })

        do {
            let identity = try await PSNAccountService(auth: auth).resolveIdentity()
            let outcome = try resolveAccount(
                provider: .playstation,
                externalAccountId: identity.externalAccountId,
                displayName: identity.displayName,
                avatarURLString: identity.avatarURLString,
                country: nil,
                birthday: nil,
                // 与 Nintendo 同一条纪律：`sourceLocale` 记的是「上次实际用于取数的语言」，
                // 绑定这一趟还没取过数，所以留空 —— 它会在第一次同步时被写成
                // `requestedAcceptLanguageLocale(...)` 的结果。空串的另一个含义是「跟随 App 语言」
                //（`ExternalTitleLocale(rawValue:)` 认不出空串，兜底正是 `.followApp`）。
                sourceLocale: "",
                titleLocale: titleLocale,
                in: context)

            try AccountCredentialStore.set(npsso, kind: .psnNPSSO,
                                           provider: .playstation, localId: outcome.account.localId)
            // 重新绑定时旧的 refresh_token 可能是作废了的：先删干净，再按这次的结果写。
            // 留着一条旧 token 的话，下次同步会先拿它去换 —— 白撞一次才落回 NPSSO。
            try AccountCredentialStore.delete(kind: .psnRefreshToken,
                                              provider: .playstation, localId: outcome.account.localId)
            if let token = captured.value, !token.isEmpty {
                try AccountCredentialStore.set(token, kind: .psnRefreshToken,
                                               provider: .playstation, localId: outcome.account.localId)
            }

            outcome.account.credentialState = .active
            // ⚠️ `credentialExpiresAt` 这里**不写**：`PSNIdentity` 不含到期信息，
            //    真正的到期时间要等第一次同步换 token 时才拿到。宁可不显示，也不编一个日期。
            outcome.account.credentialExpiresAt = nil
            try context.save()
            return outcome
        } catch let error as ExternalAPIError {
            throw AccountLinkError.service(error)
        }
    }

    // MARK: - Xbox：粘贴 OpenXBL 的 Personal API Key

    /// 用用户粘贴的 OpenXBL Personal API Key 绑定。
    ///
    /// ⚠️ **格式不做任何校验，因为没有任何可校验的形状**。NPSSO 那边能挡一道「64 个
    /// URL-safe 字符」，是因为那个长度与字符集是实测确定的；OpenXBL 的 key 是一串不透明
    /// 字符串，我们**没有可靠资料**说它长什么样 —— 编一条长度规则出来，最可能的结局是在
    /// 某天误伤一把真 key，而用户完全不知道为什么。所以这里只挡「空的」。
    ///
    /// 真伪交给**服务端**：`resolveIdentity()` 会打一次 `GET /v2/account`，key 不被接受就是
    /// 401 → `.authExpired`，而那时**一个字节都不会写进 Keychain**（纪律 1）。
    /// 这是「验证凭证」最诚实的形式 —— 问服务端，不问自己。
    ///
    /// ⚠️ 与 PlayStation 的又一处结构差异：这里**没有第二个凭证**要接。PSN 要先删掉可能
    /// 已作废的 refresh token 再按这次的结果重写，Xbox 整套鉴权就是这一把 key，
    /// `AccountCredentialStore.set` 本身就是覆盖。
    static func linkXbox(apiKey raw: String, in context: ModelContext,
                         language: AppLanguage,
                         titleLocale: ExternalTitleLocale = .followApp) async throws -> LinkOutcome {
        let apiKey = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { throw AccountLinkError.invalidInput }

        let auth = XboxAuthService(apiKeyProvider: { apiKey })
        do {
            let identity = try await XboxAccountService(auth: auth).resolveIdentity()
            let outcome = try resolveAccount(
                provider: .xbox,
                externalAccountId: identity.externalAccountId,
                displayName: identity.displayName,
                avatarURLString: identity.avatarURLString,
                country: nil,
                birthday: nil,
                // 与 PSN 逐字同一条：绑定这趟还没取过数，所以 `sourceLocale` 留空
                //（空串在 `ExternalTitleLocale(rawValue:)` 里认不出，兜底正是 `.followApp`）。
                // 第一次同步会把它写成 `requestedAcceptLanguageLocale(...)` 的实际结果。
                sourceLocale: "",
                titleLocale: titleLocale,
                in: context)

            try AccountCredentialStore.set(apiKey, kind: .xboxAPIKey,
                                           provider: .xbox, localId: outcome.account.localId)

            outcome.account.credentialState = .active
            // ⚠️ `credentialExpiresAt` **不写**：这个 key 的语义是「长期有效、不轮换」，
            //    服务端也从不回报任何到期信息。宁可不显示，也不编一个日期。
            outcome.account.credentialExpiresAt = nil
            try context.save()
            return outcome
        } catch let error as ExternalAPIError {
            throw AccountLinkError.service(error)
        }
    }

    // MARK: - 解绑

    /// 解绑：**先删凭证，再删账号行**。
    ///
    /// 顺序不能反 —— 账号行一删就再也拿不到它的 `localId`，而 `localId` 是 Keychain 条目的
    /// owner 键，于是凭证会**永久残留**在钥匙串里（用户以为解绑了，其实没有）。
    /// 记录本身随账号级联删除（`LinkedAccount.records` 是 `.cascade`）。
    static func unbind(_ account: LinkedAccount, in context: ModelContext) throws {
        try AccountCredentialStore.deleteAll(provider: account.provider, localId: account.localId)
        context.delete(account)
        try context.save()
    }

    // MARK: - 清空导入数据

    /// 一次「清空该账号导入数据」的结果（给界面做回执）。
    struct PurgeReport: Equatable {
        /// 删掉的来源记录数。
        var deletedRecords = 0
        /// 删掉的、由导入创建且用户没动过的库条目数。
        var deletedGames = 0
        /// **保留**的库条目数（用户在里面写过东西，或那本来就是他自己的游戏）。
        var keptGames = 0
    }

    /// 清空一个账号的**全部导入数据**：先删来源记录，再删「同步替我建的、我还没碰过」的库条目。
    ///
    /// 为什么要有这个动作：beta 3.1 的幂等 bug 让真账号上的每条记录、每个自动建的库条目
    /// 都存了两份（详见 `ImportCoordinator.importRecords` 里那段 save 时机的说明）。
    /// 用户已经决定走「清空后重新同步」这条路，而不是让程序自动去猜哪一份是脏的 ——
    /// 自动删数据不可逆，而这个动作是用户明确点了确认的。
    ///
    /// **删除范围的两条边界**（两条都必须满足才删）：
    ///
    /// 1. **记录**：按 `(provider, externalAccountId)` 匹配，**不看 `account` 关系**。
    ///    必须这样 —— 脏数据里有一整套记录的 `account` 是 nil（孤儿），界面按
    ///    `account?.localId` 过滤，它们在 UI 里完全不可见；只看关系的话它们会永远留在库里。
    /// 2. **库条目**：必须**由导入创建**，且**用户没动过**
    ///    （见 `isPristineImportGame`）。自动匹配会把导入的记录挂到用户自己的游戏上，
    ///    那些游戏的 `createdAt` 早于同步时刻、且多半有用户数据 —— 一条都不能删。
    ///
    /// 保留的条目不会变成孤儿记录：它们的来源记录已经删了，它们就是普通的手动条目。
    /// 用户的下一句多半是「重新同步」，那时它们会被重新匹配上（名字没变的话）。
    ///
    /// ⚠️ 调用方在返回后要按**整库替换**那一套收尾：`ImageDecodeCache.bump()` +
    /// 广播 `libraryReplacedNotification`。这不是可选项 —— 本动作一次删掉几百个条目，
    /// 界面里所有指向它们的 Game 引用（导航栈上的详情页、各种 sheet 的 state）当场变成
    /// 悬空引用，读一下就是 SwiftData fatal（见 `LibraryView.resetNavigationContext` 的说明）。
    @discardableResult
    static func purgeImportedData(_ account: LinkedAccount, in context: ModelContext) throws -> PurgeReport {
        var report = PurgeReport()

        let providerRaw = account.providerRaw
        let externalAccountId = account.externalAccountId
        let records = try context.fetch(FetchDescriptor<ExternalGameRecord>())
            .filter { $0.providerRaw == providerRaw && $0.externalAccountId == externalAccountId }

        // 先收集候选 Game（在删记录之前收集 —— 删完关系就断了）。
        //
        // ⚠️ 一个 Game 可能挂着**不止一条**记录：脏数据里两个导入批次各建了一套记录，
        // 而其中一套会被强键（titleId）自动关联到另一套建出来的那个 Game 上。那时
        // 「哪个 firstSeenAt 算它自己的」不能取先遇到的那条 —— 必须把**全部**时间戳都留着，
        // 只要有一条与 `game.createdAt` 同秒就成立（`ImportCoordinator` 用同一个 `now`
        // 建记录和建库条目，见 `isPristineImportGame`）。
        // 取第一条会漏判：真机上因此留下了一个没被清掉的导入条目。
        var slotByGame: [PersistentIdentifier: Int] = [:]
        var candidates: [(game: Game, firstSeenAts: [Date])] = []
        for record in records {
            guard let game = record.game else { continue }
            let id = game.persistentModelID
            if let index = slotByGame[id] {
                candidates[index].firstSeenAts.append(record.firstSeenAt)
            } else {
                slotByGame[id] = candidates.count
                candidates.append((game, [record.firstSeenAt]))
            }
        }

        for record in records {
            context.delete(record)
            report.deletedRecords += 1
        }

        for candidate in candidates {
            let pristine = candidate.firstSeenAts.contains {
                isPristineImportGame(candidate.game, recordFirstSeenAt: $0)
            }
            if pristine {
                context.delete(candidate.game)
                report.deletedGames += 1
            } else {
                report.keptGames += 1
            }
        }

        try context.save()
        return report
    }

    /// 这个库条目是不是「同步替我建的、我还没碰过」。
    ///
    /// 两道判断，缺一不可：
    ///
    /// ① **来路**：`isAutoCreated`，或者 —— 仅限本次清理 —— 那个 bug 时代留下的指纹。
    ///    `isAutoCreated` 是后加的字段，beta 3.1 建出来的 286 个条目全都没有标记（默认 false）。
    ///    指纹判据是「`game.createdAt` 与某条记录的 `firstSeenAt` 是同一个时刻」——
    ///    这不是巧合而是代码事实：`ImportCoordinator` 用同一个 `now` 建记录和建库条目
    ///    （`makeRecord(now:)` / `makeGame(now:)`），所以由导入创建的游戏必然与它的记录同秒。
    ///    容差 2 秒是为了容忍落库精度，不是为了让范围变宽。
    ///    ⚠️ 用户自己的游戏**不可能**满足它：那些游戏是用户当天建的，而同步发生在绑定那一刻。
    /// ② **有没有用户数据**：通关记录 / 持有 / 分组 / 评价 / 最爱 / 别名 / **用户自己挑的三类图**
    ///    （横向 / 背景 / Logo），以及下面那两组元数据，全都必须是空的。只要沾了一样，
    ///    它就是「用户经手过的条目」，无论来路如何都保留。
    ///
    /// 刻意排除在②之外的只有**竖版 / 方形两个封面槽**：`ImportCoordinator.fetchArtwork`
    /// 自己就会写它们（`:350` 的 `setArtwork(slot, data)`，槽位由图自己的宽高比决定），
    /// 还会把旧版塞错槽的竖版图原地搬进方形槽（`:322`）。所以这两个槽有图**说明不了**
    /// 用户经手过，反而几乎个个自动建条目都有。
    ///
    /// ⚠️ **2026-09-18 修正**：旧判据只排除了竖版槽，把方形槽算成「用户数据」，于是真库里
    /// 5 个僵尸条目一个都清不掉 —— 用户报的「三个地区的人中之龙 0 都绑到我自己那条了，
    /// PS4 库里还有一个人中之龙 0 的僵尸条目」正是其中之一。真库干跑：那 5 个候选
    /// **个个都是「方形槽有图、其余三槽全空」**，没有一个是用户填过图的。
    /// 判据因此与 `ImportCoordinator.isUntouchedAutoArtwork` 对齐（那边本来就只看这三类）。
    ///
    /// 残余风险（明知而接受）：用户在这样一个**已经没有任何来源记录**的自动建条目上
    /// 亲手换过封面，且没设过状态 / 元数据 / 通关 / 持有 / 分组 / 评价 / 别名 —— 那它会被
    /// 当成空壳删掉。用户 2026-09-18 明确要求「不存在这个僵尸条目」，这一档宁可删。
    /// - Parameter recordFirstSeenAt: 一条指向它的来源记录的 `firstSeenAt`。
    ///   **`nil` = 已经没有记录指向它了**（空壳清理那种情形）—— 那时指纹无从谈起，
    ///   只认 `isAutoCreated` 这个硬门，不必伪造一个时间戳去凑指纹。
    private static func isPristineImportGame(_ game: Game, recordFirstSeenAt: Date?) -> Bool {
        let looksAutoCreated: Bool
        if let recordFirstSeenAt {
            looksAutoCreated = game.isAutoCreated
                || abs(game.createdAt.timeIntervalSince(recordFirstSeenAt)) < 2
        } else {
            looksAutoCreated = game.isAutoCreated
        }

        guard looksAutoCreated else { return false }
        guard game.completions.isEmpty, game.copies.isEmpty, game.groups.isEmpty else { return false }
        guard game.reviewTitle.isEmpty, game.reviewBody.isEmpty else { return false }
        guard !game.isFavorite, game.aliases.isEmpty else { return false }
        // 2026-09-17 补的两条「用户经手过」的痕迹。`ImportCoordinator.makeGame` 只写
        // 名字 / 平台 / createdAt / status / 封面，所以下面这些一旦有值就只可能来自用户
        // （`GameMerger` 搬过来的除外 —— 那也是一次用户主动的合并，同样算经手）：
        // - 状态：详情页的状态滑块一动，`.unclassified` 就没了。**这一条同时修掉了旧判据
        //   的一个漏洞** —— 旧版会把「被我设成想玩的导入条目」当空壳删掉，而弹窗文案
        //   承诺的是「写过自己数据的条目一律保留」。
        // - 四个元数据：导入从不写它们，填过就是在编辑页填的。
        guard game.statusValue == .unclassified else { return false }
        guard game.releaseDate == nil, game.developer == nil,
              game.publisher == nil, game.genre == nil else { return false }
        // ⚠️ **竖版与方形两个槽都不算用户经手的证据**（2026-09-18 修正，理由见上面②那段）。
        // 只认横向 / 背景 / Logo 三类 —— 导入从不写它们，用户用过 SteamGridDB 或自己
        // 导入过图才会非空（与 `ImportCoordinator.isUntouchedAutoArtwork` 同一条判据）。
        for kind in ArtworkKind.allCases where kind != .poster && kind != .square {
            guard game.artwork(kind) == nil else { return false }
        }
        return true
    }

    // MARK: - 空壳清理（绑定 / 解绑 / 同步的收尾）

    /// 清掉「导入自动建、现在一条记录都不指向、也没有任何用户数据」的**空壳条目**，
    /// 返回删掉的条数。
    ///
    /// 与 `purgeImportedData` 的关系：那个是**用户显式**清空一个账号；这个是**收尾** ——
    /// 绑定 / 解绑 / 同步把记录改指之后，替导入把地上的碎屑捡掉。
    ///
    /// 病根（用户 2026-09-17 报的「我把 龍が如く２ 合并到库内的 Yakuza 2 了，但库里还有
    /// 龍が如く２」）：`GameMerger.bind` 只把 `record.game` 改指到新条目，**从不回头看旧条目**。
    /// 旧条目若是导入自动建的，就永远留成一个 0 记录、0 用户数据的空壳。另一条同样能造出
    /// 空壳的路径是同步的自动匹配（第 1 次同步建了 A，用户随后手工建了同名条目，第 2 次
    /// 同步把记录改指到用户条目 → A 变空壳），所以兜底做在**全库**这一层，而不是只补 `bind`。
    ///
    /// 三道门缺一不可：
    /// ① `isAutoCreated`（硬门：**用户自己建的条目连考虑都不考虑**）；
    /// ② 全库没有任何记录的 `game` 指向它（遍历**正向**的 `record.game`，不读
    ///    `game.externalRecords` inverse —— 与 `purgeImportedData` / `ImportCoordinator`
    ///    同一条纪律：inverse 在某些写入路径上要等 save 之后才一致）；
    /// ③ `isPristineImportGame(_, recordFirstSeenAt: nil)`。
    ///
    /// ⚠️ 全库遍历（`Game` + `ExternalGameRecord` 各一次 fetch），只在**同步收尾**与
    /// **绑定 / 解绑**这类低频动作里调用，**不进任何视图 body**。
    ///
    /// ⚠️ 调用方在真删到东西之后要按**整库替换**那一套收尾：`ImageDecodeCache.bump()` +
    /// 广播 `libraryReplacedNotification`。这不是可选项 —— 用户完全可能正停在那个空壳的
    /// 详情页上（那条 龍が如く２ 就是这么被发现的），删掉后读一下就是 SwiftData fatal。
    @discardableResult
    static func pruneOrphanImportGames(in context: ModelContext) throws -> Int {
        let records = try context.fetch(FetchDescriptor<ExternalGameRecord>())
        let referenced = Set(records.compactMap { $0.game?.persistentModelID })
        var deleted = 0
        for game in try context.fetch(FetchDescriptor<Game>()) {
            guard game.isAutoCreated, !referenced.contains(game.persistentModelID) else { continue }
            guard isPristineImportGame(game, recordFirstSeenAt: nil) else { continue }
            context.delete(game)
            deleted += 1
        }
        if deleted > 0 { try context.save() }
        return deleted
    }

    /// 单条版本：`game` 已成空壳就删掉它，返回是否删了。
    ///
    /// 判据与 `pruneOrphanImportGames` **逐字同源**（同一个 `isPristineImportGame` + 同一道
    /// 「还有没有记录指向它」），只少了那次 `Game` 全库 fetch —— 绑定 / 解绑时我们**已经知道**
    /// 该检查哪一条，没必要为了它扫全库。记录仍要 fetch 一次：不能只信 `game.externalRecords`
    /// 这个 inverse（同 ② 那条纪律）。
    @discardableResult
    static func pruneIfOrphaned(_ game: Game, in context: ModelContext) throws -> Bool {
        // 纵深守卫：调用方手里的 `game` 可能已经被别处删掉了（读已销毁模型是 fatal）。
        guard game.isLive else { return false }
        let stillReferenced = try context.fetch(FetchDescriptor<ExternalGameRecord>())
            .contains { $0.game?.persistentModelID == game.persistentModelID }
        guard !stillReferenced else { return false }
        guard isPristineImportGame(game, recordFirstSeenAt: nil) else { return false }
        context.delete(game)
        try context.save()
        return true
    }


    // MARK: - 收走「已被游玩记录覆盖」的奖杯记录

    /// 删掉「这个奖杯套已经有主」的那些遗留平台来源记录，返回删掉的条数。
    ///
    /// ## 病根
    ///
    /// 用户 2026-09-18 报的：「个别游戏比如龍が如く０读的不是 title id `CUSA01174` 而是
    /// 奖杯套 id `NPWR07319`」。跨世代共用的奖杯套（`trophyTitlePlatform` = `"PS3,PS4"`）
    /// 在名字匹配失败时会被 `PSNTrophyService` 当成「一个 PS3 游戏」建一条记录 ——
    /// 而它承载的那套奖杯，**本来就有一条 PS4/PS5 记录在承载**。真库取证：`NPWR07319` 的
    /// `1/55` 与 `CUSA01174` 的 `1/55` 是同一套（按 id 取奖杯那条路把 `CUSA01174` 的套
    /// 回报成了 `NPWR07319`，这也是它拿到奖杯的唯一途径 —— 两个名字对不上）。
    /// 于是同一个套在库里表示两次，界面上看起来就是「凭空多了个 PS3 游戏，编号还怪」。
    ///
    /// 建记录的那条规则已经改了（只在该套**无人认领**时才建，见 `PSNTrophyService.finish`
    /// 的规则 ④）。本函数负责把**已经建出来的**收走。
    ///
    /// ## 判据
    ///
    /// 一条，而且是**服务端事实**不是名字像不像：这条记录的 `titleId`（= 奖杯套 id）出现在
    /// 本次同步算出的认领集合里。那个集合来自「按 id 取奖杯」那一路 —— 我们逐条问了每个游玩
    /// 记录的 `npTitleId`，响应里回报的每个套都是那条记录自己的。
    ///
    /// 三道门：
    /// ① **只删本账号的记录**（按 `(provider, externalAccountId)` 匹配，与 `purgeImportedData`
    ///    同一个口径 —— 不看 `account` 关系，孤儿记录也要能被收走）；
    /// ② **只删 `titleId` 在认领集合里的**；集合为空（= 这一轮奖杯没取到）时什么都不做；
    /// ③ **只删遗留平台**（PS3 / PS Vita）的记录。这一条是纵深：奖杯套 id 与 `CUSA…` /
    ///    `PPSA…` 是两个永不相交的命名空间，但万一哪天相交了，也绝不该删掉一条 PS4/PS5 记录
    ///    —— 那才是这个功能存在的意义（它是被覆盖的那一方，不是覆盖别人的那一方）。
    ///
    /// ⚠️ **会删掉用户手工绑定的记录**。真库取证：`NPWR07319 → «Yakuza 0»` 与
    /// `NPWR07057 → «Resident Evil»` 都是用户手工合并/绑定的结果。这是用户 2026-09-18
    /// 明确选择的（在那两条摆在眼前的情况下选了「全清」）—— 理由是那些记录本来就不该存在，
    /// 而它们承载的奖杯在真正的主人那条记录上原样还在。
    /// **调用方必须把条数如实报给用户**（`ExternalSyncResult.supersededRecords`）。
    ///
    /// ⚠️ 调用方在真删到东西之后要按**整库替换**那一套收尾：`ImageDecodeCache.bump()` +
    /// 广播 `libraryReplacedNotification`。删记录会连带把「只靠它支撑的导入条目」变成空壳，
    /// 而那些条目正被界面读着（§54.14）。
    @discardableResult
    static func removeSupersededRecords(titleIds: Set<String>, provider: AccountProvider,
                                        externalAccountId: String,
                                        in context: ModelContext) throws -> Int {
        guard !titleIds.isEmpty else { return 0 }
        let doomed = try context.fetch(FetchDescriptor<ExternalGameRecord>()).filter { record in
            record.providerRaw == provider.rawValue
                && record.externalAccountId == externalAccountId
                && titleIds.contains(record.titleId)
                && PSNTrophyService.isLegacyPlatform(record.platform)
        }
        guard !doomed.isEmpty else { return 0 }
        for record in doomed { context.delete(record) }
        try context.save()
        return doomed.count
    }

    // MARK: - 内部

    /// 找到或新建账号行，并把这次解析到的展示信息刷新上去。
    private static func resolveAccount(provider: AccountProvider, externalAccountId: String,
                                       displayName: String, avatarURLString: String?,
                                       country: String?, birthday: String?,
                                       sourceLocale: String,
                                       titleLocale: ExternalTitleLocale = .followApp,
                                       in context: ModelContext) throws -> LinkOutcome {
        // 在内存里找而不是用 `#Predicate`：账号最多几条，而避免押上「谓词在某些 SwiftData
        // 版本上不支持 UUID/字符串组合等值比较」的风险（与 `ImportCoordinator` 同一取舍）。
        let existing = try context.fetch(FetchDescriptor<LinkedAccount>())
            .first { $0.provider == provider && $0.externalAccountId == externalAccountId }

        if let account = existing {
            account.displayName = displayName
            if let avatarURLString { account.avatarURLString = avatarURLString }
            if let country { account.country = country }
            if let birthday { account.birthday = birthday }
            // ⚠️ 重新绑定时**只更新用户这次在添加页选的语言**，不碰 `sourceLocale`：
            // 后者是「上次同步实际用了什么」，由 `ExternalSyncDriver` 在同步成功时按实况写回。
            // （以前这里只有「原本为空才写」一条规则，因为那时 `sourceLocale` 既是意图又是结果；
            // 现在两者分开了，见 `LinkedAccount.sourceLocale` 的说明。）
            account.titleLocale = titleLocale
            account.lastSyncError = nil
            return LinkOutcome(account: account, isNew: false)
        }

        let account = LinkedAccount(provider: provider,
                                    externalAccountId: externalAccountId,
                                    displayName: displayName,
                                    avatarURLString: avatarURLString,
                                    country: country,
                                    birthday: birthday,
                                    sourceLocale: sourceLocale,
                                    titleLocaleRaw: titleLocale.rawValue)
        context.insert(account)
        return LinkOutcome(account: account, isNew: true)
    }
}

/// 接住 `refreshTokenSink` 递出来的凭证原文的格子。
///
/// 存在的唯一理由见 `ExternalAccountBinder.linkPlayStation`：凭证到手时还不知道要落到哪个
/// `localId`，而闭包是 `@Sendable` 的，抓不住普通的局部 `var`。
/// **它的生命周期只有一个函数调用**，不缓存、不复用、不写日志。
private final class TokenBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?

    var value: String? {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}
