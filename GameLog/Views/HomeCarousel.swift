import SwiftUI
import SwiftData

// MARK: - 库首页轮播

/// 库首页「全部游戏」顶端的横向分页轮播（beta 2.8 新增）。
///
/// 原生 `TabView` + `.tabViewStyle(.page)` 实现分页（macOS 用原生分页 `ScrollView`+.paging，
/// 见 `pager`）；固定比例容器只作用在分页区卡片上（图片底图不撑卡片尺寸）+ 下方自绘圆点
/// 指示器（`indexDisplayMode: .never` 关掉系统圆点）。无自动轮播、无无限循环。
///
/// 五页（2026-08-30 用户定稿顺序）：
/// ① 主页横幅——用户可自定义的标题 / 副标题 / 背景图（无背景回退品牌深色渐变）+ 大头像；
/// ② 随机游戏——**从全库直接随机**一款，封面全幅打底（横图优先）+ 底部信息/评价标题 +
///    右上角**突出评分**（琥珀星标胶囊）与 shuffle 再随机；
/// ③ 我的最爱——**iPhone** 走②同款「横向封面」显示模式、只展示随机选中的一款（2026-09-15 用户
///    要求：原「置顶 1:1 方卡 + 其余列表 + 分割线」在矮卡上置顶卡与分割线重叠，改版）；
///    **iPad / macOS 保持原版式**（随机置顶 1:1 方卡 + 其余最爱列表在下）；
/// ④ 库内速览——游戏数 / 库平均分 / 想玩 / 已通关·长线 + 六状态分布；
/// ⑤ 收藏家速览——收藏档案 / 总数量 / 总花费 / 总估值（无持有记录时提示）。
struct HomeCarousel: View {
    @Environment(\.appLanguageCode) private var language
    /// 全库游戏（统计与榜单的唯一依据）。
    let games: [Game]
    /// 点击游戏行（最爱 / 趣味榜）→ 父视图推详情。
    var onSelect: (Game) -> Void = { _ in }

    @State private var page = 0
    /// 随机游戏：每次进入库首页随机的一款游戏（封面 + 信息 + 评价标题）。
    /// 存 **PersistentIdentifier 而非 Game 引用**——@State 持有已删除 Game 的引用后，
    /// body 重算访问属性会触发 SwiftData fatal（backing data detached，2026-09-05 审计实锤复现）；
    /// 存 ID 则每次求值在新鲜的 `games` 里解析，找不到（已删）自动重抽，天然自愈。
    @State private var spotlightID: PersistentIdentifier?
    /// 我的最爱页「置顶」的随机最爱（每次进入首页轮换一款；其余最爱在下方列表）。同上存 ID。
    @State private var featuredFavoriteID: PersistentIdentifier?
    /// 内容缩放因子：卡片宽/720 设计基准（钳制 0.85–2.0）。窗口缩放时经背景 GeometryReader
    /// 逐帧更新——内容字号/尺寸随卡片等比放大收缩，避免宽窗口下内容缩在角落（§45 用户要求）。
    @State private var contentUnit: CGFloat = 1
    /// 随机游戏底图偏好（设置页「个性化」）：auto=横图优先（landscape→hero）、
    /// hero=仅背景图、landscape=仅横向封面（2026-09-05 用户拍板：mac 横向封面全幅
    /// 打底在 2.8:1 卡片里上下裁切影响观感，给选择权）。
    /// iPad 横竖屏分开（用户要求，仅 iPad）：竖屏读 spotlightBackdropPreferenceKey
    /// （iPhone/macOS 同源），横屏读 spotlightBackdropPadLandscapeKey；按实测
    /// pageWidth 判定（≥950 = 横屏/超宽），与详情页 hero 版式阈值同源。
    @AppStorage(UserCustomization.spotlightBackdropPreferenceKey) private var spotlightBackdropRaw = UserCustomization.spotlightBackdropAuto
    @AppStorage(UserCustomization.spotlightBackdropPadLandscapeKey) private var spotlightBackdropPadLandscapeRaw = UserCustomization.spotlightBackdropAuto

    /// 当前生效的底图偏好：iPad 横屏走专用键，其余（iPad 竖屏/iPhone/macOS）走通用键。
    private var activeSpotlightBackdropRaw: String {
        iPadLayout.isPad && pageWidth >= iPadLayout.wideThreshold
            ? spotlightBackdropPadLandscapeRaw
            : spotlightBackdropRaw
    }

    /// 固定比例容器：宽度填满，高度 = 宽度 / 比例（数值越大卡片越矮）。
    /// 2026-08-30 用户要求「高度减少一点」：macOS 2.4 → 2.8、iOS 1.9 → 2.1。
    /// iPad 横屏（需求①，2026-09-05）：宽 1133pt 时 2.1 比例卡高 540pt 太高——横屏
    /// 加扁到 3.0（≈macOS 桌面观感）；iPad 竖屏 744pt 走 iPhone 的 2.1 不变。
    private var aspectRatio: CGFloat {
        #if os(macOS)
        2.8
        #else
        if iPadLayout.isPad && pageWidth >= iPadLayout.wideThreshold { return 3.0 }
        return 2.1
        #endif
    }

