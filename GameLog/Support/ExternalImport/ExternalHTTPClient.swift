import Foundation

/// 一次原始 HTTP 往返的结果。
struct ExternalHTTPResponse {
    let status: Int
    /// 响应头。**键统一小写** —— HTTP 头本就不区分大小写，统一在这里转一次，
    /// 省得每个调用点各写一遍 `Location`/`location` 的比较。
    let headers: [String: String]
    let data: Data

    var isSuccess: Bool { (200..<300).contains(status) }

    /// `Location`（PSN authorize 从重定向目标里取 code 用）。
    var location: String? { headers["location"] }
}

/// 外部 provider 的共享 HTTP 层。
///
/// **存在理由**：两家 provider 的请求纪律是同一套（超时、UA、节流、错误分类、
/// 「绝不记录响应体与凭证」），各写一份必然漂 —— 而这类漂移的后果是安全性的，
/// 不是风格问题。provider 只负责「拼 URL + 拼 header + 解析自己的结构」。
///
/// 安全约束（HANDOVER §53）：
/// 1. **本层没有任何日志出口**。没有 logger、没有 `print`、没有 `os_log` ——
///    不是「记得别打」，而是根本没有能打的地方。凭证只经请求头与请求体进 `URLRequest`。
/// 2. **凭证不得拼进 URL query**。URL 会进系统网络日志/崩溃报告；凭证一律走 header
///    或 POST body。（PSN 的 code 只出现在**响应**的 `Location` 里，不在我方请求里。）
/// 3. **cookies 不落盘、不收服务端 `Set-Cookie`**：ephemeral 配置 +
///    `httpCookieAcceptPolicy = .never` + `httpCookieStorage = nil`。
///    这不只是洁癖 —— PSN 侧账号身份是靠 cookie 传的（社区 issue #173 就是上一个账号的
///    cookie 泄漏到下一个账号），把 cookie 存储彻底关掉，这类串号在结构上不可能发生。
/// 4. **缓存关闭**：凭证相关的响应不该进 `URLCache`（那是磁盘上的明文副本）。
/// 5. 错误描述只带分类与**我方可控的**结构说明，绝不回传响应体原文。
///
/// 节流是**礼节性**的：任天堂/索尼都没有公开的速率限制文档，这里给一个最小请求间隔，
/// 避免一次同步把官方接口打爆。**这不是官方限速值**，不应当作「安全速率」来引用。
final class ExternalHTTPClient {
    private let defaultHeaders: [String: String]
    private let minimumRequestInterval: TimeInterval
    private let timeout: TimeInterval

    /// 允许重定向的会话（普通 API 调用）。
    private let session: URLSession
    /// 拒绝重定向的会话（PSN authorize：要的就是那个 3xx 本身）。
    private let noRedirectSession: URLSession
    private let noRedirectDelegate = NoRedirectDelegate()

    /// 节流状态。用锁而非 actor：本层是 Swift 5 语言模式（项目既有风格），
    /// 且要能从任意上下文（含 `@ModelActor` 里）直接调用。
    private let throttleLock = NSLock()
    private var nextAvailableAt: Date?

    /// 重试退避（固定值，不做指数退避 —— 见 `send` 注释）。
    private static let retryBackoff: TimeInterval = 0.8

    /// - Parameters:
    ///   - defaultHeaders: 每个请求都带的头（如任天堂强制要求的 `User-Agent`）。
    ///   - minimumRequestInterval: 两次请求的最小间隔（礼节性，非官方限速值）。
    ///   - timeout: 单请求超时（资源总超时取它的 4 倍，且不低于 120 秒）。
    ///   - protocolClasses: **仅供自动化测试**注入 `URLProtocol` 桩，让请求不出本机。
    ///     生产代码不传（走系统默认协议栈）。
    init(defaultHeaders: [String: String] = [:],
         minimumRequestInterval: TimeInterval = 0.35,
         timeout: TimeInterval = 30,
         protocolClasses: [AnyClass]? = nil) {
        self.defaultHeaders = defaultHeaders
        self.minimumRequestInterval = minimumRequestInterval
        self.timeout = timeout
        let configuration = Self.makeConfiguration(timeout: timeout,
                                                   protocolClasses: protocolClasses)
        self.session = URLSession(configuration: configuration)
        self.noRedirectSession = URLSession(configuration: configuration,
                                            delegate: noRedirectDelegate,
                                            delegateQueue: nil)
    }

