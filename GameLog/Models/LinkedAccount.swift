import Foundation
import SwiftData

// MARK: - 外部平台枚举

/// 外部游戏平台（第三方账号来源）。
///
/// ⚠️ 三个 provider 的 API 都**没有官方公开文档**，实现时按下列口径分级标注：
/// - `.nintendo`  —— Nintendo Account 的 Play Activity（`app-api.znej.nintendo.com`），
///   `官方客户端使用但未公开`。**走的是 My Nintendo / Nintendo Store 应用的 client，
///   与 Nintendo Switch Online 应用（znc / Coral）是两套东西**：znc 需要一个只能在
///   root 安卓机上由任天堂 App 内部生成的 `f` 参数，znej 不需要，也没有第三方 token 服务。
///   这条区分很关键，别再把两者混为一谈（2026-09-15 踩过，见 HANDOVER §53）。
/// - `.playstation` —— `gamelist/v2` 等端点，`社区逆向 API`（源自 PS App 流量分析），
///   但**直连索尼官方域名**。
/// - `.xbox` —— **唯一一个走第三方中转的**：OpenXBL（`api.xbl.io`），它自己的 OpenAPI
///   里写的是 `unofficial Xbox Live API`。微软官方那条链（Entra 应用 → 设备码 →
///   XSTS → titlehub）对**个人微软账号**走不通 —— 个人 MSA 没有 Entra tenant，
///   注册应用被 `AADSTS50020` 挡死（微软文档明说这是预期行为），唯一解法是开 Azure
///   账号并绑银行卡。用户 2026-09-17 明确选择「改用 OpenXBL，我不搞自己的了」。
///   ⚠️ **这条是 ROADMAP「零第三方中转」的明文例外**，见 `XboxAPI` 头部与 §63。
///
/// 详见 HANDOVER §53 / §63。
///
/// ⚠️ 这里**不**遵从 `LabelKeyed`：provider 是品牌专有名词，三语原样显示（`brandName`），
/// 走 L10n 只会得到三条与 `brandName` 逐字相同的死 key（此前正是如此，已删）。
enum AccountProvider: String, CaseIterable, Identifiable {
    case nintendo
    case playstation
    case xbox

    var id: String { rawValue }

    /// 品牌名（专有名词，三语原样显示，不进 L10n）。
    var brandName: String {
        switch self {
        case .nintendo: "Nintendo Account"
        case .playstation: "PlayStation Network"
        // ⚠️ 写「Xbox Live」是**用户 2026-09-18 的明确要求**，不是笔误、别再"修"回去。
        //    事实层面两种写法都有人用：微软 2021 年把服务改叫 "Xbox Network"，但
        //    「Xbox Live」仍是玩家与媒体日常说的名字，OpenXBL 自己的 OpenAPI 也写的是
        //    "unofficial Xbox Live API"。绑定页那个分段控件走 `shortBrandName`（"Xbox"），
        //    不受影响。这里也不写「OpenXBL」—— 挂牌照的是微软那套身份
        //    （Gamertag / Gamerscore），中转方只是取数通道，不该出现在卡片标题上。
        case .xbox: "Xbox Live"
        }
    }

    /// 分段控件用的短名（同样是专有名词，三语原样显示）。
    ///
    /// 与 `brandName` 分成两个属性，理由只有一条：**排版**。绑定页的 provider 选择器是
    /// 分段控件，三段平分一行 —— 「Nintendo Account / PlayStation Network / Xbox Live」
    /// 在 iPhone 上会被截成「Nintendo Acco… / PlayStation Net… / Xbox Live」，
    /// 靠省略号表达身份不是界面该有的样子。
    ///
    /// 账号行、卡片标题那些地方仍然用全名 —— 那里有整行宽度，短名反而显得潦草。
    var shortBrandName: String {
        switch self {
        case .nintendo: "Nintendo"
        case .playstation: "PlayStation"
        case .xbox: "Xbox"
        }
    }

    /// 该 provider 默认归入的平台（`Presets.platforms` 的 canonical 值）。
    /// 仅作兜底：记录自带平台信息时以记录为准。
    /// （Nintendo 的 `platform`/`deviceType` 字段会给出真实机型；PSN 按 `category` 覆盖成 PS4/PS5。
    /// 两者的实际取值字符串需真登录一次才能确认映射，见 HANDOVER §53 待验证项。）
    ///
    /// Xbox 侧拿的是 `devices`（一份**可用平台列表**），正常的取值路径是
    /// `XboxAPI.platform(forDevices:)`（取列表里**最老**的一代 = 原生那一代，
    /// 理由见该函数：列表含向下兼容的机器，取最新等于把「能兼容」误读成「是次世代版」）。
    /// 这里的兜底值仍是 `Xbox Series X|S` —— 它只在 `devices` **整条缺失或全认不出**时用上
    /// （解析层认不出时返回 nil，兜底是入库路径的决定），⚠️ 那是本功能里**唯一一处仍偏新**
    /// 的猜测，只是没有更好的中立值可选（`Presets.platforms` 里没有一个「未知 Xbox 世代」）。
    var fallbackPlatform: String {
        switch self {
        case .nintendo: "Nintendo Switch"
        case .playstation: "PS4"
        case .xbox: "Xbox Series X|S"
        }
    }

