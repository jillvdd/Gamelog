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
    let width: Int
    let height: Int
    let style: String?
}

struct SteamGridDBResponse<T: Decodable>: Decodable {
    let success: Bool
    let data: T
}

/// SteamGridDB 客户端：按名字搜索游戏，取封面，下载图片。
/// 请求节流到约 2 次/秒（API 免费 key 的限速）。
struct SteamGridDBClient {
    let apiKey: String

    private static let base = "https://www.steamgriddb.com/api/v2"

    /// 搜索游戏。
    func search(term: String) async throws -> [SteamGridDBGameHit] {
        let query = term.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? term
        let url = URL(string: "\(Self.base)/search/autocomplete/\(query)")!
        let data = try await requestData(url)
        let response = try JSONDecoder().decode(SteamGridDBResponse<[SteamGridDBGameHit]>.self, from: data)
        return response.success ? response.data : []
    }

    /// 取某个游戏的封面列表（竖版 600x900 优先，也取横版 460x215 兜底）。
    func grids(for gameID: Int) async throws -> [SteamGridDBGrid] {
        let url = URL(string: "\(Self.base)/grids/game/\(gameID)?dimensions=600x900,460x215")!
        let data = try await requestData(url)
        let response = try JSONDecoder().decode(SteamGridDBResponse<[SteamGridDBGrid]>.self, from: data)
        return response.success ? response.data : []
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