    /// 会话配置：**所有隐私相关的开关都在这里一次关干净**（见类型头部约束 3、4）。
    private static func makeConfiguration(timeout: TimeInterval,
                                          protocolClasses: [AnyClass]?) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = max(timeout * 4, 120)
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        // 不要「等网络恢复再发」：离线时立刻失败，由协调器统一报「无网络」，
        // 而不是让一次同步挂在那里几分钟不动。
        configuration.waitsForConnectivity = false
        // 注入桩会**整体替换**默认协议栈 —— 这正是测试要的：任何漏出去的请求都会失败，
        // 于是「测试没打真网络」这件事是被机制保证的，不是靠自觉。
        if let protocolClasses { configuration.protocolClasses = protocolClasses }
        return configuration
    }

    // MARK: - 主入口

    /// 发一次请求。
    ///
    /// 自动重试**只对幂等方法**（GET/HEAD）生效，且**至多一次**，固定短退避。
    /// 为什么不重试 POST：OAuth 的 code 换 token 是**一次性**的，传输层失败后盲目重发
    /// 可能把「其实已经成功」变成「invalid_grant」，反而制造出假的凭证失效。
    /// 为什么不做指数退避多次重试：官方接口没有公开限流策略，猛重试只会更快被封；
    /// 单次重试足以覆盖最常见的传输层抖动，剩下的交给用户「再同步一次」。
    func send(method: String = "GET",
              url: URL,
              headers: [String: String] = [:],
              body: Data? = nil,
              contentType: String? = nil,
              allowsRedirects: Bool = true,
              acceptStatuses: Set<Int> = []) async throws -> ExternalHTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        // 显式合并（不依赖 URLSession 的 config/request 头合并顺序，行为写在这里最清楚）。
        // 顺序：默认头 → 本次头，后者覆盖前者。
        for (key, value) in defaultHeaders { request.setValue(value, forHTTPHeaderField: key) }
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        request.httpBody = body

        let session = allowsRedirects ? self.session : self.noRedirectSession
        let mayRetry = (method == "GET" || method == "HEAD")

        try await throttle()
        do {
            return try await perform(request, on: session, acceptStatuses: acceptStatuses)
        } catch let error as ExternalAPIError where mayRetry && error.isRetryable {
            try await Task.sleep(nanoseconds: UInt64(Self.retryBackoff * 1_000_000_000))
            return try await perform(request, on: session, acceptStatuses: acceptStatuses)
        }
    }

    private func perform(_ request: URLRequest, on session: URLSession,
                         acceptStatuses: Set<Int>) async throws -> ExternalHTTPResponse {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            // 任务取消不是错误，是取消 —— 原样上抛，别包装成 .network 触发无意义重试。
            if urlError.code == .cancelled { throw CancellationError() }
            throw ExternalAPIError.network(ExternalAPIError.describe(urlError.code))
        }

        guard let http = response as? HTTPURLResponse else {
            throw ExternalAPIError.network("non-http response")
        }
        let headers = Self.lowercasedHeaders(http)
        if let error = Self.classify(status: http.statusCode, headers: headers,
                                     accepted: acceptStatuses, data: data) {
            throw error
        }
        return ExternalHTTPResponse(status: http.statusCode, headers: headers, data: data)
    }

    /// 状态码 → 分类。`accepted` 里的状态码视为成功（PSN authorize 要读 302 的 Location）。
    private static func classify(status: Int, headers: [String: String],
                                 accepted: Set<Int>, data: Data) -> ExternalAPIError? {
        if (200..<300).contains(status) || accepted.contains(status) { return nil }

        switch status {
        case 401, 403:
            return .authExpired
        case 429:
            return .rateLimited(retryAfter: retryAfter(headers))
        case 500...599:
            return .server(status)
        default:
            // 其余 4xx 先看有没有 OAuth 错误体：**任天堂把失效会话报成 400 而不是 401**，
            // 只看状态码会把它误判成「接口变了」。认不出来就按原始状态码归类。
            if let oauth = ExternalAPIError.fromOAuthBody(data) { return oauth }
            return .http(status)
        }
    }

    /// `Retry-After` 只认秒数形式；HTTP-date 形式返回 nil（解析它收益极低、失败面不小）。
    private static func retryAfter(_ headers: [String: String]) -> TimeInterval? {
        guard let raw = headers["retry-after"]?.trimmingCharacters(in: .whitespaces),
              let seconds = TimeInterval(raw), seconds >= 0 else { return nil }
        return seconds
    }

    private static func lowercasedHeaders(_ response: HTTPURLResponse) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            guard let name = key as? String else { continue }
            result[name.lowercased()] = (value as? String) ?? String(describing: value)
        }
        return result
    }

    // MARK: - 节流

    /// 取号式节流：**先把时间戳占住再放锁**，并发调用各拿各的槽位，
    /// 不会出现「同时算完、同时放行」的惊群。
    private func throttle() async throws {
        let (slot, now) = throttleLock.withLock { () -> (Date, Date) in
            let now = Date()
            let slot = max(now, nextAvailableAt ?? now)
            nextAvailableAt = slot.addingTimeInterval(minimumRequestInterval)
            return (slot, now)
        }

        let wait = slot.timeIntervalSince(now)
        if wait > 0 { try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
    }

    // MARK: - 便捷入口

    /// GET，返回原始数据。
    func get(_ url: URL, headers: [String: String] = [:]) async throws -> Data {
        var merged = headers
        if merged["Accept"] == nil { merged["Accept"] = "application/json" }
        return try await send(method: "GET", url: url, headers: merged).data
    }

    /// GET，解 JSON。
    func getJSON<T: Decodable>(_ type: T.Type, _ url: URL,
                               headers: [String: String] = [:]) async throws -> T {
        try Self.decode(T.self, from: try await get(url, headers: headers))
    }

    /// GET，返回完整响应（不解 body，也不把非 2xx 当失败 —— 调用方用 `acceptStatuses` 指定）。
    func getRaw(_ url: URL, headers: [String: String] = [:],
                allowsRedirects: Bool = true,
                acceptStatuses: Set<Int> = []) async throws -> ExternalHTTPResponse {
        try await send(method: "GET", url: url, headers: headers,
                       allowsRedirects: allowsRedirects, acceptStatuses: acceptStatuses)
    }

    /// POST form-urlencoded（OAuth 的 token / session_token 端点都是这个形状）。
    func postForm(_ url: URL, fields: [String: String],
                  headers: [String: String] = [:]) async throws -> ExternalHTTPResponse {
        var merged = headers
        if merged["Accept"] == nil { merged["Accept"] = "application/json" }
        return try await send(method: "POST", url: url, headers: merged,
                              body: Self.formEncode(fields),
                              contentType: "application/x-www-form-urlencoded")
    }

    /// POST form，解 JSON。
    func postFormJSON<T: Decodable>(_ type: T.Type, _ url: URL, fields: [String: String],
                                    headers: [String: String] = [:]) async throws -> T {
        try Self.decode(T.self, from: try await postForm(url, fields: fields, headers: headers).data)
    }

    /// POST JSON（`Content-Type: application/json; charset=utf-8`）。
    ///
    /// 需要它是因为**同一个 provider 可能两种都用**：任天堂的 `session_token` 端点是
    /// form-urlencoded，而 `token` 端点是 JSON —— 照一手源，不能想当然统一成一种。
    func postJSON<T: Decodable>(_ type: T.Type, _ url: URL, body: [String: String],
                                headers: [String: String] = [:]) async throws -> T {
        var merged = headers
        if merged["Accept"] == nil { merged["Accept"] = "application/json" }
        let encoded: Data
        do {
            encoded = try JSONEncoder().encode(body)   // [String: String] 可直接编码
        } catch {
            throw ExternalAPIError.internalFailure("failed to encode json request body")
        }
        let response = try await send(method: "POST", url: url, headers: merged,
                                     body: encoded,
                                     contentType: "application/json; charset=utf-8")
        return try Self.decode(T.self, from: response.data)
    }

    // MARK: - 共用工具

    /// 解 JSON，把 `DecodingError` 统一转成 `.decoding`（只带字段路径，不带值）。
    /// 两家 provider 共用一处解码入口，错误分类才不会一边一个样。
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as DecodingError {
            throw ExternalAPIError.decoding(ExternalAPIError.describe(error))
        } catch {
            throw ExternalAPIError.decoding("not json")
        }
    }

    /// RFC 3986 unreserved 字符集之外的都百分号编码。
    /// 不用 `.urlQueryAllowed`（它放行 `+&=?` 等在 value 里有语义的字符，
    /// 于是含 `+` 的 base64 值会被服务端解成空格 —— 这类 bug 极难查）。键排序只为输出稳定。
    static func formEncode(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let pairs = fields.keys.sorted().map { key -> String in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let value = fields[key] ?? ""
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            return "\(encodedKey)=\(encodedValue)"
        }
        return Data(pairs.joined(separator: "&").utf8)
    }
}

/// 拒绝一切重定向。返回 `nil` 即不跟随 —— 此时 URLSession 把那个 3xx **原样交回调用方**，
/// PSN authorize 要读的正是它的 `Location`。
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
