import Foundation

/// 下载来源侧的封面图（Nintendo / PSN 官方 CDN 的 `imageUrl`）并交给调用方落进 `Game` 的图槽。
///
/// **本类型不决定落哪个槽** —— 那是 `ImportCoordinator.fetchArtwork` 的活，因为它要按图片
/// 自己的宽高比来定（抓回来的是 1:1 官方图标还是竖版封面，由图说了算）。这里只负责
/// 「拿回来」+「确认它真的是一张图」。
///
/// 三条硬规则，每条都对应一种真实会发生的坏结局：
///
/// 1. **只填空白，绝不覆盖**。目标 Game 已经有图（用户自己挑的、或上一轮自动匹配填的）时
///    直接跳过。自动流程覆盖用户的选择是不可接受的 —— 而封面是库首页最显眼的字段。
/// 2. **失败静默**。下载失败（离线 / CDN 挂了 / 图被删）绝不让整次导入失败，甚至不该让
///    那一条记录算失败。封面是**装饰**，来源记录才是数据。
/// 3. **只认 https 且必须真的像图片**。URL 来自服务端响应，不是我们写死的常量。
///    `URL(string:)` 会把 `file:///…` 也解析成合法 URL，`URLSession` 会老老实实去读本地文件；
///    而一个 404 HTML 页或 JSON 错误体会被原样存成"封面"。所以两道闸：scheme 必须是 https，
///    字节头必须是已知图片格式。这两道闸都不贵。
struct ArtworkFetcher {
    private let http: ExternalHTTPClient

    /// 图片走独立的客户端：`Accept` 要与 API 请求分开（API 是 `application/json`），
    /// 节流间隔也放宽（CDN 不吃 API 那套限流）。
    init(http: ExternalHTTPClient? = nil) {
        self.http = http ?? ExternalHTTPClient(defaultHeaders: ["Accept": "image/*"],
                                               minimumRequestInterval: 0,
                                               timeout: 20)
    }

    /// 取一张图。任何一步不成立都返回 nil —— **本方法从不抛错**（规则 2）。
    func artworkData(from urlString: String?) async -> Data? {
        guard let url = Self.safeImageURL(urlString) else { return nil }
        guard let data = try? await http.get(url) else { return nil }
        guard Self.looksLikeImage(data) else { return nil }
        return data
    }

    // MARK: - 校验

    /// 只接受 https 的绝对 URL。
    ///
    /// 挡的是 `file:` / `data:` / `ftp:` 以及各种自定义 scheme —— 它们由**服务端**给过来，
    /// 而我们完全没有理由去读一个远端指定的本地路径。
    static func safeImageURL(_ raw: String?) -> URL? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false else { return nil }
        return url
    }

    /// 字节头是不是已知图片格式。
    ///
    /// 用魔数而不是解码：解码要引入平台图像框架（`AppImage` 在 macOS/iOS 各是一套），
    /// 而这里只需要回答「这是不是一张图」。认不出来就返回 false ——
    /// 后果只是没有封面（UI 本来就支持无封面），而不是把一段 HTML 存成封面。
    static func looksLikeImage(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(12))
        guard bytes.count >= 4 else { return false }

        // PNG：89 50 4E 47
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return true }
        // JPEG：FF D8 FF
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return true }
        // GIF：GIF8
        if bytes.starts(with: [0x47, 0x49, 0x46, 0x38]) { return true }
        // BMP：BM
        if bytes.starts(with: [0x42, 0x4D]) { return true }
        // RIFF....WEBP
        if bytes.count >= 12,
           bytes.starts(with: [0x52, 0x49, 0x46, 0x46]),
           Array(bytes[8..<12]) == [0x57, 0x45, 0x42, 0x50] { return true }
        // ISO-BMFF（HEIC/AVIF）：第 5–8 字节是 'ftyp'
        if bytes.count >= 12, Array(bytes[4..<8]) == [0x66, 0x74, 0x79, 0x70] { return true }
        return false
    }
}
