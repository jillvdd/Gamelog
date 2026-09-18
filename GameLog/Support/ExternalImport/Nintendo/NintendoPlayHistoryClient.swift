import Foundation

/// 一次取数的结果。
///
/// **为什么要带上「实际用了哪个 locale」**：请求会按 `(bearer, locale)` 试最多四个组合
/// （见 `fetchRecords`），而失败的组合恰好就是「`Gentry-Locale` 取值不被接受」这种
/// 用户看得见后果的情况 —— 用户选了繁體中文、拿回来的却是英文标题，如果客户端不说是回退
/// 造成的，他只会以为这个功能坏了或者自己选错了。把结果带出去，界面才能明说。
struct NintendoPlayHistoryFetch {
    let records: [ExternalGameRecordDTO]
    /// 真正拿到数据的那次请求用的 `Gentry-Locale`。
    let usedLocale: String
    /// 请求方原本要的 locale。
    let requestedLocale: String

    /// 是否发生了语言回退（请求值没被接受，换了别的取值才成功）。
    var didFallBackLocale: Bool { usedLocale != requestedLocale }
}

/// 拉取并解析 znej Play Activity，产出 provider 无关的 `ExternalGameRecordDTO`。
///
/// 职责边界：**本层只做「取回来 + 解析 + 合并」**，不碰 SwiftData、不判断要不要建库。
/// 入库策略（幂等、匹配、忽略、建库）全在 `ImportCoordinator` —— 那是两家 provider 共用的部分，
/// 不该在任天堂这一侧再写一遍。
struct NintendoPlayHistoryClient {
    private let http: ExternalHTTPClient
    private let auth: NintendoAuthService
    /// 本次请求要用的标题语言（由 `ExternalSyncDriver` 按账号的选择算出来）。
    private let locale: String

    init(auth: NintendoAuthService, locale: String, http: ExternalHTTPClient? = nil) {
        self.auth = auth
        self.locale = locale
        self.http = http ?? ExternalHTTPClient(
            defaultHeaders: [
                "User-Agent": NintendoAPI.userAgent,
                "Accept": "application/json",
            ],
            timeout: NintendoAPI.timeout
        )
    }

    // MARK: - 取数据

    /// 取回该账号的全部游玩记录。
    ///
    /// **一次请求覆盖全账号，没有分页**（一手源注释：不同于其他商店，任天堂不按 title 计费）。
    /// 所以这里没有「翻页循环」这种东西，也不需要 `totalItemCount` 之类的对齐。
    ///
    /// ## 两遍：主 locale，然后（只在必要时）同语言的其它区域写法
    ///
    /// 真账号实测证明**`Gentry-Locale` 的取值直接决定标题覆盖率**：`zh-CN` 几乎全部回落成
    /// 英文，`zh-TW` 有 41% 拿到繁體中文，而两次请求都是成功的。回落是**逐条**发生的、
    /// 响应里没有任何字段说明它发生了 —— 所以只能靠 `TitleScript` 看标题本身。
    ///
    /// 于是第二遍的触发条件与作用域都很窄：**主值没把目标语言吃满时**才发，**只用来改进
    /// 标题名与跟着名字走的那张图**（见 `mergeNames`），失败一律吞掉。主值那份永远是数据的权威。
    func fetchRecords() async throws -> NintendoPlayHistoryFetch {
        let credentials = try await auth.validCredentials()

        // ① 主 locale：走完整的 (bearer, locale) 梯子，这一遍决定这次同步成不成功。
        let primary = try await fetchWithLadder(credentials: credentials, locale: locale)
        var entries = primary.history.playHistories ?? []

        // ② 同语言的其它区域写法。**只在「主值用的就是我们要的语言」且「还有条目没落到
        //    目标语言上」时才发** —— 整体回退过（`primary.locale != locale`）说明这个语言
        //    的取值被服务端拒了，再问它的孪生写法只会同样被拒；而覆盖满了就没有改进空间。
        if primary.locale == locale, !Self.allTitlesMatchTarget(entries, locale: locale) {
            for alternate in NintendoAuthService.gentryLocaleAlternates(forPrimary: locale) {
                // 候选本身失败不抛：主值已经把数据拿到了，它只是额外的运气。
                guard let history = try? await fetchHistory(bearer: primary.bearer,
                                                             locale: alternate) else { continue }
                Self.mergeNames(from: history, into: &entries, targetLocale: locale)
                if Self.allTitlesMatchTarget(entries, locale: locale) { break }
            }
        }

        return NintendoPlayHistoryFetch(records: Self.records(from: entries),
                                        usedLocale: primary.locale,
                                        requestedLocale: locale)
    }

