import Foundation
import Security

/// znej Play Activity 的协议常量与响应模型。
///
/// **来源与性质（照实标注，不要美化）**：下面每个常量的值都逐字抄自
/// `wolveix/nintendo-go`（Apache-2.0，2026-08-24 版）的源码。它实现的是
/// **Nintendo Switch 应用 / Nintendo Store 应用读取自己 Play Activity 的后端** ——
/// 属于「**官方客户端使用、但未公开**」，**不是官方开发者 API**，代码注释里也不要这么叫。
///
/// ⚠️ 与 **Nintendo Switch Online（Coral / znc）** 是两套东西：znc 需要一个只能在 root
/// 安卓机上由任天堂 App 内部生成的 `f` 参数。**本实现完全不碰 znc，也不需要任何第三方
/// token / 代理 / 中转服务**（那正是本项目红线的反面）。
///
/// ⚠️ 该库自己标注为 experimental，且**没有**在真实账号上验证过。所以本层对响应的解析
/// 一律**宽松**：字段全可选、数字接受浮点、解析不出就当没有 —— 一次结构小变动不应该
/// 让整次同步失败。真实取值待实测校正（见 HANDOVER §53 待验证项）。
enum NintendoAPI {
    /// My Nintendo 侧的应用 ID（znej 用的就是这个）。
    static let clientId = "5c38e31cd085304b"
    /// 回调 scheme：`npf<clientId>`。
    static let callbackURLScheme = "npf" + clientId
    /// 回调地址：`npf<clientId>://auth`。
    static let redirectURI = callbackURLScheme + "://auth"

    static let accountsBase = "https://accounts.nintendo.com"
    static let appBase = "https://app-api.znej.nintendo.com"

    static let authorizeEndpoint = accountsBase + "/connect/1.0.0/authorize"
    static let sessionTokenEndpoint = accountsBase + "/connect/1.0.0/api/session_token"
    static let tokenEndpoint = accountsBase + "/connect/1.0.0/api/token"
    static let playHistoriesEndpoint = appBase + "/api/v2.0/users/me/play_histories"

    /// ⚠️ **未在一手源中核实的端点**。昵称用；取不到不影响绑定（见 `NintendoAccountService`）。
    static let accountProfileEndpoint = "https://api.accounts.nintendo.com/2.0.0/users/me"

    /// **必带**：网关没有 UA 一律拒绝（一手源原话：rejects a request without one）。
    /// 版本号抄自一手源，是它发布时模拟的客户端版本；任天堂改版可能让它失效。
    static let userAgent = "com.nintendo.znej/3.0.3 (iOS/26.0.1)"

    static let scope = "openid user user.mii user.email user.links[].id"

    /// 单请求超时（与一手源一致）。
    static let timeout: TimeInterval = 15

    /// 会话 token 的 `Gentry-Locale` 缺失时，任天堂回 **400** 而不是取默认值 —— 所以它是必带的。
    /// 取值按 App 当前语言算（`NintendoAuthService.locale(for:)`）。
    static let localeHeader = "Gentry-Locale"

    /// 端点常量是字符串（authorize 那个还要拼查询串），转 URL 这步单独收在一处。
    /// 不 force-unwrap：常量写错时给一个明确的错误，别在运行时崩。
    static func url(_ endpoint: String) throws -> URL {
        guard let url = URL(string: endpoint) else {
            throw ExternalAPIError.internalFailure("bad endpoint url")
        }
        return url
    }
}

// MARK: - 响应模型

extension NintendoAPI {
    /// `GET /api/v2.0/users/me/play_histories` 的响应。
    ///
    /// **刻意不声明 `hiddenTitleList`**：一手源把它当 `[]any`（形状未知 —— 那是用户刻意
    /// 隐藏的条目）。给它编一个具体形状，一旦猜错就会让**整个响应解码失败**。
    /// `Decodable` 会忽略未声明的键，所以不声明反而既安全又省事。
    struct PlayHistoryResponse: Decodable {
        var playHistories: [TitleEntry]?
        var recentPlayHistories: [DayEntry]?
        var lastUpdatedAt: String?
    }

    /// 一个标题的终身累计。
    struct TitleEntry: Decodable {
        var titleId: String?
        var titleName: String?
        /// 平台（新字段）。
        var platform: String?
        /// 平台（旧字段）。**与 `platform` 只会填一个** —— 用 `system` 取非空者。
        var deviceType: String?
        var imageUrl: String?
        var firstPlayedAt: String?
        var lastPlayedAt: String?
        var lastUpdatedAt: String?
        /// 用 `Double` 而不是 `Int` 收：JSON 里给 `120` 或 `120.0` 都能解出来。
        /// 猜错整数/浮点会让整个响应解码失败，这点宽容几乎零成本。
        var totalPlayedDays: Double?
        var totalPlayedMinutes: Double?

        /// 平台字段取非空的那一个（旧版 API 用 `deviceType`）。
        var system: String? {
            if let platform, !platform.isEmpty { return platform }
            if let deviceType, !deviceType.isEmpty { return deviceType }
            return nil
        }
    }

    /// 某一天的游玩（本实现不落库，保留结构以便将来做「最近游玩」）。
    struct DayEntry: Decodable {
        var playedDate: String?
        var dailyPlayHistories: [DayTitleEntry]?
    }

