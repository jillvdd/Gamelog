import Foundation
import SwiftData

// MARK: - 外部记录的枚举

/// 外部记录的版本类型（完整版 / 体验版）。
/// 两个 provider 都不直接给这个字段，按标题名启发式判定（`ExternalVersionType.classifyVersion(title:)`）；
/// 判不出来就留 `.unknown`，**不猜**（猜错会让体验版混进游戏库）。
enum ExternalVersionType: String, CaseIterable, Identifiable, LabelKeyed {
    case full
    case demo
    case trial
    case unknown

    var id: String { rawValue }
    var labelKey: String { "account.version.\(rawValue)" }

    /// 是否默认**不**参与自动建库（体验版/试玩版默认只记录、不建游戏）。
    var isExcludedByDefault: Bool { self == .demo || self == .trial }

    /// 按标题名启发式判定版本类型（两个 provider 都不给这个字段）。
    /// 命中体验版关键词才判 demo，否则 `.full`；空标题留 `.unknown`。
    ///
    /// 放在枚举上而不是 `ExternalGameRecord` 上，是为了让 provider 无关的 DTO 层
    /// （`ExternalGameRecordDTO`）能直接调用它 —— 网络/解析层不该依赖 SwiftData 模型类。
    ///
    /// **两类关键词的匹配方式不同，这不是随手写的**：
    /// - 日文关键词（体験版/試遊版…）没有词边界，只能子串匹配。
    /// - 拉丁关键词**必须整词匹配**。子串匹配会把 `Demon's Souls`（含 `demo`）判成体验版，
    ///   而体验版默认不进游戏库 —— 一个正常游戏静默消失，且几乎不可能联想到原因。
    ///   分词只保留 `[a-z0-9]`，于是 `demo版` → `["demo"]`（仍命中），
    ///   `Demon's Souls` → `["demon","s","souls"]`（不命中）。
    static func classifyVersion(title: String) -> ExternalVersionType {
        let lowered = title.lowercased()
        guard !lowered.isEmpty else { return .unknown }

        let japaneseKeywords = ["体験版", "体験会", "試遊版", "試玩版", "试玩版", "体验版", "序章体验"]
        if japaneseKeywords.contains(where: { lowered.contains($0) }) { return .demo }

        // 拉丁词：只留 [a-z0-9]，其余（空格、撇号、假名、汉字…）一律当分隔符。
        var latin = ""
        for scalar in lowered.unicodeScalars {
            let isLatinLetterOrDigit = (scalar.value >= 97 && scalar.value <= 122)   // a-z
                || (scalar.value >= 48 && scalar.value <= 57)                        // 0-9
            if isLatinLetterOrDigit { latin.unicodeScalars.append(scalar) }
            else { latin.append(" ") }
        }
        // 前后补空格，好把「整词」判定写成子串判定。` demo ` 同时覆盖 `Demo Version`。
        let padded = " " + latin.split(separator: " ").joined(separator: " ") + " "
        return (padded.contains(" demo ") || padded.contains(" trial version ")) ? .demo : .full
    }
}

/// 一条外部记录**不进游戏库**的原因。
///
/// 存在的理由：跳过这件事此前在库里**没有痕迹**。体验版/试玩版是靠 `versionType` 现算的，
/// 而 2026-09-18 加的 Xbox 规则（「设备里没有主机 + 游玩时长 0」→ 不导入，见
/// `XboxGameService`）**没法事后重算** —— 「这一轮没取到时长」与「真的没玩过」在库里
/// 长得一模一样（都是 `playedSeconds == nil`），拿库里的状态反推会把整轮时长取数失败
/// 误判成跳过。所以判定必须**落盘**（`ExternalGameRecord.skipReasonRaw`），落在
/// 「知道这一轮取数成没成」的那一刻。
///
/// ⚠️ **落盘的只有 `xboxPCWithoutPlaytime` 这一档**，体验版那两个 case 是 `versionType`
/// 的派生（见 `skipReason`）—— 同一个事实存两处迟早漂，而 `versionType` 本来就落库了。
enum ExternalSkipReason: String, LabelKeyed {
    /// 来源侧只有一个 PC/Win32 设备、且这一轮的游玩时长是 0。
    /// 判据与闸门见 `XboxGameService.records(from:minutes:fallbackPlatform:playtimeFetched:)`。
    case xboxPCWithoutPlaytime = "xboxPC"
    /// 体验版（派生自 `versionType`，不落库）。
    case demoVersion = "demo"
    /// 试玩版（派生自 `versionType`，不落库）。
    case trialVersion = "trial"

    /// 展示文案。体验版那两档**复用 `account.version.*`**（`ExternalVersionType` 的 key）——
    /// 那两句文案说的是版本性质，本来就只有一处该归属，重写一遍必然与版本标签长得不一样。
    var labelKey: String {
        switch self {
        case .xboxPCWithoutPlaytime: "account.skip.xboxPC"
        case .demoVersion: ExternalVersionType.demo.labelKey
        case .trialVersion: ExternalVersionType.trial.labelKey
        }
    }
}

