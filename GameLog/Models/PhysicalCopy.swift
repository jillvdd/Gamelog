import Foundation
import SwiftData

/// 持有记录（收藏家模式）：一个版本 + 数量 + 最多 6 张收藏照片。
@Model
final class PhysicalCopy {
    /// 版本名（必填，如「日版初版」「美版」）。
    var version: String
    /// 该版本持有数量（≥1）。
    var count: Int
    /// 收藏照片（最多 6 张）。「保存原图」关时存压缩 JPEG，开时存原图数据。
    var images: [Data]
    /// 添加先后（持有列表排序用）。
    var createdAt: Date

    /// 所属游戏（inverse 在 Game.copies 上声明）。
    var game: Game?

    init(version: String, count: Int = 1, images: [Data] = [], createdAt: Date = .now) {
        self.version = version
        self.count = count
        self.images = images
        self.createdAt = createdAt
    }
}
