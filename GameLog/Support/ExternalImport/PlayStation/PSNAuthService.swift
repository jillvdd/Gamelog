import Foundation

/// 由 refresh_token / NPSSO 换来的短期凭证（access token 只在内存活 1 小时）。
struct PSNCredentials {
    let accessToken: String
    /// refresh_token 的到期时间。**这是「这个绑定还能活多久」的答案** ——
    /// PSN 的 refresh_token 不轮换、不续期，会话有硬寿命上限，到期只能靠 NPSSO 重登。
    /// nil = 服务端没给这个字段（不是「永不过期」）。
    let refreshTokenExpiresAt: Date?
}

/// PSN 的一次完整换取结果。
///
/// ⚠️ **这里面装的是凭证原文**（access / refresh token）。它只在内存里短暂存在，
/// **唯一的持久化出口是 `refreshTokenSink`**（调用方接到后写 Keychain），
/// **不得**进日志、进 SwiftData、进备份 JSON。所以它是 `private` 且两个换取方法也是
/// `private` —— 一个装着凭证的类型没有理由在模块里到处可见；外部只有一个入口
/// `validCredentials()`，它保证「拿到的凭证一定已经交给了 sink」。
private struct PSNTokens {
    let accessToken: String
    let refreshToken: String?
    let accessTokenExpiresAt: Date
    let refreshTokenExpiresAt: Date?
}

