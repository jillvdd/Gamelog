import Foundation

/// SteamGridDB API v2 的搜索命中。
struct SteamGridDBGameHit: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let types: [String]?
}

/// SteamGridDB 的一张封面图（grid）。
struct SteamGridDBGrid: Decodable, Identifiable {
    let id: Int
    let url: String
    /// 缩略图 URL（浏览用,全尺寸图单张数百 KB）。
    let thumb: String?
    let width: Int
    let height: Int
    let style: String?
}

struct SteamGridDBResponse<T: Decodable>: Decodable {
    let success: Bool
    let data: T
    /// 列表端点（grids/heroes/logos）的分页信息；search 无此字段。
    var total: Int?
    var page: Int?
}

/// SteamGridDB 客户端：按名字搜索游戏，取封面，下载图片。
/// 请求节流到约 2 次/秒（API 免费 key 的限速）。
struct SteamGridDBClient {
    let apiKey: String

    init(apiKey: String) {
        self.apiKey = Self.sanitizedKey(apiKey)
    }

    /// 从存储值提取有效 key：取第一个空白分隔的 token（key 本身无空格）。
    /// 兼容从网页复制时把旁边文字（如「Revoke API Key」按钮）一起粘贴进来的情况，
    /// 也清理首尾空白。为空字符串返回空。
    static func sanitizedKey(_ raw: String) -> String {
        raw.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
    }

    private static let base = "https://www.steamgriddb.com/api/v2"

    /// 搜索游戏。
    func search(term: String) async throws -> [SteamGridDBGameHit] {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")
        let query = term.addingPercentEncoding(withAllowedCharacters: allowed) ?? term
        guard let url = URL(string: "\(Self.base)/search/autocomplete/\(query)") else {
            throw URLError(.badURL)
        }
        let data = try await requestData(url)
        let response = try JSONDecoder().decode(SteamGridDBResponse<[SteamGridDBGameHit]>.self, from: data)
        return response.success ? response.data : []
    }

    /// 取某个游戏的封面列表（竖版 600x900 优先，也取横版 460x215 兜底）。
    func grids(for gameID: Int) async throws -> [SteamGridDBGrid] {
        guard let url = URL(string: "\(Self.base)/grids/game/\(gameID)?dimensions=600x900,460x215") else {
            throw URLError(.badURL)
        }
        let data = try await requestData(url)
        let response = try JSONDecoder().decode(SteamGridDBResponse<[SteamGridDBGrid]>.self, from: data)
        return response.success ? response.data : []
    }

    /// 封面浏览分页结果。
    struct GridPage {
        let grids: [SteamGridDBGrid]
        let total: Int
        let page: Int
    }

    /// 封面浏览分页结果（**只取 2:3 竖版 600x900**——本 app 封面主格式，用户拍板；
    /// API 每页 50 条，`page` 从 0 起）。热门游戏 2:3 也有数十张（RE4 2005 ≈ 41 张），分页渐进浏览。
    func gridsPage(for gameID: Int, page: Int) async throws -> GridPage {
        guard let url = URL(string: "\(Self.base)/grids/game/\(gameID)?dimensions=600x900&page=\(page)") else {
            throw URLError(.badURL)
        }
        let data = try await requestData(url)
        let response = try JSONDecoder().decode(SteamGridDBResponse<[SteamGridDBGrid]>.self, from: data)
        return GridPage(grids: response.success ? response.data : [],
                        total: response.total ?? 0,
                        page: response.page ?? page)
    }

    /// 取某个游戏的宽幅横图 heroes（1920×620 / 3840×1240 等，适合背景/横幅用途）。
    /// 响应结构与 grids 完全一致，复用 SteamGridDBGrid。
    func heroes(for gameID: Int) async throws -> [SteamGridDBGrid] {
        guard let url = URL(string: "\(Self.base)/heroes/game/\(gameID)") else {
            throw URLError(.badURL)
        }
        let data = try await requestData(url)
        let response = try JSONDecoder().decode(SteamGridDBResponse<[SteamGridDBGrid]>.self, from: data)
        return response.success ? response.data : []
    }

    /// 取某个游戏的透明 clear logo（PNG，适合叠在背景/封面上）。
    func logos(for gameID: Int) async throws -> [SteamGridDBGrid] {
        guard let url = URL(string: "\(Self.base)/logos/game/\(gameID)") else {
            throw URLError(.badURL)
        }
        let data = try await requestData(url)
        let response = try JSONDecoder().decode(SteamGridDBResponse<[SteamGridDBGrid]>.self, from: data)
        return response.success ? response.data : []
    }

    /// 主页横幅候选（§46 用户最终口径）：**不要 2:3 封面**——只要宽幅 **hero** + 竖版卡片
    /// **342×482 / 660×930**（SGDB `dimensions` 过滤；这两档是用户指定的非 2:3 竖版尺寸）。
    func bannerCandidates(for gameID: Int) async throws -> [SteamGridDBGrid] {
        async let heros = heroes(for: gameID)
        guard let url = URL(string: "\(Self.base)/grids/game/\(gameID)?dimensions=342x482,660x930") else {
            throw URLError(.badURL)
        }
        let data = try await requestData(url)
        let resp = try JSONDecoder().decode(SteamGridDBResponse<[SteamGridDBGrid]>.self, from: data)
        let cards = resp.success ? resp.data : []
        let h = try await heros
        return h + cards
    }

