import Foundation

/// 一次同步里对某条记录的**跳过判决**。
///
/// 三态而不是 `ExternalSkipReason?`：`nil` 表达不了「这一轮判过了、不该跳」与「这一轮根本
/// 判不了」的区别，而这两者在库里的后果正好相反 ——
/// - **判过了、不该跳**：要**清掉**上一轮的跳过标记（用户可能刚在 PC 上玩了那个游戏，
///   或者来源改了数据），下一轮它就该重新参加匹配建库；
/// - **判不了**：必须**原样保留**上一轮的判决。一次网络抖动不该让规则判决翻案 ——
///   清了的话那批记录会当场被重新建库（用户刚清掉的空壳全回来），
///   而下一轮同步再删一遍。这种「同步一次多出几个游戏、再同步一次又没了」的抖动
///   比「多留一条脏记录」糟得多。
///
/// 唯一的 `unknown` 来源是 Xbox 的时长取数失败：那时的 `playedSeconds` 全是 nil，
/// 与「时长真的是 0」在数据上分不开（见 `XboxGameService.records` 的 `playtimeFetched`）。
enum ExternalSkipVerdict: Equatable {
    /// 这一轮判不了 —— **不要动库里已有的判决**。
    case unknown
    /// 这一轮判过了。`.decided(nil)` = 不该跳；`.decided(.xboxPCWithoutPlaytime)` = 该跳。
    case decided(ExternalSkipReason?)

    /// 这一轮**判定了要跳**时的原因；`unknown` 与「判定不跳」都是 nil。
    var skipReason: ExternalSkipReason? {
        guard case .decided(let reason) = self else { return nil }
        return reason
    }

    /// 这一轮压根没做出判决（见本类型说明）。
    var isUnknown: Bool { self == .unknown }
}

/// provider 无关的「一条外部游玩记录」。
///
/// **为什么要有这一层**：两家 provider 的原始结构差得很远（任天堂时长是整分钟且没有 concept，
/// PSN 有 `concept` 与 ISO-8601 时长、还有 PS4/PS5 两个 titleId），但落库只需要下面这一组字段。
/// 差异全部挡在各自的 Service 里，`ImportCoordinator` 只认这个类型 —— 于是「入库策略」
/// （幂等、墓碑、匹配、建库）只写一遍，不会因为多了一家 provider 就分叉。
///
/// 一个 DTO 严格对应**一条**要落库的记录：provider 侧的合并（如任天堂同一游戏在两台机器
/// 各返回一条）在 Service 层就做完，不要漏到协调器 —— 那是 provider 语义，不是入库语义。
struct ExternalGameRecordDTO: Equatable {
    /// 来源侧标题 ID（去重用；**不用于判定「是不是同一个游戏」**，见 `ExternalGameRecord.titleId`）。
    let titleId: String
    /// PSN 的 `concept.id`（PS4/PS5 合并键）；任天堂为 nil。
    var conceptId: String?
    /// 来源侧标题名（原样，不做本地化改写）。
    let titleName: String
    /// 归入的平台（`Presets.platforms` 的 canonical 值）。**非可选** —— 认不出来时由 Service
    /// 兜底到 `provider.fallbackPlatform`，库里不存空平台（空值会让平台筛选漏掉这条）。
    let platform: String
    /// 来源给的**原始**平台字符串，留作「实测校对映射表」用。**不落库**
    ///（落库的是 `ExternalGameRecord.platformRaw`，那个由 Service 自己填）。
    let platformRaw: String?
    /// 版本类型。不传则由标题名启发式判定（`ExternalVersionType.classifyVersion(title:)`）——
    /// 默认值放在这里而不是各 Service 里，是为了两家 provider 的判定口径不可能漂。
    let versionType: ExternalVersionType
    /// **规则判决的**跳过结论（与 `versionType` 是两个维度：那个说「这条是什么」，
    /// 这个说「这条要不要进库」）。见 `ExternalSkipVerdict` 的三态说明。
    ///
    /// 只有 Xbox 会产出非平凡的判决（`xboxPCWithoutPlaytime`：设备里一台主机都没有、
    /// 且游玩时长为 0）。体验版 / 试玩版**不走这里** —— 它们由 `versionType` 派生
    /// （见 `ExternalSkipReason`），把同一件事存两处迟早漂。
    ///
    /// 为什么判决必须**在取数层**做完再传下来、而不是入库时现算：判据里有一条是
    /// 「这一轮时长取数成功了」，那件事只有 `XboxGameService` 知道。落到库里
    /// （`playedSeconds == nil`）之后，「取数失败」与「时长确实是 0」再也分不开。
    let skipVerdict: ExternalSkipVerdict