/// 外部记录与 Game 的关联状态。
///
/// ⚠️ 2026-09-16 起已废弃、**不再被任何代码引用**（枚举本身留在这里只为让 `matchStateRaw`
/// 的注释有处可指，下一版连同字段一起删）。
///
/// 它要表达的区别 —— 「这条是我自己绑的，还是同步替我绑的」—— **库里不存**。两个理由：
/// ① 真正决定行为的是「绑没绑上」（`record.game != nil`），不是「怎么绑上的」：已经绑上的记录
///    自动逻辑一律不碰，所以手动绑定天然不会被下一轮同步改写，不需要一个标记来保护它；
/// ② 这个区别对用户没有任何意义，不该出现在界面上（它原本的三条 L10n 文案从写下那天起
///    就没有被任何视图引用过）。
enum ExternalMatchState: String, CaseIterable, Identifiable, LabelKeyed {
    /// 未关联任何 Game（等待用户绑定，或已被自动墓碑跳过）。
    case unmatched
    /// 同步时自动关联（命中 titleId / conceptId / 归一化同名）。
    case auto
    /// 用户手动绑定或合并产生的关联（不会被自动逻辑改写）。
    case manual

    var id: String { rawValue }
    var labelKey: String { "account.match.\(rawValue)" }
}

// MARK: - 外部记录模型

/// 一条来自外部账号的游玩记录（Nintendo / PSN / Xbox 各一条）。
///
/// **为什么不把外部数据直接写进 `Game`**：同一个游戏可以同时出现在
/// Nintendo Account 1、Nintendo Account 2、PSN —— 每个来源各有自己的首次游玩、最近游玩、
/// 时长。这是「一条 Game 对多条来源记录」的结构，写进 Game 会互相覆盖。
/// 所以：`Game` 是用户的游戏条目，`ExternalGameRecord` 是来源侧的事实，两者用可绑定的关系连接。
///
/// **唯一键 = `provider` + `externalAccountId` + `titleId`**（三个字段都存下来，查询时不必
/// 穿过关系；三者在创建后都不再变化，无漂移风险）。同步幂等就靠它去重，重复同步不产生重复记录。
///
/// 映射关系（详见 HANDOVER §53）：
/// - Nintendo（znej Play Activity）：`titleId` = `titleId`，`titleName` = `titleName`，
///   `platform`/`deviceType` → 平台，`firstPlayedAt`/`lastPlayedAt` = 同名字段，
///   `playedSeconds` = `totalPlayedMinutes` × 60（**来源精度是整分钟**），
///   图片 = `imageUrl`（官方 CDN）。⚠️ `playCount` 来源不提供，恒为 nil。
/// - PlayStation（gamelist/v2）：`titleId` = `titleId`（如 `CUSA01433_00` / `PPSA07950_00`），
///   `conceptId` = `concept.id`（**PS4/PS5 双版本合并键**），`firstPlayedAt` = `firstPlayedDateTime`，
///   `lastPlayedAt` = `lastPlayedDateTime`，`playedSeconds` = `playDuration` 解析值，
///   图片 = `imageUrl`（官方 CDN，支持 `?w=` 缩图）。
/// - Xbox（**经 OpenXBL 的** titlehub 等价物）：`titleId` = `titleId`（十进制串，如 `2131196662`），
///   `platform`/`platformRaw` = `devices`（**可用平台列表**，见 `XboxAPI.platform(forDevices:)`），
///   `lastPlayedAt` = `titleHistory.lastTimePlayed`，`playedSeconds` = `MinutesPlayed` × 60
///   （另取一趟 `POST /v2/player/stats`），成就四项 = `achievement`（见 `achievements`），
///   图片 = `displayImage`（`store-images`，**来源给的是 http，须升级 scheme**）。
///   ⚠️ `firstPlayedAt` / `playCount` / `conceptId` 来源不给，恒为 nil（**不编**）。
@Model
final class ExternalGameRecord {
    /// provider（`AccountProvider.rawValue`）—— 唯一键第 1 段。
    var providerRaw: String
    /// 外部账号 ID —— 唯一键第 2 段。
    var externalAccountId: String
    /// 来源侧标题 ID —— 唯一键第 3 段。
    /// Nintendo 形如 `0100000000010000`；PSN 形如 `CUSA01433_00`（PS4）/ `PPSA07950_00`（PS5）。
    /// ⚠️ 不同 titleId **不等于**不同游戏（PS4/PS5 双版本、地区变体各是一个 titleId），
    /// 所以 titleId 只用于去重，不用于判定「是不是同一个游戏」。
    var titleId: String
    /// PSN 的 `concept.id`（一个游戏所有版本的共同 ID，官方给出的合并依据）；Nintendo 为 nil。
    var conceptId: String?

