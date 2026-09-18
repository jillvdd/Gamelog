import Foundation

/// 绑定时要落进 `LinkedAccount` 的身份信息。
struct NintendoAccountIdentity {
    /// 用作 `LinkedAccount.externalAccountId`（Nintendo 的 naId）。
    let externalAccountId: String
    /// 展示名。**绝不为空串** —— 取不到昵称时退到可读的兜底。
    let displayName: String
    let country: String?
    let birthday: String?
    /// 昵称是否真的来自服务端。false = 走的兜底名，UI 可据此提示用户去改。
    let hasRealNickname: Bool
}

/// 绑定完成后解析账号身份（naId + 昵称）。
///
/// ⚠️ **两条取身份的路径，可靠性不同，必须都知道**：
/// ① `GET https://api.accounts.nintendo.com/2.0.0/users/me` —— 昵称与 naId 都在这里，
///    也是社区（nxapi 等多个独立实现）一致使用的端点。**但它不在一手源 `nintendo-go` 里**，
///    本次**未从一手源核实**。所以要能降级，不能把绑定成败押在它身上。
/// ② `id_token` 的 claim —— 一手源确实返回 `id_token`，从里面读 `sub` 是稳的
///    （它是我方直接从任天堂 token 端点经 TLS 收到的）。但那只是**一个稳定标识**，
///    不一定带昵称，且**未验签**（只读不鉴权，见 `NintendoAPI.idTokenClaims`）。
///
/// 于是顺序是：先 ① 拿全量；① 只是「端点不对/变了」就退 ② 保住绑定；
/// ① 报**凭证失效**则直接上抛 —— 那说明凭证本身有问题，不该把一个半残的账号绑进去。
///
/// 头像**暂不取**：Nintendo 侧头像字段（mii imageUri）本次未核实，宁可留 nil
/// （头像下载失败本就不影响账号可用），也不猜一个字段名写进去。
struct NintendoAccountService {
    private let http: ExternalHTTPClient
    private let auth: NintendoAuthService

    init(auth: NintendoAuthService, http: ExternalHTTPClient? = nil) {
        self.auth = auth
        self.http = http ?? ExternalHTTPClient(
            defaultHeaders: [
                "User-Agent": NintendoAPI.userAgent,
                "Accept": "application/json",
            ],
            timeout: NintendoAPI.timeout
        )
    }

    func resolveIdentity() async throws -> NintendoAccountIdentity {
        let credentials = try await auth.validCredentials()

        var profile: NintendoAPI.ProfileResponse?
        do {
            profile = try await fetchProfile(bearer: credentials.accessToken)
        } catch let error as ExternalAPIError {
            // 凭证失效不是「端点不对」，是用户要重新登录 —— 上抛，别退到 id_token 把问题盖住。
            if case .authExpired = error { throw error }
            profile = nil
        }

        if let id = profile?.id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            let nickname = profile?.nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasNickname = !(nickname ?? "").isEmpty
            return NintendoAccountIdentity(
                externalAccountId: id,
                displayName: hasNickname ? nickname! : Self.fallbackDisplayName(externalAccountId: id),
                country: profile?.country,
                birthday: profile?.birthday,
                hasRealNickname: hasNickname
            )
        }

        // 退路：从 id_token 读 `sub`。绑定能完成，只是多半没有昵称。
        guard let idToken = credentials.idToken,
              let claims = NintendoAPI.idTokenClaims(idToken),
              let subject = (claims["sub"] as? String)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !subject.isEmpty else {
            throw ExternalAPIError.apiChanged("cannot determine nintendo account id")
        }
        let nickname = (claims["nickname"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasNickname = !(nickname ?? "").isEmpty
        return NintendoAccountIdentity(
            externalAccountId: subject,
            displayName: hasNickname ? nickname! : Self.fallbackDisplayName(externalAccountId: subject),
            country: claims["country"] as? String,
            birthday: nil,
            hasRealNickname: hasNickname
        )
    }

    private func fetchProfile(bearer: String) async throws -> NintendoAPI.ProfileResponse {
        guard let url = URL(string: NintendoAPI.accountProfileEndpoint) else {
            throw ExternalAPIError.internalFailure("bad account profile url")
        }
        let response = try await http.send(method: "GET", url: url, headers: [
            "Authorization": "Bearer \(bearer)",
        ])
        return try ExternalHTTPClient.decode(NintendoAPI.ProfileResponse.self, from: response.data)
    }

    /// 没有昵称时的兜底展示名：品牌名 + 账号 ID 后四位。
    ///
    /// 为什么允许显示 ID 片段：`externalAccountId` 是服务端的账号标识，**不是凭证**
    /// （拿它登不进任何地方），而多个 Nintendo Account 并存是本功能明确支持的场景 ——
    /// 两行都叫「Nintendo Account」的话用户根本分不清哪个是哪个。
    static func fallbackDisplayName(externalAccountId: String) -> String {
        let suffix = externalAccountId.suffix(4)
        return "\(AccountProvider.nintendo.brandName) ···\(suffix)"
    }
}
