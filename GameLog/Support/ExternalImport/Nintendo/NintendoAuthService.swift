import Foundation
import CryptoKit

/// 一次待完成的浏览器登录。
struct NintendoLoginRequest {
    /// 让用户去这个地址登录。
    let url: URL
    /// PKCE 的 verifier —— **必须活到换取那一步**，且**不得落盘、不得进日志**。
    let codeVerifier: String
    /// 防串线的 `state`。
    let state: String
}

/// 由 session token 派生出来的短期凭证（只在内存里活 15 分钟）。
struct NintendoCredentials {
    let accessToken: String
    /// `id_token`。一手源发现网关有时只认它，所以一并带上（见 `NintendoPlayHistoryClient`）。
    let idToken: String?
}

/// Nintendo Account 的授权流程（浏览器一步 + 两次换取）。
///
/// **本层不认识 Keychain、不认识 SwiftData、不认识 UI** —— 它只做协议：生成登录 URL、
/// 从回调里取 code、把 code 换成 session token、用 session token 派生 access token。
/// 凭证存哪儿、界面怎么呈现由调用方决定。于是这一层可以脱离 app 独立自测，
/// 也不会出现「顺手把 token 写进库里」这种事（它根本没有能写的地方）。
///
/// 流程（全部照一手源实现，常量与出处见 `NintendoAPI` 头部）：
/// ① `makeLoginRequest()` → 把用户送去 `url` 登录 → 浏览器停在
///    `npf5c38e31cd085304b://auth#session_token_code=…&state=…`
/// ② `NintendoAPI.parseCallback(_:)` 取出 code（**在 fragment 里，不在 query**）
/// ③ `exchangeSessionTokenCode(_:codeVerifier:)` → **session_token（约 2 年）
///    —— 全流程里唯一值得持久化的值**
/// ④ `validCredentials()` → access_token（15 分钟，只在内存缓存）
///
/// 用 `actor` 是因为 access token 缓存是**共享可变状态**：一次同步里 UI 可能并行触发
/// 多次调用，用锁手工护着不如让类型系统管。
actor NintendoAuthService {
    /// 会话令牌的来源。Keychain 读取由调用方注入 —— 本层不认识 `KeychainStore`。
    typealias SessionTokenProvider = () async throws -> String?

    /// 提前量：别让 token 正好在「检查通过」与「请求发出」之间死掉（一手源取一分钟）。
    private static let expiryGrace: TimeInterval = 60

    private let http: ExternalHTTPClient
    private let sessionTokenProvider: SessionTokenProvider

    private var cachedAccessToken: String?
    private var cachedIDToken: String?
    private var cachedExpiresAt: Date?

    init(http: ExternalHTTPClient? = nil,
         sessionTokenProvider: @escaping SessionTokenProvider) {
        // `User-Agent` 是**必带**的（网关无 UA 一律拒绝），放在默认头里，
        // 于是这个 client 发出的每个请求都不会漏掉它。
        self.http = http ?? ExternalHTTPClient(
            defaultHeaders: [
                "User-Agent": NintendoAPI.userAgent,
                "Accept": "application/json"
            ],
            timeout: NintendoAPI.timeout
        )
        self.sessionTokenProvider = sessionTokenProvider
    }

    // MARK: - ① 登录 URL

    /// 生成登录 URL（PKCE S256）。纯函数 —— 不碰实例状态。
    ///
    /// ⚠️ 查询串是**手拼**的（复用 `formEncode` 的严格百分号编码），不是 `URLComponents`：
    /// `scope` 里带 `[]`、`redirect_uri` 里带 `://`，不同编码器对这些字符的处理不一致，
    /// 而一手源是 URL-encoded form 那套规则。手拼能保证与已验证的实现逐字节一致。
    static func makeLoginRequest() throws -> NintendoLoginRequest {
        guard let state = NintendoAPI.randomBase64URL(byteCount: 36),
              let verifier = NintendoAPI.randomBase64URL(byteCount: 32) else {
            throw ExternalAPIError.internalFailure("failed to generate pkce values")
        }
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()

        let query = String(decoding: ExternalHTTPClient.formEncode([
            "client_id": NintendoAPI.clientId,
            "redirect_uri": NintendoAPI.redirectURI,
            "response_type": "session_token_code",
            "scope": NintendoAPI.scope,
            "session_token_code_challenge": challenge,
            "session_token_code_challenge_method": "S256",
            "state": state,
            "theme": "login_form",
        ]), as: UTF8.self)

        guard let url = URL(string: NintendoAPI.authorizeEndpoint + "?" + query) else {
            throw ExternalAPIError.internalFailure("failed to build authorize url")
        }
        return NintendoLoginRequest(url: url, codeVerifier: verifier, state: state)
    }

    /// 回调里的 `state` 是否属于本次登录。
    ///
    /// **缺失 state 视为「无法校验」而不是「校验失败」** —— 用户手工粘贴的链接可能被截断，
    /// 因为截断就报错会让人不知所措；而真正阻止「拿别人的 code 来换」的是 PKCE 的 verifier，
    /// state 在这里的作用只是识别「粘的是上一次登录的旧链接」。
    static func callbackMatches(_ callback: NintendoCallback,
                                request: NintendoLoginRequest) -> Bool {
        guard let state = callback.state else { return true }
        return state == request.state
    }

    // MARK: - ② 换 session token

    /// 用回调里的 code 换 session token。**code 是一次性的**，换过一次就废。
    ///
    /// code 与 verifier 都放在 POST body 里 —— **不能拼进 URL**（URL 会进系统网络日志）。
    /// 返回值由调用方写入 Keychain；本层不落任何存储。
    func exchangeSessionTokenCode(_ code: String, codeVerifier: String) async throws -> String {
        let decoded: NintendoAPI.SessionTokenResponse = try await http.postFormJSON(
            NintendoAPI.SessionTokenResponse.self,
            NintendoAPI.url(NintendoAPI.sessionTokenEndpoint),
            fields: [
                "client_id": NintendoAPI.clientId,
                "session_token_code": code,
                "session_token_code_verifier": codeVerifier,
            ])

        guard let sessionToken = decoded.session_token, !sessionToken.isEmpty else {
            throw ExternalAPIError.apiChanged("session token response has no session_token")
        }
        return sessionToken
    }

    // MARK: - ③ 派生 access token

    /// 取一个当前可用的 access token。
    ///
    /// 缓存到过期才换：一个 token 管 15 分钟，而一次同步只发一两个请求 —— 不缓存的话
    /// 每次同步都要多发一个换取请求（一手源也是这么做的）。
    func validCredentials() async throws -> NintendoCredentials {
        if let token = cachedAccessToken, let expiresAt = cachedExpiresAt,
           Date().addingTimeInterval(Self.expiryGrace) < expiresAt {
            return NintendoCredentials(accessToken: token, idToken: cachedIDToken)
        }

        guard let sessionToken = try await sessionTokenProvider(), !sessionToken.isEmpty else {
            throw ExternalAPIError.authExpired
        }

        // ⚠️ 请求体是 **JSON**（一手源用 jsonRequest），**不是** form-urlencoded ——
        // 同一个 provider 的两个端点形状不同，别想当然统一。
        let decoded: NintendoAPI.TokenResponse = try await http.postJSON(
            NintendoAPI.TokenResponse.self,
            NintendoAPI.url(NintendoAPI.tokenEndpoint),
            body: [
                "client_id": NintendoAPI.clientId,
                "session_token": sessionToken,
                "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer-session-token",
            ])

        guard let accessToken = decoded.access_token, !accessToken.isEmpty else {
            throw ExternalAPIError.apiChanged("token response has no access_token")
        }

        cachedAccessToken = accessToken
        cachedIDToken = decoded.id_token
        cachedExpiresAt = Date().addingTimeInterval(decoded.expires_in ?? 900)
        return NintendoCredentials(accessToken: accessToken, idToken: decoded.id_token)
    }

    /// 凭证疑似失效时清掉缓存，下一次调用会重新派生。
    func invalidate() {
        cachedAccessToken = nil
        cachedIDToken = nil
        cachedExpiresAt = nil
    }

    // MARK: - Gentry-Locale

    /// 按 App 语言算 `Gentry-Locale`。**这个 header 是必带的** —— 不给值任天堂回 400，
    /// 而不是取默认值。
    ///
    /// ⚠️ 只有 `en-GB` 是**被一手源实证过**的取值（那是它的默认值）。其余是按任天堂各区域
    /// 商店的常见写法推的，**未经核实**。所以调用方在遇到 400 时会沿 `fallbackLocales`
    /// 往下试（见 `NintendoPlayHistoryClient`）—— 猜错语言的代价只是标题变成英文，
    /// 不该是整个功能不可用。
    ///
    /// 英文取 **`en-US`** 而不是一手源的 `en-GB`：用户点名要美版（2026-09-16）。这是**推定值**，
    /// 所以 `en-GB` 留在 `fallbackLocales` 里兜底 —— 万一 `en-US` 被拒，下一次尝试就落到
    /// 那个唯一被实证过的取值上，功能不会因此不可用。
    static func gentryLocale(appLocaleCode: String) -> String {
        let code = appLocaleCode.lowercased()
        if code.hasPrefix("ja") { return "ja-JP" }
        if code.hasPrefix("en") { return "en-US" }
        if code.hasPrefix("zh") {
            // 繁体走 zh-TW，简体走 zh-CN（同样是推定值）。
            return (code.contains("hant") || code.contains("tw") || code.contains("hk"))
                ? "zh-TW" : "zh-CN"
        }
        return fallbackLocales[0]
    }

    /// 按「账号的选择 + 当前 App 语言」算实际要用的 `Gentry-Locale`。
    ///
    /// 「跟随 App 语言」这一档必须在这里现算（`appLocaleCode` 是**当前**的界面语言），
    /// 而不是把结果落进账号 —— 落了就变成「绑定那天是什么语言就永远是什么语言」，
    /// 与这一档的名字不符。
    static func gentryLocale(for choice: ExternalTitleLocale, appLocaleCode: String) -> String {
        choice.explicitGentryLocale ?? gentryLocale(appLocaleCode: appLocaleCode)
    }

    /// 同一个语言在**别的区域**的写法。主值拿不全目标语言的标题时，`NintendoPlayHistoryClient`
    /// 会拿这些值再问一遍（逐条挑真的是目标语言的那个）。
    ///
    /// ## 为什么值得多问一遍（这不是猜，是有实测依据的）
    ///
    /// 真账号实测（2026-09-16，同一份 187 条游玩记录）：`zh-CN` 几乎全部回落成英文，
    /// `zh-TW` 有 41% 拿到繁體中文 —— **取值本身直接决定覆盖率**，而请求都是成功的
    /// （不是 400）。既然一个取值拿不全，同语言的另一个区域库就值得问。
    ///
    /// ## 纪律
    ///
    /// ⚠️ 除 `en-GB` 外这些全部是**推定值**，一手源只实证过 `en-GB`。所以三条约束：
    /// ① 每个候选失败都**不影响**主值已经拿到的结果（`try?` 吞掉）；
    /// ② 主值已经把覆盖面吃满时**根本不发**这些请求；
    /// ③ 只用它们**改进标题名与配图**，不用它们新增记录或改时长时间（见 `mergeNames`）。
    ///
    /// 列表刻意保持极短：每多一个候选就是每次同步多一次全量请求。**没有实测证据支持
    /// 覆盖率的写法不要往这里加** —— 这个函数的长度应该由证据决定，不是由想象力决定。
    static func gentryLocaleAlternates(forPrimary primary: String) -> [String] {
        switch primary {
        case "zh-TW": ["zh-HK"]     // 港区是与台区并列的另一套繁體标题库，实测值得一问
        case "zh-CN": ["zh-Hans"]   // 同一个语言的另一种写法：脚本标签式而非区域标签式
        default: []
        }
    }

    /// 兜底取值链，按「最可能是用户想要的」排序。
    ///
    /// - `en-US`：用户点名要的（美版）—— 推定值。
    /// - `en-GB`：唯一被一手源实证过的取值 —— 所以它永远留在链尾兜底。
    ///
    /// 两条一起用，就把「英文偏好」与「猜错语言不该让功能不可用」同时满足了：
    /// 请求的取值被 400 拒掉时沿这条链往下试，链尾那个一定还能用。
    ///
    /// ⚠️ 链长直接等于最坏情况下的请求数（`NintendoPlayHistoryClient.fetchWithLadder` 会
    /// 对每个取值试两种 bearer）。**只在有实测证据时才往这里加**。
    static let fallbackLocales = ["en-US", "en-GB"]

    /// 链尾那个「任何拿不准都退到这里」的取值。**只有它是被实证过的**。
    static var verifiedFallbackLocale: String { fallbackLocales[fallbackLocales.count - 1] }
}
