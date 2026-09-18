import Foundation

/// PlayStation Network 的协议常量与响应模型。
///
/// **来源与性质（照实标注，不要美化）**：Sony **没有任何公开的第三方 API 文档**，
/// 下面的常量与字段全部来自**社区逆向**（PS App 流量分析），转抄自
/// `achievement/psn-api` v2.18.1 的**已发布源码**（Apache-2.0 / MIT，npm 包内 sourcemap
/// 含原始 TypeScript）。所以本层的每一条都属于 **Undocumented / reverse-engineered API**
/// —— 不是官方 SDK，也不该在注释或 UI 里被叫作官方接口。Sony 随时可能改掉它们，
/// 所以解析一律**宽松**（字段全可选、数字接受浮点、认不出就当没有），
/// 一次结构小变动不该让整次同步失败。
///
/// ⚠️ **本实现不碰任何第三方中转**：授权与数据请求全部从本机直连
/// `ca.account.sony.com` / `m.np.playstation.com` / `dms.api.playstation.com`。
/// 社区的 403 案例几乎全是浏览器 SPA 的 CORS 场景 —— 原生 `URLSession` 不受此限。
///
/// 流程（三步，与 Nintendo 一样「凭证只换一次，之后短期令牌只在内存」）：
/// ① 用户从 `https://ca.account.sony.com/api/v1/ssocookie` 抄回 **NPSSO**（64 字符）
/// ② `exchangeNPSSOForAccessCode` —— 拿 NPSSO 换一次性 `code`（**在 302 的 `Location` 头里**）
/// ③ `exchangeAccessCodeForTokens` —— 换 access_token（1 小时，只放内存）
///    + refresh_token。refresh_token 用完之后靠它续，但**不轮换、有硬寿命**，
///    所以 NPSSO 必须一起留下（见 `ExternalCredentialKind`）。
enum PSNAPI {
    /// 授权服务基址。`psn-api` 的 `AUTH_BASE_URL.ts` 逐字如此。
    static let authBase = "https://ca.account.sony.com/api/authz/v3/oauth"
    static let authorizeEndpoint = authBase + "/authorize"
    static let tokenEndpoint = authBase + "/token"

    /// 用户自助获取 NPSSO 的地址（让他们在浏览器里登录 Sony，**不是**把密码给我们）。
    static let npsscoCookiePage = "https://ca.account.sony.com/api/v1/ssocookie"

    /// Sony 自己的账号登录页（「设置 → 游戏账号 → PlayStation → 打开登录页」那个按钮）。
    ///
    /// ⚠️ **必须与 `npsscoCookiePage` 在同一个浏览器里打开**：NPSSO 是**浏览器会话 cookie**
    /// 的产物，而这个页面的登录会把会话种在 `sony.com` 域上，`ca.account.sony.com` 才收得到。
    /// 换浏览器 / 用应用内嵌视图都不行 —— 那正是 `AddExternalAccountView` 用系统
    /// `openURL`（走默认浏览器）而不是 `SFSafariViewController` 的原因。实测 200。
    static let signInPage = "https://my.account.sony.com/central/signin/"

    /// 上面两个地址的 `URL` 形式（`openURL` 要的是 `URL` 而不是 `String`）。
    ///
    /// **不 force-unwrap**：项目纪律禁止，而这里也没有必要 —— 两行都是写死的 https 字面量，
    /// `nil` 只可能来自有人把它们改坏了，那种情况下按钮不出现（可被发现）比崩溃好。
    static let signInURL = URL(string: signInPage)
    static let npsscoCookieURL = URL(string: npsscoCookiePage)

    /// PlayStation 移动 App 的公开 client 标识。
    ///
    /// ⚠️ **这不是任何用户的凭证**：它是 Sony 自家安卓 PS App 的公开 client id/secret，
    /// 社区里到处都有（本项目经 `psn-api` v2.18.1 源码逐字核对）。它登不进任何账号，
    /// 单凭它拿不到任何人的数据 —— 真正的授权仍要用户自己的 NPSSO。
    /// 与 Nintendo 侧的 `clientId` 是同一性质的东西。
    static let clientId = "09515159-7237-4370-9b40-3806e67c0891"
    /// `base64("\(clientId):\(secret)")`，抄自 `psn-api` 的 `Authorization` 常量。
    /// 拆成两段写，是为了让「它是 `id:secret` 的 base64」这件事在代码里看得见。
    static let basicAuthorization = "Basic " + Data("\(clientId):ucPjka5tntB2KqsP".utf8)
        .base64EncodedString()

