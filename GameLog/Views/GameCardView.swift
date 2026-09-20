import SwiftUI
import SwiftData

/// 五类图解码缓存已抽到 Support/ImageDecodeCache.swift（key = persistentModelID+字段，
/// 不再对整段图片 Data 做 O(n) 哈希）。此处保留清空入口供「清除缓存」调用。
extension GameCardView {
    /// 清空封面解码缓存（「清除缓存」功能调用；NSCache 内存态，正常也会自动清理）。
    static func clearCoverCache() {
        ImageDecodeCache.bump()
    }
}

/// 已销毁模型的占位格：**什么都不读、什么都不画**，只把格子尺寸占住。
///
/// 它不是「装饰」，是防止进程崩溃的最后一格。批量删除后 SwiftUI 可能还会用旧数组
/// 重跑一次卡片 body，而那时模型已经销毁（`!game.isLive`）—— 读它任何一个属性
/// 都是 `Fatal error: This backing data was detached from a context`，整进程崩
/// （详见 `GameCardView.body` 里那段说明）。这里刻意不接收 `Game` 参数：
/// 拿不到模型就无法误读它。
///
/// 尺寸按卡型给足（网格卡 2:3、方形网格卡 1:1、列表行 62、宽卡 100），这样下一帧真数据
/// 刷新时网格/列表不会先塌一下再弹回来。
struct DeletedModelPlaceholder: View {
    enum Style {
        case gridCard
        /// 方形网格卡（1:1）。**必须单独一档**：两种网格的格子高度不同，
        /// 删除那一帧若按 `gridCard` 预留 2:3，方形网格的行高会先塌一截再弹回来。
        case squareGridCard
        case listRow
        case wideCard
    }

    let style: Style

    var body: some View {
        switch style {
        case .gridCard:
            Color.clear.aspectRatio(2.0 / 3.0, contentMode: .fit)
        case .squareGridCard:
            Color.clear.aspectRatio(1.0, contentMode: .fit)
        case .listRow:
            Color.clear.frame(height: 62)
        case .wideCard:
            Color.clear.frame(minHeight: 100)
        }
    }
}

/// 卡片左上角的「我的最爱」爱心角标（网格卡 / iOS 宽卡共用）。
struct FavoriteHeartBadge: View {
    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 12))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
    }
}

/// 游戏名右侧的平台图标：最多显示 maxCount 个，超出显示 +N。
/// 仅作为平台符号提示，下方的平台文字行保持不变。
/// 与名字同行时整体垂直居中对齐（不用 firstTextBaseline——图标放大系数随平台不同，
/// 底对齐会让各图标顶部参差；居中后多出的高度上下均分，观感齐平）。
struct GamePlatformIcons: View {
    let platforms: [String]
    var maxCount: Int = 3
    var iconSize: CGFloat = 12