    /// 横向封面浏览分页结果（**只取 920×430 横版**——游戏横向封面主格式；API 每页 50 条，`page` 从 0 起）。
    func landscapesPage(for gameID: Int, page: Int) async throws -> GridPage {
        guard let url = URL(string: "\(Self.base)/grids/game/\(gameID)?dimensions=920x430&page=\(page)") else {
            throw URLError(.badURL)
        }
        let data = try await requestData(url)
        let response = try JSONDecoder().decode(SteamGridDBResponse<[SteamGridDBGrid]>.self, from: data)
        return GridPage(grids: response.success ? response.data : [],
                        total: response.total ?? 0,
                        page: response.page ?? page)
    }

    /// 方形封面浏览分页结果（**只取 1:1 方形**——SGDB 方形有 512×512 与 1024×1024 两档，双档都查；
    /// 客户端再按 width == height 过滤兜住未来新增的方图尺寸。API 每页 50 条，`page` 从 0 起）。
    func squaresPage(for gameID: Int, page: Int) async throws -> GridPage {
        guard let url = URL(string: "\(Self.base)/grids/game/\(gameID)?dimensions=512x512,1024x1024&page=\(page)") else {
            throw URLError(.badURL)
        }
        let data = try await requestData(url)
        let response = try JSONDecoder().decode(SteamGridDBResponse<[SteamGridDBGrid]>.self, from: data)
        let all = response.success ? response.data : []
        return GridPage(grids: all.filter { $0.width == $0.height },
                        total: response.total ?? 0,
                        page: response.page ?? page)
    }

    /// 下载图片数据。
    func fetchImage(urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }

    /// 自动匹配封面：搜索第一个命中 → 竖版优先的第一张封面 → 下载。
    /// 无命中或无封面返回 nil（调用方静默降级）；网络/服务异常会 throw。
    func autoCover(for term: String) async throws -> Data? {
        let hits = try await search(term: term)
        guard let first = hits.first else { return nil }
        let all = try await grids(for: first.id)
        guard let grid = Self.sorted(all).first else { return nil }
        return try await fetchImage(urlString: grid.url)
    }

    /// 自动匹配附加图（1:1 方形封面/横向封面/背景图/Logo）：搜索第一个命中 → 对应端点第一张 → 下载。
    /// heroes/logos 一次全量返回、按像素面积大图优先；square/landscape 用尺寸过滤端点第一页（square 额外按 width==height 过滤）。
    func autoArtwork(for term: String, kind: ArtworkKind) async throws -> Data? {
        let hits = try await search(term: term)
        guard let first = hits.first else { return nil }
        guard let grid = try await artworkResults(for: first.id, kind: kind).first else { return nil }
        return try await fetchImage(urlString: grid.url)
    }

    /// 按图类取某游戏的候选图列表（kind→端点的唯一 switch；搜索面板与自动匹配共用）。
    /// poster 首页竖版优先排序；square/landscape 用尺寸过滤端点第 0 页；hero/logo 全量大图优先。
    func artworkResults(for gameId: Int, kind: ArtworkKind) async throws -> [SteamGridDBGrid] {
        switch kind {
        case .poster:
            let page = try await gridsPage(for: gameId, page: 0)
            return SteamGridDBClient.sorted(page.grids)
        case .square:
            return try await squaresPage(for: gameId, page: 0).grids
        case .landscape:
            return try await landscapesPage(for: gameId, page: 0).grids
        case .hero:
            return try await heroes(for: gameId).sorted { $0.width * $0.height > $1.width * $1.height }
        case .logo:
            return try await logos(for: gameId).sorted { $0.width * $0.height > $1.width * $1.height }
        }
    }

    /// 分页类型的**服务器全量总数**（gridsPage 的 `total` 字段）；hero/logo 不分页，返回第 0 页 count。
    /// CoverSearchSheet 的「加载更多」用此值判断是否还有下一页——用第 0 页 count 会让分页死掉。
    func artworkTotal(for gameId: Int, kind: ArtworkKind, firstPageCount: Int) async -> Int {
        guard kind.supportsPaging, let page = try? await artworkPage(for: gameId, kind: kind, page: 0) else {
            return firstPageCount
        }
        return max(page.total, firstPageCount)
    }

    /// 按图类取分页查询（仅 supportsPaging 类型；hero/logo 不分页返回 nil）。
    func artworkPage(for gameId: Int, kind: ArtworkKind, page: Int) async throws -> GridPage? {
        switch kind {
        case .poster: try await gridsPage(for: gameId, page: page)
        case .square: try await squaresPage(for: gameId, page: page)
        case .landscape: try await landscapesPage(for: gameId, page: page)
        case .hero, .logo: nil
        }
    }

    /// 竖版优先、大尺寸优先的封面排序（CoverSearchSheet 与自动匹配共用）。
    static func sorted(_ grids: [SteamGridDBGrid]) -> [SteamGridDBGrid] {
        grids.sorted { lhs, rhs in
            if lhs.height > lhs.width && rhs.height < rhs.width { return true }
            if lhs.height < lhs.width && rhs.height > rhs.width { return false }
            return (lhs.width * lhs.height) > (rhs.width * rhs.height)
        }
    }

    private func requestData(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        try await Task.sleep(nanoseconds: 500_000_000)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