    /// 来源侧标题名（原样保存，不做本地化改写；匹配时归一化另算）。
    var titleName: String
    /// 归入的平台（`Presets.platforms` 的 canonical 值）。
    var platform: String
    /// 来源给的**原始**平台字符串。
    ///
    /// 落库而不是丢掉，是因为它是**唯一能校对映射表的证据**：Nintendo 的 `platform` /
    /// `deviceType` 与 PSN 的 `category` 的真实取值字符串从未实测过（见 HANDOVER §53），
    /// 而 `ExternalPlatformNormalizer` 的别名表是照着公开命名习惯预置的。
    /// 不落库 → 永远只能看到「归一化后的结果」，认错成什么都无从发现；落库 → 下次同步就能
    /// 拿着真实取值把表改对，或者确认这段映射根本用不上、该删。
    var platformRaw: String?
    /// 版本类型。
    var versionTypeRaw: String = ExternalVersionType.unknown.rawValue

    /// **规则判决**的落库值：来源事实判定「这条不该进游戏库」时写下原因（nil = 没被规则跳过）。
    ///
    /// 与 `isIgnored` 是**两件事，刻意分成两个字段**：那个是**用户的意图**（「这条我不要了」，
    /// 可在记录面板撤销），这个是**来源事实的判决**（「这个标题只跑得在 PC 上、而且一分钟都
    /// 没玩过」，用户撤销不了，但可以手动把记录绑到某个条目上让它进库）。混成一个字段的话，
    /// 下一轮同步要么把用户的忽略覆盖掉，要么把判决丢掉 —— 两者都是错的。
    ///
    /// 落库而不是每次现算：**「这一轮没取到游玩时长」与「真的没玩过」在库里长得一样**
    ///（都是 `playedSeconds == nil`），重算会把一次网络抖动升级成「整批记录被判跳过」。
    /// 写入时机只有一处（`ImportCoordinator.refresh`），那里知道取数成没成。
    ///
    /// ⚠️ 只有规则比 `versionType` 更细的那一档需要它（`xboxPCWithoutPlaytime`）；
    /// 体验版/试玩版由 `skipReason` 从 `versionType` 派生，本字段对它们是 nil。
    var skipReasonRaw: String?

    /// 首次游玩时间（两家来源都给；解析不出则为 nil —— **缺失是正常情况，不阻断入库**）。
    var firstPlayedAt: Date?
    /// 最近游玩时间。
    var lastPlayedAt: Date?
    /// 累计游玩秒数（**统一换算成秒**：PSN 的 `playDuration` 是 ISO-8601 duration，
    /// Nintendo 的 `playingTime` 是分钟，两者在这里归一）。nil = 来源不提供
    /// （PS3/Vita 拿不到时长是 Sony 侧的硬缺口，UI 必须能表达「无数据」而非 0）。
    var playedSeconds: Int?
    /// 游玩次数（仅 PSN 提供 `playCount`）。
    var playCount: Int?

    // MARK: 奖杯（仅 PSN 提供；Nintendo 没有奖杯体系，这九个字段恒为 nil）
    //
    // 存成九个可空标量而不是一个复合属性（Codable struct），是**迁移策略**决定的：
    // 可选标量的新增是 SwiftData 无歧义的一条轻量迁移路径，本项目从未用过复合属性，
    // 不拿它做第一次试验。读写一律走 `trophies` 这个值类型出口，调用点不散着拼九个字段。
    //
    // `nil` = **这条记录没有奖杯数据**（Nintendo 全部、以及 PSN 里没匹配上奖杯套的那些），
    // 与「0 个奖杯」是两件事 —— 同 `playedSeconds` 的纪律。

    var trophyPlatinumEarned: Int?
    var trophyGoldEarned: Int?
    var trophySilverEarned: Int?
    var trophyBronzeEarned: Int?
    var trophyPlatinumDefined: Int?
    var trophyGoldDefined: Int?
    var trophySilverDefined: Int?
    var trophyBronzeDefined: Int?
    /// PSN 的 `progress`（来源自己算的百分比）。nil = 来源没给，界面按计数现算。
    var trophyPercent: Int?

    // MARK: 成就（仅 Xbox 提供；Nintendo 与 PSN 都没有这个体系，这四个字段恒为 nil）
    //
    // 与上面那九件套是**两套互不折算**的体系（奖杯分级 vs 成就点数），见 `AchievementProgress`。
    // 同样存成可空标量而不是一个复合属性 —— 与 `trophy*` 同一条迁移策略
    //（可选标量的新增是 SwiftData 无歧义的一条轻量迁移路径，本项目从未用过复合属性）。
    // 读写一律走 `achievements` 那个值类型出口，调用点不散着拼四个字段。
    //
    // `nil` = **这条记录没有成就数据**，与「0 个成就」是两件事 —— 同 `playedSeconds` 的纪律。

