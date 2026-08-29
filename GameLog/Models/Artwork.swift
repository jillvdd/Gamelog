import CoreGraphics
import Foundation

/// 五类游戏图（2:3 封面 / 方形 / 横向 / 背景图 / Logo）的深模块。
///
/// 每类图的全部知识集中在一张表里：
/// - 编辑页标题 / 搜索面板标题 / 空结果提示（三个 L10n key）
/// - SteamGridDB 搜索端点与尺寸过滤（走 SteamGridDBClient 的对应方法）
/// - 编辑页缩略预览的宽高比与缩略图宽
/// - 是否 Toggle 门控（封面恒在是唯一例外）
/// - Game 上的存储字段读写（`Game.artwork(_:)` / `Game.setArtwork(_:_:)`）
///
/// 2026-08-29 深化：此前 kind 知识摊在 8 个文件（编辑页 70 行平行接线 × 5 类、
/// 客户端与搜索面板各一份 switch、BulkArtworkFill 脚本被迫手抄 kind→字段映射）。
/// 加一类新图从「10 文件 diff」变为「一个 case + 一个 Game 存储字段」。
///
/// L10n key 约定（勿改后缀，与枚举 case 一一对应）：
///   game.<raw>（编辑页 Toggle/标题）、cover.title<Cap>（搜索面板标题）、
///   cover.no<Cap>（空结果提示）。
enum ArtworkKind: String, CaseIterable, Identifiable, Hashable {
    case poster
    case square
    case landscape
    case hero
    case logo

    var id: String { rawValue }

    // MARK: - 表驱动配置

    /// 编辑页标题 / Toggle 文案 key（如 game.square）。
    var labelKey: String { "game.\(rawValue)" }

    /// 搜索面板标题 key（cover.title / cover.titleSquare …）。
    var searchTitleKey: String {
        self == .poster ? "cover.title" : "cover.title\(rawValue.prefix(1).uppercased())\(rawValue.dropFirst())"
    }

    /// 空结果提示 key（cover.noGrids / cover.noSquare …；poster 沿用历史 key 名）。
    var noResultKey: String {
        self == .poster ? "cover.noGrids" : "cover.no\(rawValue.prefix(1).uppercased())\(rawValue.dropFirst())"
    }

    /// 是否由 Toggle 门控（关 = 清空）。封面是主视觉恒显示，唯一例外。
    var isToggleGated: Bool { self != .poster }

    /// 编辑页缩略预览宽高比（nil = Logo 等不定比例，contain 显示 + 衬底）。
    var previewAspect: Double? {
        switch self {
        case .poster: 0.75
        case .square: 1.0
        case .landscape: 2.14
        case .hero: 3.1
        case .logo: nil
        }
    }

    /// 编辑页缩略预览宽。
    var previewThumbWidth: CGFloat {
        switch self {
        case .poster: 72
        case .square: 96
        case .landscape: 128
        case .hero: 168
        case .logo: 128
        }
    }

    /// 搜索面板网格列宽下限（poster 竖图窄格；hero 横图宽格）。
    var searchColumnRange: ClosedRange<Double> {
        switch self {
        case .poster: 90...120
        case .landscape, .hero: 200...280
        case .square, .logo: 140...200
        }
    }

    /// 是否支持分页加载（grids 端点的尺寸过滤查询；hero/logo 一次全量返回）。
    var supportsPaging: Bool { self == .poster || self == .square || self == .landscape }

    /// SteamGridDB 搜索词的编辑页建议列宽（搜索面板用）。
    /// 端点选择在 SteamGridDBClient.artworkData(for:kind:page:)（唯一 switch）。
}

// MARK: - Game 存储接口

extension Game {
    /// 读某类图（externalStorage 懒加载由 SwiftData 管理；解码走 ImageDecodeCache 的各视图扩展）。
    func artwork(_ kind: ArtworkKind) -> Data? {
        switch kind {
        case .poster: coverData
        case .square: squareData
        case .landscape: landscapeData
        case .hero: heroData
        case .logo: logoData
        }
    }

    /// 写某类图（nil = 清空）。所有图写入路径统一入口。
    func setArtwork(_ kind: ArtworkKind, _ data: Data?) {
        switch kind {
        case .poster: coverData = data
        case .square: squareData = data
        case .landscape: landscapeData = data
        case .hero: heroData = data
        case .logo: logoData = data
        }
    }
}
