import Foundation

/// 外部账号（Nintendo / PSN）同步过程中的失败分类。
///
/// 分这么细的理由是**动作不同**：网络抖动是「稍后再试」，凭证失效是「必须重新登录」，
/// 结构变了是「等 GameLog 适配」。全塌成一个 `Error` 的话 UI 只能给出一句无用的
/// 「同步失败」，用户不知道该做什么。
///
/// 硬性约束（HANDOVER §53）：
/// 1. **任何分支都不得把服务端响应体原文或凭证带进错误**。带关联值的那几个 case
///    只收**我方可控的结构说明**（如「playHistories 不是数组」），构造点在 Service 层，
///    由人写死；本层不做任何 `String(data:)` 转换后抛错的事。
/// 2. `errorDescription` 只给中性短句，**不含关联值** —— 万一有人把它直接扔进弹窗，
///    也不会漏出诊断细节。开发者要看细节用 `diagnosticDetail`。
enum ExternalAPIError: Error, Equatable {
    /// 传输层失败：无网络 / 超时 / DNS / TLS。**可重试**。
    case network(String)

    /// 凭证失效或不被服务端接受（HTTP 401/403，或 OAuth `invalid_grant`）→ 需要重新绑定。
    /// **必须与 `.network` 分开**：一个是「稍后再试」，一个是「重新登录」，混起来 UI 给不出正确动作。
    case authExpired

    /// 用户手工提供的凭证本身格式就不对（NPSSO 长度/字符不符、粘贴的回调 URL 里没有 code）。
    ///
    /// 单独成一类，是因为**只有这一类用户可以自己改好** —— 其余分类都只能引导重绑或等待。
    /// 只在绑定流程里出现，不会落进 `LinkedAccount.lastSyncErrorRaw`。
    case invalidCredential(String)

    /// 被限流。`retryAfter` 只在服务端给了 `Retry-After: <秒>` 时非空
    /// （HTTP-date 形式忽略 —— 解析它是额外的失败面，收益极低）。
    case rateLimited(retryAfter: TimeInterval?)

    /// 响应能解析，但结构与预期不符（接口改了）。`detail` 只说「哪个字段怎么了」。
    case apiChanged(String)

    /// 服务端 5xx。**可重试**。
    case server(Int)

    /// 其他非 2xx 且无法进一步归类。
    case http(Int)

    /// 反序列化失败。`detail` 只含**字段路径**，绝不含字段值（见 `describe(_:DecodingError)`）。
    case decoding(String)

    /// 我方内部故障（随机数生成失败、URL 拼不出来、响应缺了必需字段等）。
    /// **不是**服务端的问题，重试无用；`detail` 同样只写我方可控的描述。
    case internalFailure(String)
}

// MARK: - 映射到落库分类

extension ExternalAPIError {
    /// 落库用的粗分类（`LinkedAccount.lastSyncErrorRaw` / `AccountSyncErrorKind`）。
    ///
    /// `AccountSyncErrorKind` 是给「下次同步时展示上次失败原因」用的，粒度比本类型粗：
    /// - `.decoding` 归到 `.apiChanged` —— 解析不了就是「接口跟我们对不上了」，与结构变化同因。
    /// - `.http` / `.internalFailure` 归到 `.unknown` —— 认不出来的就是认不出来，别硬塞进已知桶里。
    /// - `.invalidCredential` 归到 `.authExpired` —— 它本就不该落库（绑定期错误），
    ///   真要落了，对用户的动作提示与凭证失效一致：重新提供凭证。
    var syncErrorKind: AccountSyncErrorKind {
        switch self {
        case .network: .network
        case .authExpired, .invalidCredential: .authExpired
        case .rateLimited: .rateLimited
        case .apiChanged, .decoding: .apiChanged
        case .server: .server
        case .http, .internalFailure: .unknown
        }
    }

    /// 展示层文案 key（由分类决定，**不展示原始错误**）。
    var messageKey: String { syncErrorKind.labelKey }

    /// 是否值得原样重发一次。
    ///
    /// 只收「原样重发有意义」的三类：传输层抖动、5xx、限流。**凭证失效与结构变化重发一万次
    /// 也是同样的结果**，重试只会拖慢失败反馈。
    var isRetryable: Bool {
        switch self {
        case .network, .server, .rateLimited: true
        case .authExpired, .invalidCredential, .apiChanged, .http, .decoding, .internalFailure: false
        }
    }

