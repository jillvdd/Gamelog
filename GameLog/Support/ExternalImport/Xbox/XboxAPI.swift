import Foundation

// =============================================================================
//  Xbox Live（**经由 OpenXBL**）的协议常量、响应模型与容错解析。
//
//  ⚠️⚠️ 这是本项目里**唯一**一个数据要经过第三方服务器的 provider。
//      这句话必须留在文件最上面 —— 它不是一个实现细节，是这块代码的性质。
// =============================================================================
//
//  ## 三家 provider 的取数通道性质完全不同，别混为一谈
//
//  - **Nintendo / PlayStation：本机直连官方域名**（`app-api.znej.nintendo.com` /
//    `m.np.playstation.com` …）。只有**端点**是社区逆向来的，数据路径上没有第三方。
//  - **Xbox：数据先到第三方。** 微软官方那条链（Entra 应用 → 设备码 → 用户令牌 →
//    XSTS → titlehub）对**个人微软账号**走不通 —— 个人 MSA 没有 Entra tenant，
//    注册应用会被 `AADSTS50020` 挡死（微软文档明说这是预期行为），唯一解法是开
//    Azure 账号并绑银行卡。用户 2026-09-17 明确选择「改用 OpenXBL，我不搞自己的了」。
//    这条是 ROADMAP「零第三方中转」的**明文例外**，见 §63。
//
//  ## OpenXBL 是什么
//
//  `api.xbl.io`。**它自己在其 OpenAPI 里写的是 "unofficial Xbox Live API"** ——
//  不是微软官方服务。所以本实现（以及任何 UI 文案）**不得**把它包装成官方接口，
//  也不该把「OpenXBL」四个字印在用户看到的卡片标题上：挂牌照的是**微软的**身份与成绩
//  （Gamertag / Gamerscore / 成就），中转方只是取数通道。
//
//  代价如实记下（不是免责声明）：**用户的 API key 与请求内容会经过这台第三方服务器**。
//  凭证本身仍然只进 Keychain（`ExternalCredentialKind.xboxAPIKey`），不进 SwiftData、
//  不进备份、不进日志 —— 那几条纪律不受本条影响。
//
//  ## 鉴权
//
//  只有一个 opaque 的 **Personal API Key**（用户从 `https://xbl.io/dashboard` 自己建），
//  放在 **`X-Authorization`** 头里。**不是 `Authorization`** —— 写错这个头实测得到 401。
//  没有 OAuth、没有回调、没有短期 token 可派，所以它既不轮换也没有刷新机制。
//
//  ## 响应外壳（**成功与失败的形状不对称，两边都必须判**）
//
//  成功：`{"content": {...}, "code": 200}` —— `code` 是**数字**。
//  失败：`{"code": "ERROR", "message": "Invalid API key."}` —— `code` 是**字符串**，
//        且 HTTP 状态码是 **401**（2026-09-18 实测：伪造的 36 位 key / 明显不是 key
//        的串 / 空 key 各试一次，三次都是 `401` + 上面那个 body）。
//
//  只判一种会静默吞掉错误（spike 里正是这么踩的），所以 `Envelope` 两种都收。
//
//  ## 字段真实性标注（避免把推断写成事实）
//
//  下面每一条模型的字段名与类型都来自 **2026-09-18 对真账号（xuid `2535410324111447`、
//  330 条 title）的一次实测**，不是从文档抄的（OpenXBL 没有这些端点的公开文档）。
//  标了「⚠️ 未实测」的那些是**推断**，第一次真同步后应回来核对。
enum XboxAPI {
    /// 基址。**第三方中转**（见文件头）。
    static let base = "https://api.xbl.io"

    /// 账号档案（Gamertag / 头像 / xuid）。
    static let accountEndpoint = base + "/v2/account"
    /// 游玩记录（含成就数、Gamerscore、最近游玩、平台列表、封面）。
    static let titlesEndpoint = base + "/v2/titles"
    /// 游玩时长。**批量 POST**（逐游戏 GET 要 330 次请求，免费档 150/小时，不可行）。
    static let playerStatsEndpoint = base + "/v2/player/stats"