    /// OAuth 回调：**Sony 安卓 PS App 的私有 scheme**。授权成功后 Sony 往这个地址 302，
    /// 我们只读那个 `Location` 头，**从不真的去打开它**。所以不需要注册 URL scheme，
    /// 也不会把用户丢进一个打不开的深链（这正是 PSN 侧只能手工粘贴 NPSSO 的原因）。
    static let redirectURI = "com.scee.psxandroid.scecompcall://redirect"

    /// 申请 code 时用的授权范围（`psn-api` 逐字）。
    static let scope = "psn:mobile.v2.core psn:clientapp"

    static let trophyBase = "https://m.np.playstation.com/api/trophy"
    static let userProfileBase = "https://m.np.playstation.com/api/userProfile/v1/internal/users"
    /// 游玩记录（`gamelist/v2`）。
    static let gameListBase = "https://m.np.playstation.com/api/gamelist/v2/users"
    /// accountId 的第二条取法（第一条是 trophy summary）。
    static let dmsBase = "https://dms.api.playstation.com/api"

    /// 单页条数。**200 是社区一致的实测上限**，再大不会被拒但也只会返回 200 条。
    static let pageSize = 200
    /// 奖杯标题单页条数。**800 是 psn-api 文档写明的该端点上限**
    ///（游玩记录那 200 的上限不适用于它），所以这里单独一个常量，不与 `pageSize` 混用。
    static let trophyPageSize = 800

    /// 按 id 查奖杯时**一批最多几个**。**这是服务端的硬限制，不是我们挑的数**：
    /// `psn-api` 的文档写死「There is a limit of 5 title IDs which can be included in the
    /// npTitleIds query. Trying to include more than 5 will result in a Bad Request
    /// (query: npTitleId) error being returned.」—— 超一个整批就被拒。
    static let trophyTitleIdBatchSize = 5
    /// 翻页护栏：即使 `totalItemCount` 一直报错也不至于无限翻（200 × 50 = 10000 条）。
    static let maxPages = 50

    static let timeout: TimeInterval = 20

    /// 端点常量是字符串，转 URL 这步单独收在一处。不 force-unwrap。
    static func url(_ endpoint: String) throws -> URL {
        guard let url = URL(string: endpoint) else {
            throw ExternalAPIError.internalFailure("bad psn endpoint url")
        }
        return url
    }

    /// 带查询串的 URL。查询值统一走 `ExternalHTTPClient.formEncode`（严格百分号编码）。
    static func url(_ endpoint: String, query: [String: String]) throws -> URL {
        guard !query.isEmpty else { return try url(endpoint) }
        let encoded = String(decoding: ExternalHTTPClient.formEncode(query), as: UTF8.self)
        return try url(endpoint + "?" + encoded)
    }
}

// MARK: - 响应模型

extension PSNAPI {
    /// `GET /api/gamelist/v2/users/{accountId}/titles` 的响应。
    ///
    /// **刻意不声明 `media` / `concept.media` / `concept.titleIds`**：它们对本功能没有用，
    /// 而 `concept.titleIds` 在文档里是数组、社区实测见过空格分隔的单字符串 ——
    /// 给它编一个具体类型，猜错一次就会让**整个响应**解码失败。`Decodable` 会忽略未声明的键，
    /// 所以不声明反而既安全又省事（与 Nintendo 侧不声明 `hiddenTitleList` 同理）。
    /// concept 的 `id` 仍然要（它是 PS4/PS5 双版本的合并键）。
    struct PlayedGamesResponse: Decodable {
        var titles: [TitleEntry]?
        /// 总条数（驱动翻页）。用 `Double` 收：整数/浮点都解得出来。
        var totalItemCount: Double?
        var nextOffset: Double?
        var previousOffset: Double?
    }

