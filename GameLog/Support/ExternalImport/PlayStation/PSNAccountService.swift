import Foundation

/// 绑定时要落进 `LinkedAccount` 的身份信息。
struct PSNAccountIdentity {
    /// 用作 `LinkedAccount.externalAccountId`（PSN 的 accountId，18–19 位数字串）。
    let externalAccountId: String
    /// 展示名（在线 ID）。**绝不为空串** —— 取不到时退到可读的兜底。
    let displayName: String
    let avatarURLString: String?
    /// 在线 ID 是否真的来自服务端。false = 走的兜底名，UI 可据此提示用户去改。
    let hasRealOnlineId: Bool
}

/// 绑定完成后解析账号身份（accountId + 在线 ID + 头像）。
///
/// **两条取 accountId 的路径**（都是社区逆向端点，可靠性不同，必须都知道）：
/// ① `GET {trophyBase}/v1/users/me/trophySummary` → `accountId`。**首选** —— 奖杯服务是
///    PSN 上最稳的一个（存在十几年、变更极少），而且 `psn-api` 就是拿它当「我是谁」用的。
/// ② `GET {dmsBase}/v1/devices/accounts/me` → `accountId`。备选，设备服务。
/// ① 只是「端点不对/变了」就退 ② 保住绑定；① 报**凭证失效**则直接上抛 ——
/// 那说明凭证本身有问题，不该把一个半残的账号绑进去。
///
/// 拿不到 accountId 就**必须失败**：它是 `ExternalGameRecord` 唯一键的第 2 段，
/// 编一个（比如用 `"me"`）会让记录在换绑后与旧账号的数据撞在一起。
struct PSNAccountService {
    private let http: ExternalHTTPClient
    private let auth: PSNAuthService

    init(auth: PSNAuthService, http: ExternalHTTPClient? = nil) {
        self.auth = auth
        self.http = http ?? ExternalHTTPClient(
            defaultHeaders: ["Accept": "application/json"],
            timeout: PSNAPI.timeout)
    }

    func resolveIdentity() async throws -> PSNAccountIdentity {
        let credentials = try await auth.validCredentials()
        let bearer = credentials.accessToken
        let accountId = try await resolveAccountId(bearer: bearer)

        // 在线 ID 与头像取不到**不影响绑定** —— 账号能不能同步只取决于凭证。
        var profile: PSNAPI.ProfileResponse?
        do {
            profile = try await fetchProfile(accountId: accountId, bearer: bearer)
        } catch let error as ExternalAPIError {
            if case .authExpired = error { throw error }
            profile = nil
        }

        let onlineId = profile?.onlineId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasOnlineId = !(onlineId ?? "").isEmpty
        return PSNAccountIdentity(
            externalAccountId: accountId,
            displayName: hasOnlineId ? onlineId! : Self.fallbackDisplayName(accountId: accountId),
            avatarURLString: Self.avatarURL(from: profile?.avatars),
            hasRealOnlineId: hasOnlineId
        )
    }

    // MARK: - accountId

    private func resolveAccountId(bearer: String) async throws -> String {
        do {
            let summary: PSNAPI.TrophySummaryResponse = try await getJSON(
                try PSNAPI.url("\(PSNAPI.trophyBase)/v1/users/me/trophySummary"), bearer: bearer)
            if let id = Self.normalized(summary.accountId) { return id }
        } catch let error as ExternalAPIError {
            if case .authExpired = error { throw error }
            // 其余错误（端点变了 / 结构不符 / 200 带 error）退到备选路径。
        }

        let devices: PSNAPI.AccountDevicesResponse = try await getJSON(
            try PSNAPI.url("\(PSNAPI.dmsBase)/v1/devices/accounts/me", query: [
                "includeFields": "device,systemData",
                "platform": "PS5,PS4,PS3,PSVita",
            ]),
            bearer: bearer)
        if let id = Self.normalized(devices.accountId) { return id }

        throw ExternalAPIError.apiChanged("cannot determine psn account id")
    }

    // MARK: - 请求

    private func getJSON<T: Decodable>(_ url: URL, bearer: String) async throws -> T {
        let response = try await http.send(method: "GET", url: url,
                                           headers: ["Authorization": "Bearer \(bearer)"])
        // 与 `PSNGameService` 同理：200 里带 error 必须先探出来，否则会解码成空对象，
        // 被当成「服务端没给这个字段」而不是「这次请求失败了」。
        if let apiError = PSNAPI.apiError(in: response.data) { throw apiError }
        return try ExternalHTTPClient.decode(T.self, from: response.data)
    }

    private func fetchProfile(accountId: String, bearer: String) async throws -> PSNAPI.ProfileResponse {
        try await getJSON(try PSNAPI.url("\(PSNAPI.userProfileBase)/\(accountId)/profiles"),
                          bearer: bearer)
    }

    // MARK: - 兜底

    /// 最后一张头像。
    ///
    /// ⚠️ `avatars[]` 的顺序**未经核实**（社区截图里是小 → 大，但没有文档）。取最后一张是
    /// 按那个观察押的；押错的代价只是头像分辨率差一点，不影响任何功能与数据。
    private static func avatarURL(from avatars: [PSNAPI.ProfileResponse.Avatar]?) -> String? {
        avatars?
            .compactMap { $0.url?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .last { !$0.isEmpty }
    }

    private static func normalized(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    /// 没有在线 ID 时的兜底展示名：品牌名 + accountId 后四位。
    ///
    /// 为什么允许显示 ID 片段：`accountId` 是服务端的账号标识，**不是凭证**
    /// （拿它登不进任何地方），而多个 PSN 账号并存是本功能明确支持的场景 ——
    /// 两行都叫「PlayStation Network」的话用户根本分不清哪个是哪个。
    static func fallbackDisplayName(accountId: String) -> String {
        "\(AccountProvider.playstation.brandName) ···\(accountId.suffix(4))"
    }
}
