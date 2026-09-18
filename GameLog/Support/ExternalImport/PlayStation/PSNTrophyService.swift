import Foundation

/// 拉取 PSN 的**奖杯标题**列表，并把它与游玩记录合并。
///
/// ## 为什么这个服务同时干两件事
///
/// 游玩记录走的 `gamelist/v2` 是 **PS4 / PS5 / PC 专用**的 —— `psn-api` v2.18.1 里
/// `getRecentlyPlayedGames` 的 `categories` 类型就是字面量联合
/// `"ps4_game" | "ps5_native_game"`，`getPurchasedGames` 的文档更是直接写死
/// 「This endpoint returns only PS4 and PS5 games.」。PS3 与 PS Vita 是遗留平台，
/// **加 `categories` 也拿不到**（那条取值列表本身也无一手资料，见 HANDOVER §56）。
///
/// 而奖杯端点 `GET /api/trophy/v1/users/{accountId}/trophyTitles` 是 `psn-api` 里
/// **唯一**会把 `"PS3"` / `"Vita"` 写进 `trophyTitlePlatform` 的端点。于是：
/// 「补全用户账号里的 PS3/Vita 游戏」和「取每个游戏的奖杯数量」是同一份数据的两个用途，
/// 合并进一个服务。
///
/// ## 三个取数口，别再合并回去
///
/// 1. `fetchTrophyTitles()` —— 全量奖杯标题（1~2 次请求）。**PS3/Vita 的唯一来源**，
///    同时给 `merge` 做一遍免费的名字匹配。
/// 2. `attachByName(gamelist:trophies:)` —— 纯内存的第一遍（免费），
///    同时算出「哪些套已经有主」与「谁还没认下」。`finish(_:trophies:byTitleId:)` 收尾。
/// 3. `fetchTrophies(forTitleIds:)` —— 按 `titleId` 精确补（每 5 个 id 1 次请求）。
///    名字匹配**实测过半失败**（`gamelist` 的 name 是商店商品名，不是奖杯套名），
///    所以 3 不是锦上添花，是主力。
///
/// ⚠️ 端点是 **Undocumented / reverse-engineered API**（见 `PSNAPI` 头部），
/// 不是官方 SDK。解析一律宽松。
struct PSNTrophyService {
    private let http: ExternalHTTPClient
    private let auth: PSNAuthService
    private let accountId: String
    /// 与游玩记录用**同一个** `Accept-Language` —— 两边拿回来的名字必须能对上，
    /// 否则名字匹配会大面积失败（见 `merge`）。
    private let acceptLanguage: String?

    init(auth: PSNAuthService, accountId: String, acceptLanguage: String? = nil,
         http: ExternalHTTPClient? = nil) {
        self.auth = auth
        self.accountId = accountId
        self.acceptLanguage = acceptLanguage
        self.http = http ?? ExternalHTTPClient(
            defaultHeaders: ["Accept": "application/json"],
            timeout: PSNAPI.timeout)
    }

    // MARK: - 取数据

    /// 取回该账号的全部奖杯标题（自动翻页）。失败语义与 `PSNGameService` 一致。
    func fetchTrophyTitles() async throws -> [PSNAPI.TrophyTitleEntry] {
        var credentials = try await auth.validCredentials()
        do {
            return try await fetchAllPages(bearer: credentials.accessToken)
        } catch let error as ExternalAPIError where error == .authExpired {
            await auth.invalidate()
            credentials = try await auth.validCredentials()
            return try await fetchAllPages(bearer: credentials.accessToken)
        }
    }

    /// 翻页取全部。收尾条件与 `PSNGameService.fetchAllPages` 同一套（空页 / 原地打转 /
    /// 不满一页 / 收满 / `maxPages` 护栏），理由见那边的注释，不重复。
    private func fetchAllPages(bearer: String) async throws -> [PSNAPI.TrophyTitleEntry] {
        var collected: [PSNAPI.TrophyTitleEntry] = []
        var seen = Set<String>()
        var offset = 0

        for _ in 0..<PSNAPI.maxPages {
            let page = try await fetchPage(bearer: bearer, offset: offset)
            let titles = page.trophyTitles ?? []

            let countBefore = collected.count
            for entry in titles {
                guard let id = Self.usableId(entry), !seen.contains(id) else { continue }
                seen.insert(id)
                collected.append(entry)
            }

            if titles.isEmpty { break }
            if collected.count == countBefore { break }   // 服务端在原地打转
            offset += PSNAPI.trophyPageSize

            let total = Int((page.totalItemCount ?? 0).rounded())
            if total > 0, collected.count >= total { break }
            if total == 0, titles.count < PSNAPI.trophyPageSize { break }
        }
        return collected
    }

