import Foundation

/// 拉取并解析 PSN 的已玩游戏列表，产出 provider 无关的 `ExternalGameRecordDTO`。
///
/// 职责边界与 `NintendoPlayHistoryClient` 完全一致：**只做「取回来 + 解析」**，
/// 不碰 SwiftData、不判断要不要建库。入库策略（幂等、墓碑、匹配）全在 `ImportCoordinator`。
///
/// ⚠️ 端点是 **Undocumented / reverse-engineered API**（见 `PSNAPI` 头部），
/// 解析一律宽松。
struct PSNGameService {
    private let http: ExternalHTTPClient
    private let auth: PSNAuthService
    /// 要查的 accountId。`"me"` 也是合法取值（服务端认），但入库的唯一键需要真实 ID，
    /// 所以正常路径传的是 `PSNAccountService` 解析出来的那个。
    private let accountId: String
    /// 影响标题语言的 `Accept-Language`（标准 HTTP 头，直接用 App 语言的 BCP-47 标签）。
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

    /// 取回该账号的全部游玩记录（自动翻页）。
    ///
    /// access token 被服务端拒（401/403）时**重取一次**再试：那说明它在「我以为还有效」的
    /// 窗口里失效了（时钟偏差 / 服务端提前作废），重取代价极小，是最可能的原因。
    /// 只重试一次 —— 第二次还拒就是凭证真有问题，该让用户重新绑定，不是继续撞。
    func fetchRecords() async throws -> [ExternalGameRecordDTO] {
        var credentials = try await auth.validCredentials()
        do {
            return try await fetchAllPages(bearer: credentials.accessToken)
        } catch let error as ExternalAPIError where error == .authExpired {
            await auth.invalidate()
            credentials = try await auth.validCredentials()
            return try await fetchAllPages(bearer: credentials.accessToken)
        }
    }

    /// 翻页取全部条目。
    ///
    /// 终止条件四选一，都留着是有意的：`totalItemCount` 是**社区文档抄错过的字段**
    /// （它在 `psn-api` 的类型注释里被写成了「trophy titles 的总数」），不能单独信它；
    /// 空页、「这一页没有一条新记录」、「不满一页」是三个互相独立的收尾信号；
    /// `maxPages` 是最后一道防无限翻的护栏。
    ///
    /// ⚠️ 「这一页没有新记录」那条不是凑数的：服务端如果一直重复返回同一页、
    /// 而 `totalItemCount` 又给了一个偏大的数，前三条**全都不会成立** ——
    /// 没有它就会老老实实翻满 50 页，打 50 次请求。这类「看起来在前进其实没动」的循环
    /// 只有在真的跑起来才看得见，所以用一个不依赖服务端数字的条件兜住。
    private func fetchAllPages(bearer: String) async throws -> [ExternalGameRecordDTO] {
        var collected: [PSNAPI.TitleEntry] = []
        var seenTitleIds = Set<String>()
        var offset = 0

        for _ in 0..<PSNAPI.maxPages {
            let page = try await fetchPage(bearer: bearer, offset: offset)
            let titles = page.titles ?? []

            let countBefore = collected.count
            for entry in titles {
                // 跨页去重：唯一键是 titleId，重复会让同一条记录在库里自撞。
                guard let titleId = Self.usableTitleId(entry),
                      !seenTitleIds.contains(titleId) else { continue }
                seenTitleIds.insert(titleId)
                collected.append(entry)
            }

            if titles.isEmpty { break }
            if collected.count == countBefore { break }   // 服务端在原地打转
            offset += PSNAPI.pageSize

            let total = Int((page.totalItemCount ?? 0).rounded())
            if total > 0, collected.count >= total { break }
            if total == 0, titles.count < PSNAPI.pageSize { break }
        }

        return Self.records(from: collected, fallbackPlatform: AccountProvider.playstation.fallbackPlatform)
    }

    private func fetchPage(bearer: String, offset: Int) async throws -> PSNAPI.PlayedGamesResponse {
        let url = try PSNAPI.url(
            "\(PSNAPI.gameListBase)/\(accountId)/titles",
            query: [
                "limit": String(PSNAPI.pageSize),
                "offset": String(offset),
            ])
        var headers = ["Authorization": "Bearer \(bearer)"]
        if let acceptLanguage, !acceptLanguage.isEmpty {
            headers["Accept-Language"] = acceptLanguage
        }
        let response = try await http.send(method: "GET", url: url, headers: headers)

        // ⚠️ 先探「HTTP 200 里带 error」再解码。不探的话那种响应会解码成 `titles: nil`，
        //    于是「同步成功、0 条记录」—— 用户看到的是「我的账号里没有游戏」，
        //    完全看不出其实是出错了。这是 PSN 侧独有、也最隐蔽的失败形状。
        if let apiError = PSNAPI.apiError(in: response.data) { throw apiError }

        return try ExternalHTTPClient.decode(PSNAPI.PlayedGamesResponse.self, from: response.data)
    }