    var body: some View {
        let shown = platforms.prefix(maxCount)
        HStack(alignment: .center, spacing: 3) {
            ForEach(shown, id: \.self) { p in
                PlatformIcon(platform: p, size: iconSize)
            }
            if platforms.count > maxCount {
                Text(verbatim: "+\(platforms.count - maxCount)")
                    .font(.system(size: iconSize * 0.85))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 网格卡的格子形状。库里的两种网格只差这一个参数，其余（徽章位置、信息行、极简模式、
/// 右键菜单）全部共用 —— 所以它是 `GameCardView` 的参数，而不是另写一个卡片视图。
enum CardShape {
    /// 竖版封面网格（2:3）。库的默认网格，也是 iOS 网格。
    case portrait
    /// 方形封面网格（1:1，macOS 第三视图）。
    ///
    /// 语义（用户拍板）：**整格统一 1:1**。填充方式**不看格子形状**，看「这张图放进这个 1:1
    /// 格会不会被裁」—— 由 `AppImage.letterboxes(inBoxAspect:)` 判定：
    /// 方图与竖版封面都比 1:1 格窄 → `fill`（方图满铺；竖图居中裁切填满，格子齐平，
    /// 代价是竖图上下被裁）；**横图比格子宽 → `fit`** 完整显示、上下留空。
    /// 所以 §55 的结论原样成立（方形网格用方图满铺），只是补上了横图这一档。
    case square
}

/// 网格视图中的游戏卡片：封面 + 库显示分徽章 + 名称 + 平台/日期。
/// 极简模式（2026-09-05 用户要求，设置「个性化」开关默认关）：只显示封面 +
/// 右上角胶囊 + 爱心角标，封面下方信息全部隐藏。
struct GameCardView: View {
    @Environment(\.appLanguageCode) private var language
    /// 网格极简模式开关（UserCustomization.minimalGridKey，默认关闭）。
    @AppStorage(UserCustomization.minimalGridKey) private var minimalGrid = false
    let game: Game
    /// 格子形状。默认竖版 = 既有全部调用点零改动。
    var shape: CardShape = .portrait

    /// 封面锚点比例：竖版 2:3、方形 1:1。
    private var coverAspectRatio: CGFloat {
        shape == .square ? 1.0 : 2.0 / 3.0
    }

    /// 封面填充方式：**由「这张图放进这个格子会不会被裁」决定**，不由格子形状决定。
    ///
    /// 判据只有一处 —— `AppImage.letterboxes(inBoxAspect:)`（`Models/Artwork.swift`）：
    /// 源图比格子更宽（宽出 1.15 一档）就 `fit`（完整显示、上下留空），否则 `fill`（填满、裁边）。
    ///
    /// - 方形网格 + 方图 → 比 1:1 格窄 → `fill`，方图正好满铺（§55 的决策，没变）；
    /// - 方形网格 + 竖版封面 → 更窄 → `fill`，居中裁切填满（格子齐平，代价是竖图上下被裁）；
    /// - 方形网格 + **横图** → 更宽 → `fit`（**新增**：以前方形网格一律 `fill`，
    ///   而横图被裁掉的是左右两侧，正是用户报的"封面被放大然后裁切"）；
    /// - 竖版网格 + 方图 → 更宽 → `fit`（上下留空，§54.6）；
    /// - 竖版网格 + 竖版封面 → 一样宽 → `fill`（照旧）。
    ///
    /// 关键是**看实际要画的那张图**（`preferredArtwork`，方形网格读的是 `squareGridImage`）——
    /// 改造前这里读的是「封面位那一张是不是方形」（旧属性 `Game.coverIsSquare`，已删除），
    /// 那个问法有两个答不出的：方形网格读的是**另一个槽**（方图），横图也不是「非方」两个字
    /// 能概括的（320×176 落进"非方"就一律被裁）。
    ///
    /// 单拆一个属性是因为三元表达式会读不出来（`.fill` 被推成 `CGSize`）。
    private var coverContentMode: ContentMode {
        guard let image = preferredArtwork else { return .fill }
        return image.letterboxes(inBoxAspect: coverAspectRatio) ? .fit : .fill
    }

    /// 内容是否需要自己圆角：`fit` 那一半够不到外层框的四个角，要自己圆（否则是四个直角
    /// 浮在圆角卡片里）。`fill` 那一半由外层 `cover` 的 `clipShape` 裁，这里给 0 = 什么都不做。
    private var coverInnerRadius: CGFloat {
        coverContentMode == .fit ? 8 : 0
    }

    private var cover: some View {
        // 固定比例方格锚点：用 Color.clear 占位确定尺寸，图片覆盖裁剪，
        // 避免 Image 自带比例撑高单元格导致与相邻卡片重叠（参见 §4.22 安全图案）。
        // ⚠️ 锚点**不随图片比例变**：方图与竖图占同样大的格子，网格才不会错位。
        Color.clear
            .aspectRatio(coverAspectRatio, contentMode: .fit)
            .overlay { coverContent }
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// 卡片该读哪张图 —— **两种网格各有一套槽位优先级**，都定义在 `Artwork.swift`：
    /// - 竖版网格：`Game.coverImage`（2:3 竖版优先，没有才退方图）；
    /// - 方形网格：`Game.squareGridImage`（**1:1 方图优先**，没有才退竖版封面居中裁切）。
    ///
    /// 分两套的原因是 2026-09-17 用户实测反馈「库内原有游戏的方形网格视图没有用方形封面而是
    /// 竖向封面」：两槽都有的游戏若照 `coverImage` 读，1:1 格子里塞的是竖版封面。
    private var preferredArtwork: AppImage? {
        shape == .square ? game.squareGridImage : game.coverImage
    }

    @ViewBuilder
    private var coverContent: some View {
        if let image = preferredArtwork {
            Image(appImage: image)
                .resizable()
                .aspectRatio(contentMode: coverContentMode)
                // fit 的那一半要自己圆角；fill 的那一半由外层裁，见 `coverInnerRadius`。
                .clipShape(RoundedRectangle(cornerRadius: coverInnerRadius))
        } else {
            ZStack {
                Rectangle()
                    .fill(Color.semantic(.quaternarySystemFill))
                Image(systemName: "gamecontroller")
                    .font(.system(size: 32))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var platformText: String {
        let list = game.platformList
        guard !list.isEmpty else { return "" }
        let shown = list.prefix(2).map { Presets.display($0, category: .platform, language: language) }
            .joined(separator: " · ")
        if list.count > 2 {
            return "\(shown) · +\(list.count - 2)"
        }
        return shown
    }

    /// 通关日期行（全部记录中最大的通关日期，与库排序同口径；无日期不显示）。
    private var clearDateText: String? {
        game.latestCompletionDate.map {
            L10n.tr("card.cleared", [Self.cardDate($0, language: language)], lang: language)
        }
    }

    /// 发售日期行（有发售日才显示）。
    private var releaseDateText: String? {
        game.releaseDate.map {
            L10n.tr("card.released", [Self.cardDate($0, language: language)], lang: language)
        }
    }

    /// 跟随界面语言的卡片日期格式。此前 `Date.formatted` 跟随系统 locale，
    /// 中文界面会显示英文日期「2 Aug 2026」。
    /// DateFormatter 按 language 缓存——大网格每卡片每次渲染都新建 Formatter
    /// 是已知性能坑（苹果文档明示重 Formatter 创建昂贵，2026-09-05 审计）。
    private static var cardDateFormatters: [String: DateFormatter] = [:]
    static func cardDate(_ date: Date, language: String) -> String {
        let fmt: DateFormatter
        if let cached = cardDateFormatters[language] {
            fmt = cached
        } else {
            let f = DateFormatter()
            f.locale = Locale(identifier: language)
            if language == "zh-Hans" || language == "ja" {
                f.dateFormat = "yyyy年M月d日"
            } else {
                f.dateFormat = "MMM d, yyyy"
            }
            cardDateFormatters[language] = f
            fmt = f
        }
        return fmt.string(from: date)
    }

    var body: some View {
        // ⚠️ 删除守卫必须在最外层，且必须在**读任何属性之前**。
        //
        // 为什么卡片 body 会拿着一个已销毁的模型再跑一遍：批量删除（「清空导入数据」一次
        // 删掉几百个条目、备份导入整库替换）之后，`@Query` 会给出新数组，但 SwiftUI 已经
        // 排队的渲染动作（实测是 `ScrollViewCommitMutation.commit`）仍带着**旧数组**里那个
        // 子视图重新求值 —— 而那一刻删除早已落盘。2026-09-16 真机崩溃现场就是它。
        //
        // 判据用 `Game.isLive`（= `modelContext != nil`），**不是 `isDeleted`** ——
        // 后者在 `save()` 之后会翻回 false，见 `Game.isLive` 的说明。
        if !game.isLive {
            // 方形网格要单独一档占位：1:1 与 2:3 的格子高度不同，用错档会让行高先塌再弹。
            DeletedModelPlaceholder(style: shape == .square ? .squareGridCard : .gridCard)
        } else if minimalGrid {
            // 极简模式：仅封面 + 右上角胶囊 + 爱心角标（无名称/平台/日期信息行）。
            ZStack(alignment: .topTrailing) {
                cover
                GameBadge(game: game, style: .glass)
                    .padding(6)
            }
            .overlay(alignment: .topLeading) {
                if game.isFavorite {
                    FavoriteHeartBadge()
                        .padding(8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            fullCard
        }
    }

    /// 完整信息卡（默认）：封面 + 徽章 + 名称/平台 + 日期行。
    private var fullCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                cover
                GameBadge(game: game, style: .glass)
                    .padding(6)
            }
            .overlay(alignment: .topLeading) {
                if game.isFavorite {
                    FavoriteHeartBadge()
                        .padding(8)
                }
            }
            // 名字 + 平台图标：一行放得下就并排；放不下（多平台/超宽字标）图标换到名字下方一行，名字不被挤压省略。
            // 图标行与名字中轴对齐（各平台放大系数不同，基线/底对齐会顶部参差）。
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 4) {
                    Text(verbatim: game.displayName(for: language))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    GamePlatformIcons(platforms: game.platformList, maxCount: 3, iconSize: 12)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: game.displayName(for: language))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    GamePlatformIcons(platforms: game.platformList, maxCount: 3, iconSize: 12)
                }
            }
            if !platformText.isEmpty {
                Text(verbatim: platformText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            // 发售日期在上(有才显示),通关日期在下——按时间先后自然排列。
            if let releaseDateText {
                Text(verbatim: releaseDateText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let clearDateText {
                Text(verbatim: clearDateText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func formatScore(_ score: Double) -> String {
        String(format: "%.1f", score)
    }
}

/// 列表视图中的游戏行。
struct GameRowView: View {
    @Environment(\.appLanguageCode) private var language
    let game: Game

    private var subtitle: String {
        game.platformList
            .map { Presets.display($0, category: .platform, language: language) }
            .joined(separator: " · ")
    }

    var body: some View {
        // 已销毁模型的守卫 —— 同 `GameCardView.body` 的那段说明，必须在读任何属性之前。
        if !game.isLive {
            DeletedModelPlaceholder(style: .listRow)
        } else {
            rowContent
        }
    }

    /// 行内缩略图的框。写成常量是因为**画图的判据与 `frame` 必须用同一个数** ——
    /// 分头写一个 40/54、一个 0.74，改一处漏一处就会变成「按这个比例判断、放进那个框里」。
    private static let thumbSize = CGSize(width: 40, height: 54)
    private static var thumbAspect: CGFloat { thumbSize.width / thumbSize.height }

    private var rowContent: some View {
        HStack(spacing: 12) {
            Group {
                if let image = game.coverImage {
                    Image(appImage: image)
                        .resizable()
                        // 比 40×54 这个框宽的图（方形来源的 1:1 图标、导入的横图）完整显示、
                        // 上下留空；竖版封面同样宽 → 照旧填满裁切。行高不变，列表不会跳。
                        // 见 `AppImage.letterboxes(inBoxAspect:)`（判据只有那一处）。
                        .aspectRatio(contentMode: image.letterboxes(inBoxAspect: Self.thumbAspect) ? .fit : .fill)
                } else {
                    ZStack {
                        Rectangle().fill(Color.semantic(.quaternarySystemFill))
                        Image(systemName: "gamecontroller").foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(width: Self.thumbSize.width, height: Self.thumbSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(verbatim: game.displayName(for: language))
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    GamePlatformIcons(platforms: game.platformList, maxCount: 4, iconSize: 13)
                }
                if !subtitle.isEmpty {
                    Text(verbatim: subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            GameBadge(game: game, style: .plain)
        }
        .padding(.vertical, 4)
    }
}

/// iOS 库「单列横向卡」视图（2026-08-28 第五稿）：SwiftUI 卡片形态——玻璃材质圆角卡底
/// （.regularMaterial + 细描边 + 投影，明暗模式自适应）。左列 = **方形封面**满卡高
/// （上下左右全贴边无框，方形空间零裁切；无方图回落竖版封面等高居中透卡底），封面右上角
/// 覆盖液态玻璃评分/状态胶囊（与网格卡同一 glassCapsuleBadge）；右列整块 = 可显示文字区：
/// 标题（词边界断行，同详情页 lineBreakAwareTitle 口径）+ 平台图标行在顶端，元数据面板
/// （发售日期 / 厂商·发行商 / 游戏类型 / 通关日期，裸值带小标题，缺项跳过）贴底。
struct GameWideCardView: View {
    @Environment(\.appLanguageCode) private var language
    let game: Game
    /// 所在内容列实测宽（LibraryView 背景 GeometryReader 测量传入；0 = 未知，回退横版卡）。
    /// iPad 竖/横屏分档与竖版卡封面边长都由此驱动（与 header/hero 的宽度阈值同源）。
    var viewWidth: CGFloat = 0

    private var clearDateValue: String? {
        game.latestCompletionDate.map { GameCardView.cardDate($0, language: language) }
    }

    private var releaseDateText: String? {
        game.releaseDate.map { GameCardView.cardDate($0, language: language) }
    }

    private var genreText: String? {
        let genre = game.genre?.trimmingCharacters(in: .whitespaces) ?? ""
        return genre.isEmpty ? nil : genre
    }

    /// 卡内标题：套详情页同款词边界断行（U+2060 禁词内断行；iOS 专属函数，macOS 原样）。
    private var titleText: String {
        #if os(iOS)
        lineBreakAwareTitle(game.displayName(for: language), language: language)
        #else
        game.displayName(for: language)
        #endif
    }

    var body: some View {
        // 已销毁模型的守卫 —— 同 `GameCardView.body` 的那段说明，必须在读任何属性之前。
        if !game.isLive {
            DeletedModelPlaceholder(style: .wideCard)
        } else if iPadLayout.isPadLandscapeCard(viewWidth: viewWidth) {
            horizontalCard
        } else if iPadLayout.isPad {
            iPadPortraitCard
        } else {
            horizontalCard
        }
    }

    /// iPad 竖屏竖版卡（2026-09-05 需求①）：横版卡 260pt 方形封面吃掉大半列宽，
    /// 文字区仅剩 ~65pt 五项元数据必然省略。改上图下文：方形封面满列宽在上，
    /// 标题/平台/元数据满宽在下，文字可用宽 ~349pt。封面与文字间 10pt 间距。
    /// 元数据仍贴底（与横版同构），标题区顶端。
    private var iPadPortraitCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            imageArea(edge: iPadPortraitEdge)
                .overlay(alignment: .topTrailing) {
                    trailingBadge.padding(6)
                }
                .overlay(alignment: .topLeading) {
                    if game.isFavorite {
                        FavoriteHeartBadge()
                            .padding(8)
                    }
                }

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: titleText)
                        .font(.system(size: titleFontSize, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    GamePlatformIcons(platforms: game.platformList, maxCount: 5, iconSize: 15)
                }
                Spacer(minLength: 6)
                metaBlock
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: iPadPortraitEdge + iPadLayout.padPortraitTextBlockHeight)
        .background(.regularMaterial, in: Self.cardShape)
        .overlay(Self.cardShape.strokeBorder(.quaternary, lineWidth: 0.5))
        .clipShape(Self.cardShape)
        .shadow(color: .black.opacity(0.14), radius: 6, x: 0, y: 2)
    }

    /// iPad 竖屏卡封面边长 = 双列布局列宽：（内容宽 − 列间距 14）÷ 2，钳最小 200。
    /// viewWidth 未传（0）时回退 349（iPad mini 竖屏实测列宽）。
    private var iPadPortraitEdge: CGFloat {
        guard viewWidth > 0 else { return 349 }
        return max(200, (viewWidth - 14) / 2)
    }
    private var titleFontSize: CGFloat { iPadLayout.isPadLandscapeCard(viewWidth: viewWidth) ? 18 : 15 }
    private var metaFontSize: CGFloat { iPadLayout.isPadLandscapeCard(viewWidth: viewWidth) ? 14 : 12 }
    private var metaLabelFontSize: CGFloat { iPadLayout.isPadLandscapeCard(viewWidth: viewWidth) ? 10 : 9 }
    private var metaSpacing: CGFloat { iPadLayout.isPadLandscapeCard(viewWidth: viewWidth) ? 5 : 4 }

    /// 横版卡（iPhone 全部 + iPad 横屏）：左方形封面满卡高、右文字列（原版结构）。
    private var horizontalCard: some View {
        HStack(alignment: .top, spacing: 0) {
            // 左列：方形封面满卡高（宽 = 卡高），上下左右全贴边，左缘圆角由整卡 clipShape 裁出；
            // 右上角评分/状态胶囊（覆盖在图上，网格卡同款 padding 6）。
            imageArea
                .frame(width: cardHeight, height: cardHeight)
                .overlay(alignment: .topTrailing) {
                    trailingBadge.padding(6)
                }
                .overlay(alignment: .topLeading) {
                    if game.isFavorite {
                        FavoriteHeartBadge()
                            .padding(8)
                    }
                }

            // 右列：整块可显示文字区——标题+平台在顶端，元数据面板贴底（中段弹性空隙）。
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: titleText)
                        .font(.system(size: titleFontSize, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    GamePlatformIcons(platforms: game.platformList, maxCount: 5, iconSize: iPadLayout.isPadLandscapeCard(viewWidth: viewWidth) ? 15 : 12)
                }
                Spacer(minLength: 4)
                metaBlock
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.semantic(.quaternarySystemFill).opacity(0.45))
        }
        .frame(height: cardHeight)
        .background(.regularMaterial, in: Self.cardShape)
        .overlay(Self.cardShape.strokeBorder(.quaternary, lineWidth: 0.5))
        .clipShape(Self.cardShape)
        .shadow(color: .black.opacity(0.14), radius: 6, x: 0, y: 2)
    }

    private static let cardShape = RoundedRectangle(cornerRadius: 14, style: .continuous)
    /// 卡高 = 左列方形封面边长。标题块（两行 ~52）进右列后，为保元数据五项完整显示，
    /// 从 170 加到 215（两行长名 + 五项面板 + 内距的临界预算）。
    /// iPad 横屏档（2026-09-05）：双列卡列宽 ~350+，卡高升到 260，封面/字号同比例
    /// 放大（标题 18 / 元数据 14 / 小标题 10）适配大屏；iPhone 保持 215 单列不变。
    /// iPad 竖屏走 iPadPortraitCard（上图下文），不用此值。
    private var cardHeight: CGFloat { iPadLayout.isPadLandscapeCard(viewWidth: viewWidth) ? 260 : 215 }

    /// 右列元数据块（2026-08-27 用户追加定稿）：每项 = 小标题（game.releaseDate/developer/
    /// publisher/genre/card.clearedDate，三语现成 key）+ 值；厂商与发行商**分两行**。各缺项整组跳过。
    @ViewBuilder
    private var metaBlock: some View {
        VStack(alignment: .leading, spacing: metaSpacing) {
            if let releaseDateText {
                metaItem(titleKey: "game.releaseDate", value: releaseDateText, valueLimit: 1)
            }
            if let clearDateValue {
                metaItem(titleKey: "card.clearedDate", value: clearDateValue, valueLimit: 1)
            }
            if let developerText {
                metaItem(titleKey: "game.developer", value: developerText, valueLimit: 2)
            }
            if let publisherText {
                metaItem(titleKey: "game.publisher", value: publisherText, valueLimit: 2)
            }
            if let genreText {
                metaItem(titleKey: "game.genre", value: genreText, valueLimit: 1)
            }
        }
    }

    private var developerText: String? {
        let s = game.developer?.trimmingCharacters(in: .whitespaces) ?? ""
        return s.isEmpty ? nil : s
    }

    private var publisherText: String? {
        let s = game.publisher?.trimmingCharacters(in: .whitespaces) ?? ""
        return s.isEmpty ? nil : s
    }

    /// 一条元数据：小号次要色标题 + 值（长值在词边界处截断省略）。字号随 iPad 档升档。
    @ViewBuilder
    private func metaItem(titleKey: String, value: String, valueLimit: Int) -> some View {
        #if os(iOS)
        let valueText = lineBreakAwareTitle(value, language: language)
        #else
        let valueText = value
        #endif
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: L10n.tr(titleKey, lang: language))
                .font(.system(size: metaLabelFontSize, weight: .medium))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Text(verbatim: valueText)
                .font(.system(size: metaFontSize))
                .foregroundStyle(.secondary)
                .lineLimit(valueLimit)
                .multilineTextAlignment(.leading)
        }
    }

    /// 封面区（方形满边长、上下左右全贴边）：1:1 图 `fill` 零裁切正好填满；
    /// 无 1:1 图用竖版封面 `fit` 等高完整展示（左右透卡底材质，不垫灰底）；
    /// 全无图手柄占位。frame 定尺寸在前、clipped 在后，防图铺出图区（§40.1 教训）。
    /// 边长参数化：横版卡 = cardHeight，iPad 竖版卡 = iPadPortraitEdge（列宽）。
    ///
    /// 两条分支的取舍**故意不一样**，别"统一"掉：第一支有图就占满整格（§55 的方形满铺），
    /// 只有「比这个 1:1 格更宽的图」（横图）才改判 `fit` —— 否则它会变成中间一条；
    /// 第二支本来就是 `fit`（竖版封面在这个正方形图区里左右留白是定稿的观感）。
    @ViewBuilder
    private func imageArea(edge: CGFloat) -> some View {
        Group {
            if let image = game.squareImage {
                Image(appImage: image)
                    .resizable()
                    // 判据的框比例就是 1（正方形图区）。见 `AppImage.letterboxes(inBoxAspect:)`。
                    .aspectRatio(contentMode: image.letterboxes(inBoxAspect: 1) ? .fit : .fill)
                    .frame(width: edge, height: edge)
                    .clipped()
            } else if let image = game.coverImage {
                Image(appImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: edge, height: edge)
                    .clipped()
            } else {
                ZStack {
                    Rectangle().fill(Color.semantic(.quaternarySystemFill))
                    Image(systemName: "gamecontroller")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                }
                .frame(width: edge, height: edge)
            }
        }
    }

    private var imageArea: some View { imageArea(edge: cardHeight) }

    /// 右上角徽章：GameBadge(.glass) 统一入口（规则与样式单一归属 Support/StatusStyle.swift）。
    private var trailingBadge: some View {
        GameBadge(game: game, style: .glass)
    }
}

/// 新建分组的弹窗。空名或重名不允许保存。
struct NewGroupSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \GameGroup.name) private var groups: [GameGroup]
    @State private var name = ""

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }
    private var isDuplicate: Bool {
        !trimmed.isEmpty && groups.contains { $0.name == trimmed }
    }

    var body: some View {
        VStack(spacing: 16) {
            LText("group.newGroup")
                .font(.headline)
            BorderedTextField(text: $name, placeholder: L10n.tr("group.name", lang: language))
                #if os(macOS)
                .frame(width: 280)
                #else
                .frame(maxWidth: .infinity)
                #endif
            // 固定高度占位，避免错误出现时窗口跳动
            Text(verbatim: isDuplicate ? L10n.tr("group.nameExists", lang: language) : " ")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(1)
            HStack {
                Button(L10n.tr("common.cancel", lang: language)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.tr("common.save", lang: language)) {
                    context.insert(GameGroup(name: trimmed))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmed.isEmpty || isDuplicate)
            }
        }
        .padding(24)
        #if os(macOS)
        .frame(width: 360)
        #else
        .frame(maxWidth: .infinity)
        #endif
    }
}
