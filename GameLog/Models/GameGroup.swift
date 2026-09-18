import Foundation
import SwiftData

/// 自定义分组（如"塞尔达系列"）。一个游戏可进多个分组，不可嵌套。
@Model
final class GameGroup {
    var name: String
    /// 分组评价（自由文字，可空）。
    var review: String = ""
    var createdAt: Date

    /// 多对多（inverse 在 Game.groups 上声明）。
    var games: [Game]

    init(name: String, review: String = "", createdAt: Date = .now) {
        self.name = name
        self.review = review
        self.createdAt = createdAt
        self.games = []
    }
}

extension GameGroup {
    /// 这个分组是不是**还挂在某个 context 上**（判据与理由见 `Game.isLive`）。
    /// 单独写一份而不是共用泛型：`@Model` 的 `modelContext` 由宏生成，且这里只给
    /// 「编辑窗口开着时目标被删」这一处守卫用 —— 多一层抽象不值当。
    var isLive: Bool { modelContext != nil }
}