    private func fetchPage(bearer: String, offset: Int) async throws -> PSNAPI.TrophyTitlesResponse {
        let url = try PSNAPI.url(
            "\(PSNAPI.trophyBase)/v1/users/\(accountId)/trophyTitles",
            query: [
                "limit": String(PSNAPI.trophyPageSize),
                "offset": String(offset),
            ])
        var headers = ["Authorization": "Bearer \(bearer)"]
        if let acceptLanguage, !acceptLanguage.isEmpty {
            headers["Accept-Language"] = acceptLanguage
        }
        let response = try await http.send(method: "GET", url: url, headers: headers)

        // ⚠️ 与游玩记录同理：先探「HTTP 200 里带 error」再解码，否则那种响应会解成
        //    `trophyTitles: nil` —— 一次「成功但 0 条」的同步，用户完全看不出是出错了。
        if let apiError = PSNAPI.apiError(in: response.data) { throw apiError }

        return try ExternalHTTPClient.decode(PSNAPI.TrophyTitlesResponse.self, from: response.data)
    }

    /// 这条奖杯标题能不能用；能就返回它的 `npCommunicationId`（去重键）。
    /// 与 `PSNGameService.usableTitleId` 同一条纪律：**翻页循环与解析必须用同一个判定**，
    /// 否则计数会把注定被丢的条目也算进去，让翻页提前收尾。
    static func usableId(_ entry: PSNAPI.TrophyTitleEntry) -> String? {
        guard let id = entry.npCommunicationId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !id.isEmpty,
              let name = entry.trophyTitleName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return nil }
        return id
    }

    // MARK: - 按 npTitleId 精确对号

    /// 一个 `npTitleId` 名下取回的奖杯信息。
    ///
    /// 两件事装在一起是因为它们**来自同一个响应**（`titles/trophyTitles?npTitleIds=…`），
    /// 分两次取纯属浪费：进度给展示用，`communicationIds` 给「这个套有没有主」的判定用。
    struct TitleTrophies: Equatable {
        /// 可用于展示的进度（`bestProgress`：取总数最多的一套，隐藏的整套跳过）。
        /// nil = 这个标题名下没有可展示的奖杯套 —— 与「取数失败」是两回事。
        var progress: TrophyProgress?
        /// 这个标题名下**全部**奖杯套的 `npCommunicationId`，**含隐藏的**。
        ///
        /// 隐藏与否不影响归属：用户在奖杯列表里隐藏一个套，那个套仍然是这个标题的。
        /// 这个集合回答的是「这套奖杯是不是已经有主了」—— 见 `finish` 的规则 ③。
        var communicationIds: Set<String>
    }

    /// 用**游玩记录里的 `titleId`** 直接取奖杯，返回 `titleId → 奖杯信息`。
    ///
    /// ## 为什么必须有这一条（而不是只靠 `merge` 的名字匹配）
    ///
    /// `gamelist` 给的 `name` 是**商店商品名**，不是奖杯套名。用户真库实测过这些：
    /// 「双人成行 PS4™ 和 PS5™」（同捆包）、「Devil May Cry 5 Series」（合集）、
    /// 「《使命召唤®》」（带书名号）、「UNCHARTED: The Thief's End」这类**永远**匹配不上
    /// `trophyTitleName`；而 PS4/PS5 同名不同版本（《The Last of Us Part II》在库里三条）
    /// 又会被「匹配不唯一就不贴」的保守规则整组放弃。
    /// **实测：101 条 PS4/PS5 记录里，纯名字匹配只认下 31 条。**
    ///
    /// 这个端点按我们传进去的 npTitleId 分组返回（见 `PSNAPI.TrophyTitlesByIdResponse`），
    /// **一个名字都不看** —— 于是上面那三类全部自然解决。
    ///
    /// ## 代价（知情的）
    ///
    /// 每次最多 5 个 id（`PSNAPI.trophyTitleIdBatchSize`），101 条记录 = 21 次请求。
    /// 原先正是因为这个数才决定不做，现在改主意是因为**名字匹配的一半失败率**远超这 21 次请求
    /// 的代价 —— 而且只对**名字没认下的那些**发（认下的不再问），实测约 14 批。
    /// 请求数与记录数成线性、有确定上界，与 §54 那种「上百张封面下载」不是一个量级。
    ///
    /// ⚠️ 返回的是 `TitleTrophies` 而不是裸进度：同步收尾要靠 `communicationIds` 判定
    /// 「这个套是不是已经有主」（见 `TitleTrophies` 与 `finish`）。
    func fetchTrophies(forTitleIds ids: [String]) async throws -> [String: TitleTrophies] {
        // 去重且保序：同一条记录可能被算进多次（同捆包 SKU 与本体 SKU 各有 titleId，
        // 但归一化后可能重名），重复查询只是白花一个 id 名额。
        var seen = Set<String>()
        let unique = ids.filter { !$0.isEmpty && seen.insert($0).inserted }
        guard !unique.isEmpty else { return [:] }

        var credentials = try await auth.validCredentials()
        do {
            return try await runBatches(unique, bearer: credentials.accessToken)
        } catch let error as ExternalAPIError where error == .authExpired {
            // 与 `fetchTrophyTitles` 同一条纪律：凭证失效只重取一次，不再往上抛。
            await auth.invalidate()
            credentials = try await auth.validCredentials()
            return try await runBatches(unique, bearer: credentials.accessToken)
        }
    }

    /// 分批跑完。
    ///
    /// 批次失败**不整条放弃**：先逐条重试那一批（`fetchIndividually`），拿回几条算几条。
    /// 只有**一条都没拿回来**时才往外抛 —— 那说明这条路整个不通（不是「这些游戏恰好没奖杯」），
    /// 上层据此置 `trophyUnavailable`，否则「奖杯一个都没有」会与「功能没做」长得一样。
    private func runBatches(_ ids: [String], bearer: String) async throws
        -> [String: TitleTrophies] {
        var out: [String: TitleTrophies] = [:]
        var attemptedBatches = 0
        var lastError: Error?

        var index = 0
        while index < ids.count {
            let end = min(index + PSNAPI.trophyTitleIdBatchSize, ids.count)
            let batch = Array(ids[index..<end])
            index = end
            attemptedBatches += 1

            do {
                out.merge(try await fetchBatch(batch, bearer: bearer)) { _, new in new }
            } catch let error as ExternalAPIError where error == .authExpired {
                throw error   // 凭证失效要原样上去触发重取，不能被下面吞掉
            } catch {
                lastError = error
                out.merge(try await fetchIndividually(batch, bearer: bearer)) { _, new in new }
            }
        }

        if attemptedBatches > 0, out.isEmpty, let lastError { throw lastError }
        return out
    }

    /// 一批被拒时逐条重试。
    ///
    /// **为什么需要这一层**：文档写明「查询一个不存在的 titleId 会返回 Resource not found」——
    /// 那是**整批**失败，一个坏 id 会把同批另外 4 个一起带走。逐条重试让坏 id 只损失它自己。
    /// 只在批失败时才走到这里，正常路径一次都不发。
    private func fetchIndividually(_ ids: [String], bearer: String) async throws
        -> [String: TitleTrophies] {
        var out: [String: TitleTrophies] = [:]
        for id in ids {
            do {
                out.merge(try await fetchBatch([id], bearer: bearer)) { _, new in new }
            } catch let error as ExternalAPIError where error == .authExpired {
                throw error
            } catch {
                continue   // 这一个 id 取不到就跳过；「全都没拿到」由 `runBatches` 判定
            }
        }
        return out
    }

    /// 一批（≤5 个 id）的请求。
    private func fetchBatch(_ ids: [String], bearer: String) async throws
        -> [String: TitleTrophies] {
        let url = try PSNAPI.url(
            "\(PSNAPI.trophyBase)/v1/users/\(accountId)/titles/trophyTitles",
            query: ["npTitleIds": ids.joined(separator: ",")])
        var headers = ["Authorization": "Bearer \(bearer)"]
        if let acceptLanguage, !acceptLanguage.isEmpty {
            headers["Accept-Language"] = acceptLanguage
        }
        let response = try await http.send(method: "GET", url: url, headers: headers)

        // 与另外两个取数口同一条：先探「HTTP 200 里带 error」再解码。
        // ⚠️ `psn-api` 自己对**这个**端点恰好没做这步检查（其余端点都做了），别照抄它。
        if let apiError = PSNAPI.apiError(in: response.data) { throw apiError }

        let decoded = try ExternalHTTPClient.decode(
            PSNAPI.TrophyTitlesByIdResponse.self, from: response.data)
        var out: [String: TitleTrophies] = [:]
        for entry in decoded.titles ?? [] {
            guard let id = entry.npTitleId?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !id.isEmpty else { continue }
            // 套 id 全收（含隐藏的）—— 这一份数据同时回答「进度是多少」与「这个套属于谁」，
            // 后者是同步收尾清掉跨世代幽灵记录的唯一依据（见 `finish` 的规则 ③）。
            var communicationIds: Set<String> = []
            for title in entry.trophyTitles ?? [] {
                guard let cid = title.npCommunicationId?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !cid.isEmpty else { continue }
                communicationIds.insert(cid)
            }
            out[id] = TitleTrophies(progress: Self.bestProgress(in: entry.trophyTitles),
                                    communicationIds: communicationIds)
        }
        return out
    }

    /// 一个 npTitleId 下的奖杯进度。
    ///
    /// 取**总数最多**的那一套，而不是数组第一个：顺序在服务端没有承诺，取最大是可复现的
    /// （也挡住「同一 id 带两个奖杯套」这种没有承诺过的情况）。
    /// 隐藏的整套跳过 —— 与 `merge` 对 `hiddenFlag` 的口径一致：隐藏是用户的显式动作。
    static func bestProgress(in entries: [PSNAPI.TrophyTitleEntry]?) -> TrophyProgress? {
        var best: TrophyProgress?
        for entry in entries ?? [] {
            if entry.hiddenFlag == true { continue }
            guard let progress = PSNAPI.trophyProgress(defined: entry.definedTrophies,
                                                       earned: entry.earnedTrophies,
                                                       percent: entry.progress) else { continue }
            // 并列时保留先到的（数组顺序），保证同一份响应得到同一个结果。
            if let current = best, current.definedTotal >= progress.definedTotal { continue }
            best = progress
        }
        return best
    }

    // MARK: - 合并

    /// 第一遍（**免费**）的产物：按名字贴完奖杯之后，两个问题各有一个答案 ——
    /// 「哪些套已经有主」与「谁还没认下」。
    ///
    /// 为什么要把「有主」单独算出来：规则 ③ 建 PS3/Vita 记录的前提是**那个套无主**。
    /// 名字匹配这一遍是免费的（奖杯标题列表本来就得拉），它顺手给出的「有主」信息
    /// 因此不必再去问一次服务端。
    struct NamePass {
        var records: [ExternalGameRecordDTO]
        /// 名字匹配认下的套：它属于 `records` 里的某条记录（同名 + 同平台，唯一命中，
        /// 或者名字对上了但有多条同名无从选择 —— 两种都说明这个套有主）。
        var claimed: Set<String>
        /// 这一遍没贴上奖杯的 gamelist `titleId`，交给按 id 精确对号那一路。
        var unresolved: [String]
    }

    /// 收尾的结果。除了最终记录表，还带出**本次同步算出的认领集合** ——
    /// 同步收尾要用它清掉历史上已经建出来的幽灵记录
    ///（`ExternalAccountBinder.removeSupersededRecords`）。
    struct MergeOutcome {
        var records: [ExternalGameRecordDTO]
        /// 被某条 gamelist 记录认领的奖杯套 id。
        ///
        /// ⚠️ 是**本次同步**的口径：只包含这一轮真的问到的那些（名字匹配的 + 按 id 取回的）。
        /// 拿它当「全库权威」用会漏 —— 只在「刚刚同步完、判据新鲜」这个前提下成立，
        /// 而唯一的调用点正好满足这个前提。
        var claimedTrophySets: Set<String>
    }

    /// 第一遍：按**名字 + 平台**把奖杯贴到已有游玩记录上。
    ///
    /// 规则：只按名字不够 —— PS4 版与 PS5 版是**两个不同的奖杯套**（`CUSA…` / `PPSA…`），
    /// 但 `trophyTitleName` 常常逐字相同。只按名字会把 PS5 那套的进度写到 PS4 那条记录上
    /// —— 数据是错的，而且界面上看不出来。匹配到多条（同名同平台的两条记录）时**一条都不贴**：
    /// 宁可显示「—」，也不要给一个游戏贴一份不知道属于哪一条的进度。
    ///
    /// ⚠️ **这一遍只是「免费的第一遍」**（奖杯标题列表本来就得拉，比对是纯内存计算），
    /// 它认不下的那些由 `fetchTrophies(forTitleIds:)` 按 id 精确补 —— 名字匹配的失败率
    /// 实测过半（`gamelist` 的 name 是商店商品名），**不要**以为走到这里就结束了。
    static func attachByName(gamelist: [ExternalGameRecordDTO],
                             trophies: [PSNAPI.TrophyTitleEntry]) -> NamePass {
        var result = gamelist
        // 归一化名 → 下标。归一化走 `GameLinker` 的那一套（大小写 / 标点 / 全半角），
        // 与「自动关联到已有游戏」同一口径 —— 两处若各用一套，同一个名字会一处能匹配一处不能。
        var indexesByName: [String: [Int]] = [:]
        for (index, dto) in gamelist.enumerated() {
            indexesByName[GameLinker.normalizedTitle(dto.titleName), default: []].append(index)
        }
        var claimed: Set<String> = []

        for entry in trophies {
            guard let titleId = usableId(entry),
                  let name = entry.trophyTitleName?
                      .trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { continue }
            // 隐藏是用户在奖杯列表里的**显式动作**，整条跳过（包括不贴到已有记录）。
            if entry.hiddenFlag == true { continue }

            let platforms = PSNAPI.platforms(forTrophyPlatform: entry.trophyTitlePlatform)
            let progress = PSNAPI.trophyProgress(defined: entry.definedTrophies,
                                                 earned: entry.earnedTrophies,
                                                 percent: entry.progress)

            let matches = (indexesByName[GameLinker.normalizedTitle(name)] ?? []).filter {
                platforms.contains(result[$0].platform)
            }
            guard !matches.isEmpty else { continue }
            // 名字对上了（哪怕对上多条）= 这个套是库里某条游玩记录的，**不是无主的**。
            // 这一步是规则 ③ 的关键输入：跨世代套（`PS3,PS4` 共用）若在这里被认下，
            // 收尾就不会再替它建一条 PS3 记录 —— 否则同一个套会在库里表示两次。
            claimed.insert(titleId)
            // 多条同名同平台时一条都不贴：宁可显示「—」，也不要贴一份不知道属于哪一条的进度。
            if matches.count == 1, let progress { result[matches[0]].trophies = progress }
        }

        // 「还没认下」= 记录里还没有奖杯的那些。**按记录算而不是按套算**：一个套对不上名字，
        // 但它对应的记录可能已经因为别的套（同捆包/合集）贴上了奖杯，那就不必再问。
        let resolved = Set(result.filter { $0.trophies != nil }.map(\.titleId))
        let unresolved = gamelist.map(\.titleId).filter { !resolved.contains($0) }
        return NamePass(records: result, claimed: claimed, unresolved: unresolved)
    }

    /// 收尾：并进按 id 对号那一遍的结果，再补 PS3 / PS Vita 记录。
    ///
    /// 三条规则：
    ///
    /// **① 按 id 的结果只填空白**。第一遍贴上的保持不动 —— 名字 + 平台双重命中的可信度
    /// 不比按 id 差，而且换掉会让「同一份数据两次同步得到不同结果」。
    ///
    /// **② 认领集合 = 两遍的并集**。第一遍给出的是「名字对上的那些套」，第二遍给出的
    /// 是「每条游玩记录自己名下的套」（**含隐藏的** —— 隐藏只影响展示，不影响归属）。
    ///
    /// **③ 只有 `gamelist` 覆盖不到的 PS3 / PS Vita 才新建记录**，`titleId` 用
    /// `npCommunicationId`（形如 `NPWR00845_00`，与 `CUSA…` 不同命名空间，不会自撞）。
    /// 代价是**这批记录没有时长也没有次数**（索尼不提供）—— 界面显示「—」而不是 0。
    ///
    /// ⚠️ **④ 已经被认领的套，一条记录都不建。** 这是 2026-09-18 补的第 4 条，起因是用户
    /// 真账号上的「个别游戏读到的不是 title id `CUSA01174` 而是奖杯套 id `NPWR07319`」：
    /// 跨世代共用的奖杯套（`trophyTitlePlatform` = `"PS3,PS4"`）在名字匹配失败时，
    /// 规则 ③ 会把它当成「一个 PS3 游戏」建一条记录，而同一套奖杯**本来就有一条 PS4 记录
    /// 在承载**（真库取证：`NPWR07319` 的 `1/55` 与 `CUSA01174` 的 `1/55` 是同一套）。
    /// 于是同一个套在库里表示两次，界面上看起来就是「凭空多了一个 PS3 游戏，编号还怪」。
    /// 旧规则（「平台里含 PS4/PS5 就不建」）挡不住它 —— 那样会连「只在 PS3 上玩过、
    /// 但 gamelist 里也有同款 PS4 版」的真记录一起挡掉；而「这个套有没有主」是**服务端事实**，
    /// 精确认领正好只挡掉该挡的。
    static func finish(_ pass: NamePass, trophies: [PSNAPI.TrophyTitleEntry],
                       byTitleId: [String: TitleTrophies]) -> MergeOutcome {
        var result = pass.records
        var claimed = pass.claimed

        for index in result.indices where result[index].trophies == nil {
            result[index].trophies = byTitleId[result[index].titleId]?.progress
        }
        for info in byTitleId.values { claimed.formUnion(info.communicationIds) }

        var knownTitleIds = Set(result.map(\.titleId))
        for entry in trophies {
            guard let titleId = usableId(entry),
                  let name = entry.trophyTitleName?
                      .trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { continue }
            // 隐藏是用户在奖杯列表里的**显式动作**，整条跳过（包括不贴到已有记录）。
            if entry.hiddenFlag == true { continue }
            guard !knownTitleIds.contains(titleId) else { continue }
            // ④ 这个套已经有主 —— 它的奖杯在真正的主人那条记录上，别再表示一次。
            guard !claimed.contains(titleId) else { continue }

            let platforms = PSNAPI.platforms(forTrophyPlatform: entry.trophyTitlePlatform)
            guard let legacy = legacyPlatform(in: platforms) else { continue }

            let progress = PSNAPI.trophyProgress(defined: entry.definedTrophies,
                                                 earned: entry.earnedTrophies,
                                                 percent: entry.progress)
            let icon = entry.trophyTitleIconUrl?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(ExternalGameRecordDTO(
                titleId: titleId,
                titleName: name,
                platform: legacy,
                platformRaw: entry.trophyTitlePlatform,
                firstPlayedAt: nil,
                lastPlayedAt: nil,
                playedSeconds: nil,
                playCount: nil,
                trophies: progress,
                imageURLString: (icon?.isEmpty == false) ? icon : nil))
            knownTitleIds.insert(titleId)
        }
        // 新插进来的 PS3/Vita 条目两个时间都是 nil，重排一次让它们按「最近游玩优先」
        // 落到末尾（用的是 `PSNGameService` 那把唯一的排序，不在这里再写一遍）。
        let sorted = PSNGameService.sortedByRecency(result)
        return MergeOutcome(records: sorted, claimedTrophySets: claimed)
    }

    /// 这组平台里有没有 `gamelist` 覆盖不到的那两个；有就返回第一个。
    ///
    /// 顺序即 `trophyTitlePlatform` 里的书写顺序（`"PS4,PSVITA"` → 先 PS4 后 PS Vita）——
    /// 走到这里说明没有任何一条已存记录匹配上，所以取 PS Vita 是安全的。
    private static func legacyPlatform(in platforms: [String]) -> String? {
        platforms.first(where: isLegacyPlatform)
    }

    /// 这个平台是不是 `gamelist/v2` 覆盖不到的那两个。
    ///
    /// **判定只有这一处**：建记录时（`legacyPlatform(in:)`）与同步收尾清删时
    /// （`ExternalAccountBinder.removeSupersededRecords`）共用它 —— 两处各写一遍字符串，
    /// 就会出现「建的时候算遗留、清的时候不算」（或反过来）。
    static func isLegacyPlatform(_ platform: String) -> Bool {
        platform == "PS3" || platform == "PS Vita"
    }
}