    /// 用户自助创建 Personal API Key 的页面（「设置 → 游戏账号 → Xbox → 打开」那个按钮）。
    /// 与 PSN 的两个按钮同一性质：把用户送到**服务方自己的**页面去拿码，我们不代收密码。
    static let dashboardPage = "https://xbl.io/dashboard"

    /// `URL` 形式（`openURL` 要的是 `URL`）。**不 force-unwrap**（项目纪律），
    /// 写坏了的后果是按钮不出现 —— 可被发现，比崩溃好。
    static let dashboardURL = URL(string: dashboardPage)

    /// 一次批量问多少个 titleId 的时长。**实测可行**：本机 330 条分 4 批问完。
    ///
    /// ⚠️ 服务端**不会**为每个请求的 titleId 都回一条 stat：第一批 100 个只回了 92 条。
    /// 把那 8 条单独再问一次**仍然一条都不回** —— 所以「没回」= 这条**没有时长数据**
    /// （Xbox 360 的游戏一律没有：实测 42 个 360 标题 0 个有值），
    /// **不是**被响应条数上限截掉。落 nil（界面显示「—」），不猜一个 0 进去。
    static let statsBatchSize = 100

    /// 单请求超时。比 PSN 的 20 秒宽一点：`/v2/titles` 一次要回 330 条（约 440KB），
    /// 而 PSN 那条是 200 条一页翻着拿的。
    static let timeout: TimeInterval = 30

    /// 端点常量是字符串，转 URL 这步单独收在一处。不 force-unwrap。
    static func url(_ endpoint: String) throws -> URL {
        guard let url = URL(string: endpoint) else {
            throw ExternalAPIError.internalFailure("bad xbl endpoint url")
        }
        return url
    }
}

// MARK: - 响应外壳

extension XboxAPI {
    /// OpenXBL 的响应外壳。
    ///
    /// **`code` 的两种形状都必须收下来**：成功是数字（`200`），失败是字符串
    /// （`"ERROR"`）。只声明 `Int` 的话失败响应会整个解码失败，于是「key 无效」
    /// 被误报成「接口变了」—— 用户该做的动作（重新绑）完全不同。
    struct Envelope<Content: Decodable>: Decodable {
        var code: Code?
        /// ⚠️ **服务端自由文本，绝不读取、绝不带进错误**（`ExternalAPIError` 的纪律）。
        /// 声明它只是为了不让「多了一个没声明的键」变成解码失败。
        var message: String?
        var content: Content?

        /// 成功是数字（`200`），失败是字符串（`"ERROR"`）。
        enum Code: Decodable {
            case status(Int)
            case token(String)

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let number = try? container.decode(Int.self) {
                    self = .status(number)
                    return
                }
                self = .token(try container.decode(String.self))
            }
        }
    }

    /// 外壳判定：这次响应算不算失败？成功返回 nil。
    ///
    /// ⚠️ **这里刻意不建错误码表。** 实测过的唯一一种字符串 `code` 是 `"ERROR"`，
    /// 而它**总是伴随 HTTP 401** —— 那个已经被共享层归成 `.authExpired` 了
    /// （`ExternalHTTPClient.classify`），不需要在这里再认一遍。
    /// 其余 token 的语义没有任何可靠资料，编一张表出来就是拿猜测冒充事实
    /// （与 `PSNAPI.apiError` 拒绝给 Sony 的错误码建表同一条纪律）。
    static func failure<Content>(in envelope: Envelope<Content>) -> ExternalAPIError? {
        switch envelope.code {
        case .status(let status) where (200..<300).contains(status):
            return nil
        case .status(let status):
            // 极少见（实测失败都是 401，已被共享层拦下）。真出现说明包装层自相矛盾。
            return .server(status)
        case .token:
            return .apiChanged("xbl response carried an error code inside a 2xx response")
        case nil:
            // 没有 code 字段：不是 OpenXBL 的形状，由调用方按「content 在不在」判。
            return nil
        }
    }

    /// 先过外壳、再解 `content`。**所有取数路径都走这一处** —— 绕开它的调用点会
    /// 把「失败响应」当成「服务端没给这个字段」，那正是外壳存在的理由。
    static func decode<Content: Decodable>(_ type: Content.Type, from data: Data) throws -> Content {
        let envelope = try ExternalHTTPClient.decode(Envelope<Content>.self, from: data)
        if let error = failure(in: envelope) { throw error }
        guard let content = envelope.content else {
            throw ExternalAPIError.apiChanged("xbl response has neither content nor an error code")
        }
        return content
    }

    /// 请求头的公共部分。**凭证只在这里进 HTTP 头**，绝不进 URL query（URL 会进系统网络日志）。
    ///
    /// 不加 `User-Agent`：OpenXBL 在 Cloudflare 后面按 UA 拦，`python-urllib` 的默认 UA
    /// 会被 403，而 **URLSession 的默认 UA 实测是通的**（spike 结论）。
    static func headers(apiKey: String, acceptLanguage: String? = nil) -> [String: String] {
        var headers = [
            "X-Authorization": apiKey,          // ⚠️ 不是 Authorization，写错实测 401
            "Accept": "application/json",
        ]
        if let acceptLanguage, !acceptLanguage.isEmpty {
            headers["Accept-Language"] = acceptLanguage
        }
        return headers
    }
}