    /// 一个已玩过的标题。
    struct TitleEntry: Decodable {
        /// 版本级 ID，形如 `CUSA01433_00`（PS4）/ `PPSA07950_00`（PS5）。
        var titleId: String?
        var name: String?
        /// 按请求语言本地化的名字（靠 `Accept-Language` 头影响）。
        var localizedName: String?
        var imageUrl: String?
        var localizedImageUrl: String?
        /// 平台类别，形如 `ps4_game` / `ps5_native_game` / `pspc_game` / `unknown`。
        var category: String?
        /// 游玩次数。同上用 `Double` 收。
        var playCount: Double?
        /// 版本聚合信息（`id` 是 PS4/PS5 的合并键）。
        var concept: Concept?
        /// RFC3339。⚠️ 实测有 `.12Z` 这种**两位小数秒**，见 `parseTimestamp`。
        var firstPlayedDateTime: String?
        var lastPlayedDateTime: String?
        /// ISO-8601 duration（`PT228H56M33S`）。**小时可超 24**，见 `parseDurationSeconds`。
        var playDuration: String?

        struct Concept: Decodable {
            /// 一个游戏所有版本的共同 ID（官方给出的合并依据）。`Int64` 而非 `Int`：够大。
            var id: Int64?
        }

        /// 取展示名：优先本地化名，空则原名。
        var displayName: String? {
            if let localizedName, !localizedName.isEmpty { return localizedName }
            if let name, !name.isEmpty { return name }
            return nil
        }
    }

    /// `GET /api/trophy/v1/users/me/trophySummary` 的响应。**这里只取 `accountId`**，
    /// 奖杯数据本功能用不到，不声明（少一个字段就少一个解码失败面）。
    struct TrophySummaryResponse: Decodable {
        var accountId: String?
    }

    // MARK: 奖杯标题（`GET /api/trophy/v1/users/{accountId}/trophyTitles`）
    //
    // ⚠️ 这是本功能里**唯一**会返回 PS3 / PS Vita 的平台信息的端点 —— 游玩记录那个
    //    `gamelist/v2` 是 PS4/PS5/PC 专用的（见 `PSNTrophyService` 头部的说明），
    //    所以「补全 PS3/Vita」和「取奖杯数量」两件事共用这一个端点。
    //
    // 与全部 PSN 模型同一口径：**字段全可选、数字用 `Double`**。Sony 改一次字段名
    // 不该让整次同步失败；认不出来就当没有。

    /// `GET /api/trophy/v1/users/{accountId}/trophyTitles` 的响应。
    struct TrophyTitlesResponse: Decodable {
        var trophyTitles: [TrophyTitleEntry]?
        /// 总条数（驱动翻页）。同上用 `Double` 收。
        var totalItemCount: Double?
        var nextOffset: Double?
        var previousOffset: Double?
    }

    /// `GET /api/trophy/v1/users/{accountId}/titles/trophyTitles?npTitleIds=…` 的响应。
    ///
    /// ⚠️ 这是**唯一**能把「游玩记录里的 `titleId`（`CUSA…` / `PPSA…`）」与奖杯套直接对上号的
    /// 端点：它按**我们传进去的** npTitleId 分组返回，整条路径**不经过名字**。
    /// `psn-api` 的文档把它明确写成「a way of linking the npCommunicationId of a Trophy Set
    /// to a titles npTitleId」—— 那不是顺带用途，就是这个端点的正经用途。
    struct TrophyTitlesByIdResponse: Decodable {
        var titles: [Entry]?

        struct Entry: Decodable {
            /// 我们传进去的那个 id，原样回显（键的可靠性就靠它）。
            var npTitleId: String?
            /// 该标题的奖杯套。理论上一个，但按数组收 —— 没有承诺只有一个。
            var trophyTitles: [TrophyTitleEntry]?
        }
    }

