import Foundation

/// 绑定时要落进 `LinkedAccount` 的身份信息。
///
/// ⚠️ **没有「Gamertag 是不是真的」这个字段**。曾经有过，但没有任何读取方 ——
/// 而 `displayName` 本身已经保证了非空（取不到 Gamertag 时走可读的兜底名），
/// 界面不需要、也无从区分「这个名字是真的还是兜底的」。留一个没人读的字段只会
/// 让下一个人以为它被用着。真需要时再加，判据现成（`gamertag == nil`）。
struct XboxAccountIdentity {
    /// 用作 `LinkedAccount.externalAccountId`（xuid，19 位数字串）。
    let externalAccountId: String
    /// 展示名（Gamertag）。**绝不为空串** —— 取不到时退到可读的兜底。
    let displayName: String
    let avatarURLString: String?
}

/// 绑定 / 同步时解析账号身份（xuid + Gamertag + 头像）。
///
/// **一个端点就够**：`GET /v2/account` 一次给全（实测返回 `profileUsers[0]`，里面有
/// `id` / `hostId` / 16 项 `settings`）。与 PSN 那边要试两条取 accountId 的路径不同 ——
/// 那是因为 PSN 的 accountId 与档案在两个不同的服务上，而 Xbox 这边只有一家（OpenXBL）。
///
/// 拿不到 xuid 就**必须失败**：它是 `ExternalGameRecord` 唯一键的第 2 段，
/// 编一个会让记录在换绑后与旧账号的数据撞在一起。
///
/// ⚠️ 本服务**不写 Keychain、不碰 SwiftData** —— 与 `PSNAccountService` 同一条边界。
struct XboxAccountService {
    private let http: ExternalHTTPClient
    private let auth: XboxAuthService

    init(auth: XboxAuthService, http: ExternalHTTPClient? = nil) {
        self.auth = auth
        self.http = http ?? ExternalHTTPClient(
            defaultHeaders: ["Accept": "application/json"],
            timeout: XboxAPI.timeout)
    }

    func resolveIdentity() async throws -> XboxAccountIdentity {
        let apiKey = try await auth.apiKey()
        let response: XboxAPI.AccountResponse = try await getJSON(
            try XboxAPI.url(XboxAPI.accountEndpoint),
            headers: XboxAPI.headers(apiKey: apiKey))

        guard let user = response.profileUsers?.first,
              let xuid = Self.normalized(user.id) ?? Self.normalized(user.hostId) else {
            throw ExternalAPIError.apiChanged("xbl account response has no profileUsers[0].id")
        }

        let settings = user.settings ?? []
        let gamertag = Self.setting("Gamertag", in: settings)
            ?? Self.setting("ModernGamertag", in: settings)
            ?? Self.setting("UniqueModernGamertag", in: settings)

        return XboxAccountIdentity(
            externalAccountId: xuid,
            displayName: gamertag ?? Self.fallbackDisplayName(xuid: xuid),
            avatarURLString: XboxAPI.secureImageURL(Self.setting("GameDisplayPicRaw", in: settings)))
    }

    // MARK: - 请求

    private func getJSON<T: Decodable>(_ url: URL, headers: [String: String]) async throws -> T {
        let response = try await http.send(method: "GET", url: url, headers: headers)
        // 外壳（成功数字 code / 失败字符串 code）由 `XboxAPI.decode` 统一判 ——
        // 绕开它会把失败响应当成「服务端没给这个字段」。
        return try XboxAPI.decode(T.self, from: response.data)
    }

    // MARK: - 兜底

    /// 取一个档案 setting 的值（去空白；空串按「没有」处理）。
    ///
    /// **按 id 线性找而不是建字典**：一次就 16 项，而字典会掩盖「同一个 id 出现两次」
    /// 这种异常 —— 线性找天然取第一个，行为可预期。
    private static func setting(_ id: String, in settings: [XboxAPI.AccountResponse.ProfileUser.Setting]) -> String? {
        for setting in settings where setting.id == id {
            return normalized(setting.value)
        }
        return nil
    }

    private static func normalized(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    /// 没有 Gamertag 时的兜底展示名：品牌名 + xuid 后四位。
    ///
    /// 为什么允许显示 ID 片段：`xuid` 是服务端的账号标识，**不是凭证**
    /// （拿它登不进任何地方），而多个 Xbox 账号并存是明确支持的场景 ——
    /// 两行都叫「Xbox Live」的话用户根本分不清哪个是哪个。
    /// 与 `PSNAccountService.fallbackDisplayName` 同一口径。
    static func fallbackDisplayName(xuid: String) -> String {
        "\(AccountProvider.xbox.brandName) ···\(xuid.suffix(4))"
    }
}
