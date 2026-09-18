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
///
/// 读写都在本文件：存储字段（`artwork(_:)` / `setArtwork(_:_:)`）在前，解码后的
/// `AppImage` 访问器（`coverImage` / `squareGridImage` 等）在后。
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

// MARK: - 解码后的图（读的唯一入口）

/// 2026-09-16：这六个访问器从 `Views/GameCardView.swift` 搬到这里 —— 它们**一行视图代码都没有**
/// （解码走 `Support/ImageDecodeCache`），却决定了每个格子怎么显示封面。搬过来有三个好处：
/// 与 `artwork(_:)` / `setArtwork(_:_:)` 读写同一处、能进 DataSmokeTest（视图文件编不进去）、
/// 以及「封面位读哪个槽」这条规矩不再藏在一个 600 行的视图文件里。
extension Game {
    /// 「封面位」的读法：**2:3 竖版封面优先，没有就用方形封面**。
    ///
    /// 为什么要有这层兜底：外部账号导入抓回来的是官方 1:1 图标，按用户要求写进「方形封面」
    /// 那一栏（见 `ImportCoordinator.fetchArtwork`）。而网格卡 / 列表卡 / 分组选择器 /
    /// 分享缩略图 / 详情页这些「封面位」读的都是本属性 —— 没有兜底的话，导入进来的游戏在
    /// 这些地方会变成一片空白，而图其实就在库里。
    ///
    /// ⚠️ 兜底**只影响读**，两个槽在库里始终是独立的（编辑页、备份、`setArtwork` 都按五类图
    /// 各存各的）。所以用户单独设了方形封面时，竖版槽照旧优先；两个都没有才是无封面。
    ///
    /// ⚠️ 这层兜底也让「只有方图」的游戏在竖版格子里的读法变成方图 —— 正是想要的：
    /// 显示层按 `AppImage.letterboxes(inBoxAspect:)` 判定，方图在 2:3 的框里会走
    /// `scaledToFit` 居中留白，而不是被左右裁一截（§54.6）。
    var coverImage: AppImage? {
        ImageDecodeCache.image(for: self, field: "cover", data: coverData) ?? squareImage
    }

    /// 「**方形网格**位」的读法：**1:1 方图优先，没有才退到竖版封面**。
    ///
    /// 为什么不能沿用 `coverImage`：那个属性的规矩是「2:3 竖版优先」（见上），于是两槽都有的
    /// 游戏（用户库里 125/278 款是这样）在方形网格里会显示竖版封面，塞进 1:1 的格子只剩中间
    /// 一条 —— 2026-09-17 用户实测反馈的原话就是「库内原有游戏的方形网格视图没有用方形封面
    /// 而是竖向封面」。方形网格有自己的读法，跟 `coverImage` 是**并列关系**，不是替代。
    ///
    /// 两层兜底各自管一半：这里保证「有方图就用方图」，`coverImage` 那层继续保证「竖版网格
    /// 不会因为图存在方图槽而变空白」。只有竖版封面的 2 款游戏仍然如期显示（居中裁切填满）。
    ///
    /// ⚠️ 同理**不落库、不改 `coverData`/`squareData`**：只是个读法，两个槽在库里始终独立。
    var squareGridImage: AppImage? {
        squareImage ?? coverImage
    }

    /// 详情页横幅背景图。
    var heroImage: AppImage? {
        ImageDecodeCache.image(for: self, field: "hero", data: heroData)
    }

    /// 游戏 Logo（透明 PNG）。详情页在「背景图 + Logo 同时设置」时替代 2:3 封面。
    var logoImage: AppImage? {
        ImageDecodeCache.image(for: self, field: "logo", data: logoData)
    }

    /// 1:1 方形封面（SteamGridDB 方形 grid）。iOS 单列卡大图主格式。
    var squareImage: AppImage? {
        ImageDecodeCache.image(for: self, field: "square", data: squareData)
    }

    /// 横向封面（SteamGridDB 920×430 横版 grid）。iOS 详情页横幅与库横向卡共用。
    var landscapeImage: AppImage? {
        ImageDecodeCache.image(for: self, field: "landscape", data: landscapeData)
    }
}

