import Foundation

/// 拉取并解析 Xbox Live 的已玩游戏列表（经 OpenXBL），产出 provider 无关的 `ExternalGameRecordDTO`。
///
/// 职责边界与 `PSNGameService` / `NintendoPlayHistoryClient` 完全一致：**只做「取回来 + 解析」**，
/// 不碰 SwiftData、不判断要不要建库。入库策略（幂等、墓碑、匹配）全在 `ImportCoordinator`。
///
/// ⚠️ 端点是**第三方中转发来的、且没有公开文档**（见 `XboxAPI` 文件头）。
/// 解析一律宽松。
///
/// ## 两次请求，不是一个
///
/// 游玩记录（`/v2/titles`，一次给全 330 条）与**游玩时长**在两个端点上，而时长只能**批量 POST**
/// 问（逐游戏 GET 要 330 次请求，免费档 150 次/小时，那是可行性问题不是耐心问题）。
/// 所以这里编排两次调用，把结果合成一份 DTO 列表 —— 编排收在本服务内，
/// 是因为「怎么分批问」是这个 provider 的实现细节，不该漏到同步驱动里。
struct XboxGameService {
    private let http: ExternalHTTPClient
    private let auth: XboxAuthService
    /// 要查的 xuid。**不传 `"me"`**：入库的唯一键需要真实 ID。
    private let xuid: String
    /// 影响标题语言的 `Accept-Language`。**实测生效**：同一批 330 条标题里
    /// zh-CN 与 en-US 有 115 条不同、en-US 与 ja-JP 有 127 条不同（2026-09-17）。
    private let acceptLanguage: String?

    init(auth: XboxAuthService, xuid: String, acceptLanguage: String? = nil,
         http: ExternalHTTPClient? = nil) {
        self.auth = auth
        self.xuid = xuid
        self.acceptLanguage = acceptLanguage
        self.http = http ?? ExternalHTTPClient(
            defaultHeaders: ["Accept": "application/json"],
            timeout: XboxAPI.timeout)
    }

    /// 一次取数的结果。
    struct Fetched {
        var records: [ExternalGameRecordDTO]
        /// **时长那一路没取到**（游玩记录本身是拿到的）。
        ///
        /// 单独立一个标志而不是让整次同步失败，与 PSN 侧对奖杯的处理同一条理由：
        /// 为一条辅助数据把 330 条游玩记录一起丢掉是更糟的结果。但**必须说出来** ——
        /// 不说的话用户看到的是满屏「—」，会以为 Xbox 根本不给时长（其实是这次没取到）。
        var playtimeUnavailable: Bool
    }

    // MARK: - 取数据

    func fetch() async throws -> Fetched {
        let apiKey = try await auth.apiKey()

        let titles = try await fetchTitles(apiKey: apiKey)
        let titleIds = titles.compactMap { Self.usableTitleId($0) }

        // 时长取失败**不牵连整次同步**（见 `Fetched.playtimeUnavailable`）。
        // 空字典 = 一条时长都没有，界面显示「—」—— 与「来源不提供」长得一样，
        // 所以那个标志必须一路传到回执里。
        var minutes: [String: Int] = [:]
        var playtimeUnavailable = false
        do {
            minutes = try await fetchMinutes(titleIds: titleIds, apiKey: apiKey)
        } catch {
            playtimeUnavailable = true
        }

        return Fetched(
            records: Self.records(from: titles, minutes: minutes,
                                  fallbackPlatform: AccountProvider.xbox.fallbackPlatform),
            playtimeUnavailable: playtimeUnavailable)
    }

    private func fetchTitles(apiKey: String) async throws -> [XboxAPI.TitleEntry] {
        let response = try await http.send(
            method: "GET",
            url: try XboxAPI.url(XboxAPI.titlesEndpoint),
            headers: XboxAPI.headers(apiKey: apiKey, acceptLanguage: acceptLanguage))
        let content = try XboxAPI.decode(XboxAPI.TitlesResponse.self, from: response.data)
        return content.titles ?? []
    }

    // MARK: - 游玩时长（批量）