    /// 绑定该 provider 需要用户手抄一段凭证（无法用系统登录会话完成）。
    /// PSN 的 NPSSO 落在 Sony 的 Android PS App scheme 上 → 只能手工粘贴，见 `PSNAuthService`。
    /// Xbox 的 personal API key 同样是用户从服务方页面复制来的，见 `XboxAuthService`。
    var requiresManualCredentialEntry: Bool { self != .nintendo }
}

/// 凭证状态。
/// **只存状态，不存凭证本身** —— 真正的 session_token / access_token / refresh_token / NPSSO
/// 一律在 Keychain（`KeychainStore`），绝不进 SwiftData、不进备份 JSON、不进日志。
enum AccountCredentialState: String, CaseIterable, Identifiable, LabelKeyed {
    /// 凭证可用。
    case active
    /// 会话已到期且无法自动续期，需要用户重新绑定。
    case expired
    /// Keychain 中已查不到（抹掉设备 / 用户手动清理 / 换机）。
    case missing
    /// 尚未写入凭证（建账号流程中断时会短暂出现）。
    case none

    var id: String { rawValue }
    var labelKey: String { "account.credState.\(rawValue)" }
}

/// 上次同步失败的原因分类（**只存分类，不存原始错误**，避免把服务端响应体写进库）。
enum AccountSyncErrorKind: String, CaseIterable, Identifiable, LabelKeyed {
    case network      // 无网络 / 超时
    case authExpired  // 凭证失效
    case rateLimited  // 被限流
    case apiChanged   // 响应结构与预期不符（接口变了）
    case server       // 服务端 5xx
    case unknown

    var id: String { rawValue }
    var labelKey: String { "account.syncError.\(rawValue)" }
}

/// 外部账号的「标题与封面语言」。
///
/// 存在的理由：来源标题是按请求语言**本地化过的**（Nintendo 走 `Gentry-Locale`，
/// PlayStation 走 `Accept-Language`），而 App 界面语言只有三档、且与「我想让那边的游戏
/// 叫什么名字」不一定是一回事 —— 简体界面下的用户完全可能想要繁体标题（港台译名）
/// 或日文原名。所以这是个**独立的、账号级的**选择。
///
/// ⚠️ 三家的取值**都是推定的**（Nintendo 唯一被一手源实证过的是 `en-GB`，见
/// `NintendoAuthService`）。但**失败形状分两种，别把两条路当成一件事**：
/// - Nintendo：取值不被接受会**得到 400**，客户端退到 `en-GB` 重试，并把这次回退
///   **明确告诉用户**（`LinkedAccount.localeFallbackFrom`）—— 不静默降级。
/// - PlayStation / Xbox：`Accept-Language` 是标准 HTTP 头，不被接受的值只会被**忽略**、
///   不会报错，服务端也**不回报**实际用了哪个语言 —— 所以这两家检测不到回退，
///   `localeFallbackFrom` 对它们恒为空（不假装能检测）。
///   （Xbox 侧 2026-09-17 实测过 `Accept-Language` 确实生效：同一批 330 条标题里
///   zh-CN 与 en-US 有 115 条不同、en-US 与 ja-JP 有 127 条不同，见 §63。）
enum ExternalTitleLocale: String, CaseIterable, Identifiable, LabelKeyed {
    /// 跟随 App 界面语言（默认）。
    case followApp
    /// 繁體中文（Nintendo `zh-TW`；其余两家见 `acceptLanguage`）。
    case zhHant
    /// 简体中文（Nintendo `zh-CN`；其余两家见 `acceptLanguage`）。
    case zhHans
    /// 日本語（Nintendo `ja-JP`）。
    case ja
    /// English（Nintendo `en-US`，美版）。
    case en

    var id: String { rawValue }
    var labelKey: String { "account.titleLocale.\(rawValue)" }

    /// 该档位对应的 Nintendo `Gentry-Locale` 取值。
    /// `followApp` 返回 nil —— 「跟随 App 语言」要由调用方拿**当前**的 App 语言现算，
    /// 而不是在这里猜一个默认值（那会让「跟随」变成「固定」）。
    var explicitGentryLocale: String? {
        switch self {
        case .followApp: nil
        case .zhHant: "zh-TW"
        case .zhHans: "zh-CN"
        case .ja: "ja-JP"
        case .en: "en-US"
        }
    }