    /// 按 (bearer, locale) 的梯子试到某一个成功为止，返回成功的那一份与用的是哪个组合。
    ///
    /// 梯子 = **语言候选链 × bearer 候选**，两个维度各自对应一类**具体的**已知失败模式：
    ///   - 语言：链首是本次要的取值（`Gentry-Locale` 的取值是推定出来的，猜错会得到 400），
    ///     往下依次是 `NintendoAuthService.fallbackLocales`（含唯一被实证过的 en-GB）。
    ///   - bearer：access token 优先，其次 id_token —— 一手源实测网关有时只认后者。
    /// 于是最坏情况是 `候选数 × 2` 次请求，最好情况（首次就成功）是 1 次。
    ///
    /// 失败时只在「换个组合确实可能好」的两类错误上继续往下试，其余立刻抛 ——
    /// 网络断了、被限流、响应解析不了，换 bearer 或换语言都不会变好，白试只会拖慢失败反馈。
    private func fetchWithLadder(credentials: NintendoCredentials, locale: String) async throws
        -> (history: NintendoAPI.PlayHistoryResponse, bearer: String, locale: String) {
        // 本次要的取值排第一，其余兜底取值按链序跟上（**去掉重复**：英文档位请求的就是链首）。
        let locales = [locale] + NintendoAuthService.fallbackLocales.filter { $0 != locale }
        var bearers = [credentials.accessToken]
        if let idToken = credentials.idToken, !idToken.isEmpty {
            bearers.append(idToken)
        }
        var attempts: [(bearer: String, locale: String)] = []
        for bearer in bearers {
            for candidate in locales { attempts.append((bearer, candidate)) }
        }

        var lastError = ExternalAPIError.internalFailure("no play history attempt was made")
        for attempt in attempts {
            do {
                let history = try await fetchHistory(bearer: attempt.bearer, locale: attempt.locale)
                return (history, attempt.bearer, attempt.locale)
            } catch let error as ExternalAPIError {
                lastError = error
                guard Self.warrantsAnotherAttempt(error) else { throw error }
            }
        }
        throw lastError
    }

    private func fetchHistory(bearer: String, locale: String) async throws -> NintendoAPI.PlayHistoryResponse {
        guard let url = URL(string: NintendoAPI.playHistoriesEndpoint) else {
            throw ExternalAPIError.internalFailure("bad play history url")
        }
        // `Gentry-Locale` **必带**：不给值任天堂回 400，而不是取默认值。
        let response = try await http.send(method: "GET", url: url, headers: [
            "Authorization": "Bearer \(bearer)",
            NintendoAPI.localeHeader: locale,
        ])
        return try ExternalHTTPClient.decode(NintendoAPI.PlayHistoryResponse.self, from: response.data)
    }

    /// 这个错误换一个 (bearer, locale) 组合是否有意义。
    private static func warrantsAnotherAttempt(_ error: ExternalAPIError) -> Bool {
        switch error {
        case .authExpired, .invalidCredential:
            // 凭证被拒 —— 换 id_token 可能有用。
            true
        case .http(let status):
            // 非 OAuth 形状的 400：最可能是 `Gentry-Locale` 取值不被接受。
            // （OAuth 形状的 400 已在共享层被归成 .authExpired，不会走到这里。）
            status == 400
        case .network, .rateLimited, .server, .apiChanged, .decoding, .internalFailure:
            false
        }
    }

    // MARK: - 语言候选（第二遍）

    /// 这批条目的标题**全部**落在目标语言上了吗 —— 是的话就没有必要再问别的区域写法。
    ///
    /// 只看有名字的条目：与服务层过滤的条件一致（缺 titleId 或缺 titleName 的条目会被
    /// `records(from:)` 丢掉）。否则一条缺名字的条目会让「永远没吃满」恒成立，候选请求
    /// 每轮白发一次。
    ///
    /// **空列表返回 true**：返回空更可能是服务端换了形状，而不是「标题全部没有目标语言」。
    /// 与 `ImportCoordinator` 那条「整批为空不动 `presentInLastSync`」是同一条纪律 ——
    /// 拿一个可疑的输入去触发额外请求，没有任何好处。
    static func allTitlesMatchTarget(_ entries: [NintendoAPI.TitleEntry], locale: String) -> Bool {
        let named = entries.compactMap { entry -> String? in
            guard let name = entry.titleName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { return nil }
            return name
        }
        guard !named.isEmpty else { return true }
        return named.allSatisfy { TitleScript.of($0).matches(localeCode: locale) }
    }

