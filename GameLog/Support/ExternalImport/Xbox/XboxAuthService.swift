import Foundation

/// OpenXBL 的鉴权。**结构上刻意与另外两家同构，尽管它几乎没有可做的事。**
///
/// Xbox 侧的鉴权就是**一个长期不轮换的 API key**：没有 OAuth、没有 code 换取、
/// 没有 access / refresh 之分，所以这里没有缓存、没有过期时间、没有重登。
///
/// 那为什么还要有这一层（而不是让 Service 直接读 Keychain）？
/// ① **「凭证从哪来」仍然只有一个注入点** —— Service 拿不到 Keychain 的句柄，
///    于是「凭证只在 Keychain 与同步驱动之间存在」这条纪律在 Xbox 上照样成立；
/// ② 绑定期用同一个类型就能试一次 key 是否可用，不必把 Keychain 写进去再读出来。
///
/// ⚠️ **本层没有 `invalidate()`，那不是遗漏**：另外两家的 `invalidate()` 清的是
/// **缓存的短期 token**，而这里根本没有可缓存的东西 —— key 每次现读 Keychain。
/// 一次 401 就是「这个 key 不被接受」，重试一万次也是同样的结果
///（见 `ExternalAPIError.isRetryable`：`.authExpired` 不可重试）。
struct XboxAuthService {
    /// API key 来源（Keychain 读取由调用方注入）。
    typealias APIKeyProvider = () async throws -> String?

    private let apiKeyProvider: APIKeyProvider

    init(apiKeyProvider: @escaping APIKeyProvider) {
        self.apiKeyProvider = apiKeyProvider
    }

    /// 取一个可用于请求的 key。
    ///
    /// Keychain 里没有（换机 / 抹掉设备 / 用户手动清过钥匙串）→ `.authExpired`，
    /// 与另外两家「凭证不在了」的收场一致：界面显示「需要重新登录」而不是「同步失败」。
    func apiKey() async throws -> String {
        let raw = try await apiKeyProvider()
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { throw ExternalAPIError.authExpired }
        return trimmed
    }
}