    /// 已获得的成就数。`0` 是合法状态（有成就套但一个都没拿到），不是「没有数据」。
    var achievementEarned: Int?
    /// 成就总数。
    var achievementTotal: Int?
    /// 已获得的 Gamerscore。
    var gamerscoreEarned: Int?
    /// Gamerscore 总数。
    var gamerscoreTotal: Int?

    /// 来源侧图片 URL（官方 CDN 原样保存；本地图存进 `game` 的 artwork，失败不影响导入）。
    var imageURLString: String?

    /// 首次/最近一次在同步里看到这条记录的时间（用于「来源侧已删除」的检测）。
    var firstSeenAt: Date
    var lastSeenAt: Date
    /// 最近一次同步时这条记录是否仍出现在来源响应里。
    /// 来源侧数据被清空/账号下架游戏时置 false，UI 上标注「来源已无此记录」而不是直接删。
    var presentInLastSync: Bool = true

    /// 关联状态。
    /// ⚠️ 2026-09-16 起**不再读写**（本版保留字段只为不动 schema，下一版清理）：
    /// 「自动关联 vs 手动关联」的区别本来就由 `game != nil` 单独承担 —— `GameMerger` 与
    /// `ExternalRecordLinkSheet` 用的是「有没有绑上」而不是「怎么绑上的」。
    var matchStateRaw: String = ExternalMatchState.unmatched.rawValue
    /// 是否**曾经**关联过 Game。
    /// ⚠️ 2026-09-16 起**不再读写**（同上，保留字段只为不动 schema）。
    /// 它原来的用途是「自动墓碑」：`hasBeenLinked && game == nil` 被当成「用户删掉了那个游戏」。
    /// 但那把两个相反的意图压进了同一个判据 —— 用户点「解除关联」与用户「删掉游戏」产生的
    /// 状态完全一样，而前者本该是可逆的。现在由 `isIgnored` 显式承担「别再导入了」。
    var hasBeenLinked: Bool = false

    /// **「别再自动导入这条」的唯一判据。**
    ///
    /// 两个来源，一个语义：
    /// - 用户在记录面板点「忽略此条」（显式、可撤销）；
    /// - 用户删掉了这条记录当时绑着的游戏（`Game` 的删除路径置位）—— 没有这一步的话，
    ///   用户每同步一次就得删一次同一个游戏。
    ///
    /// 与「关联」正交：`isIgnored == true` 的记录仍可以被手动关联（用户改主意了），
    /// 一旦关联上，自动逻辑本来就不会再动它（见 `ImportCoordinator` 的决策阶梯①）。
    var isIgnored: Bool = false

    /// 所属账号（inverse 在 `LinkedAccount.records` 上声明；删账号即级联删记录）。
    var account: LinkedAccount?
    /// 关联的 Game（inverse 在 `Game.externalRecords` 上声明；删游戏**不删**记录，
    /// 只是把关联摘掉 —— 来源事实本身仍在）。
    var game: Game?

    init(provider: AccountProvider, externalAccountId: String, titleId: String,
         conceptId: String? = nil, titleName: String, platform: String,
         platformRaw: String? = nil,
         versionType: ExternalVersionType = .unknown,
         skipReason: ExternalSkipReason? = nil,
         firstPlayedAt: Date? = nil, lastPlayedAt: Date? = nil,
         playedSeconds: Int? = nil, playCount: Int? = nil,
         trophies: TrophyProgress? = nil,
         achievements: AchievementProgress? = nil,
         imageURLString: String? = nil,
         firstSeenAt: Date = .now) {
        self.providerRaw = provider.rawValue
        self.externalAccountId = externalAccountId
        self.titleId = titleId
        self.conceptId = conceptId
        self.titleName = titleName
        self.platform = platform
        self.platformRaw = platformRaw
        self.versionTypeRaw = versionType.rawValue
        self.skipReasonRaw = skipReason?.rawValue
        self.firstPlayedAt = firstPlayedAt
        self.lastPlayedAt = lastPlayedAt
        self.playedSeconds = playedSeconds
        self.playCount = playCount
        // ⚠️ 九个字段在这里**逐个赋值**，不能写 `self.trophies = trophies`：
        // `trophies` 是 `extension` 里的计算属性，它的 setter 要读 `self`，而此刻
        // 后面的 `imageURLString` / `firstSeenAt` 等还没初始化 —— Swift 会直接拒绝编译。
        self.trophyPlatinumEarned = trophies?.platinumEarned
        self.trophyGoldEarned = trophies?.goldEarned
        self.trophySilverEarned = trophies?.silverEarned
        self.trophyBronzeEarned = trophies?.bronzeEarned
        self.trophyPlatinumDefined = trophies?.platinumDefined
        self.trophyGoldDefined = trophies?.goldDefined
        self.trophySilverDefined = trophies?.silverDefined
        self.trophyBronzeDefined = trophies?.bronzeDefined
        self.trophyPercent = trophies?.percent
        // 成就四项同理逐个赋值（见上）。
        self.achievementEarned = achievements?.earned
        self.achievementTotal = achievements?.total
        self.gamerscoreEarned = achievements?.gamerscoreEarned
        self.gamerscoreTotal = achievements?.gamerscoreTotal
        self.imageURLString = imageURLString
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = firstSeenAt
        self.presentInLastSync = true
        self.matchStateRaw = ExternalMatchState.unmatched.rawValue
        self.hasBeenLinked = false
        self.isIgnored = false
        self.account = nil
        self.game = nil
    }
}