    /// 一个奖杯套（= 一个标题的一个平台版本）。`psn-api` 的 `TrophyTitle`。
    struct TrophyTitleEntry: Decodable {
        /// `"trophy"` = PS3 / PS4 / PS Vita；`"trophy2"` = PS5。诊断用，不参与判定。
        var npServiceName: String?
        /// 奖杯套 ID，形如 `NPWR00845_00`。**与 `titleId`（`CUSA…` / `PPSA…`）不是一回事** ——
        /// 两者之间没有可推导的关系，只能靠名字（`PSNTrophyService.attachByName`）或靠
        /// `TrophyTitlesByIdResponse` 那条按 id 分组的路径（`fetchTrophies(forTitleIds:)`）关联。
        var npCommunicationId: String?
        /// 游戏名（受 `Accept-Language` 影响，与游玩记录那边的本地化名通常逐字相同）。
        var trophyTitleName: String?
        /// 方形游戏图标（官方 CDN）。可作 PS3/Vita 记录的唯一图像来源。
        var trophyTitleIconUrl: String?
        /// 平台。**可能是逗号分隔的多值**（`"PS4,PSVITA"` 这种跨平台共用奖杯套），
        /// 所以解析一律走 `platforms(forTrophyPlatform:)`，不要当单值用。
        var trophyTitlePlatform: String?
        /// 这个奖杯套一共几个奖杯。
        var definedTrophies: TrophyCounts?
        /// 用户已经拿到几个。
        var earnedTrophies: TrophyCounts?
        /// 完成百分比（Sony 自己算的）。
        var progress: Double?
        /// 用户在自己的奖杯列表里隐藏了这个标题。**隐藏是用户的显式动作**，
        /// 本实现据此整条跳过（见 `PSNTrophyService`）。
        var hiddenFlag: Bool?
        /// ISO-8601。**不是游玩时间** —— 是「最后一次拿到奖杯 / 首次同步」的时间，
        /// 不作为 `lastPlayedAt` 落库（那会是编造）。
        var lastUpdatedDateTime: String?
    }

    /// 按等级分的奖杯个数。`psn-api` 的 `TrophyCounts`。
    ///
    /// ⚠️ `platinum` 在类型上是 `0 | 1`（一个奖杯套最多一个白金），但**不按枚举解** ——
    /// 服务端给的是数字，按 `Double` 收再夹到 0/1，结构小变动不会让整个响应解不出来。
    struct TrophyCounts: Decodable {
        var bronze: Double?
        var silver: Double?
        var gold: Double?
        var platinum: Double?
    }

    /// `GET /api/userProfile/v1/internal/users/{accountId}/profiles` 的响应。
    struct ProfileResponse: Decodable {
        var onlineId: String?
        var avatars: [Avatar]?

        struct Avatar: Decodable {
            var size: String?
            var url: String?
        }
    }

    /// `GET /api/v1/devices/accounts/me` 的响应（accountId 的备选取法）。
    struct AccountDevicesResponse: Decodable {
        var accountId: String?
    }

    /// `POST /token` 的响应（换 code 与刷 refresh 两种用途共用同一个形状）。
    struct TokenResponse: Decodable {
        var access_token: String?
        var refresh_token: String?
        var id_token: String?
        var expires_in: Double?
        /// refresh_token 的剩余寿命（秒）。**不轮换**，所以它才是「这个绑定还能活多久」的答案。
        var refresh_token_expires_in: Double?
        var token_type: String?
    }
}

// MARK: - 容错解析

extension PSNAPI {
    /// PSN 给的时间戳。典型是 `2015-07-10T19:40:19Z`，但**实测有 `2024-08-03T19:28:27.12Z`
    /// 这种两位小数秒** —— `ISO8601DateFormatter` 的 `.withFractionalSeconds` 只吃固定位数。
    ///
    /// 实现**不在这里**：规则本身与 Xbox 逐字相同（那边是**七位**小数秒），所以实体在
    /// `ExternalTimestamp.parse`，这里只留 PSN 侧的入口名（调用点与冒烟测试已经按这个
    /// 名字写了十几处，改名只会制造无谓的改动面）。
    static func parseTimestamp(_ raw: String?) -> Date? {
        ExternalTimestamp.parse(raw)
    }