// MARK: - 响应模型
//
// 与全部 provider 同一口径：**字段全可选、认不出来就当没有**。
// OpenXBL 是第三方包装，它自己转手的那一层随时可能改字段类型，
// 一次结构小变动不该让整次同步失败。
//
// ⚠️ 注意请求与响应的大小写**不一致**（两边都是实测值，不是笔误）：
//    请求体里写 `titleId`（驼峰），而批量统计的**响应**里是 `titleid`（全小写）。

extension XboxAPI {
    /// `GET /v2/account` 的响应。
    struct AccountResponse: Decodable {
        var profileUsers: [ProfileUser]?

        struct ProfileUser: Decodable {
            /// xuid —— 用作 `LinkedAccount.externalAccountId`。与 `hostId` 实测同值。
            var id: String?
            var hostId: String?
            var isSponsoredUser: Bool?
            var settings: [Setting]?

            struct Setting: Decodable {
                var id: String?
                var value: String?
            }
        }
    }

    /// `GET /v2/titles` 的响应。
    struct TitlesResponse: Decodable {
        var titles: [TitleEntry]?
        var xuid: String?
    }

    /// 一个已玩过的标题。
    ///
    /// ⚠️ **来源不给「首次游玩时间」，一个字都不给** —— 实测 330 条里没有任何与之相关的
    /// 字段（`titleHistory` 只有下面那三个键）。所以 `ExternalGameRecordDTO.firstPlayedAt`
    /// 恒为 nil，**不编**：界面上那一格显示「—」才是对的。
    /// ⚠️ 同样**不给 `playCount`**。
    struct TitleEntry: Decodable {
        /// 数字串（如 `"2131196662"`）。**去重与批量查时长的键**。
        var titleId: String?
        /// 标题名（**受 `Accept-Language` 影响**，实测 zh-CN 与 en-US 有 115/330 条不同）。
        var name: String?
        /// ⚠️ 来源把**可用平台**给成一个列表而不是单值（`["PC", "XboxSeries"]`）。
        /// 取值集合实测五种：`XboxSeries` / `XboxOne` / `Xbox360` / `PC` / `Win32`
        /// （另见过一条 `Nintendo Switch`）。组合最多的是 `XboxOne+XboxSeries`（118 条）。
        var devices: [String]?
        /// 成就与 Gamerscore。**330/330 条都有**。
        var achievement: Achievement?
        /// 最近游玩时间。`lastTimePlayed` 实测 330/330 条都有，
        /// 形如 `2026-09-15T01:20:50.0474465Z`（**七位**小数秒，见 `ExternalTimestamp`）。
        var titleHistory: TitleHistory?
        /// 封面。是 `store-images.s-microsoft.com` 的**商品图**，
        /// ⚠️ 实测给的是 `http://`，需要升级成 https 才下得下来（见 `secureImageURL`）。
        var displayImage: String?
        /// 媒体类型。本账号 330 条**全是 `"Game"`**（未见过别的取值）。
        var type: String?
        /// ⚠️ **这个才是「它是不是上世代/上上世代游戏」的来源事实**，与上面那个 `type` 不是一回事。
        ///
        /// 实测 330 条的取值与分布（2026-09-18 在真实响应上普查）：
        /// | 取值 | 条数 | 含义 |
        /// |---|---|---|
        /// | `Application` | 288 | 本世代（One / Series / PC）原生应用 |
        /// | `Xbox360Game` | 32 | Xbox 360 游戏 |
        /// | `XboxArcadeGame` | 8 | Xbox Live Arcade（360 世代的数字发行） |
        /// | `XboxOriginalGame` | 2 | 初代 Xbox 游戏（Ninja Gaiden Black / Morrowind） |
        ///
        /// **它把「360 及更早」这一类从推断变成了事实**：实测里 `devices` 含 `Xbox360` 的
        /// **42 条全部**是非 `Application`，而 `Application` 的 **288 条一条都不含 `Xbox360`**
        ///（两个集合完全不相交）。所以「这是不是 360 世代」不再需要靠 `devices` 的顺序去猜。
        ///
        /// ⚠️ **但它分不出 Xbox One 与 Xbox Series**：这两类的 `mediaItemType` 同为
        /// `Application`（实测 One-only 6 条 / Series-only 29 条 / 两者兼有 118 条，取值都一样），
        /// 那一段仍然只能走 `devices` 的折叠（见 `platform(forDevices:)`）。
        var mediaItemType: String?
        /// 与成就端点对号用。328/330 有值。**本功能暂不用**，留档。
        var serviceConfigId: String?