    // MARK: - 解析

    /// 这条条目能不能变成一条记录；能就返回它的 titleId。
    ///
    /// ⚠️ **翻页循环与解析必须用同一个判定**。两边判得不一样的话，`collected.count` 会把
    /// 注定被丢弃的条目也算进去，于是 `collected.count >= totalItemCount` 提前成立，
    /// 翻页在**还没收满**的时候就停了 —— 表现是「少了几条游戏」，只在大账号上才看得出来。
    /// （不是假想：写成两套判定后，冒烟测试里「4 条里 2 条有效」的桩立刻复现了这个提前收尾。）
    static func usableTitleId(_ entry: PSNAPI.TitleEntry) -> String? {
        guard let titleId = entry.titleId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !titleId.isEmpty,
              let name = entry.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return nil }
        return titleId
    }

    /// `titles[]` → DTO。**一条 titleId 对应一条 DTO，这里不做 concept 合并。**
    ///
    /// 为什么不合并 PS4/PS5 双版本：`conceptId` 是「同一个游戏的不同版本」的合并键，
    /// 而我们的唯一键是 `provider + accountId + titleId` —— 两个版本的 titleId **本来就不同**，
    /// 不会自撞。合并会丢掉「用户其实在 PS5 上也玩过」这个事实，而「两条来源记录 → 一个游戏」
    /// 正是本功能的数据模型（`Game` 是用户的条目，`ExternalGameRecord` 是来源侧的事实）。
    /// 让两条记录都留着、由 `GameLinker` 按 `conceptId` 关联到同一个 `Game`，既不丢信息又能合并。
    ///
    /// （对照 Nintendo 侧：那里**必须**按 titleId 合并，因为同一台游戏机的两台机器会返回
    /// 两条 titleId 完全相同的记录，那才是真会自撞的重复。）
    static func records(from titles: [PSNAPI.TitleEntry],
                        fallbackPlatform: String) -> [ExternalGameRecordDTO] {
        let records = titles.compactMap { entry -> ExternalGameRecordDTO? in
            // 缺 id 或缺名字的条目直接跳过：两者都是落库与匹配的必需字段，
            // 半条记录进了库只会变成一条永远匹配不上的孤儿。
            guard let titleId = Self.usableTitleId(entry),
                  let titleName = entry.displayName?
                      .trimmingCharacters(in: .whitespacesAndNewlines),
                  !titleName.isEmpty else { return nil }

            // 图片优先本地化版本，空则退回原图。
            let image = [entry.localizedImageUrl, entry.imageUrl]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }

            return ExternalGameRecordDTO(
                titleId: titleId,
                conceptId: entry.concept?.id.map(String.init),
                titleName: titleName,
                platform: PSNAPI.platform(forCategory: entry.category) ?? fallbackPlatform,
                platformRaw: entry.category,
                firstPlayedAt: PSNAPI.parseTimestamp(entry.firstPlayedDateTime),
                lastPlayedAt: PSNAPI.parseTimestamp(entry.lastPlayedDateTime),
                playedSeconds: PSNAPI.parseDurationSeconds(entry.playDuration),
                // PS3/Vita 拿不到时长是 Sony 侧的硬缺口，`playedSeconds` 会落 nil（UI 显示「—」），
                // 而 `playCount` 它们照样给 —— 两个字段的可得性互不影响。
                playCount: entry.playCount.map { Int($0.rounded()) },
                imageURLString: image
            )
        }

        return Self.sortedByRecency(records)
    }

    /// 最近玩过的排前面，其次按时长 —— 与 Nintendo / Xbox 同一套排序，输出稳定可断言。
    ///
    /// **实体在 `ExternalGameRecordDTO.sortedByRecency`**（三个 provider 共用一处）。这里只留
    /// PSN 侧的入口名：调用点（本文件的入库路径 + `PSNTrophyService.finish`）已经按这个名字写了，
    /// 改名只会制造无谓的改动面。
    ///
    /// `PSNTrophyService.finish` 也要用它：它往游玩记录里插入了新的 PS3/Vita 条目，
    /// 那些条目两个时间都是 nil，必须重新排一次才会落到末尾 —— 而不是因为「后追加的」落在末尾
    /// （同一件事在两个服务里各写一遍必然漂）。
    static func sortedByRecency(_ records: [ExternalGameRecordDTO]) -> [ExternalGameRecordDTO] {
        ExternalGameRecordDTO.sortedByRecency(records)
    }
}