    /// 分批问时长，返回 `titleId → 分钟`。
    ///
    /// **只收服务端真的回了 `value` 的那些**：请求里给了的 titleId 若没回、或回了但没有
    /// `value` 键，就是「这条没有时长数据」（实测确认过：把没回的单独再问一次仍然不回，
    /// 所以不是响应条数上限）。落进字典之外 = 那条记录的 `playedSeconds` 是 nil，
    /// **不补 0** —— 「没玩过」与「来源不提供」在界面上必须长得不一样。
    private func fetchMinutes(titleIds: [String], apiKey: String) async throws -> [String: Int] {
        guard !titleIds.isEmpty else { return [:] }

        var out: [String: Int] = [:]
        var index = 0
        while index < titleIds.count {
            let chunk = Array(titleIds[index..<min(index + XboxAPI.statsBatchSize, titleIds.count)])
            index += XboxAPI.statsBatchSize

            let body = XboxAPI.PlayerStatsRequest(
                xuids: [xuid],
                stats: chunk.map { .init(name: Self.minutesPlayedStat, titleId: $0) })
            let encoded: Data
            do {
                encoded = try JSONEncoder().encode(body)
            } catch {
                throw ExternalAPIError.internalFailure("failed to encode xbl stats request")
            }

            let response = try await http.send(
                method: "POST",
                url: try XboxAPI.url(XboxAPI.playerStatsEndpoint),
                headers: XboxAPI.headers(apiKey: apiKey),
                body: encoded,
                contentType: "application/json")
            let content = try XboxAPI.decode(XboxAPI.PlayerStatsResponse.self, from: response.data)

            for collection in content.statlistscollection ?? [] {
                for stat in collection.stats ?? [] {
                    guard stat.name == Self.minutesPlayedStat,
                          let titleId = stat.titleid,
                          let minutes = stat.value?.value else { continue }
                    out[titleId] = minutes
                }
            }
        }
        return out
    }

    /// 统计项名。**实测就是这个字面量**（响应里原样回显），不是猜的。
    private static let minutesPlayedStat = "MinutesPlayed"

    // MARK: - 解析

    /// 这条条目能不能变成一条记录；能就返回它的 titleId。
    ///
    /// 与 PSN 侧同名函数同一条纪律：**翻页/批量与解析必须用同一个判定** ——
    /// 两边判得不一样的话，「有 titleId 的有几条」就会被数错。
    static func usableTitleId(_ entry: XboxAPI.TitleEntry) -> String? {
        guard let titleId = entry.titleId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !titleId.isEmpty,
              let name = entry.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return nil }
        return titleId
    }

    /// `titles[]` → DTO。**一条 titleId 对应一条 DTO。**
    ///
    /// ⚠️ `conceptId` **留 nil**。Xbox 侧有一个 `modernTitleId`，从命名上像是
    /// 「跨世代共用的商品 ID」（PSN 的 `concept.id` 的对位物），但**它的语义没有实测确认过**
    /// —— 而 `conceptId` 是 `GameLinker` 自动把两条记录并到同一个游戏的依据，
    /// 猜错会静默合并两个不同的游戏。所以先不填，等能验证时再说（§63 待验证项）。
    ///
    /// ⚠️ `playCount` 恒为 nil：来源不给这个字段（不是解析失败）。
    static func records(from titles: [XboxAPI.TitleEntry],
                        minutes: [String: Int],
                        fallbackPlatform: String) -> [ExternalGameRecordDTO] {
        let records = titles.compactMap { entry -> ExternalGameRecordDTO? in
            guard let titleId = Self.usableTitleId(entry),
                  let titleName = entry.name?
                      .trimmingCharacters(in: .whitespacesAndNewlines),
                  !titleName.isEmpty else { return nil }

            return ExternalGameRecordDTO(
                titleId: titleId,
                titleName: titleName,
                platform: XboxAPI.platform(forMediaItemType: entry.mediaItemType,
                                           devices: entry.devices) ?? fallbackPlatform,
                platformRaw: XboxAPI.platformRaw(forDevices: entry.devices),
                // 来源不给首次游玩时间（实测 330 条里一个字都没有）—— 留 nil，**不编**。
                firstPlayedAt: nil,
                lastPlayedAt: XboxAPI.parseTimestamp(entry.titleHistory?.lastTimePlayed),
                // 来源给的是**整分钟**，统一换算成秒（与 Nintendo 的 `totalPlayedMinutes` 同一处理）。
                playedSeconds: minutes[titleId].map { $0 * 60 },
                // 成就与 Gamerscore 走**自己的**字段，不是 `trophies`：那是 PSN 的奖杯体系，
                // 两个东西的计数口径完全不同（奖杯分级 vs 成就点数），不能互相折算。
                // 四项都缺 → `AchievementProgress.init?` 返回 nil（= 这条没有成就数据）。
                achievements: AchievementProgress(earned: entry.achievement?.currentAchievements,
                                                  total: entry.achievement?.totalAchievements,
                                                  gamerscoreEarned: entry.achievement?.currentGamerscore,
                                                  gamerscoreTotal: entry.achievement?.totalGamerscore),
                imageURLString: XboxAPI.secureImageURL(entry.displayImage))
        }
        return ExternalGameRecordDTO.sortedByRecency(records)
    }

    /// 最近玩过的排前面，其次按时长 —— 与 Nintendo / PSN 同一套排序，输出稳定可断言。
    ///
    /// 实体在 `ExternalGameRecordDTO.sortedByRecency`（三个 provider 共用一处）。
    /// 这里只留 provider 侧的入口名。
    static func sortedByRecency(_ records: [ExternalGameRecordDTO]) -> [ExternalGameRecordDTO] {
        ExternalGameRecordDTO.sortedByRecency(records)
    }
}