// MARK: - 派生访问

extension ExternalGameRecord {
    var provider: AccountProvider {
        get { AccountProvider(rawValue: providerRaw) ?? .nintendo }
        set { providerRaw = newValue.rawValue }
    }

    var versionType: ExternalVersionType {
        get { ExternalVersionType(rawValue: versionTypeRaw) ?? .unknown }
        set { versionTypeRaw = newValue.rawValue }
    }

    /// **落库的**规则判决（只看 `skipReasonRaw`，认不出的取值当没有）。
    ///
    /// 与 `skipReason` 的差别只有一个，但很要紧：**它不含体验版**。`ImportCoordinator`
    /// 的决策阶梯要按它分流 —— 体验版有自己的第 ③ 档（`excludedByVersion` 那个计数与
    /// 「体验版」文案是用户看得见的回执，并进来会让那份回执永远归零）。
    var storedSkipReason: ExternalSkipReason? {
        skipReasonRaw.flatMap(ExternalSkipReason.init(rawValue:))
    }

    /// 「这条为什么不进游戏库」——**阶梯与界面共用的那一个**。
    ///
    /// 两级：落库的规则判决优先（`xboxPCWithoutPlaytime`），其余由 `versionType` 派生
    /// （体验版 / 试玩版：它们照常入库留档，只是不进游戏库，见 `allowsAutoMatching`）。
    ///
    /// 派生一档**不落库**的理由：`versionType` 本来就落库了，同一件事存两处迟早漂；
    /// 而反过来（把体验版也写进 `skipReasonRaw`）会让「这条为什么没进库」这个问题出现
    /// 两个可能为真的答案。
    var skipReason: ExternalSkipReason? {
        if let stored = storedSkipReason { return stored }
        switch versionType {
        case .demo: return .demoVersion
        case .trial: return .trialVersion
        default: return nil
        }
    }

    /// 决策阶梯的判据：**别再自动导入这条**（用户点的「忽略」，或落库的规则判决）。
    ///
    /// ⚠️ 体验版**不在其中** —— 见 `storedSkipReason`。两者在界面上是同一档（「已忽略」，
    /// 见 `isShownAsIgnored`），在阶梯上是相邻的两档，这个不对称是有意的。
    var isSkipped: Bool { isIgnored || storedSkipReason != nil }

    /// 记录列表的「已忽略」档与行内标签的判据（本页 UI 的唯一入口）。
    ///
    /// 两道门的口径**故意不完全一样**，这不是随手写的：
    /// - **用户点过「忽略此条」**（`isIgnored`）：无论有没有关联都算。那一档的用途是
    ///   「让忽略可撤销」，把一条已绑定的记录藏起来，用户就再也找不到撤销按钮了（既有行为）。
    /// - **规则判决**（`skipReason`）：**只有没进库时才算**。用户手工把它绑到某个条目上之后
    ///   它就不再是「被忽略的记录」了 —— 否则同一条记录会同时出现在「已关联」与「已忽略」
    ///   两处，而用户刚做完的动作正是「我要它进库」；下一轮同步则因为阶梯第 ① 档保护已绑记录，
    ///   它也不会被重新摘下来，两边的说法必须一致。
    var isShownAsIgnored: Bool {
        isIgnored || (game == nil && skipReason != nil)
    }

    /// 去重键（`provider|accountId|titleId`）。仅用于内存字典去重与调试展示，
    /// **不落库**（落库会与三个源字段产生漂移）。
    var dedupeKey: String { "\(providerRaw)|\(externalAccountId)|\(titleId)" }

    /// 游玩时长（小时，一位小数）。nil = 来源不提供时长。
    var playedHours: Double? {
        playedSeconds.map { Double($0) / 3600 }
    }

