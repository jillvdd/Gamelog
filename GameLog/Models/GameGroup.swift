import Foundation
import SwiftData

/// 自定义分组（如"塞尔达系列"）。一个游戏可进多个分组，不可嵌套。
@Model
final class GameGroup {
    var name: String
    var createdAt: Date

    /// 多对多（inverse 在 Game.groups 上声明）。
    var games: [Game]

    init(name: String, createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
        self.games = []
    }
}