    let firstPlayedAt: Date?
    let lastPlayedAt: Date?
    /// 累计游玩秒数（**统一换算成秒**）。
    let playedSeconds: Int?
    /// 游玩次数（任天堂不提供，恒为 nil）。
    let playCount: Int?
    /// 奖杯进度。**仅 PSN 提供**（Nintendo 没有奖杯体系），且只有匹配上奖杯套的标题才有。
    /// `var` 而不是 `let`：奖杯来自**另一个端点**，由 `PSNTrophyService.attachByName` 在
    /// gamelist 记录取回之后贴上来 —— 这是本类型里唯一一个二次写入的字段。
    var trophies: TrophyProgress?
    /// 成就进度。**仅 Xbox 提供**（成就数与 Gamerscore 是微软那套体系，与奖杯不能互相折算）。
    /// 与 `trophies` 不同，它是 `let`：成就就在 `/v2/titles` 那**同一条响应**里，
    /// 没有「另一个端点后贴上来」这回事。
    let achievements: AchievementProgress?
    let imageURLString: String?

    init(titleId: String,
         conceptId: String? = nil,
         titleName: String,
         platform: String,
         platformRaw: String? = nil,
         versionType: ExternalVersionType? = nil,
         skipVerdict: ExternalSkipVerdict = .decided(nil),
         firstPlayedAt: Date? = nil,
         lastPlayedAt: Date? = nil,
         playedSeconds: Int? = nil,
         playCount: Int? = nil,
         trophies: TrophyProgress? = nil,
         achievements: AchievementProgress? = nil,
         imageURLString: String? = nil) {
        self.titleId = titleId
        self.conceptId = conceptId
        self.titleName = titleName
        self.platform = platform
        self.platformRaw = platformRaw
        let achTotal = achievements?.total ?? trophies?.definedTotal
        self.versionType = versionType ?? ExternalVersionType.classifyVersion(title: titleName, achievementTotal: achTotal, platform: platform)
        self.skipVerdict = skipVerdict
        self.firstPlayedAt = firstPlayedAt
        self.lastPlayedAt = lastPlayedAt
        // 负数时长只可能是解析出了 bug。宁可当「没有这个数」（界面显示「—」）也不要让它落库 ——
        // 负值会污染统计，而且事后没人分得清它是来源的错还是我们算错。
        self.playedSeconds = playedSeconds.flatMap { $0 >= 0 ? $0 : nil }
        self.playCount = playCount.flatMap { $0 >= 0 ? $0 : nil }
        self.trophies = trophies
        self.achievements = achievements
        self.imageURLString = imageURLString
    }
}

extension ExternalGameRecordDTO {
    /// 最近玩过的排前面，其次按时长。
    ///
    /// **三个 provider 共用这一处**：排序口径漂了的表现是「同一个游戏在 PSN 记录里排第 3、
    /// 在 Xbox 记录里排第 7」，用户看得见但查不出原因。放这里而不是各 Service 里，
    /// 是因为所有 Service 的产出都是这个类型 —— 它是这条规则唯一不会漏掉的家。
    ///
    /// 两个时间都 nil 的条目落末尾（`distantPast`），而不是「保持原顺序」——
    /// 显式排一次，输出才稳定可断言（PSN 那边靠它把后插入的 PS3/Vita 条目送下去）。
    static func sortedByRecency(_ records: [ExternalGameRecordDTO]) -> [ExternalGameRecordDTO] {
        records.sorted { lhs, rhs in
            let left = lhs.lastPlayedAt ?? .distantPast
            let right = rhs.lastPlayedAt ?? .distantPast
            if left != right { return left > right }
            return (lhs.playedSeconds ?? 0) > (rhs.playedSeconds ?? 0)
        }
    }
}