    /// 把候选 locale 那一遍的标题名并进来。**只换名字（和跟着名字走的那张图），
    /// 不新增条目、不改其它字段。**
    ///
    /// - 为什么不整条替换：时长 / 首次与最近游玩这些字段与语言**无关**，两遍拿到的是
    ///   同一份数据；让候选有机会改它们，就等于给「同一批记录有两个可能值」开了一个口子，
    ///   而主值那一份才是我们认定的权威。
    /// - **图标跟着名字一起换**：任天堂的图标是按语言发的（实测：日文名的游戏拿回的就是
    ///   日文版商品图，简体中文名的拿回简体中文图），名字换成了中文而图还是英文那张，
    ///   正是用户 2026-09-16 反馈的「标题是繁體中文、封面是英文」。两者必须成对。
    /// - 为什么不新增候选里多出来的 titleId：主值没返回它，说明它不在这次的目标集合里
    ///   （被用户隐藏的条目、地区差异都可能）。凭空加一条会得到一个没有时长的半条记录 ——
    ///   宁可漏（下次同步它还在），不可乱增。
    /// - 换名条件是**双向**的：只有「当前名不是目标语言」**且**「候选名是目标语言」才换。
    ///   单向（只看候选有名字就换）会让候选的回落结果——英文——把主值刚拿到的中文名冲掉，
    ///   那是把 41% 的覆盖率换成 0%。
    static func mergeNames(from history: NintendoAPI.PlayHistoryResponse,
                           into entries: inout [NintendoAPI.TitleEntry],
                           targetLocale: String) {
        var byTitleId: [String: (name: String, image: String?)] = [:]
        for entry in history.playHistories ?? [] {
            guard let id = entry.titleId, let name = entry.titleName, !name.isEmpty else { continue }
            // 同一 titleId 多条（同一游戏在两台机器上玩）时取第一条：名字在这一组里是一样的。
            if byTitleId[id] == nil { byTitleId[id] = (name, entry.imageUrl) }
        }
        guard !byTitleId.isEmpty else { return }

        entries = entries.map { entry in
            guard let id = entry.titleId,
                  let better = byTitleId[id],
                  let current = entry.titleName,
                  !TitleScript.of(current).matches(localeCode: targetLocale),
                  TitleScript.of(better.name).matches(localeCode: targetLocale) else { return entry }
            var updated = entry
            updated.titleName = better.name
            // 图与名字成对：候选那张图没给就留着主值那张（宁可图不变，也不清空）。
            if let image = better.image, !image.isEmpty { updated.imageUrl = image }
            return updated
        }
    }

    // MARK: - 解析与合并

    /// `playHistories[]` → DTO。响应版入口。
    static func records(from history: NintendoAPI.PlayHistoryResponse) -> [ExternalGameRecordDTO] {
        records(from: history.playHistories ?? [])
    }

    /// `playHistories[]` → DTO。
    ///
    /// **必须按 titleId 合并**：一手源注明「同一游戏在两台机器上玩会返回两条」
    /// （`platform` 与 `deviceType` 各只填一个）。而我们的唯一键是
    /// provider + externalAccountId + titleId —— 不合并的话这两条会自己撞自己。
    ///
    /// 合并规则：
    /// - `playedSeconds` **累加**（两台机器的时长都是真实游玩时间）。
    /// - `firstPlayedAt` 取最早、`lastPlayedAt` 取最晚。
    /// - 图片取第一个非空的（同一 titleId 的图基本一致，没必要做选择）。
    /// - `platform` 由 `Accumulator.platform(titleId:dominant:fallbackPlatform:)` 按三档优先级定
    ///   （titleId 前缀 > 时长占优的机器 > 兜底平台）。缺点是一条记录只存得下一个平台，
    ///   「Switch 和 Switch 2 都玩过」这个信息在库里看不出来 —— 取舍写在那段注释里。
    static func records(from entries: [NintendoAPI.TitleEntry]) -> [ExternalGameRecordDTO] {
        var accumulators: [String: Accumulator] = [:]

        for entry in entries {
            // 缺 id 或缺名字的条目直接跳过：两者都是落库与匹配的必需字段，
            // 半条记录进了库只会变成一条永远匹配不上的孤儿。
            guard let titleId = entry.titleId?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !titleId.isEmpty,
                  let titleName = entry.titleName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !titleName.isEmpty else { continue }

            var accumulator = accumulators[titleId] ?? Accumulator(titleId: titleId, titleName: titleName)
            accumulator.absorb(entry)
            accumulators[titleId] = accumulator
        }

        let fallback = AccountProvider.nintendo.fallbackPlatform
        return accumulators.values
            .map { $0.dto(fallbackPlatform: fallback) }
            // 最近玩过的排前面，其次按时长 —— 与一手源的排序一致，也让输出稳定可断言。
            .sorted { lhs, rhs in
                let left = lhs.lastPlayedAt ?? .distantPast
                let right = rhs.lastPlayedAt ?? .distantPast
                if left != right { return left > right }
                return (lhs.playedSeconds ?? 0) > (rhs.playedSeconds ?? 0)
            }
    }