    /// 奖杯进度的**唯一读写口**（九个字段在这一处拼/拆）。
    ///
    /// 读：九个里**一个都没有**才算「没有奖杯数据」。全是 0 是合法状态
    /// （游戏有奖杯套但一个都没拿到），那时必须返回一个全 0 的值而不是 nil ——
    /// 否则界面上「0/42」会退化成「—」，把「一个都没拿」说成「来源没有数据」。
    ///
    /// 写：nil 会把九个字段一起清空。**调用点不要拿它来表达「这次没取到」** ——
    /// 「取不到就不动」是 `ImportCoordinator.refresh` 的职责（`?? record.trophies`）。
    var trophies: TrophyProgress? {
        get {
            let values = [trophyPlatinumEarned, trophyGoldEarned, trophySilverEarned,
                          trophyBronzeEarned, trophyPlatinumDefined, trophyGoldDefined,
                          trophySilverDefined, trophyBronzeDefined, trophyPercent]
            guard values.contains(where: { $0 != nil }) else { return nil }
            return TrophyProgress(
                platinumEarned: trophyPlatinumEarned ?? 0,
                goldEarned: trophyGoldEarned ?? 0,
                silverEarned: trophySilverEarned ?? 0,
                bronzeEarned: trophyBronzeEarned ?? 0,
                platinumDefined: trophyPlatinumDefined ?? 0,
                goldDefined: trophyGoldDefined ?? 0,
                silverDefined: trophySilverDefined ?? 0,
                bronzeDefined: trophyBronzeDefined ?? 0,
                percent: trophyPercent)
        }
        set {
            trophyPlatinumEarned = newValue?.platinumEarned
            trophyGoldEarned = newValue?.goldEarned
            trophySilverEarned = newValue?.silverEarned
            trophyBronzeEarned = newValue?.bronzeEarned
            trophyPlatinumDefined = newValue?.platinumDefined
            trophyGoldDefined = newValue?.goldDefined
            trophySilverDefined = newValue?.silverDefined
            trophyBronzeDefined = newValue?.bronzeDefined
            trophyPercent = newValue?.percent
        }
    }

    /// 成就进度的**唯一读写口**（四个字段在这一处拼/拆）。
    ///
    /// 读：四个里**一个都没有**才算「没有成就数据」。组装规则（全缺 → nil、负数按 0 收）
    /// 在 `AchievementProgress.init?` 里，不在这里再写一遍。
    ///
    /// 写：nil 会把四个字段一起清空。**调用点不要拿它来表达「这次没取到」** ——
    /// 「取不到就不动」是 `ImportCoordinator.refresh` 的职责（`?? record.achievements`）。
    var achievements: AchievementProgress? {
        get {
            AchievementProgress(earned: achievementEarned,
                                total: achievementTotal,
                                gamerscoreEarned: gamerscoreEarned,
                                gamerscoreTotal: gamerscoreTotal)
        }
        set {
            achievementEarned = newValue?.earned
            achievementTotal = newValue?.total
            gamerscoreEarned = newValue?.gamerscoreEarned
            gamerscoreTotal = newValue?.gamerscoreTotal
        }
    }

    /// 时长展示文本用的小时数（四舍五入到整数小时；不足 1 小时按 1 小时显示）。
    var displayHours: Int? {
        guard let h = playedHours else { return nil }
        return max(1, Int(h.rounded()))
    }

    /// 这条记录该不该出一张**游玩记录卡**（`PlayActivityView`，Nintendo 独有）。
    ///
    /// 两道门：
    /// ① **来源是 Nintendo** —— PSN 记录走奖杯卡（`GameDetailView.trophySources`）、
    ///    Xbox 记录走成就卡（`showsXboxAchievementCard`）。三类卡在详情页里并列摆在同一块区域，
    ///    同一条记录不能既出一张这种卡又出一张那种 —— 那看起来就是同一份数据说了两遍话。
    /// ② **三项至少一项有值** —— 三项全无时那张卡只剩一个品牌名，比不显示更糟
    ///    （与 `trophySources` 的纪律一致：用户会以为数据丢了）。
    ///
    /// 判定放在模型上、不写在视图里：这是「哪条记录算数」的口径，DataSmoke 覆盖得到；
    /// 视图那边只剩「怎么画」。第一项/最近/时长本身的口径见 `PlayActivity`。
    var showsPlayActivityCard: Bool {
        provider == .nintendo
            && PlayActivity.hasAny(firstPlayedAt: firstPlayedAt,
                                   lastPlayedAt: lastPlayedAt,
                                   hours: displayHours)
    }