    /// 解析 ISO-8601 duration（`playDuration`，形如 `PT228H56M33S`）→ 秒。
    ///
    /// ⚠️ **不能用 `DateComponentsFormatter`**：它按「时分秒」建模，超过 24 小时会被折成天，
    /// 而 PSN 的时长轻易超过 24 小时 —— 文档自己的示例就是 228 小时。手写解析只认
    /// `P[n]W[n]D T[n]H[n]M[n]S` 这一族，数字可以是小数（`PT1.5S` / `PT1,5S`）。
    /// 认不出来返回 nil（nil = 来源不提供，UI 显示「—」，而不是伪装成 0 秒）。
    static func parseDurationSeconds(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.hasPrefix("P") else { return nil }

        var total = 0.0
        var digits = ""
        var inTimePart = false
        var sawUnit = false

        for character in trimmed.dropFirst() {
            if character == "T" { inTimePart = true; continue }
            if character.isNumber || character == "." || character == "," {
                digits.append(character == "," ? "." : character)   // 逗号也是合法的小数点
                continue
            }
            guard let value = Double(digits) else { return nil }
            digits = ""
            sawUnit = true
            switch character {
            case "W": total += value * 604_800
            case "D": total += value * 86_400
            // 时/分/秒只可能出现在 T 之后；出现在前面说明这不是我们认识的形状，别猜。
            case "H" where inTimePart: total += value * 3_600
            case "M" where inTimePart: total += value * 60
            case "S" where inTimePart: total += value
            // 月/年不做等效换算（时长里不该出现），认不出来就别猜。
            default: return nil
            }
        }
        guard sawUnit, digits.isEmpty, total >= 0 else { return nil }
        return Int(total.rounded())
    }

    /// PSN 的 `category` → 平台（`Presets.platforms` 的 canonical 值）。
    ///
    /// **显式表而不是直接丢给 `ExternalPlatformNormalizer`**：后者的关键词表是按
    /// 「用户手填的平台名」设计的，对 `pspc_game`（PC）/ `psp_game`（PSP）这类紧凑写法
    /// 认不出来（`pspcgame` 里没有它认识的 `psp` 那条）。认不出来时才退回归一化器。
    ///
    /// `ps5_native_game` 必须排在前面 —— 它是 PS5 的原生版本，而 PS4 版在 PS5 上跑
    /// 也会出现在列表里（`ps4_game`），两者靠 category 区分。
    static func platform(forCategory raw: String?) -> String? {
        guard let raw else { return nil }
        let key = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch key {
        case "ps5_native_game", "ps5_game": return "PS5"
        case "ps4_game": return "PS4"
        case "ps3_game": return "PS3"
        case "psvita_game", "ps_vita_game": return "PS Vita"
        case "psp_game": return "PSP"
        case "pspc_game": return "PC"
        default: return ExternalPlatformNormalizer.canonical(fromRaw: key)
        }
    }

    /// 奖杯标题的 `trophyTitlePlatform` → 平台列表。
    ///
    /// **与 `platform(forCategory:)` 分开写、不做成同一个函数**：那边的输入是单值
    /// （`ps4_game` 这种紧凑小写写法），这边的输入是**逗号分隔的显示名**
    ///（`"PS4,PSVITA"` / `"PS3"` / `"PS5"`）。合并只会让两张表互相污染。
    ///
    /// 三条口径：
    /// - **逐项判定**：列表里有一项认不出来就**只丢那一项**，不要让整条记录跟着归兜底 ——
    ///   `"PS4,PSVITA"` 里认不出 `VITA` 却把 PS4 也丢了，是比不识别更糟的失败。
    /// - **保留顺序、去重**：调用方（`PSNTrophyService`）按这个顺序挑「legacy 平台」。
    /// - 认不出来返回空数组（**不是** `[fallback]`）—— 兜底是调用方的决定，不是解析层的。
    static func platforms(forTrophyPlatform raw: String?) -> [String] {
        guard let raw else { return [] }
        var out: [String] = []
        for piece in raw.split(separator: ",") {
            let key = piece.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            let canonical: String?
            switch key {
            case "ps5": canonical = "PS5"
            case "ps4": canonical = "PS4"
            case "ps3": canonical = "PS3"
            case "vita", "psvita", "ps vita": canonical = "PS Vita"
            default: canonical = ExternalPlatformNormalizer.canonical(fromRaw: key)
            }
            if let canonical, !out.contains(canonical) { out.append(canonical) }
        }
        return out
    }