    /// 该档位对应的 `Accept-Language` 取值（**PSN 与 Xbox 共用**）。nil = 跟随 App 语言。
    ///
    /// 一个属性而不是两家各一份：这是个标准 HTTP 头，两个 provider 请求的是同一件事
    /// （「让那边的游戏叫什么名字」）。各写一份的话，某一档改了一处漏一处，
    /// 同一个「繁體中文」在两个来源上就会读到两套取值。
    ///
    /// ⚠️ **这些标签没有一手资料**（HANDOVER §53.10 待验证项 7：能接受哪些语言标签
    /// 从未实测过）。取值按 Sony 自家 web / App 的命名习惯**推断**，并且给的是**降级阶梯**
    /// 而不是单值 —— `Accept-Language` 是标准头，服务端会取第一个它认识的语言，
    /// 不认识就跳到下一个；不会像 Nintendo 的 `Gentry-Locale` 那样 400。
    /// 所以多列几个写法是**免费的保险**，不是猜。
    ///
    /// 首次真账号同步后请核对：若繁體档拿回来的仍是简体，说明服务端认的是别的写法，
    /// 改这里的字符串即可（`account.titleLocale.coverage` 那行会显示有多少条真的落了目标语言）。
    var acceptLanguage: String? {
        switch self {
        case .followApp: nil
        case .zhHant: "zh-Hant-TW,zh-Hant,zh-TW"
        case .zhHans: "zh-Hans-CN,zh-Hans,zh-CN"
        case .ja: "ja-JP,ja"
        case .en: "en-US,en"
        }
    }

    /// 中文档位（详情页要提示「繁体不一定拿得到」时用）。
    var isChinese: Bool { self == .zhHant || self == .zhHans }
}

// MARK: - 账号模型

/// 一个已绑定的外部游戏账号（Nintendo Account 1 / Nintendo Account 2 / PSN 1 …）。
///
/// 设计要点（2026-09-15 引入，见 HANDOVER §53）：
/// - `provider` + `externalAccountId` 唯一标识一个外部账号；`localId` 是**只属于本机**的
///   稳定 UUID，同时用作 Keychain item 的 account 键。三者的区别很重要：
///   `externalAccountId` 来自服务端（换了重新绑定还是同一个），`localId` 换绑就换新。
/// - 同一个 provider 可以有多个账号（两个 Nintendo Account 并存是明确支持的场景）。
/// - **本模型不含任何凭证字段**，这是硬性约束：凭证全在 Keychain，备份里也不含本模型的
///   任何数据（`BackupDTO` 是白名单式 Codable，不写进去就不会外泄）。
@Model
final class LinkedAccount {
    /// 本机稳定 UUID（Keychain item 的 account 键）。
    var localId: UUID
    /// provider（`AccountProvider.rawValue`）。
    var providerRaw: String
    /// 服务端账号 ID：Nintendo 的 `naId`（19 位数字串）/ PSN 的 `accountId`（18–19 位数字串）
    /// / Xbox 的 `xuid`（19 位数字串，实测与 `hostId` 同值）。
    var externalAccountId: String
    /// 展示名（Nintendo 取 `nickname`，PSN 取在线 ID）。
    var displayName: String
    /// 头像 URL（远端地址原样保存，展示时按需下载；下载失败不影响账号可用）。
    var avatarURLString: String?
    /// 国家/地区（Nintendo `users/me` 返回；部分 Nintendo 接口要求带上，故留档）。
    var country: String?
    /// 生日（Nintendo `users/me` 返回的 `MM/DD` 形式；同上，留档备用）。
    var birthday: String?

    var linkedAt: Date
    var lastSyncAt: Date?
    /// 上次同步成功处理的记录条数（用于「最近同步 3 分钟前 · 128 条」）。
    var lastSyncRecordCount: Int = 0
    /// 上次同步失败原因分类（nil = 上次成功）。
    var lastSyncErrorRaw: String?
    /// 自动同步开关（v1 只有手动「立即同步」；此开关为后续自动同步预留，UI 上标注）。
    var autoSyncEnabled: Bool = false
    /// 凭证状态（`AccountCredentialState.rawValue`）。
    var credentialStateRaw: String = AccountCredentialState.active.rawValue
    /// 凭证预计到期时间（可展示「约 X 天后需要重新登录」，不做强制登出依据）。
    var credentialExpiresAt: Date?