    /// 这条记录该不该出一张 **Xbox 成就卡**（`XboxAchievementView`，Xbox 独有）。
    ///
    /// 两道门与 `showsPlayActivityCard` 逐条对位：
    /// ① **来源是 Xbox**（三类卡互斥的理由见那一条）；
    /// ② **成就四项或游玩两项至少一项有值** —— 全无时那张卡只剩一个品牌名。
    ///
    /// ⚠️ 与 Nintendo 那张的差别在第二道门：任天堂只有「游玩三项」，Xbox 是「成就 + 游玩」
    /// 两组，**只要有一组有值**就该出卡。实测 330/330 条都有 `achievement`，所以这道门
    /// 实际上很少真的挡下谁 —— 但它不是死代码：时长那一路取不到时（`playtimeUnavailable`）
    /// `playedSeconds` 会是 nil，而成就有值的记录仍然要出卡。
    ///
    /// ⚠️ 成就那一边判的是 `hasDisplayableValue` 而**不是** `achievements != nil`：
    /// Xbox 上确实有条目带 `totalAchievements = 0` 与 `totalGamerscore = 0`（没有成就的
    /// 游戏 / 应用），那种条目有 `achievement` 对象、两格却都印 `—` —— 不该算「有内容」。
    ///
    /// ⚠️ 游玩那一边**不看 `playedSeconds` 而看 `displayHours`**：那是「不足 1 小时按 1 小时」
    /// 的展示值，与卡片上真正印出来的东西同一个来源（同 `showsPlayActivityCard`）。
    var showsXboxAchievementCard: Bool {
        provider == .xbox
            && (achievements?.hasDisplayableValue == true
                || PlayActivity.hasAny(firstPlayedAt: firstPlayedAt,
                                       lastPlayedAt: lastPlayedAt,
                                       hours: displayHours))
    }

    /// PSN 奖杯卡头部那行「平台」：**这条记录在来源侧的平台列表**，`PS3,PS4` → `PS3/PS4`。
    ///
    /// 为什么是列表而不是单值：`platform`（canonical 单值）是导入时按 `platformRaw` 折算出的
    /// **一个**平台，而来源自己给的是一个**列表** —— 同一个奖杯套横跨 PS3/PS4 时它写
    /// `"PS3,PS4"`，用户说的「港版人中之龙 0 = PS3/PS4」正是这个事实被压成单值 `PS3` 丢掉的。
    ///
    /// `platformRaw` 在真库里有**两种形状**（2026-09-17 在本机库实测，PSN 101 条：
    /// `ps4_game` 43 / `ps5_native_game` 43 / `PS3` 26 / `unknown` 11 / `PS3,PS4` 7 /
    /// `PSVITA` 6 / `PSVITA,PS4` 2 / `PS3,PSVITA` 1 + 3 条媒体 App）。两种都是来源事实：
    /// - 带逗号 = 奖杯端点的 `trophyTitlePlatform` → `PSNAPI.platforms(forTrophyPlatform:)`；
    /// - 不带逗号 = gamelist 的 `category`（紧凑小写写法 `ps4_game`）或奖杯端点给的单值
    ///   （`PS3` / `PSVITA`）→ 先按 category 表查，查不动再走奖杯那条（`PSVITA` 正是靠这条兜住）。
    ///
    /// 两条路都认不出（如 `"unknown"`）才退回 `platform` —— 它是导入时的折算值，永远非空。
    /// **纯来源事实，不猜地区**（编号前缀与销售地区不是一一对应）。
    var psnPlatformDisplay: String? {
        guard provider == .playstation else { return nil }
        let raw = platformRaw?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let raw, !raw.isEmpty {
            let parsed: [String]
            if raw.contains(",") {
                parsed = PSNAPI.platforms(forTrophyPlatform: raw)
            } else {
                parsed = PSNAPI.platform(forCategory: raw).map { [$0] }
                    ?? PSNAPI.platforms(forTrophyPlatform: raw)
            }
            if !parsed.isEmpty { return parsed.joined(separator: "/") }
        }
        return platform.isEmpty ? nil : platform
    }

    /// Xbox 成就卡头部那行「平台」：**这条记录在来源侧的可用平台列表**，
    /// `XboxOne,XboxSeries` → `Xbox One/Xbox Series X|S`。
    ///
    /// 与 `psnPlatformDisplay` 同一条理由：`platform`（canonical 单值）是导入时按
    /// `XboxAPI.platform(forDevices:)` 折算出的**一个**「原生那一代」，而来源自己给的是一个
    /// **列表**（「这个标题能在哪些机器上玩」，含向下兼容的那几台 —— 见该函数的说明：
    /// 取最老的一代是因为列表**不是**世代声明）。同一个游戏在 Xbox 360 与 Xbox One 上是两个
    /// titleId、两条记录、两张卡，压成单值就分不出谁是谁了。
    ///
    /// 两处与 PSN 侧的差别，都是**来源事实**决定的：
    /// - 不拼编号。PSN 那行是「平台 · `NPWR-08547`」，因为用户点名要看奖杯套号；Xbox 的
    ///   `titleId` 是十进制的 `2131196662`，Xbox 自己的界面都不显示它，写上去只是噪音。
    /// - 只有一种形状（逗号分隔的 `devices`），不像 PSN 的 `platformRaw` 有一堆历史写法 ——
    ///   所以不需要 `psnPlatformDisplay` 里那段「先按 category 表查、查不动再走另一条」的分支。
    ///
    /// 认不出的一项被丢掉（见 `XboxAPI.platforms(forRawPlatforms:)`）；一个都没认出来
    /// 才退回 `platform` —— 它是导入时的折算值，永远非空。**纯来源事实，不猜。**
    var xboxPlatformDisplay: String? {
        guard provider == .xbox else { return nil }
        let parsed = XboxAPI.platforms(forRawPlatforms: platformRaw)
        if !parsed.isEmpty { return parsed.joined(separator: "/") }
        return platform.isEmpty ? nil : platform
    }