    /// 一个 titleId 的累计器。
    private struct Accumulator {
        let titleId: String
        var titleName: String
        var imageURLString: String?
        var firstPlayedAt: Date?
        var lastPlayedAt: Date?
        /// 是否见过时长字段。**「没见过」与「是 0」不是一回事** ——
        /// 字段缺失应当落 nil（界面显示「—」），而不是伪装成「玩过 0 秒」。
        var sawPlayedMinutes = false
        var playedMinutes: Double = 0
        /// 按**归一化后**的平台累计时长：归一化后再分桶，`Switch` 与 `Nintendo Switch`
        /// 才不会算成两台机器。
        var minutesByPlatform: [String: Double] = [:]
        var rawPlatform: String?

        init(titleId: String, titleName: String) {
            self.titleId = titleId
            self.titleName = titleName
        }

        mutating func absorb(_ entry: NintendoAPI.TitleEntry) {
            let minutes = max(0, entry.totalPlayedMinutes ?? 0)
            if entry.totalPlayedMinutes != nil {
                sawPlayedMinutes = true
                playedMinutes += minutes
            }

            if let system = entry.system {
                rawPlatform = rawPlatform ?? system
                if let canonical = ExternalPlatformNormalizer.canonical(fromRaw: system) {
                    minutesByPlatform[canonical, default: 0] += minutes
                }
            }

            if let image = entry.imageUrl, !image.isEmpty, imageURLString == nil {
                imageURLString = image
            }
            if let first = NintendoAPI.parseTimestamp(entry.firstPlayedAt) {
                firstPlayedAt = firstPlayedAt.map { min($0, first) } ?? first
            }
            if let last = NintendoAPI.parseTimestamp(entry.lastPlayedAt) {
                lastPlayedAt = lastPlayedAt.map { max($0, last) } ?? last
            }
        }

        func dto(fallbackPlatform: String) -> ExternalGameRecordDTO {
            // 时长占优的机器；一台都认不出来时退到 provider 兜底平台。
            let dominant = minutesByPlatform.max { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value < rhs.value
            }?.key

            return ExternalGameRecordDTO(
                titleId: titleId,
                conceptId: nil,   // 任天堂没有 concept —— PS4/PS5 合并是 PSN 侧才有的概念
                titleName: titleName,
                platform: Self.platform(titleId: titleId,
                                        dominant: dominant,
                                        fallbackPlatform: fallbackPlatform),
                platformRaw: rawPlatform,
                firstPlayedAt: firstPlayedAt,
                lastPlayedAt: lastPlayedAt,
                playedSeconds: sawPlayedMinutes ? Int((playedMinutes * 60).rounded()) : nil,
                playCount: nil,   // 任天堂不提供游玩次数
                imageURLString: imageURLString
            )
        }

        /// 决定这条记录归入哪个平台。**三档优先级，顺序不能反**：
        ///
        /// ① **titleId 前缀**（`NintendoTitleId`）—— 实测下来只有它真的可靠。
        ///    真账号上的 374 条记录**全部**退到了兜底值 `Nintendo Switch`，说明
        ///    `entry.system`（`platform` / `deviceType`）要么是 nil、要么给的是我们认不出来的取值；
        ///    而 titleId 前缀在同一批数据上是 100% 正确的（连图片 CDN 都印证了同一套划分）。
        /// ② **`entry.system` 归一化后的时长占优值** —— 接口哪天真的给了平台，以它为准。
        /// ③ provider 兜底平台 —— 前两档都没有时的最后一道，保证 `platform` 非空。
        ///
        /// ⚠️ ①② 回答的不是同一个问题：前缀说「这个游戏是哪个平台的商品」，
        /// `system` 说「用户在哪台机器上玩的」。同一个 Switch 1 游戏在 Switch 2 上玩，
        /// 两者会不一致 —— 这里取前者，因为平台在库里是一级**筛选**维度，用户要按
        /// 「这个游戏属于哪个平台」筛，而不是按「我最近用哪台机器」。
        /// 取舍的代价写在 `ExternalGameRecordDTO.platform` 上（一条记录只存得下一个平台）。
        static func platform(titleId: String, dominant: String?, fallbackPlatform: String) -> String {
            NintendoTitleId.platform(forTitleId: titleId) ?? dominant ?? fallbackPlatform
        }
    }
}