    /// Nintendo 侧请求标题语言用的 locale（`Gentry-Locale` header 的值，如 `ja-JP` / `en-GB`）。
    /// **该 header 是必带的**：不给值任天堂会回 400 而不是取默认。
    ///
    /// ⚠️ 这是**实际用于取数的值**（诊断与展示用），不是用户的选择 —— 用户的选择是
    /// `titleLocaleRaw`。两者分开是因为「用户想要繁體中文」与「接口真正接受的是什么」是两件事：
    /// Nintendo 侧取值不被接受时会退到 `en-GB`，而这件事必须能被看见（否则用户只会觉得
    /// 「我明明选了繁体，拿回来的还是英文」）。PSN 侧同样写这个字段，但它只是「这次请求
    /// 带了什么 `Accept-Language`」—— 服务端不回报实际用了哪个语言，所以那边的
    /// `localeFallbackFrom` 恒为空（见 `ExternalTitleLocale` 的说明）。
    var sourceLocale: String = ""
    /// 用户选的标题与封面语言（`ExternalTitleLocale.rawValue`）。空串 = 跟随 App 语言。
    ///
    /// 与 `sourceLocale` 的分工：这个是**意图**，那个是**结果**。改这个不会自动改那个 ——
    /// 用户改完语言要点「重新同步并刷新标题与封面」，那时才用它算出新的 `sourceLocale`。
    var titleLocaleRaw: String = ""
    /// 上次同步时语言是否被接口拒绝、退回了 `en-GB`（nil = 没有发生回退）。
    /// 只存**用于展示的布尔与目标值**，不存任何响应内容。
    var localeFallbackFrom: String?
    /// 用户手动标记「不再导入」的 titleId（墓碑）。
    ///
    /// ⚠️ 2026-09-16 起**不再读写**（本版保留字段只为不动 schema，下一版清理）。
    /// 它做的事现在由 `ExternalGameRecord.isIgnored` 承担 —— 逐条记录一个布尔，
    /// 可撤销、可筛选、界面上看得见，而这里的数组只能靠一行代码的 if-else 优先级生效。
    var suppressedTitleIds: [String] = []

    /// 该账号同步下来的全部外部游玩记录（inverse 在本属性上声明）。
    @Relationship(deleteRule: .cascade, inverse: \ExternalGameRecord.account)
    var records: [ExternalGameRecord]

    init(localId: UUID = UUID(), provider: AccountProvider, externalAccountId: String,
         displayName: String, avatarURLString: String? = nil,
         country: String? = nil, birthday: String? = nil, sourceLocale: String = "",
         titleLocaleRaw: String = "",
         linkedAt: Date = .now, credentialState: AccountCredentialState = .active) {
        self.localId = localId
        self.providerRaw = provider.rawValue
        self.externalAccountId = externalAccountId
        self.displayName = displayName
        self.avatarURLString = avatarURLString
        self.country = country
        self.birthday = birthday
        self.linkedAt = linkedAt
        self.lastSyncAt = nil
        self.lastSyncRecordCount = 0
        self.lastSyncErrorRaw = nil
        self.autoSyncEnabled = false
        self.credentialStateRaw = credentialState.rawValue
        self.credentialExpiresAt = nil
        self.sourceLocale = sourceLocale
        self.titleLocaleRaw = titleLocaleRaw
        self.localeFallbackFrom = nil
        self.suppressedTitleIds = []
        self.records = []
    }
}

// MARK: - 派生访问

extension LinkedAccount {
    /// provider（读取兜底 Nintendo，写入存 rawValue）。
    var provider: AccountProvider {
        get { AccountProvider(rawValue: providerRaw) ?? .nintendo }
        set { providerRaw = newValue.rawValue }
    }

    /// 凭证状态（未知兜底 `.expired` —— 读不懂的状态按「需要重新登录」处理最安全）。
    var credentialState: AccountCredentialState {
        get { AccountCredentialState(rawValue: credentialStateRaw) ?? .expired }
        set { credentialStateRaw = newValue.rawValue }
    }

    /// 上次同步失败原因（nil = 成功）。
    var lastSyncError: AccountSyncErrorKind? {
        get { lastSyncErrorRaw.flatMap(AccountSyncErrorKind.init(rawValue:)) }
        set { lastSyncErrorRaw = newValue?.rawValue }
    }

    /// 用户选的标题语言；空串（或认不出来的值）→ 跟随 App 语言。
    var titleLocale: ExternalTitleLocale {
        get { ExternalTitleLocale(rawValue: titleLocaleRaw) ?? .followApp }
        set { titleLocaleRaw = newValue.rawValue }
    }

    /// 该账号的标题语言是否**跟随 App 语言**（决定界面上要不要显示「跟随中」的说明文字）。
    var titleLocaleFollowsApp: Bool { titleLocale == .followApp }

    /// 这个账号是不是**还挂在某个 context 上**（判据与理由见 `Game.isLive`）。
    ///
    /// 解绑会 `context.delete(account)` + `save()`，而列表 / 详情页可能还攥着旧的
    /// `@Query` 结果再渲染一帧 —— 读它的 `displayName` 就是 SwiftData fatal。
    var isLive: Bool { modelContext != nil }
}