extension AppImage {
    /// 「这张图装不进这个框」的容差 —— **`isSquareArtwork` 与 `letterboxes` 唯一的那个数**。
    ///
    /// 两个判据必须同源：不同源就会出现「算它是方形、却按横图留白」这种自相矛盾
    /// （同一个 1:1.05 的图，一处说方正一处说不正）。下沿 0.9 留在 `isSquareArtwork` 里
    /// 没有一起提出来，是因为它只被那一个判据用 —— 提出来反而像是公共契约。
    static let aspectTolerance: CGFloat = 1.15

    /// 这张图是不是「方形」（宽高比 1:1 附近）。
    ///
    /// 容差 0.9–1.15 而不是严格 1.0：来源图标常见 512×512、1000×1000，也有 1:1.02 这种
    /// 带一点边距的；而真竖版封面至少是 3:4 = 0.75，离 0.9 很远，不会误判。
    /// 尺寸不可读一律返回 false —— 保持历史行为（裁切），因为绝大多数封面确实是竖版。
    ///
    /// 判定规则只有这一处（导入时的槽位选择 `ImportCoordinator`、编辑页缩略图都走它），
    /// 免得「什么算方形」在几个视图里各有一套阈值。
    ///
    /// ⚠️ **显示层不要用这个判据** —— 它只回答「源图是不是 1:1」，回答不了「放进这个框
    /// 会不会被裁」。显示层要的是 `letterboxes(inBoxAspect:)`（见那边：2026-09-17 之前
    /// 显示层复用本判据，于是 320×176 的横图被当成「非方」→ 裁切，正是用户报的封面被裁）。
    var isSquareArtwork: Bool {
        let size = self.size
        guard size.width > 0, size.height > 0 else { return false }
        let ratio = size.width / size.height
        return ratio >= 0.9 && ratio <= Self.aspectTolerance
    }

    /// 这张图放进**这个比例的框**里，该**留白**（`scaledToFit` → 上下留空）还是
    /// **裁切**（`scaledToFill` → 填满但切边）？
    ///
    /// 判据只有一条：**源图比框更宽（宽出一个容差档）就留白**。此时裁切切掉的正是左右两侧，
    /// 也就是标题往往所在的位置；留白则整图可见、上下留空，正是「这是一张横图」的事实。
    ///
    /// 为什么不能再按「方 / 非方」二分（2026-09-17 用户实测）：
    /// ```
    /// 源 320×176（=1.82，外部账号导入的 PS3 / PS Vita 奖杯横幅）
    ///   「是方形吗？」→ 否 → 裁切 → 2:3 的格子里只剩中间一条
    ///   「比框宽吗？」→ 是 → 留白 ✅
    /// ```
    /// 二分法只有两档，而「比框窄」「比框宽」是连续的 —— 横图落进第二档就必然被裁，
    /// 这是二分法的缺口，不是某一处视图的疏漏。
    ///
    /// 本判据**逐字复现**改造前显示层的全部行为，只多出横图这一档：
    /// ```
    /// 框 2:3 + 源 2:3  → 0.667 > 0.767 ? 否 → 裁切（改造前：裁切）
    /// 框 2:3 + 源 1:1  → 1.0   > 0.767 ? 是 → 留白（改造前：「源图是方形就留白」那条 → 留白）
    /// 框 1:1 + 源 1:1  → 1.0   > 1.15  ? 否 → 裁切（改造前：方形网格无条件裁切）✅ §55 不动
    /// 框 1:1 + 源 2:3  → 0.667 > 1.15  ? 否 → 裁切（改造前：裁切）✅
    /// 框 2:3 + 源 1.82 → 1.82  > 0.767 ? 是 → 留白 ← **本次新增**（PS3 / Vita 的横图）
    /// ```
    /// 特别地，**方形网格里放方图仍然裁切** —— §55「方形网格用方图填满」的决策没有被推翻。
    ///
    /// 尺寸不可读一律返回 false（保持历史行为：裁切）—— 与 `isSquareArtwork` 同一条纪律。
    ///
    /// **不落库、不新增字段**：只解码后的宽高比说了算。落库的话就有两个真相（字段与图），
    /// 用户换一张图之后字段立刻变成谎话。
    func letterboxes(inBoxAspect boxAspect: CGFloat) -> Bool {
        guard boxAspect > 0 else { return false }
        let size = self.size
        guard size.width > 0, size.height > 0 else { return false }
        return (size.width / size.height) > boxAspect * Self.aspectTolerance
    }
}