        struct Achievement: Decodable {
            var currentAchievements: Int?
            var totalAchievements: Int?
            var currentGamerscore: Int?
            var totalGamerscore: Int?
            /// 来源自己算的完成百分比。**本功能不用它**：成就卡按计数现算，
            /// 免得出现「来源说 43%、但 25/52 算出来是 48%」这种两套口径打架。
            var progressPercentage: Int?
        }

        struct TitleHistory: Decodable {
            var lastTimePlayed: String?
            var visible: Bool?
            var canHide: Bool?
        }
    }

    /// `POST /v2/player/stats` 的请求体。**批量**问一组 titleId 的某个统计项。
    ///
    /// ⚠️ 这是本功能里唯一一个 POST —— 不是「写操作」，是这个端点只收 POST
    ///（实测 GET 拿不到）。它只读数据，不改任何东西。
    struct PlayerStatsRequest: Encodable {
        var xuids: [String]
        var stats: [RequestedStat]

        struct RequestedStat: Encodable {
            var name: String
            var titleId: String     // ⚠️ 请求驼峰、响应全小写（两边都是实测值）
        }
    }

    /// `POST /v2/player/stats` 的响应。
    struct PlayerStatsResponse: Decodable {
        var statlistscollection: [Collection]?

        struct Collection: Decodable {
            var stats: [Stat]?
        }

        struct Stat: Decodable {
            /// ⚠️ 全小写（请求里是 `titleId`）。
            var titleid: String?
            var name: String?
            /// ⚠️ **实测是字符串**（`"1527"`），不是数字。用 `LenientInt` 收两种写法，
            /// 理由见那个类型本身。
            var value: LenientInt?
        }
    }

    /// 收「数字」或「数字字符串」两种写法。
    ///
    /// 存在的理由：`value` 实测是字符串，但 OpenXBL 是**第三方包装**，它转手的那一层
    /// 随时可能改成数字 —— 而字段类型一变，**整个响应**（330 条）解码失败会让整次同步
    /// 报「接口变了」。六行包装换掉一个「一次上游改动 = 全库同步失败」的失败面。
    ///
    /// 认不出来的值（非数字串、null）→ `nil`（= 这条没有数据）。
    struct LenientInt: Decodable {
        let value: Int?

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Int.self) {
                value = number
                return
            }
            if let text = try? container.decode(String.self) {
                value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
                return
            }
            value = nil
        }
    }
}