/// PlayStation Network 的授权流程（NPSSO → code → token，外加 refresh）。
///
/// **本层不认识 Keychain、不认识 SwiftData、不认识 UI** —— 与 `NintendoAuthService` 同构：
/// 三个凭证来源（NPSSO / refresh_token）由调用方用闭包注入，换到的 refresh_token 交给调用方
/// 落 Keychain。于是这一层可以脱离 app 独立自测，也不存在「顺手把凭证写进库里」这种事。
///
/// ⚠️ **为什么 PSN 侧只能让用户手工粘贴 NPSSO**：Sony 的回调 scheme
/// `com.scee.psxandroid.scecompcall://` 是**安卓 PS App 私有的**，官方 iOS App 走的是
/// WKWebView 里的 JS bridge（`webkit.messageHandlers.sneiprlsif`），那套协议第三方 App
/// 用不了、也没被验证过。所以「手工复制 NPSSO」是**唯一可靠路径**，不是偷懒的降级。
/// 好在 NPSSO 只是一串从 Sony 自己页面复制的码，**用户从不需要把密码交给 GameLog**。
///
/// 用 `actor` 的理由与 Nintendo 侧相同：access token 缓存是共享可变状态。
actor PSNAuthService {
    /// NPSSO 来源（64 字符）。Keychain 读取由调用方注入。
    typealias NPSSOProvider = () async throws -> String?
    /// refresh_token 来源。
    typealias RefreshTokenProvider = () async throws -> String?
    /// 换到新 refresh_token 时交出去落盘。
    ///
    /// ⚠️ 实测 PSN 的 refresh_token **不轮换**，所以这个闭包通常写入的是同一个值。
    /// 仍然保留它，是因为「万一哪天开始轮换而我们没存」的后果是会话在某天**毫无征兆地失效**，
    /// 且用户完全无从判断原因；多做一次写入的成本几乎为零。
    typealias RefreshTokenSink = (String) async throws -> Void

    /// 提前量：别让 token 正好在「检查通过」与「请求发出」之间死掉。
    private static let expiryGrace: TimeInterval = 60
    /// 服务端不给 `expires_in` 时的默认寿命（社区实测 access token 约 1 小时）。
    private static let defaultAccessTokenLifetime: TimeInterval = 3_600

    private let http: ExternalHTTPClient
    private let npssoProvider: NPSSOProvider
    private let refreshTokenProvider: RefreshTokenProvider
    private let refreshTokenSink: RefreshTokenSink

    private var cachedAccessToken: String?
    private var cachedExpiresAt: Date?
    private var cachedRefreshTokenExpiresAt: Date?

    init(http: ExternalHTTPClient? = nil,
         npssoProvider: @escaping NPSSOProvider,
         refreshTokenProvider: @escaping RefreshTokenProvider,
         refreshTokenSink: @escaping RefreshTokenSink) {
        self.http = http ?? ExternalHTTPClient(
            defaultHeaders: ["Accept": "application/json"],
            timeout: PSNAPI.timeout)
        self.npssoProvider = npssoProvider
        self.refreshTokenProvider = refreshTokenProvider
        self.refreshTokenSink = refreshTokenSink
    }

    // MARK: - ① 拿 NPSSO 换一次性 code

    /// 用 NPSSO 换一次性 `code`。
    ///
    /// **这个请求永远不会返回 200** —— Sony 回 302，`code` 在 `Location` 头里，
    /// 所以我们显式关掉重定向跟随，把那个 3xx **原样收下来**读头。
    /// ⚠️ NPSSO 只放在 `Cookie` 头里，**绝不进 URL query**（URL 会进系统网络日志）。
    func exchangeNPSSOForAccessCode(_ npsso: String) async throws -> String {
        let url = try PSNAPI.url(PSNAPI.authorizeEndpoint, query: [
            "access_type": "offline",
            "client_id": PSNAPI.clientId,
            "redirect_uri": PSNAPI.redirectURI,
            "response_type": "code",
            "scope": PSNAPI.scope,
        ])
        let response = try await http.getRaw(
            url,
            headers: ["Cookie": "npsso=\(npsso)"],
            allowsRedirects: false,
            // 3xx 全部接受：一手实现观察到的是 302，但把 301/303/307/308 也收下来
            // 不会有害 —— 我们只读 `Location`，多认几种状态码只是少一种「莫名其妙失败」。
            acceptStatuses: [301, 302, 303, 307, 308])

        guard (300..<400).contains(response.status) else {
            // 200 意味着 Sony 没有按预期重定向（多半是 NPSSO 已经失效，页面直接渲染了）。
            throw ExternalAPIError.invalidCredential("psn authorize did not redirect")
        }
        guard let location = response.location, let code = PSNAPI.code(fromRedirect: location) else {
            throw ExternalAPIError.invalidCredential("psn authorize redirect has no code")
        }
        return code
    }

    // MARK: - ② 换 token

    /// 用一次性 `code` 换 access token + refresh token。**code 是一次性的**，换过即废。
    ///
    /// `redirect_uri` 必须与申请授权时**逐字节一致**（Sony 会校验）。
    /// body 是 form-urlencoded，且走 `postForm` —— **POST 不会被 HTTP 层自动重试**，
    /// 这正是我们要的：code 只能消费一次，盲重发会把「其实已经成功」变成 `invalid_grant`。
    private func exchangeAccessCodeForTokens(_ code: String) async throws -> PSNTokens {
        let response = try await http.postForm(
            try PSNAPI.url(PSNAPI.tokenEndpoint),
            fields: [
                "code": code,
                "redirect_uri": PSNAPI.redirectURI,
                "grant_type": "authorization_code",
                "token_format": "jwt",
            ],
            headers: ["Authorization": PSNAPI.basicAuthorization])
        return try Self.tokens(from: response)
    }

    /// 用 refresh_token 续一个 access token。
    ///
    /// ⚠️ 与「换 code」是**两个不同的 grant**：这里不带 `redirect_uri`，但**要带 `scope`**。
    /// 照一手实现，两处形状不同，别想当然统一。
    private func exchangeRefreshTokenForTokens(_ refreshToken: String) async throws -> PSNTokens {
        let response = try await http.postForm(
            try PSNAPI.url(PSNAPI.tokenEndpoint),
            fields: [
                "refresh_token": refreshToken,
                "grant_type": "refresh_token",
                "token_format": "jwt",
                "scope": PSNAPI.scope,
            ],
            headers: ["Authorization": PSNAPI.basicAuthorization])
        return try Self.tokens(from: response)
    }

    // MARK: - ③ 取一个当前可用的 access token

    /// 取一个当前可用的 access token（缓存到过期才换）。
    ///
    /// 顺序是「先 refresh，refresh 被拒才动 NPSSO」：NPSSO 的寿命是有限的、用一次少一次，
    /// 能不动就不动。但 refresh 报**凭证类**错误时立刻落到 NPSSO 重登 —— 那是 refresh 用完
    /// 硬寿命之后的唯一出路，不试就只能让用户手动重绑。
    ///
    /// **网络类失败不会触发重登**：网断了不代表凭证失效，白跑一趟还会掩盖真实原因。
    func validCredentials() async throws -> PSNCredentials {
        if let token = cachedAccessToken, let expiresAt = cachedExpiresAt,
           Date().addingTimeInterval(Self.expiryGrace) < expiresAt {
            return PSNCredentials(accessToken: token,
                                  refreshTokenExpiresAt: cachedRefreshTokenExpiresAt)
        }

        if let refreshToken = try await refreshTokenProvider(), !refreshToken.isEmpty {
            do {
                return try await adopt(try await exchangeRefreshTokenForTokens(refreshToken))
            } catch let error as ExternalAPIError where Self.warrantsNPSSORelogin(error) {
                // 落到下面走 NPSSO 重登。
            }
        }

        guard let npsso = try await npssoProvider(), !npsso.isEmpty else {
            throw ExternalAPIError.authExpired
        }
        let code = try await exchangeNPSSOForAccessCode(npsso)
        return try await adopt(try await exchangeAccessCodeForTokens(code))
    }

    /// 凭证疑似失效时清掉缓存，下一次调用会重新派生。
    func invalidate() {
        cachedAccessToken = nil
        cachedExpiresAt = nil
        cachedRefreshTokenExpiresAt = nil
    }

    // MARK: - 内部

    private func adopt(_ tokens: PSNTokens) async throws -> PSNCredentials {
        cachedAccessToken = tokens.accessToken
        cachedExpiresAt = tokens.accessTokenExpiresAt
        cachedRefreshTokenExpiresAt = tokens.refreshTokenExpiresAt

        if let rotated = tokens.refreshToken, !rotated.isEmpty {
            try await refreshTokenSink(rotated)
        }
        return PSNCredentials(accessToken: tokens.accessToken,
                              refreshTokenExpiresAt: tokens.refreshTokenExpiresAt)
    }

    /// 这个错误是否值得退回 NPSSO 重登。
    private static func warrantsNPSSORelogin(_ error: ExternalAPIError) -> Bool {
        switch error {
        // `.apiChanged` 也算：token 端点回 OAuth `invalid_client`/`unauthorized_client` 时
        // 共享层归到这一类，而它同样意味着这个 refresh grant 已经不被接受了。
        case .authExpired, .invalidCredential, .apiChanged: true
        case .network, .rateLimited, .server, .http, .decoding, .internalFailure: false
        }
    }

    /// 解 `/token` 的响应。**先探「200 里带 error」再解码** —— 否则那种响应会解码成
    /// 一个字段全空的 token，接着被当成「拿到凭证了」用下去。
    private static func tokens(from response: ExternalHTTPResponse) throws -> PSNTokens {
        if let apiError = PSNAPI.apiError(in: response.data) { throw apiError }

        let decoded = try ExternalHTTPClient.decode(PSNAPI.TokenResponse.self, from: response.data)
        guard let accessToken = decoded.access_token?.trimmingCharacters(in: .whitespacesAndNewlines),
              !accessToken.isEmpty else {
            throw ExternalAPIError.apiChanged("token response has no access_token")
        }

        let now = Date()
        let lifetime = decoded.expires_in ?? defaultAccessTokenLifetime
        return PSNTokens(
            accessToken: accessToken,
            refreshToken: decoded.refresh_token,
            accessTokenExpiresAt: now.addingTimeInterval(max(lifetime, 0)),
            refreshTokenExpiresAt: decoded.refresh_token_expires_in
                .map { now.addingTimeInterval(max($0, 0)) })
    }
}