    /// 把一组 `TrophyCounts` 收成一个 `TrophyProgress`。
    ///
    /// **`defined` 与 `earned` 都缺 → 返回 nil**（= 没有奖杯数据），而不是一个全 0 的值：
    /// 全 0 是「有奖杯套但一个都没拿到」的合法状态，两者在界面上必须长得不一样
    /// （「0 / 42」vs「—」）。
    ///
    /// 负数（服务端自相矛盾）按 0 收；`platinum` 夹到 0/1。
    static func trophyProgress(defined: TrophyCounts?,
                               earned: TrophyCounts?,
                               percent: Double?) -> TrophyProgress? {
        guard defined != nil || earned != nil else { return nil }
        func count(_ value: Double?) -> Int { max(0, Int((value ?? 0).rounded())) }
        return TrophyProgress(
            platinumEarned: min(1, count(earned?.platinum)),
            goldEarned: count(earned?.gold),
            silverEarned: count(earned?.silver),
            bronzeEarned: count(earned?.bronze),
            platinumDefined: min(1, count(defined?.platinum)),
            goldDefined: count(defined?.gold),
            silverDefined: count(defined?.silver),
            bronzeDefined: count(defined?.bronze),
            percent: percent.map { min(100, max(0, Int($0.rounded()))) })
    }

    /// 从 302 的 `Location` 里取一次性 `code`。
    ///
    /// 形如 `com.scee.psxandroid.scecompcall://redirect/?code=v3.XXXX&...`。
    /// `psn-api` 的做法是「按 `redirect/` 切一刀再当查询串解」，这里更稳一点：
    /// 先按 URL 正确解析，再退到在原文里扫 `code=`（分隔符按 query / fragment 都认）。
    /// 取不到返回 nil（调用方据此提示「NPSSO 无效或已过期」，属 `.invalidCredential`）。
    static func code(fromRedirect location: String) -> String? {
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let components = URLComponents(string: trimmed) {
            if let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
               !code.isEmpty {
                return code
            }
            if let fragment = components.fragment,
               let code = queryValue(named: "code", in: fragment) {
                return code
            }
        }

        // 兜底：原文里扫。用户/中间层可能给出不是干净 URL 的 Location。
        for chunk in trimmed.split(whereSeparator: { "#?&".contains($0) }) {
            if let code = queryValue(named: "code", in: String(chunk)) { return code }
        }
        return nil
    }

    private static func queryValue(named name: String, in query: String) -> String? {
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0] == Substring(name) else { continue }
            let value = String(parts[1]).removingPercentEncoding ?? String(parts[1])
            return value.isEmpty ? nil : value
        }
        return nil
    }

    // MARK: - 「HTTP 200 里带 error」
    //
    // ⚠️ 这是 PSN 侧**独有的**失败形状，与 Nintendo 完全不同：请求成功、状态码 200、
    //    但 body 是 `{"error":{"code":…,"message":…}}`。只看状态码会把它当成一次成功的同步
    //    —— 后果是「你的账号里一个游戏都没有」，而那是最糟的失败模式：用户看不出是出错了。
    //    `psn-api` 的每个调用点后面都跟着一句 `if (response?.error) throw`，正是这个原因。

    /// 响应体顶层有没有服务端错误对象？有就给一个分类错误。
    ///
    /// **只取分类，绝不回传 `message`** —— 那是服务端自由文本，与我们「不把响应体内容带进
    /// 错误描述」的纪律相冲突（见 `ExternalAPIError`）。
    ///
    /// ⚠️ **这里不建立错误码表**：Sony 的 `code` 语义没有任何可靠资料，编一张表出来
    /// 就是拿猜测冒充事实。一律归成 `.apiChanged`（响应结构与预期不符）——
    /// 它既不会把用户误导向「重新登录」去白折腾一次重绑，也不会被静默当成成功。
    /// 待实测校正见 HANDOVER §53 待验证项。
    static func apiError(in data: Data) -> ExternalAPIError? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["error"] != nil else { return nil }
        // OAuth 形状（`{"error":"invalid_grant"}`）交给共享层已有的白名单判定，
        // 那条路能正确地区分出「需要重新登录」，别在这里抢它的活。
        if let oauth = ExternalAPIError.fromOAuthBody(data) { return oauth }
        return .apiChanged("psn api returned an error object inside a 200 response")
    }
}