// MARK: - 解析

extension XboxAPI {
    /// `devices`（一份**可用平台列表**）→ 平台（`Presets.platforms` 的 canonical 值）。
    ///
    /// **一张显式表，而不是直接丢给 `ExternalPlatformNormalizer`**：后者的关键词表是按
    /// 「用户手填的平台名」设计的，`XboxSeries` / `XboxOne` / `Xbox360` / `Win32` 这几个
    /// 紧凑写法它一个都认不出（`key("XboxSeries")` = `xboxseries`，而对不上预设值
    /// `Xbox Series X|S` 的归一化键 `xboxseriess`）。认不出来时才退回归一化器 ——
    /// 实测出现过的那条 `Nintendo Switch` 正是靠它兜住的。
    ///
    /// 入库该落哪个平台 —— **先看来源给的一手事实，事实没有才折叠 `devices`**。
    ///
    /// 分工：
    /// ① `mediaItemType` 是**来源明说的**「这是哪一类的游戏」（`Xbox360Game` / `XboxArcadeGame` /
    ///    `XboxOriginalGame`），命中就直接采信 —— 那 42 条从此不再经过任何推断；
    /// ② `Application`（本世代的 288 条）与取值缺失时才落到 `devices` 的折叠，
    ///    而那一段要分的只剩「Xbox One 还是 Xbox Series」（见 `platform(forDevices:)` 的局限）。
    ///
    /// 两级是**严格兜底**关系：② 的结果对 ① 命中过的那些条目本来也逐字相同
    ///（实测两个集合完全不相交：含 `Xbox360` 的 42 条全是非 `Application`，288 条 `Application`
    /// 一条都不含 `Xbox360`），所以这里**不会改变任何既有条目的落库结果**，
    /// 唯一的变化是「这个判断的依据从顺序变成了来源事实」——
    /// 外加初代 Xbox 那 2 条从 `Xbox 360` 归正到预设里的 `Xbox`。
    static func platform(forMediaItemType mediaItemType: String?, devices: [String]?) -> String? {
        if let fact = platform(forMediaItemType: mediaItemType) { return fact }
        return platform(forDevices: devices)
    }

    /// `mediaItemType` → 平台。**只认来源明说的那三种**，`Application` 与认不出的一律返回 nil
    /// （nil 的语义是「这个字段没给出答案」，由调用方退到 `devices` —— 不是「没有平台」）。
    ///
    /// `XboxArcadeGame` 归 `Xbox 360`：Xbox Live Arcade 是 360 世代的数字发行渠道，
    /// 实测这 8 条（Super Meat Boy / Banjo-Kazooie / Plants vs. Zombies …）的 `devices`
    /// 也都是 `Xbox360+XboxOne+XboxSeries`。
    ///
    /// `XboxOriginalGame` 归 **`Xbox`**（预设里初代那一条，与 GameCube / PS2 同代）——
    /// 实测这 2 条是 Ninja Gaiden Black 与 Morrowind，都是 2001–2002 年初代游戏。
    /// 折叠 `devices` 会得到 `Xbox 360`（它们确实能在 360 上跑），但那是向下兼容，
    /// 不是它原本属于哪一代 —— 来源既然明说了，就没有理由再退回推断。
    static func platform(forMediaItemType mediaItemType: String?) -> String? {
        guard let raw = mediaItemType?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        switch raw {
        case "XboxOriginalGame": return "Xbox"
        case "Xbox360Game", "XboxArcadeGame": return "Xbox 360"
        // `Application` = 本世代，没有回答「One 还是 Series」；未见的取值一律不猜。
        default: return nil
        }
    }