    struct DayTitleEntry: Decodable {
        var titleId: String?
        var titleName: String?
        var platform: String?
        var imageUrl: String?
        var totalPlayedMinutes: Double?
    }

    /// `POST /connect/1.0.0/api/session_token` 的响应。
    struct SessionTokenResponse: Decodable {
        var session_token: String?
    }

    /// `POST /connect/1.0.0/api/token` 的响应。
    /// ⚠️ 这个端点的请求体是 **JSON**（不是 form）—— 一手源用的是 `jsonRequest`。
    struct TokenResponse: Decodable {
        var access_token: String?
        var id_token: String?
        var token_type: String?
        var expires_in: Double?
    }

    /// `GET /2.0.0/users/me` 的响应。⚠️ 端点未经一手源核实，字段一律可选。
    struct ProfileResponse: Decodable {
        var id: String?
        var nickname: String?
        var country: String?
        var birthday: String?
    }
}

// MARK: - 容错解析

extension NintendoAPI {
    /// 任天堂给的时间戳：完整 RFC3339、带毫秒、不带时区、或纯日期。
    ///
    /// 照抄一手源的「依次试几种布局」策略（`RFC3339` → `2006-01-02T15:04:05` → `DateOnly`）。
    /// **解析不出返回 nil** —— 时间缺失是正常情况（`ExternalGameRecord.firstPlayedAt` 本就可空），
    /// 不能让它变成一次同步失败。
    static func parseTimestamp(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        for formatter in iso8601Formatters {
            if let date = formatter.date(from: trimmed) { return date }
        }
        for formatter in plainFormatters {
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }

    /// 带时区的 ISO-8601（含/不含毫秒两种）。
    private static let iso8601Formatters: [ISO8601DateFormatter] = {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return [withFraction, plain]
    }()

    /// 不带时区与纯日期两种。Go 的 `time.Parse` 对无时区输入按 UTC 处理，这里保持一致，
    /// **不要**改成本地时区 —— 那会让同一份数据在不同时区的设备上落到不同日期。
    private static let plainFormatters: [DateFormatter] = {
        ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = format
            return formatter
        }
    }()

    /// 从 `id_token`（JWT）里读出 claim。
    ///
    /// ⚠️ **不验签**，只解 base64 读字段。这样可接受的前提是：
    /// ① 它是我方直接从任天堂 token 端点经 TLS 收到的，不是第三方转交的；
    /// ② 读出来的值**只用于本机身份标识与展示，绝不参与任何授权判定**
    ///    （能不能同步只取决于凭证在服务端是否被接受）。
    /// 一旦有人想拿它当鉴权依据，这个前提就不成立了。
    static func idTokenClaims(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }

        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }
}

/// 浏览器登录回调里我们关心的两样东西。
struct NintendoCallback {
    /// `session_token_code`（**一次性**，换完即废）。
    let code: String
    /// 回显的 `state`。可能缺失 —— 缺失时调用方不做校验：
    /// 真正拦住「拿别人的 code 来换」的是 PKCE 的 verifier，`state` 在这里只用来
    /// 识别「用户粘的是上一次登录的旧链接」。
    let state: String?
}

// MARK: - PKCE 与 base64url

extension NintendoAPI {
    /// PKCE 用的随机串：base64url **无填充**（RawURLEncoding）。
    /// 一手源用 36 字节做 state、32 字节做 verifier，这里保持一致。
    static func randomBase64URL(byteCount: Int) -> String? {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes) == errSecSuccess else {
            return nil
        }
        return Data(bytes).base64URLEncodedString()
    }

    /// 从回调 URL 里取 `session_token_code` 与回显的 `state`。
    ///
    /// **code 在 URL 的 fragment 里，不在 query** —— 只查 query 永远取不到。
    /// 这里先按 URL 正确解析，再退到「在原文里扫键值对」：用户复制回来的往往不是干净 URL
    /// （带浏览器 UI 文字、被截断、只有 fragment），扫一遍能救回一部分。
    ///
    /// 取不到返回 nil（调用方据此提示「粘贴的链接不对」，属 `.invalidCredential`）。
    static func parseCallback(_ raw: String) -> NintendoCallback? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let components = URLComponents(string: trimmed) {
            // fragment 优先：那是 code 真正所在的位置。
            if let fragment = components.fragment,
               let code = queryValue(named: "session_token_code", in: fragment) {
                return NintendoCallback(code: code,
                                        state: queryValue(named: "state", in: fragment))
            }
            if let code = components.queryItems?
                .first(where: { $0.name == "session_token_code" })?.value,
               !code.isEmpty {
                let state = components.queryItems?.first(where: { $0.name == "state" })?.value
                return NintendoCallback(code: code, state: state)
            }
        }

        // 兜底：在原文里扫 `session_token_code=...`（分隔符按 fragment / query 的写法都认）。
        for chunk in trimmed.split(whereSeparator: { "#?&".contains($0) }) {
            let text = String(chunk)
            guard let code = queryValue(named: "session_token_code", in: text) else { continue }
            return NintendoCallback(code: code, state: queryValue(named: "state", in: text))
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
}

extension Data {
    /// base64url（RFC 4648 §5）无填充编码。
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