    /// 供开发者定位的补充说明（**由我方构造，不含服务端原文与凭证**）。
    /// **UI 不得展示** —— 展示一律走 `messageKey` + L10n。
    var diagnosticDetail: String? {
        switch self {
        case .network(let detail), .invalidCredential(let detail),
             .apiChanged(let detail), .decoding(let detail), .internalFailure(let detail):
            detail
        case .authExpired, .rateLimited, .server, .http:
            nil
        }
    }
}

// MARK: - 中性描述

extension ExternalAPIError: LocalizedError {
    /// 刻意**不含关联值**：这里可能被任何通用错误弹窗取用，不能把诊断细节漏出去。
    var errorDescription: String? {
        switch self {
        case .network: "External API transport error"
        case .authExpired: "External API credential is no longer accepted"
        case .invalidCredential: "External API credential is malformed"
        case .rateLimited: "External API rate limit reached"
        case .apiChanged: "External API response shape changed"
        case .server(let status): "External API server error \(status)"
        case .http(let status): "External API HTTP error \(status)"
        case .decoding: "External API response could not be decoded"
        case .internalFailure: "External API client failed internally"
        }
    }
}

// MARK: - 构造辅助（Service 层共用）

extension ExternalAPIError {
    /// 从 OAuth 风格的错误体判定分类：`{"error": "...", "error_description": "..."}`。
    ///
    /// 为什么需要：**任天堂的账号端点把失效会话报成 HTTP 400 而不是 401**，
    /// 只看状态码会把它误判成「接口变了」。PSN 也可能以 **HTTP 200 携带 error 体**返回，
    /// 所以这个判定不能只看非 2xx —— 调用方两种时机都可以调。
    ///
    /// **只认白名单里的 `error` 码**（固定 token，取值有限，是协议的一部分）。
    /// `error_description` 是服务端自由文本，**绝不读取、绝不带进错误里**。
    /// 认不出来返回 nil，让调用方按状态码走原分类 —— 宁可粗，不可错。
    static func fromOAuthBody(_ data: Data) -> ExternalAPIError? {
        struct Envelope: Decodable { let error: String }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { return nil }

        switch envelope.error {
        case "invalid_grant", "access_denied":
            return .authExpired
        case "invalid_client":
            // client_id / 内嵌凭据不被接受了 —— 那是我们这一侧写死的常量过期，不是用户的问题。
            return .apiChanged("OAuth client rejected")
        case "unauthorized_client":
            return .apiChanged("OAuth grant type not permitted for client")
        case "invalid_request":
            return .apiChanged("OAuth request rejected")
        case "invalid_scope":
            return .apiChanged("OAuth scope rejected")
        default:
            return nil
        }
    }

    /// `DecodingError` → 只含**字段路径**的短说明。
    ///
    /// ⚠️ **不要用 `context.debugDescription`** —— 它会把出错处的字段值一起拼进去，
    /// 那正是「不得把响应体带进错误」要挡的东西。这里只走 `codingPath` 的 key 名。
    static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            "missing key \(path(context.codingPath + [key]))"
        case .typeMismatch(_, let context):
            "type mismatch at \(path(context.codingPath))"
        case .valueNotFound(_, let context):
            "null where a value was expected at \(path(context.codingPath))"
        case .dataCorrupted(let context):
            "corrupted data at \(path(context.codingPath))"
        @unknown default:
            "unknown decoding failure"
        }
    }

    private static func path(_ keys: [CodingKey]) -> String {
        keys.isEmpty ? "<root>" : keys.map(\.stringValue).joined(separator: ".")
    }

    /// `URLError.Code` → 短说明（开发者向，不含 URL）。
    static func describe(_ code: URLError.Code) -> String {
        switch code {
        case .notConnectedToInternet: "offline"
        case .timedOut: "timeout"
        case .cannotFindHost, .cannotConnectToHost: "cannot reach host"
        case .networkConnectionLost: "connection lost"
        case .secureConnectionFailed, .serverCertificateUntrusted: "tls failure"
        case .badServerResponse: "bad server response"
        default: "urlerror \(code.rawValue)"
        }
    }
}