    var body: some View {
        VStack(spacing: 8) {
            pager
                // 高度 = 实测列宽/比例，硬性定值（见 pageHeight）。
                .frame(height: max(pageHeight, 80))
            carouselDots
        }
        .frame(maxWidth: .infinity)
        // 测准内容列实际宽 → pageWidth（卡片宽高的唯一来源）与 contentUnit 都由此驱动；
        // 窗口缩放逐帧跟随，宽高同源同步（缩放时比例恒定）。
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        pageWidth = proxy.size.width
                        contentUnit = Self.clampedUnit(proxy.size.width)
                    }
                    .onChange(of: proxy.size.width) { _, w in
                        pageWidth = w
                        contentUnit = Self.clampedUnit(w)
                    }
            }
        )
        .onAppear {
            if spotlight == nil {
                spotlightID = Self.randomSpotlightID(games: games, avoiding: nil)
            }
            if featuredFavorite == nil {
                featuredFavoriteID = Self.randomFavoriteID(games: favorites, avoiding: nil)
            }
            reloadUserImages()
        }
        // 库首页重新出现（从设置/详情返回）时刷新用户图，套用设置页可能刚改的横幅/头像。
        .onReceive(NotificationCenter.default.publisher(for: UserCustomization.userImagesChangedNotification)) { _ in
            reloadUserImages()
        }
    }

    /// 横幅背景 + 头像：**载入一次进 @State**，不做每次 body 求值都读磁盘解码
    /// （bannerBackgroundImage() 是同步 Data(contentsOf:) + NSImage 解码，横幅图可达数 MB，
    /// 窗口缩放逐帧重算时会反复走磁盘——2026-09-05 审计发现）。设置页改图后发通知刷新。
    @State private var bannerImage: AppImage?
    @State private var avatarImage: AppImage?

    private func reloadUserImages() {
        bannerImage = UserCustomization.bannerBackgroundImage()
        avatarImage = UserCustomization.avatarImage()
    }

    /// 实测内容列宽 = 每页卡片的宽（也是高的唯一来源）。不用 aspectRatio（弹性高度下会被
    /// 页内大图的理想尺寸打败，§46 实证）也不用 containerRelativeFrame（在导航分栏内容列里
    /// 解析到比内容列更宽的容器，卡片钻到悬浮侧边栏下面，§46 用户实测三点问题）——
    /// 只信外层实测值：纯算术定尺寸，图片/容器都改变不了卡片盒子。
    @State private var pageWidth: CGFloat = 0
    private var pageHeight: CGFloat { pageWidth / aspectRatio }

    // MARK: - 随机对象解析（ID → Game，已删自愈）

    /// 随机游戏当前游戏：按 ID 在新鲜 games 里解析；ID 失效（游戏已删）自动重抽一款。
    /// 每次求值都解析（而非缓存 Game 引用）——这是悬空引用崩溃的自愈点。
    private var spotlight: Game? {
        if let spotlightID, let hit = games.first(where: { $0.persistentModelID == spotlightID }) {
            return hit
        }
        let fresh = Self.randomSpotlightID(games: games, avoiding: nil)
        if fresh != spotlightID { spotlightID = fresh }
        return fresh.flatMap { id in games.first { $0.persistentModelID == id } }
    }

    /// 最爱置顶当前游戏：同 spotlight 口径（只在 favorites 里解析与重抽）。
    private var featuredFavorite: Game? {
        if let featuredFavoriteID,
           let hit = favorites.first(where: { $0.persistentModelID == featuredFavoriteID }) {
            return hit
        }
        let fresh = Self.randomFavoriteID(games: favorites, avoiding: nil)
        if fresh != featuredFavoriteID { featuredFavoriteID = fresh }
        return fresh.flatMap { id in favorites.first { $0.persistentModelID == id } }
    }

    /// 设计基准宽（contentUnit = 卡片宽 / 此值）。
    private static let referenceWidth: CGFloat = 720

    /// 内容缩放因子：钳制在 0.85–2.0，窗口再宽也不至于字号失控。
    /// iPad 横屏（需求①）：宽 1133pt 裸算 unit=1.57 → 字号/头像/间距整体放大 ~57%，
    /// 横屏「卡片过大」的观感大头在此——钳到 1.15（与竖屏 1.03 观感衔接），卡片变扁后
    /// 内容量不变、字号只略放大；iPhone 分支不动（宽 < 950 走原钳制）。
    private static func clampedUnit(_ width: CGFloat) -> CGFloat {
        if iPadLayout.isPad && width >= iPadLayout.wideThreshold {
            return min(max(width / referenceWidth, 0.85), 1.15)
        }
        return min(max(width / referenceWidth, 0.85), 2.0)
    }

    /// 分页容器。macOS 无 `PageTabViewStyle`（`@available(macOS, unavailable)`）——
    /// 用原生分页 `ScrollView` 实现同款横滑翻页；iOS 按用户指定走原生 `TabView` + `.page`。
    ///
    /// 「翻页/独立页」手感（2026-08-30 用户要求，区别于「连续滑动」）：
    /// - 页间 `spacing` 留缝：翻页时前一页尾与后一页头之间有呼吸间隙，页面彼此成片；
    /// - `.viewAligned(limitBehavior: .always)`：松手必吸附到整页（不可中途停靠），
    ///   且按**页面视图对齐**（支持页缝，`.paging` 只按视口倍数、会被页缝打乱）。
    /// - 每页卡片带轻投影（卡片 .shadow），翻页时更"浮起的纸片"。
    @ViewBuilder
    private var pager: some View {
        #if os(macOS)
        // 页宽 = 实测内容列宽（pageWidth），不用 containerRelativeFrame（越界根因，见 body 注）。
        // 高度链：外层 .frame(height: pageHeight) 定 ScrollView 高 → 行内显式 frame 定页宽高，
        // 卡片盒子与图/容器完全解耦。
        //
        // 指示条用 .never（永不显示）。⚠️ macOS 27 实测 .hidden 档对横向 ScrollView **失效**
        // （独立四组对照实验：无修饰符/.hidden 有条、.never 干净、死区裁切无效——条画在
        // NSScrollView 视口内部底部预留区，clipped 裁不到；NSScroller frame 位于内容正下方
        // 17pt，AppleShowScrollBars=Always 时常驻）。
        ScrollView(.horizontal) {
            HStack(spacing: 18) {
                ForEach(0..<5, id: \.self) { i in
                    pageView(at: i)
                        .frame(width: pageWidth, height: pageHeight)
                        .clipped()
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
        .scrollPosition(id: Binding<Int?>(get: { page }, set: { page = $0 ?? 0 }))
        .scrollIndicators(.never)
        #else
        // iOS：TabView 分页自身把每页钳到视口宽；高度用同一实测值，比例恒定。
        TabView(selection: $page) {
            ForEach(0..<5, id: \.self) { i in
                pageView(at: i)
                    .frame(height: max(pageHeight, 80))
                    .clipped()
                    .tag(i)
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        #endif
    }

    @ViewBuilder
    private func pageView(at index: Int) -> some View {
        switch index {
        case 0: bannerPage
        case 1: spotlightPage
        case 2: favoritesPage
        case 3: statsPage
        case 4: holdingsPage
        default: EmptyView()
        }
    }

    // MARK: - 圆点指示器

    /// 分页圆点：当前页拉长高亮、其余灰点；**整块可点跳页**——macOS 在 `withAnimation` 里改
    /// `page` 会带动画滚动（`.scrollPosition` 绑定遵守动画事务），iOS TabView 选中变化自带动画。
    private var carouselDots: some View {
        HStack(spacing: 5) {
            ForEach(0..<5, id: \.self) { i in
                Button {
                    goToPage(i)
                } label: {
                    Capsule()
                        .fill(i == page ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: i == page ? 18 : 6, height: 6)
                }
                .buttonStyle(.plain)
                // 触控目标放大但不撑布局太多：视觉仍是细圆点，点击不费劲。
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
            }
        }
        .animation(.easeInOut(duration: 0.2), value: page)
    }

    /// 跳页（圆点点击）：两端状态一致 + 动画。越界/同页忽略。
    private func goToPage(_ index: Int) {
        guard (0..<5).contains(index), index != page else { return }
        withAnimation(.easeInOut(duration: 0.28)) {
            page = index
        }
    }

    // MARK: - ① 主页横幅

    private var bannerPage: some View {
        ZStack {
            // 背景：用户自定义图等比填充裁边；无图回退品牌深色渐变（与开屏/分享卡同款配色）。
            // 同 spotlightBackdrop 根治口径：Color.clear 承接尺寸、图做 overlay 永不参与布局
            // （弹性 frame 不钳制布局，任意比例图都会以理想尺寸撑破 ZStack，§46 实证）。
            Color.clear
                .overlay {
                    if let image = bannerImage {
                        Image(appImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        LinearGradient(
                            colors: [Color(red: 0.13, green: 0.115, blue: 0.09),
                                     Color(red: 0.075, green: 0.067, blue: 0.055)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    }
                }
                .clipped()
            // 深色遮罩保证前景文字在任何背景图上可读。
            LinearGradient(
                colors: [.black.opacity(0), .black.opacity(0.6)],
                startPoint: .top, endPoint: .bottom
            )

            HStack(spacing: 26 * contentUnit) {
                bannerAvatar
                VStack(alignment: .leading, spacing: 8 * contentUnit) {
                    Text(verbatim: bannerTitle)
                        .font(.system(size: 34 * contentUnit, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(verbatim: bannerSubtitle)
                        .font(.system(size: 18 * contentUnit))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(30 * contentUnit)
        }
        // 帧定位在前、裁切在后（§40.1 教训：scaledToFill 图不得铺出图区）。
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .clipShape(Self.cardShape)
        .overlay(Self.cardShape.strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }

    /// 横幅标题：用户自定义（空则回退 app 名）。
    private var bannerTitle: String {
        let t = UserDefaults.standard.string(forKey: UserCustomization.bannerTitleKey) ?? ""
        return t.isEmpty ? L10n.tr("app.menu", lang: language) : t
    }

    /// 横幅副标题：用户自定义（空则回退「共 N 款游戏」）。
    private var bannerSubtitle: String {
        let t = UserDefaults.standard.string(forKey: UserCustomization.bannerSubtitleKey) ?? ""
        return t.isEmpty ? L10n.tr("home.bannerSubtitleDefault", [games.count], lang: language) : t
    }

    /// 大头像：用户头像，未设时同理占位（圆框 + 描边）；随卡片缩放（更大更大气）。
    private var bannerAvatar: some View {
        Group {
            if let image = avatarImage {
                Image(appImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: 96 * contentUnit, height: 96 * contentUnit)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 3 * contentUnit.rounded(.up)))
        .shadow(color: .black.opacity(0.35), radius: 10 * contentUnit, y: 4 * contentUnit)
    }

    // MARK: - ③ 我的最爱

    /// 我的最爱页：**iPhone** 走②随机游戏同款「横向封面」显示模式（只展示随机选中的一款）；
    /// **iPad / macOS 保持原版式**（随机置顶 1:1 方卡 + 其余列表在下），未改动。
    @ViewBuilder
    private var favoritesPage: some View {
        #if os(iOS)
        if iPadLayout.isPad {
            favoritesListPage
        } else {
            favoritesSpotlightPage
        }
        #else
        favoritesListPage
        #endif
    }

    /// 原版式（iPad / macOS）：随机置顶一款 1:1 方卡 + 其余最爱列表在下。
    private var favoritesListPage: some View {
        carouselCard(icon: "heart.fill", titleKey: "game.favorites") {
            if favorites.isEmpty {
                emptyHint("home.favoritesHint")
            } else if let featured = featuredFavorite {
                GeometryReader { geo in
                    let rest = favorites.filter { $0.persistentModelID != featured.persistentModelID }
                    VStack(spacing: 8) {
                        if rest.isEmpty {
                            // 只有一款最爱：置顶卡占满整页。
                            featuredFavoriteCard(featured)
                                .frame(height: geo.size.height)
                        } else {
                            featuredFavoriteCard(featured)
                                .frame(height: geo.size.height * 0.55)
                            Divider().opacity(0.6)
                            gameRows(rest) { game, _ in
                                gameRow(rank: nil, game) { onSelect(game) }
                            }
                        }
                    }
                }
            }
        }
    }

    /// 置顶的最爱卡：1:1 方形封面（占满行高）+ 信息 + 爱心角标。整卡点进详情。
    private func featuredFavoriteCard(_ game: Game) -> some View {
        Button(action: { onSelect(game) }) {
            HStack(spacing: 14 * contentUnit) {
                squareCover(game)
                    .frame(maxHeight: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                VStack(alignment: .leading, spacing: 3 * contentUnit) {
                    HStack(alignment: .firstTextBaseline, spacing: 6 * contentUnit) {
                        Text(verbatim: game.displayName(for: language))
                            .font(.system(size: 18 * contentUnit, weight: .semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 4 * contentUnit)
                        Image(systemName: "heart.fill")
                            .font(.system(size: 12 * contentUnit))
                            .foregroundStyle(Color.pink)
                    }
                    if !game.platformList.isEmpty {
                        GamePlatformIcons(platforms: game.platformList, maxCount: 4, iconSize: 12 * contentUnit)
                    }
                    if let score = game.libraryScore {
                        Text(verbatim: GameCardView.formatScore(score))
                            .font(.system(size: 16 * contentUnit, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 2 * contentUnit)
                    if !game.reviewTitle.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 4 * contentUnit) {
                            Image(systemName: "text.quote")
                                .font(.system(size: 12 * contentUnit))
                                .foregroundStyle(Color.accentColor)
                            Text(verbatim: game.reviewTitle)
                                .font(.system(size: 14 * contentUnit))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10 * contentUnit)
            .background(Self.cardShape.fill(Color.semantic(.quaternarySystemFill)))
            .clipShape(Self.cardShape)
        }
        .buttonStyle(PressFeedbackButtonStyle())
    }

    #if os(iOS)
    // MARK: ③ iPhone 版「横向封面」版式（与②逐项同构，②本身代码未改动）

    /// iPhone 版「我的最爱」：与②随机游戏**同一显示模式**——有横图/背景图 → 全幅打底 + 压底
    /// 文字块；否则 → 2:3 封面 + 右侧文字（同②的两种形态，判定口径也一致：复用 backdropImage）。
    /// **只展示随机选中的那一款**——不再有「置顶卡 + 其余列表 + 分割线」（原版式在矮卡上置顶卡
    /// 会与分割线重叠，2026-09-15 用户报告并要求改成②的样式）。
    @ViewBuilder
    private var favoritesSpotlightPage: some View {
        if let game = featuredFavorite {
            if backdropImage(for: game) != nil {
                favoritesFullBleed(game)
            } else {
                favoritesPortraitFallback(game)
            }
        } else {
            emptyHint("home.favoritesHint")
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Self.cardShape.fill(Color.semantic(.controlBackground)))
                .clipShape(Self.cardShape)
        }
    }

    /// 全幅版：底图铺满 + 压底文字块（评分小胶囊 / 名称+平台 / 评价标题），右上角爱心标。
    /// 高度走硬性定值（§51 口径：只有定值 frame 才钳制布局，否则内容撑破页面盒会连圆角一起被裁）。
    private func favoritesFullBleed(_ game: Game) -> some View {
        Button(action: { onSelect(game) }) {
            ZStack(alignment: .bottom) {
                spotlightBackdrop(game)
                LinearGradient(
                    colors: [.black.opacity(0.02), .black.opacity(0.72)],
                    startPoint: .top, endPoint: .bottom
                )
                favoritesTextBlock(game, onPhoto: true)
                    .padding(16 * contentUnit)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            .frame(height: max(pageHeight, 80), alignment: .topLeading)
        }
        .buttonStyle(PressFeedbackButtonStyle())
        .clipShape(Self.cardShape)
        .overlay(Self.cardShape.strokeBorder(.white.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 4)
        .overlay(alignment: .topTrailing) { favoriteHeartBadge.padding(12 * contentUnit) }
    }

    /// 竖版回退版（该最爱没有横图/背景图）：左 2:3 封面 + 右文字列，版式对齐②的 iOS 回退分支。
    private func favoritesPortraitFallback(_ game: Game) -> some View {
        Button(action: { onSelect(game) }) {
            HStack(spacing: 16 * contentUnit) {
                posterCover(game)
                favoritesTextBlock(game, onPhoto: false)
                Spacer(minLength: 0)
            }
            .padding(16 * contentUnit)
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity)
            .frame(height: max(pageHeight, 80), alignment: .topLeading)
        }
        .buttonStyle(PressFeedbackButtonStyle())
        .background(Self.cardShape.fill(Color.semantic(.controlBackground)))
        .overlay(Self.cardShape.strokeBorder(.quaternary, lineWidth: 0.5))
        .clipShape(Self.cardShape)
        .shadow(color: .black.opacity(0.09), radius: 9, y: 2)
        .overlay(alignment: .topTrailing) { favoriteHeartBadge.padding(12 * contentUnit) }
    }

    /// 文字块。`onPhoto` = 压在照片上：白字版、评价标题紧随（靠 ZStack 压底）；
    /// false = 普通卡上：主色字版、评价标题用 Spacer 推到文字列底部（与②回退版同款）。
    private func favoritesTextBlock(_ game: Game, onPhoto: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6 * contentUnit) {
            spotlightScoreInline(game)
            // 平台图标与标题中轴对齐（详情页 nameRow 统一口径）。
            HStack(alignment: .center, spacing: 8 * contentUnit) {
                Text(verbatim: game.displayName(for: language))
                    .font(.system(size: 20 * contentUnit, weight: .bold))
                    .foregroundStyle(onPhoto ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !game.platformList.isEmpty {
                    GamePlatformIcons(platforms: game.platformList, maxCount: 4, iconSize: 13 * contentUnit)
                }
            }
            if !onPhoto { Spacer(minLength: 4 * contentUnit) }
            // 评价标题（与②同款：这张卡的重点展示对象之一）。
            HStack(alignment: .firstTextBaseline, spacing: 5 * contentUnit) {
                Image(systemName: "text.quote")
                    .font(.system(size: 12 * contentUnit))
                    .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.42))
                if game.reviewTitle.isEmpty {
                    Text(verbatim: L10n.tr("home.spotlightNoReview", lang: language))
                        .font(.system(size: 15 * contentUnit))
                        .foregroundStyle(onPhoto ? AnyShapeStyle(.white.opacity(0.75)) : AnyShapeStyle(.tertiary))
                } else {
                    Text(verbatim: game.reviewTitle)
                        .font(.system(size: 15 * contentUnit, weight: .medium))
                        .foregroundStyle(onPhoto ? AnyShapeStyle(.white.opacity(0.92)) : AnyShapeStyle(.secondary))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
        }
    }

    /// 右上角爱心标：与②的 shuffle 同款胶囊（不可点）——标的是「这张卡展示的是最爱」。
    private var favoriteHeartBadge: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 13 * contentUnit, weight: .semibold))
            .foregroundStyle(Color.pink)
            .padding(8 * contentUnit)
            .background(Capsule().fill(.black.opacity(0.45)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 1))
    }
    #endif

    private var favorites: [Game] {
        games.filter(\.isFavorite)
    }

    /// 从我喜爱列表里随机挑一款置顶（每次进入首页换一轮，尽量不重复上一款）。
    private static func randomFavoriteID(games: [Game], avoiding avoid: PersistentIdentifier?) -> PersistentIdentifier? {
        guard !games.isEmpty else { return nil }
        if let avoid, games.count > 1,
           let next = games.filter({ $0.persistentModelID != avoid }).randomElement() {
            return next.persistentModelID
        }
        return games.randomElement()?.persistentModelID
    }

    // MARK: - ④ 库内速览

    private var statsPage: some View {
        carouselCard(icon: "chart.bar.fill", titleKey: "home.statsTitle") {
            statTiles([
                (value: "\(games.count)",
                 label: L10n.tr("stats.totalGames", lang: language)),
                (value: averageScore.map { String(format: "%.1f", $0) } ?? "—",
                 label: L10n.tr("stats.avgScore", lang: language)),
                (value: "\(backlogCount)",
                 label: L10n.tr("stats.backlogCount", lang: language)),
                (value: "\(completedCount)",
                 label: L10n.tr(GameStatus.completed.labelKey, lang: language)),
            ])
            statusDistribution
        }
    }

    private var averageScore: Double? { LibraryStats.averageScore(games) }
    private var backlogCount: Int { LibraryStats.backlogCount(games) }
    /// 已通关 + 长线游玩（详情页视为同一类）。
    private var completedCount: Int {
        games.filter(\.isCompletedOrLongRunning).count
    }

    /// 六状态计数分布行（想玩…已通关，每状态一个计数胶囊）。
    private var statusDistribution: some View {
        HStack(spacing: 6) {
            ForEach(GameStatus.allCases) { status in
                let n = games.filter { $0.statusValue == status }.count
                HStack(spacing: 3) {
                    Text(verbatim: L10n.tr(status.labelKey, lang: language))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(verbatim: "\(n)")
                        .monospacedDigit()
                        .foregroundStyle(Color.accentColor)
                }
                .font(.system(size: 10 * contentUnit, weight: .medium))
                .padding(.horizontal, 7 * contentUnit)
                .padding(.vertical, 3 * contentUnit)
                .background(
                    Capsule().fill(Color.accentColor.opacity(0.12))
                )
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - ⑤ 收藏家速览

    private var holdingsPage: some View {
        carouselCard(icon: "shippingbox.fill", titleKey: "home.holdingsTitle") {
            let totals = LibraryStats.collectorTotals(games.flatMap(\.copies), language: language)
            if totals.editionCount == 0 {
                emptyHint("home.holdingsHint")
            } else {
                statTiles([
                    (value: "\(totals.editionCount)",
                     label: L10n.tr("copy.overviewEditions", lang: language)),
                    (value: "\(totals.totalQuantity)",
                     label: L10n.tr("copy.overviewQuantity", lang: language)),
                    (value: PriceFormat.string(totals.totalSpent, language: language) ?? "—",
                     label: L10n.tr("copy.overviewSpent", lang: language)),
                    (value: PriceFormat.string(totals.totalEstimate, language: language) ?? "—",
                     label: L10n.tr("copy.overviewEstimate", lang: language)),
                ])
            }
        }
    }

    // MARK: - ② 随机游戏（第 2 页；全库随机）

    /// 随机游戏底图按设置页偏好解析：auto=横向封面优先、无则背景图；hero=仅背景图；
    /// landscape=仅横向封面。都取不到返回 nil（调用点回退竖版版式/渐变）。
    private func backdropImage(for game: Game) -> AppImage? {
        switch activeSpotlightBackdropRaw {
        case UserCustomization.spotlightBackdropHero:
            return game.heroImage
        case UserCustomization.spotlightBackdropLandscape:
            return game.landscapeImage
        default:
            return game.landscapeImage ?? game.heroImage
        }
    }

    /// 随机游戏页：解析出底图（按偏好）→ 封面全幅打底（提亮）；否则（仅竖版封面/
    /// 无图）→ 网格同款 2:3 封面 + 文字右侧（2026-08-30 用户定稿：竖图不放大打底，避免特高观感）。
    private var spotlightPage: some View {
        Group {
            if let game = spotlight {
                if backdropImage(for: game) != nil {
                    spotlightFullBleed(game)
                } else {
                    spotlightPortraitFallback(game)
                }
            } else {
                emptyHint("stats.noData")
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Self.cardShape.fill(Color.semantic(.controlBackground)))
                    .clipShape(Self.cardShape)
            }
        }
    }

    /// 全幅打底版（有横图）：封面 scaledToFill 铺满 + 轻遮罩（封面比前景文字偏亮），
    /// 名称/平台/评价标题压底；右上角评分 + shuffle。
    /// iOS 小屏紧凑布局（§46 末，用户拍板）：平均分改**单行小胶囊**（「平均分 ★数字」）放标题
    /// 上方（文字块整体下移一行）、平台图标并入标题右侧一行——大屏胶囊 + 图标独立行太占纵向空间。
    private func spotlightFullBleed(_ game: Game) -> some View {
        Button(action: { onSelect(game) }) {
            // ZStack 压底对齐：文字块钉在卡片底缘；底图/渐变吃满提案不受对齐影响。
            ZStack(alignment: .bottom) {
                spotlightBackdrop(game)
                LinearGradient(
                    colors: [.black.opacity(0.02), .black.opacity(0.72)],
                    startPoint: .top, endPoint: .bottom
                )
                #if os(iOS)
                VStack(alignment: .leading, spacing: 6 * contentUnit) {
                    spotlightScoreInline(game)
                    // 平台图标与标题中轴对齐（详情页 nameRow 统一口径；firstTextBaseline 对
                    // 图片等效底对齐，图标放大系数不同会顶部参差）。
                    HStack(alignment: .center, spacing: 8 * contentUnit) {
                        Text(verbatim: game.displayName(for: language))
                            .font(.system(size: 20 * contentUnit, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if !game.platformList.isEmpty {
                            GamePlatformIcons(platforms: game.platformList, maxCount: 4, iconSize: 13 * contentUnit)
                        }
                    }
                    // 评价标题（随机游戏的重点展示对象）。
                    HStack(alignment: .firstTextBaseline, spacing: 5 * contentUnit) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 12 * contentUnit))
                            .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.42))
                        if game.reviewTitle.isEmpty {
                            Text(verbatim: L10n.tr("home.spotlightNoReview", lang: language))
                                .font(.system(size: 15 * contentUnit))
                                .foregroundStyle(.white.opacity(0.75))
                        } else {
                            Text(verbatim: game.reviewTitle)
                                .font(.system(size: 15 * contentUnit, weight: .medium))
                                .foregroundStyle(.white.opacity(0.92))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
                .padding(16 * contentUnit)
                .frame(maxWidth: .infinity, alignment: .leading)
                #else
                VStack(alignment: .leading, spacing: 6 * contentUnit) {
                    Text(verbatim: game.displayName(for: language))
                        .font(.system(size: 22 * contentUnit, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !game.platformList.isEmpty {
                        GamePlatformIcons(platforms: game.platformList, maxCount: 4, iconSize: 13 * contentUnit)
                    }
                    // 评价标题（随机游戏的重点展示对象）。
                    HStack(alignment: .firstTextBaseline, spacing: 5 * contentUnit) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 12 * contentUnit))
                            .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.42))
                        if game.reviewTitle.isEmpty {
                            Text(verbatim: L10n.tr("home.spotlightNoReview", lang: language))
                                .font(.system(size: 15 * contentUnit))
                                .foregroundStyle(.white.opacity(0.75))
                        } else {
                            Text(verbatim: game.reviewTitle)
                                .font(.system(size: 15 * contentUnit, weight: .medium))
                                .foregroundStyle(.white.opacity(0.92))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
                .padding(18 * contentUnit)
                .frame(maxWidth: .infinity, alignment: .leading)
                #endif
            }
        }
        .buttonStyle(PressFeedbackButtonStyle())
        .clipShape(Self.cardShape)
        .overlay(Self.cardShape.strokeBorder(.white.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 4)
        #if os(macOS)
        .overlay(alignment: .topTrailing) { spotlightScoreOverlay(game).padding(12 * contentUnit) }
        #else
        // iOS：评分已并入文字块（标题上方小胶囊），右上角只留 shuffle。
        .overlay(alignment: .topTrailing) { spotlightShuffleButton(game).padding(12 * contentUnit) }
        #endif
    }

    /// iOS 单行小评分胶囊：「平均分 ★数字」一行排布（紧凑，放标题上方）。
    @ViewBuilder
    private func spotlightScoreInline(_ game: Game) -> some View {
        if let score = game.libraryScore {
            HStack(spacing: 5 * contentUnit) {
                Text(verbatim: L10n.tr("group.avgScore", lang: language))
                    .font(.system(size: 11 * contentUnit, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                Image(systemName: "star.fill")
                    .font(.system(size: 11 * contentUnit))
                    .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.42))
                Text(verbatim: GameCardView.formatScore(score))
                    .font(.system(size: 13 * contentUnit, weight: .bold))
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 9 * contentUnit)
            .padding(.vertical, 4 * contentUnit)
            .background(Capsule().fill(.black.opacity(0.45)))
            .overlay(
                Capsule().strokeBorder(Color(red: 1.0, green: 0.72, blue: 0.42).opacity(0.55),
                                      lineWidth: 1)
            )
        }
    }

    /// shuffle 再随机按钮（iOS 右上角单独用；macOS 与评分胶囊并排）。
    private func spotlightShuffleButton(_ game: Game) -> some View {
        Button {
            spotlightID = Self.randomSpotlightID(games: games, avoiding: game.persistentModelID)
        } label: {
            Image(systemName: "shuffle")
                .font(.system(size: 13 * contentUnit, weight: .semibold))
                .foregroundStyle(.white)
                .padding(8 * contentUnit)
                .background(Capsule().fill(.black.opacity(0.45)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// 竖版回退版（仅 2:3 封面或无图）：左=网格同款 2:3 封面（完整不裁剪），右=文字信息。
    /// iOS 同样走紧凑口径：评分小胶囊在标题上方、平台图标并入标题右侧（与全幅版一致）。
    private func spotlightPortraitFallback(_ game: Game) -> some View {
        Button(action: { onSelect(game) }) {
            HStack(spacing: 16 * contentUnit) {
                posterCover(game)
                VStack(alignment: .leading, spacing: 6 * contentUnit) {
                    #if os(iOS)
                    spotlightScoreInline(game)
                    #endif
                    // iOS 平台图标与标题中轴对齐（详情页 nameRow 口径）；macOS 保持基线对齐版式。
                    #if os(iOS)
                    HStack(alignment: .center, spacing: 8 * contentUnit) {
                        Text(verbatim: game.displayName(for: language))
                            .font(.system(size: 20 * contentUnit, weight: .bold))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if !game.platformList.isEmpty {
                            GamePlatformIcons(platforms: game.platformList, maxCount: 4, iconSize: 13 * contentUnit)
                        }
                    }
                    #else
                    Text(verbatim: game.displayName(for: language))
                        .font(.system(size: 20 * contentUnit, weight: .bold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    #endif
                    #if os(macOS)
                    if !game.platformList.isEmpty {
                        GamePlatformIcons(platforms: game.platformList, maxCount: 4, iconSize: 13 * contentUnit)
                    }
                    #endif
                    Spacer(minLength: 4 * contentUnit)
                    // 评价标题（随机游戏的重点展示对象）。
                    HStack(alignment: .firstTextBaseline, spacing: 5 * contentUnit) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 12 * contentUnit))
                            .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.42))
                        if game.reviewTitle.isEmpty {
                            Text(verbatim: L10n.tr("home.spotlightNoReview", lang: language))
                                .font(.system(size: 15 * contentUnit))
                                .foregroundStyle(.tertiary)
                        } else {
                            Text(verbatim: game.reviewTitle)
                                .font(.system(size: 15 * contentUnit, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16 * contentUnit)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressFeedbackButtonStyle())
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Self.cardShape.fill(Color.semantic(.controlBackground)))
        .overlay(Self.cardShape.strokeBorder(.quaternary, lineWidth: 0.5))
        .clipShape(Self.cardShape)
        .shadow(color: .black.opacity(0.09), radius: 9, y: 2)
        #if os(macOS)
        .overlay(alignment: .topTrailing) { spotlightScoreOverlay(game).padding(12 * contentUnit) }
        #else
        // iOS：评分已并入文字块，右上角只留 shuffle。
        .overlay(alignment: .topTrailing) { spotlightShuffleButton(game).padding(12 * contentUnit) }
        #endif
    }

    /// 右上角：突出评分（琥珀星标胶囊）+ shuffle 再随机（macOS 用；iOS 拆成
    /// 文字块内 spotlightScoreInline + 独立 spotlightShuffleButton）。
    private func spotlightScoreOverlay(_ game: Game) -> some View {
        HStack(spacing: 8) {
            if let score = game.libraryScore {
                HStack(spacing: 6 * contentUnit) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 13 * contentUnit))
                        .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.42))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: L10n.tr("group.avgScore", lang: language))
                            .font(.system(size: 9 * contentUnit, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                        Text(verbatim: GameCardView.formatScore(score))
                            .font(.system(size: 20 * contentUnit, weight: .bold))
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12 * contentUnit)
                .padding(.vertical, 6 * contentUnit)
                .background(Capsule().fill(.black.opacity(0.45)))
                .overlay(
                    Capsule().strokeBorder(Color(red: 1.0, green: 0.72, blue: 0.42).opacity(0.55),
                                          lineWidth: 1)
                )
            }
            spotlightShuffleButton(game)
        }
    }

    /// 随机游戏全幅底色（仅在有横图时被调用）：横图 scaledToFill + 轻微提亮。
    /// 根治（§46 三点问题）：Color.clear 承接提案尺寸、图只做 overlay——overlay 内的图
    /// **永不参与布局定尺寸**；此前「scaledToFill + 弹性 frame」被图理想尺寸撑破
    /// （460:215 图按宽填充报 545pt 高 > 卡片盒 417pt），ZStack 溢出→上下内容被裁。
    @ViewBuilder
    private func spotlightBackdrop(_ game: Game) -> some View {
        Color.clear
            .overlay {
                if let image = backdropImage(for: game) {
                    Image(appImage: image)
                        .resizable()
                        .scaledToFill()
                        .brightness(0.06)
                } else {
                    LinearGradient(
                        colors: [Color(red: 0.13, green: 0.115, blue: 0.09),
                                 Color(red: 0.075, green: 0.067, blue: 0.055)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }
            }
            .clipped()
    }

    /// 网格同款 2:3 封面（完整展示不放大裁剪；无图占位）。宽 110 基准随卡片缩放。
    @ViewBuilder
    private func posterCover(_ game: Game) -> some View {
        Group {
            if let image = game.coverImage {
                Image(appImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(Color.semantic(.quaternarySystemFill))
                    Image(systemName: "gamecontroller")
                        .font(.system(size: 22 * contentUnit))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: 110 * contentUnit, height: 165 * contentUnit)
        .clipShape(RoundedRectangle(cornerRadius: 10 * contentUnit))
        .overlay(RoundedRectangle(cornerRadius: 10 * contentUnit).strokeBorder(.quaternary, lineWidth: 1))
        .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
    }

    /// 随机游戏入口：从库里随机挑一款（每次进入首页换一轮，尽量不重复上一款）。
    private static func randomSpotlightID(games: [Game], avoiding avoid: PersistentIdentifier?) -> PersistentIdentifier? {
        guard !games.isEmpty else { return nil }
        if let avoid, games.count > 1,
           let next = games.filter({ $0.persistentModelID != avoid }).randomElement() {
            return next.persistentModelID
        }
        return games.randomElement()?.persistentModelID
    }

    /// 1:1 方形封面：优先方形图，无则竖版封面正裁填满，再退占位。
    @ViewBuilder
    private func squareCover(_ game: Game) -> some View {
        Group {
            if let image = game.squareImage ?? game.coverImage {
                Image(appImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle()
                        .fill(Color.semantic(.quaternarySystemFill))
                    Image(systemName: "gamecontroller")
                        .font(.system(size: 26))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary, lineWidth: 0.5))
    }

    // MARK: - 卡片骨架

    private static let cardShape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    /// 通用卡片容器：图标 + 标题头 + 内容区（内容填满剩余高度，列表页内滚）。
    private func carouselCard<Content: View>(icon: String, titleKey: String,
                                             @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10 * contentUnit) {
            HStack(spacing: 6 * contentUnit) {
                Image(systemName: icon)
                    .font(.system(size: 14 * contentUnit))
                    .foregroundStyle(Color.accentColor)
                LText(titleKey)
                    .font(.system(size: 17 * contentUnit, weight: .semibold))
            }
            content()
        }
        .padding(16)
        // 宽度走弹性（内容本就撑满页面宽），**高度必须硬性定值**——§46 口径：只有定值 frame
        // 才钳制布局。用 `maxHeight: .infinity` 时，内容自然高超过页面盒的页（④⑤ 速览页：
        // 2×2 瓦片 + 六状态分布实测 ~145pt > 可用 ~119pt）会把卡片撑破页面盒，超出的部分被
        // TabView 页面居中后由 `.clipped()` 从上下裁掉——两端的圆角正好被切走，⑤ 页只剩一段弧、
        // ④ 页直接变直角，与 ①②③ 页的 16pt 圆角对不上（2026-09-15 用户报告实锤，§51）。
        // 定值高度让卡片盒子恒等于页面盒：内容再高也只在盒内溢出（由 clipShape 收边）。
        .frame(maxWidth: .infinity)
        .frame(height: max(pageHeight, 80), alignment: .topLeading)
        .background(Self.cardShape.fill(Color.semantic(.controlBackground)))
        .overlay(Self.cardShape.strokeBorder(.quaternary, lineWidth: 0.5))
        .clipShape(Self.cardShape)
        .shadow(color: .black.opacity(0.09), radius: 9, y: 2)
    }

    /// 速览页瓦片版式：卡片矮时（iPhone，2.1 比例 ≈176pt）2×2 网格的自然高放不进页面盒，
    /// 卡片会被撑破（圆角被裁，见 carouselCard 注释）——改**单行四列**（实测 ~80pt，宽裕）；
    /// 卡片够高（iPad / macOS / 宽窗）保持 2×2 观感不变。阈值 260pt：iPhone 全系（≈163–200pt）
    /// 走紧凑，iPad 竖 339 / 横 367、macOS 最窄窗 ~285 都走 2×2。
    private var usesCompactStatTiles: Bool { pageHeight < 260 }

    /// 四个统计瓦片（版式按卡片高度自适应，见 usesCompactStatTiles）。
    private func statTiles(_ items: [(value: String, label: String)]) -> some View {
        Group {
            if usesCompactStatTiles {
                HStack(spacing: 8) {
                    ForEach(items.indices, id: \.self) { i in
                        statTile(value: items[i].value, label: items[i].label)
                    }
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(items.indices, id: \.self) { i in
                        statTile(value: items[i].value, label: items[i].label)
                    }
                }
            }
        }
    }

    /// 统计小瓦片：大数值 + 次要小标签（随卡片缩放）。
    private func statTile(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2 * contentUnit) {
            Text(verbatim: value)
                .font(.system(size: 24 * contentUnit, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(verbatim: label)
                .font(.system(size: 12 * contentUnit))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10 * contentUnit)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.semantic(.quaternarySystemFill))
        )
    }

    /// 空态提示（最爱为空 / 持有记录为空）。
    private func emptyHint(_ key: String) -> some View {
        HStack(spacing: 6 * contentUnit) {
            Image(systemName: "info.circle")
                .font(.system(size: 15 * contentUnit))
                .foregroundStyle(.secondary)
            LText(key)
                .font(.system(size: 15 * contentUnit))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 8 * contentUnit)
    }

    /// 游戏行列表（卡片剩余高度内滚动；`row` 的第二参 = 行下标，供计算名次）。
    private func gameRows(_ games: [Game], row: @escaping (Game, Int) -> some View) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(games.enumerated()), id: \.element.persistentModelID) { index, game in
                    row(game, index)
                    if index < games.count - 1 {
                        Divider().opacity(0.5)
                    }
                }
            }
        }
    }

    /// 单行：可带名次或缩略图。缩略图用封面（34×46 竖版，与库网格观感一致）；无封面用占位。
    @ViewBuilder
    private func gameRow(rank: Int?, _ game: Game, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10 * contentUnit) {
                if let rank {
                    Text(verbatim: "\(rank)")
                        .font(.system(size: 12 * contentUnit, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 24 * contentUnit, alignment: .trailing)
                }
                Group {
                    if let image = game.coverImage {
                        Image(appImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color.semantic(.quaternarySystemFill))
                    }
                }
                .frame(width: 34 * contentUnit, height: 46 * contentUnit)
                .clipShape(RoundedRectangle(cornerRadius: 5 * contentUnit))

                VStack(alignment: .leading, spacing: 2 * contentUnit) {
                    Text(verbatim: game.displayName(for: language))
                        .font(.system(size: 12 * contentUnit, weight: .medium))
                        .lineLimit(1)
                    if !game.platformList.isEmpty {
                        Text(verbatim: game.platformList
                            .prefix(2)
                            .map { Presets.display($0, category: .platform, language: language) }
                            .joined(separator: " · "))
                            .font(.system(size: 11 * contentUnit))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if let score = game.libraryScore {
                    Text(verbatim: GameCardView.formatScore(score))
                        .font(.system(size: 12 * contentUnit, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4 * contentUnit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}