/// 来源给的原始平台字符串 → `Presets.platforms` 的 canonical 值。
///
/// **为什么两家 provider 共用**：任天堂的 `platform`/`deviceType` 与 PSN 的 `category`
/// 是同一件事（「这条记录属于哪台机器」），映射表各写一份必然漂 —— 而平台是游戏库的
/// 一级筛选维度，漂了就是同一个平台在库里出现两种写法。
///
/// ⚠️ **PSN 与 Xbox 的真实取值已经实测过了**（PSN 的 `category` 见 `PSNAPI.platform(forCategory:)`，
/// Xbox 的 `devices` 见 `XboxAPI.platform(forDevices:)` —— 两家各自有一张显式表处理紧凑写法，
/// 认不出来才落到这里）。任天堂侧仍未实测。
/// 所以这里的策略是**保守**：精确匹配（预设值本身 + 少量别名）→ 关键词包含匹配 →
/// **都认不出来就返回 nil**，由调用方落 `provider.fallbackPlatform`。
/// 宁可退到兜底，也不要靠猜把 PS5 的游戏记成 PS4。
enum ExternalPlatformNormalizer {
    /// 精确匹配表：`Presets.platforms` 全部预设值 + 别名。
    private static let table: [String: String] = {
        var map: [String: String] = [:]
        // 预设值自己就是 canonical（先把它们全部登记，别名不会覆盖既有键）。
        for platform in Presets.platforms where map[key(platform)] == nil {
            map[key(platform)] = platform
        }
        // 别名：provider 侧常见的写法差异 / 预设里没有的旧称。
        // 「Switch」是平台改名前的旧名（历史数据里就是它），别名表里保留映射。
        let aliases: [String: String] = [
            "Switch": "Nintendo Switch",
            "Switch 2": "Nintendo Switch 2",
            // 任天堂硬件代号（Play Activity API 返回的 platform / deviceType）：
            // HAC = Handheld Audio Console (Switch 1)
            // BEE = Bumblebee / Beedle (Switch 2)
            // WUP = Wii U Project (Wii U)
            "BEE": "Nintendo Switch 2",
            "HAC": "Nintendo Switch",
            "WUP": "Wii U",
            "PlayStation 5": "PS5",
            "PlayStation 4": "PS4",
            "PlayStation 3": "PS3",
            "PlayStation Vita": "PS Vita",
            "PlayStation Portable": "PSP",
            "Nintendo 3DS": "3DS",
            // Xbox 侧实测来的两个紧凑写法（2026-09-18，330 条 `devices` 取值）。
            // 其余三种（`XboxOne` / `Xbox360` / `PC`）归一化后本来就命中预设值，
            // 只有这两个对不上：`xboxseries` ≠ `key("Xbox Series X|S")` = `xboxseriess`，
            // 而 `win32` 在预设里根本没有对位物。
            "XboxSeries": "Xbox Series X|S",
            "Win32": "PC",
        ]
        for (alias, platform) in aliases where map[key(alias)] == nil {
            map[key(alias)] = platform
        }
        return map
    }()

    /// 关键词包含匹配（精确匹配失败后的第二档）。**顺序有意义**：
    /// 「switch 2」必须排在「switch」前面，否则 Switch 2 会被吞成 Switch。
    /// 归一化后的字符串已无空格与标点，所以这里写的是紧凑形式。
    private static let containsPatterns: [(needle: String, platform: String)] = [
        ("switch2", "Nintendo Switch 2"),
        ("switch", "Nintendo Switch"),
        ("playstation5", "PS5"),
        ("ps5", "PS5"),
        ("playstation4", "PS4"),
        ("ps4", "PS4"),
        ("playstation3", "PS3"),
        ("ps3", "PS3"),
        ("playstationvita", "PS Vita"),
        ("psvita", "PS Vita"),
        ("playstationportable", "PSP"),
    ]

    /// 归一化键：小写 + 去掉所有非字母数字字符。
    /// 这样 "Nintendo Switch 2" / "nintendo-switch-2" / "NintendoSwitch2" 是同一个键。
    private static func key(_ raw: String) -> String {
        var out = ""
        for scalar in raw.lowercased().unicodeScalars
        where CharacterSet.alphanumerics.contains(scalar) {
            out.unicodeScalars.append(scalar)
        }
        return out
    }

    /// 认不出来返回 nil（**不是**返回「其他」—— 「其他」是个正经预设值，不该被我们占用）。
    static func canonical(fromRaw raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = key(trimmed)
        if let exact = table[normalized] { return exact }
        return containsPatterns.first { normalized.contains($0.needle) }?.platform
    }

    /// 认不出来就落兜底值。**入库路径一律走这个**（保证 `platform` 非空）。
    static func resolve(raw: String?, fallback: String) -> String {
        canonical(fromRaw: raw) ?? fallback
    }
}