    /// 搜索这条记录时，除标题之外还要参与匹配的**来源事实**。
    ///
    /// 放在模型上的理由与 `showsPlayActivityCard` / `showsXboxAchievementCard` 同一条：
    /// DataSmoke 只编译 Models + Support，把这份清单写在视图里就等于没有测试 —— 而
    /// 「PSN 记了平台列表、Xbox 忘了记」正是**真实发生过的一次漏**（2026-09-18 对等审计的
    /// GAP 1）：同一个 Xbox 记录的 `platform` 被折算成 `Xbox Series X|S`、而来源列表里其实
    /// 还有 `Xbox One`，用户在账号页搜「Xbox One」搜不到它，PSN 侧同样情形却搜得到。
    ///
    /// 两种平台写法都要收：canonical 的 `platform` **与**来源列表展开的
    /// `psnPlatformDisplay` / `xboxPlatformDisplay`（各自对非本 provider 返回 nil，直接并进来即可）。
    /// `titleId` 是原样收的 —— 归一化会把 `CUSA12167_00` 里的下划线吃掉，而用户眼睛看到的是
    /// 界面上的 `CUSA-12167`，两种写法都得搜得到。
    ///
    /// **不含标题**（`titleName` 由调用方单独传，`GameLinker.matches` 的签名就是分着的），
    /// 也**不含已关联条目的名字** —— 那要读 `game`，得先判 `isLive`，属于调用方的上下文。
    var searchExtras: [String?] {
        [platform, psnPlatformDisplay, xboxPlatformDisplay, titleId]
    }

    /// 来源编号的展示写法：`CUSA01887_00` → `CUSA-01887`、`NPWR08547_00` → `NPWR-08547`。
    ///
    /// 两步：① 去掉第一个 `_` 起的服务后缀（`_00` 是 Sony 自己的服务标记，对用户没有信息量）；
    /// ② 在「字母段 → 数字段」的边界插一个连字符（`CUSA01887` 一路连读认不出分段）。
    ///
    /// **形状不符合就原样返回，不猜**：要求整个编号恰好是「一段字母 + 一段数字」。于是
    /// 已带连字符的（`CUSA-01887`）、纯字母、纯数字、以及字母段之后又出现字母的
    /// （`0100000000ABCD00` 这种）一律不动。Nintendo 的 16 位十六进制 titleId
    /// 天然落在这一档 —— 它们都以数字开头（`0100…`），遇到第一个字母就返回原样。
    var titleCodeDisplay: String {
        let trimmed = titleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return titleId }
        let base = String(trimmed.prefix { $0 != "_" })
        var letters = 0
        var digits = 0
        for ch in base {
            if ch.isLetter {
                // 字母段已经结束过（数字段非空）又冒出字母 / 已经进入数字段又回头 —— 形状不符。
                if digits > 0 { return trimmed }
                letters += 1
            } else if ch.isNumber {
                digits += 1
            } else {
                return trimmed
            }
        }
        guard letters > 0, digits > 0 else { return trimmed }
        return String(base.prefix(letters)) + "-" + base.dropFirst(letters)
    }

    /// 把记录挂到某个 Game 上。
    ///
    /// 「是用户手动绑的还是匹配引擎绑的」**不记录**（见 `ExternalMatchState` 的说明）：
    /// 已经绑上的记录在下一轮同步里一律原样保留，所以手动绑定本身就是稳的。
    func link(to game: Game) {
        self.game = game
    }

    /// 摘掉与 Game 的关联（解绑）。
    ///
    /// **这是可逆动作**：只摘关联，不置 `isIgnored`。下次同步若这条记录又匹配上（同一个
    /// titleId / conceptId / 归一化同名），它会被重新自动关联 —— 那正是「解除关联」的字面
    /// 含义。用户若想「以后都别再导入了」，那是另一个动作（`isIgnored`），界面上分开摆。
    func unlink() {
        self.game = nil
    }

    /// 这条记录是不是**还挂在某个 context 上**（判据与完整理由见 `Game.isLive`）。
    ///
    /// 「清空该账号导入数据」会一次删掉几百条记录，而处置面板 / 列表可能还攥着旧数组。
    var isLive: Bool { modelContext != nil }
}