    /// `devices`（**可用平台列表**）→ 入库用的单个平台。
    ///
    /// **取列表里最老的一代**（= 这个标题**原生**属于的那一代）。
    ///
    /// ⚠️ 这里曾经是「取最新的一代」，**错了**，2026-09-18 用户报回来的原话：
    /// 「很多游戏都是只有明确的上世代（xbox one）版的，比如 Dark Souls III，但是在同步入库的
    /// 时候被划分成了 Xbox Series X 游戏」「甚至 Avatar 或者 Call of Duty 2 这种 Xbox 360 游戏
    /// 也被划分成了 Xbox Series X 游戏」。
    ///
    /// 错在哪：**`devices` 是「这个标题能在哪些机器上玩」，不是「它是哪一代的」**。
    /// 向下兼容的 Xbox One 游戏会同时列出 `XboxOne` 与 `XboxSeries`（Dark Souls III 就是），
    /// 而 360 的兼容游戏会把 `Xbox360` 和后面两代一起列出来（Avatar / CoD 2 就是）——
    /// 取最新的一代等于**把「能向下兼容」误读成「是次世代版」**。
    ///
    /// ⚠️ **量级在真实响应上量过，比最初记的大**：把 330 条按两种折叠各跑一遍，
    /// 旧规则（取最新）落下 `Xbox Series X|S` **293 条 / 330（89%）**，
    /// 新规则（取最老）是 360: 42 / One: 206 / Series: 53 / PC: 28。
    /// 也就是说这不是「个别游戏错了」，而是**整库九成的平台标签都是错的**。
    ///
    /// 取最老的一代正是「这个标题原生是哪一代」：360 游戏 → `Xbox 360`、One 游戏 → `Xbox One`、
    /// 只在次世代上有的 → `Xbox Series X|S`。跨世代真原生双版本（如 Halo Infinite）会落在**较老**
    /// 那一代 —— 那是这份数据能给出的最接近事实的答案。
    ///
    /// ⚠️ **局限，如实记下**：本函数**分不出**「向下兼容」与「原生双版本」。两者在 `devices`
    /// 里长得一样（都含 `XboxSeries`），`mediaItemType` 也一样（都是 `Application`）——
    /// 实测 One-only / Series-only / 两者兼有这三组的字段取值**完全一致**，所以这不是「还没找到字段」，
    /// 是这份数据里**没有**能区分它们的事实。不猜。360 及更早那一类**已经不受这条局限影响**了
    ///（`mediaItemType` 给出了事实，见上）。
    /// 成就卡头部那行副标题仍按**完整列表**展开（`platforms(forRawPlatforms:)`），
    /// 「它能在哪几台上玩」这个事实一个字没丢。
    ///
    /// ⚠️ 实际入库走的是 `platform(forMediaItemType:devices:)`，本函数是它的第二级 ——
    /// 单独调用它的地方（`platforms(forRawPlatforms:)` 的逐个元素）是在问「这个取值本身
    /// 叫什么名字」，那时没有 `mediaItemType` 可看，也不该有。
    ///
    /// 认不出来返回 nil（**不是**返回兜底值）：兜底是入库路径的决定（`resolve(raw:fallback:)`），
    /// 不是解析层的。
    static func platform(forDevices devices: [String]?) -> String? {
        guard let devices, !devices.isEmpty else { return nil }
        let keys = devices.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        func has(_ names: String...) -> Bool { names.contains { keys.contains($0) } }

        // 顺序即语义：**从最老的一代往最新排**，第一个命中的就是原生那一代。
        if has("xbox360") { return "Xbox 360" }
        if has("xboxone") { return "Xbox One" }
        if has("xboxseries") { return "Xbox Series X|S" }
        if has("pc", "win32") { return "PC" }
        // 剩下的交给共享归一化器（按来源给的顺序，第一个认得出的算数）。
        for key in keys {
            if let canonical = ExternalPlatformNormalizer.canonical(fromRaw: key) { return canonical }
        }
        return nil
    }

    /// `devices` → 「这个标题**只有 PC**、一台主机都没有」。
    ///
    /// 判据是**列举**而不是「有没有 pc 这一项」：`["PC","XboxOne"]`（跨平台合集的常态）为假，
    /// 只有每个 token 都落在 `{pc, win32}` 里才为真。认不出的 token（实测见过一条
    /// `Nintendo Switch`）同样算「不是只有 PC」—— 宁可漏跳也不误跳。
    ///
    /// ⚠️ 这个函数**只回答「设备列表」这一问**，跳不跳还取决于另外两条
    /// （游玩时长为 0、这一轮时长取数成功），三条都在 `XboxGameService.records` 里合。
    /// 单独看这一条会把 `FINAL FANTASY XV WINDOWS EDITION` / `Halo: 士官長合輯`
    /// 这类「在 Xbox 上玩的 PC 版」一起误伤 —— 它们的 `devices` 也只有 PC，
    /// 但时长是 53h / 234h（2026-09-18 真库取证）。
    static func isPCOnly(devices: [String]?) -> Bool {
        guard let devices, !devices.isEmpty else { return false }
        return devices.allSatisfy { device in
            let key = device.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return key == "pc" || key == "win32"
        }
    }

    /// `platformRaw`（`"XboxOne,XboxSeries"`）→ **每个平台各自的** canonical 值。
    ///
    /// 与 `platform(forDevices:)` 的分工：那个是**入库**用的折算（列表 → 一个「原生那一代」），
    /// 这个是**展示**用的展开（列表 → 列表），给成就卡头部那行「哪个版本」用
    /// （同 PSN 侧的 `psnPlatformDisplay`：同一个游戏的两个世代版本会出两张卡，
    /// 没有这一行就分不出谁是谁）。
    ///
    /// ✅ **共用同一张映射表**：逐个元素调 `platform(forDevices:)`，所以
    /// 「`XboxSeries` 归到 `Xbox Series X|S`」这件事仍然只有一处定义。
    ///
    /// 认不出的那一项**丢掉、不整条归兜底**（与 `PSNAPI.platforms(forTrophyPlatform:)` 同口径），
    /// 重复项去重，顺序按来源给的顺序 —— 来源给的就是「这个 titleId 能在哪些机器上玩」。
    static func platforms(forRawPlatforms raw: String?) -> [String] {
        guard let raw else { return [] }
        var out: [String] = []
        for piece in raw.split(separator: ",") {
            let value = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty,
                  let canonical = platform(forDevices: [value]),
                  !out.contains(canonical) else { continue }
            out.append(canonical)
        }
        return out
    }

    /// `devices` → 落库的 `platformRaw`（来源给的原文，逗号连接）。
    ///
    /// 落库而不是丢掉，理由与 PSN 侧同一条：它是**唯一能校对映射表的证据**。
    /// 这里尤其重要 —— `XboxSeries` 这种紧凑写法与 `Presets.platforms` 的
    /// `Xbox Series X|S` 差得很远，映射对不对只能靠真实取值回头验。
    static func platformRaw(forDevices devices: [String]?) -> String? {
        guard let devices, !devices.isEmpty else { return nil }
        let cleaned = devices
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return cleaned.isEmpty ? nil : cleaned.joined(separator: ",")
    }

    /// 来源给的图片地址 → 可用的 https 地址。
    ///
    /// ⚠️ **实测来源给的是 `http://`**（`http://store-images.s-microsoft.com/image/apps.…`）。
    /// 原样丢给 `URLSession` 会被 ATS 挡掉 —— 本项目**没有任何 ATS 例外**，也不打算为它开一个，
    /// 表现会是「封面一条都下不来，而日志里什么都没有」。同一台主机同一个路径
    /// **https 实测 200**（`image/jpeg`，2160×2160 —— 1:1 方形图，会落进方形槽）。
    ///
    /// 所以只把 scheme 升级，**不动主机与路径**。认不出来的形状原样返回（不猜、不拼）。
    static func secureImageURL(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let insecure = "http://"
        if trimmed.hasPrefix(insecure) {
            return "https://" + trimmed.dropFirst(insecure.count)
        }
        return trimmed
    }

    /// 时间戳解析。实体在 `ExternalTimestamp`（**PSN 与 Xbox 共用一处**）——
    /// 两家给的都是 RFC3339，失败形状也一样（小数秒位数不是 3：PSN 两位、Xbox 七位）。
    static func parseTimestamp(_ raw: String?) -> Date? {
        ExternalTimestamp.parse(raw)
    }
}
