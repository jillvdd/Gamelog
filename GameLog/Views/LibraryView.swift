import SwiftUI
import SwiftData

#if os(macOS)
import AppKit
#endif

/// 主界面：网格/列表切换、搜索、平台筛选、排序、分享、新建入口。
struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    /// 整库替换锁定期（根容器经 environment 下传）：true 时只渲染静态占位，
    /// 不持有/不渲染任何 Game/Group——杜绝替换中的 detached 访问崩溃（2026-09-08）。
    @Environment(\.libraryReplacing) private var libraryReplacing
    @Query(sort: \Game.createdAt) private var games: [Game]
    let groupFilter: GameGroup?
    /// 非分组视图（全部游戏 / 侧边栏某平台）的平台过滤，由侧边栏选择驱动，切换即重置。
    var platform: String? = nil
    /// 状态过滤（想玩/在玩/搁置/弃坑/已通关），由侧边栏/iOS 筛选菜单选择驱动，与 groupFilter/platform 互斥。
    var statusFilter: GameStatus? = nil
    /// 虚拟分组「我的最爱」：仅显示 isFavorite 游戏（侧边栏/iOS 筛选菜单进入，与分组/平台/状态互斥）。
    var favoritesOnly: Bool = false

    @State private var searchText = ""
    /// 库视图模式（`LibraryViewMode` 原始值，**双平台共用**）。可选项按平台不同，见 `LibraryViewMode.available`。
    /// 此前是两套互不相干的键（macOS 一个 `useGridView` Bool、iOS 一个三态字符串）；
    /// macOS 加方形网格后是三态，两个 Bool 表达不了，所以合并成这一个。
    /// 读到的原始值一律经 `resolved(_:)` 收敛 —— 它会把「本平台不支持的档位」也折回网格
    ///（比如从 iOS 备份恢复到 macOS 时留下的 `wideCard`）。
    @AppStorage(UserCustomization.libraryViewModeKey) private var viewModeRaw = ""
    /// 旧键一次性迁移守卫（`onAppear` 里跑，各平台读各自的历史键）。跨平台，故不在 `#if os(iOS)` 内。
    @State private var didMigrateLibraryViewMode = false
    #if os(iOS)
    /// 宽卡双列网格的实测内容列宽（背景 GeometryReader 测量，HomeCarousel pageWidth 同款
    /// 模式）——供 GameWideCardView 做 iPad 横竖屏分档与竖版卡封面边长。首帧 0 时卡片走
    /// 349 回退边长，onAppear 即校正（与轮播 pageWidth 起步 0 同口径）。
    @State private var wideCardGridWidth: CGFloat = 0
    #endif
    /// 分组视图内局部平台过滤（不持久化，切换分组即重置）。
    @State private var groupPlatformFilter = ""
    @AppStorage("librarySort") private var sortRaw = LibrarySort.recentEdit.rawValue
    /// 隐藏上方毛玻璃（设置「个性化」开关）：开启 = 无标题 + 完全无毛玻璃（全局应用，各页面一致）。
    @AppStorage(UserCustomization.hideToolbarGlassKey) private var hideToolbarGlass = false

    @State private var path = NavigationPath()
    /// iOS：详情页编程式 push 的目标（复用外层导航栈，避免双层 NavigationStack）。
    @State private var selectedGame: Game?
    @State private var pendingDeleteGame: Game?
    @State private var editingGame: Game?
    @State private var groupPickerGame: Game?
    /// 右键菜单「合并到另一个游戏…」的源条目（并进用户随后选中的那个）。
    @State private var mergeSourceGame: Game?
    @State private var showingNewGame = false
    @State private var showingShare = false

    private var sortOption: LibrarySort { LibrarySort(rawValue: sortRaw) ?? .completionDate }

    /// 当前视图模式：原始值经平台收敛（未知值 / 本平台不支持的档位一律回退网格）。
    /// 迁移未跑或键为空时也走这里 —— `resolved("")` 给的是网格，而 `onAppear` 的迁移会立刻写上真实值。
    private var viewMode: LibraryViewMode {
        LibraryViewMode.resolved(viewModeRaw)
    }

    /// 还活着的游戏。批量删除（清空导入数据 / 整库替换）后 SwiftUI 可能拿**旧数组**
    /// 再渲染一帧，读一个已销毁模型就是 `Fatal error: This backing data was detached`。
    /// 卡片自带 `isLive` 守卫，但给到下层的**数组**（轮播、分组统计）没有 —— 在源头拦。
    /// 本视图所有下游（轮播、`visibleGames`、`allFavorites`）都从这一个入口取。
    private var liveGames: [Game] { games.filter(\.isLive) }

    /// 分组模式下工具栏平台菜单的候选：本组内出现的平台（预设世代倒序 + 自定义排最后）。
    private var groupPlatforms: [String] {
        guard let group = groupFilter, group.isLive else { return [] }
        return Presets.ordered(group.games.flatMap { $0.completions.map(\.platform) })
    }

    private var visibleGames: [Game] {
        // 平台过滤在分组/非分组两种模式下都生效（iOS 由分组/平台两个菜单驱动；macOS 分组模式叠加 groupPlatformFilter）。
        //
        // 先滤掉已销毁的模型：数组级消费者（分组统计、轮播、搜索结果）没有卡片那层
        // `isLive` 守卫，得在源头拦。
        //
        // 分组本身也要活在：`LibraryQuery.filter` 在 group 非 nil 时直接读 `group.games`，
        // 而侧边栏选中态与这里有两帧缝隙（选中被删分组时读一次就是 SwiftData fatal）。
        if let groupFilter, !groupFilter.isLive { return [] }
        var result = LibraryQuery.filter(
            games: liveGames, group: groupFilter,
            platform: platform, status: statusFilter, search: searchText
        )
        if favoritesOnly {
            result = result.filter(\.isFavorite)
        }
        #if os(macOS)
        // 只在分组视图内生效（工具栏的平台菜单仅分组模式下出现）；这里只判「有没有选中分组」，
        // 不用 `if let` 绑名字——绑了也不用，编译器会报未使用警告。
        if groupFilter != nil, !groupPlatformFilter.isEmpty {
            result = result.filter { $0.platformList.contains(groupPlatformFilter) }
        }
        #endif
        return LibraryQuery.sorted(result, by: sortOption, language: language)
    }

    /// 虚拟分组「我的最爱」的全体成员（统计区块依据——不受搜索/排序影响）。
    ///
    /// 滤掉已销毁的模型：批量删除（清空导入数据 / 整库替换）后 SwiftUI 可能拿**旧数组**
    /// 再渲染一帧，而读一个已销毁模型（这里下游是 `GroupStatsSectionContent`，会读分数、
    /// 平台、时长）就是 `Fatal error: This backing data was detached`。卡片自带 `isLive`
    /// 守卫，但统计区块读的是数组本身，得在这里拦（2026-09-16 崩溃同源，见 `Game.isLive`）。
    private var allFavorites: [Game] {
        liveGames.filter(\.isFavorite)
    }

    /// 轮播只出现在「全部游戏」起始页：无分组、无平台、无状态、非最爱虚拟分组。
    private var showsHomeCarousel: Bool {
        groupFilter == nil && platform == nil && statusFilter == nil && !favoritesOnly
    }

    /// 点击轮播内游戏行 → 复用库的推详情路径（macOS path / iOS selectedGame）。
    private func openDetail(_ game: Game) {
        #if os(macOS)
        path.append(game)
        #else
        selectedGame = game
        #endif
    }

    private var navigationTitleText: String {
        if favoritesOnly {
            return L10n.tr("game.favorites", lang: language)
        }
        if let statusFilter {
            return L10n.tr(statusFilter.labelKey, lang: language)
        }
        if let platform {
            return Presets.display(platform, category: .platform, language: language)
        }
        // 分组可能已被整库替换删掉（选中态还差一帧才被 RootView 的 onChange 清掉）——
        // 读死分组的 `name` 就是 SwiftData fatal。
        if let groupFilter, groupFilter.isLive { return groupFilter.name }
        return L10n.tr("library.all", lang: language)
    }

    /// iOS 起始页内联标题开关（2026-09-05 用户要求）：「全部游戏」+ 轮播页的标题不再占
    /// 导航大标题，改渲染在五页轮播下方、游戏列表上方。仅在实际显示轮播内容页时生效——
    /// 空库 / 搜索无结果（轮播不显示）与其他筛选态（最爱/状态/平台/分组）仍走系统大标题。
    private var showsInlineHomeTitle: Bool {
        showsHomeCarousel && !liveGames.isEmpty && !visibleGames.isEmpty
    }

    /// 轮播下方的内联标题：字号对齐系统大标题，与其他页标题视觉一致。
    private var inlineHomeTitle: some View {
        Text(verbatim: L10n.tr("library.all", lang: language))
            .font(.largeTitle.weight(.bold))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 切换分组/平台筛选时重置导航上下文：退出已打开的详情页、清空搜索词。
    /// 否则同 case 分支内切换（如平台 A → 平台 B）视图身份不变，path/selectedGame/searchText 会残留。
    /// 整库替换时同样调用：额外清掉持有旧 Game 的 sheet state，否则 sheet 里
    /// 的编辑/分组/删除/合并页访问 detached 模型即 SwiftData fatal（2026-09-08）。
    ///
    /// ⚠️ 这里清的是**本视图所有**挂在 `libraryReplacing` 门内的 Game 状态。新增一个
    /// `@State var x: Game?` + `.sheet(item:)` 时，必须同时往这里加一行 —— 漏一个，
    /// 整库替换后那张 sheet 会带着已删对象重新弹出来（`mergeSourceGame` 就是这么漏的）。
    private func resetNavigationContext() {
        #if os(macOS)
        path = NavigationPath()
        #else
        selectedGame = nil
        #endif
        searchText = ""
        editingGame = nil
        groupPickerGame = nil
        pendingDeleteGame = nil
        mergeSourceGame = nil
        showingNewGame = false
        showingShare = false
    }

    // MARK: - 分组视图（游戏 + 底部统计/评价）

    /// 分组内容：游戏网格/列表在上，统计与评价区块在下；空分组也显示区块。
    /// 统计始终反映整个分组，不受搜索/平台筛选影响。
    private func groupContent(group: GameGroup) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if visibleGames.isEmpty {
                    ContentUnavailableView {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                    } description: {
                        LText("library.noResult")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    // 分组页与「我的最爱」页的分支完全相同，故两处逐字一致。
                    #if os(iOS)
                    switch viewMode {
                    // `.squareGrid` 只做在 macOS：`available` 不含它，`resolved(_:)` 也拦得住。
                    // 并进网格臂只为让 switch 穷尽。
                    case .grid, .squareGrid: gameGrid(visibleGames)
                    case .wideCard: gameWideCards(visibleGames)
                    case .list: gameList(visibleGames)
                    }
                    #else
                    switch viewMode {
                    case .grid: gameGrid(visibleGames)
                    case .squareGrid: gameSquareGrid(visibleGames)
                    // `.wideCard` 是 iOS 专属，同理由 `available` 挡在外面。
                    case .wideCard: gameGrid(visibleGames)
                    case .list: gameList(visibleGames)
                    }
                    #endif
                }

                Divider()
                GroupStatsSection(group: group)
                GroupReviewSection(group: group)
            }
            .padding()
            .frame(maxWidth: 1500)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    /// 「全部游戏」起始页顶端的五页轮播。
    /// 传 `liveGames` 而不是原始 `@Query` 结果：轮播的统计/榜单读的是**数组本身**（没有卡片守卫）。
    private var carousel: some View {
        HomeCarousel(games: liveGames, onSelect: openDetail)
    }

    /// 虚拟分组「我的最爱」内容：游戏列表在上、统计在下（无评价区块）。
    private var favoritesContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if allFavorites.isEmpty {
                    ContentUnavailableView {
                        Image(systemName: "heart")
                            .font(.system(size: 48))
                    } description: {
                        LText("home.favoritesHint")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else if visibleGames.isEmpty {
                    ContentUnavailableView {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                    } description: {
                        LText("library.noResult")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    // 分组页与「我的最爱」页的分支完全相同，故两处逐字一致。
                    #if os(iOS)
                    switch viewMode {
                    // `.squareGrid` 只做在 macOS：`available` 不含它，`resolved(_:)` 也拦得住。
                    // 并进网格臂只为让 switch 穷尽。
                    case .grid, .squareGrid: gameGrid(visibleGames)
                    case .wideCard: gameWideCards(visibleGames)
                    case .list: gameList(visibleGames)
                    }
                    #else
                    switch viewMode {
                    case .grid: gameGrid(visibleGames)
                    case .squareGrid: gameSquareGrid(visibleGames)
                    // `.wideCard` 是 iOS 专属，同理由 `available` 挡在外面。
                    case .wideCard: gameGrid(visibleGames)
                    case .list: gameList(visibleGames)
                    }
                    #endif
                }

                Divider()
                // 统计区块反映全部最爱（不受搜索/排序影响）。
                GroupStatsSectionContent(games: allFavorites)
            }
            .padding()
            .frame(maxWidth: 1500)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    /// 网格：自适应列，卡片可点击进详情、右键菜单。
    @ViewBuilder
    private func gameGrid(_ games: [Game]) -> some View {
        // alignment: .top——GridItem 默认垂直居中,同行里较高的卡片(如平台名折两行)
        // 会把矮卡片顶边压下去,造成每列顶端参差;顶部对齐后每行卡片顶端平齐。
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16, alignment: .top)], spacing: 16) {
            ForEach(games) { game in
                gameCard(game)
            }
        }
    }

    /// 方形封面网格（macOS 第三视图）：**列宽/格距与 `gameGrid` 逐字相同**，只有卡片形状不同
    ///（1:1 满铺 vs 2:3）。这样切换视图时格子位置不跳，用户看到的只是封面比例变了。
    ///
    /// 只做在 macOS —— iOS 的三种模式已定（网格/宽卡/列表），`LibraryViewMode.available` 也按平台分了。
    #if os(macOS)
    @ViewBuilder
    private func gameSquareGrid(_ games: [Game]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16, alignment: .top)], spacing: 16) {
            ForEach(games) { game in
                gameSquareCard(game)
            }
        }
    }
    #endif

    /// 列表（分组模式下用 LazyVStack 包进同一 ScrollView，避免嵌套 List）。
    @ViewBuilder
    private func gameList(_ games: [Game]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(games) { game in
                gameRow(game)
            }
        }
    }

    #if os(iOS)
    /// iOS 单列横向卡视图（间距 12 与网格一致）。
    /// iPad（需求⑤ + 需求①，2026-09-05）：双列卡（左右一列两个游戏），列间距 14、
    /// 行间距 12；横屏走横版卡（260pt 卡高升档）、竖屏走竖版卡（上图下文）——
    /// 分档与几何由 GameWideCardView 依据内容列实测宽自算。
    ///
    /// ⚠️ 列宽测量**必须走 background GeometryReader**（2026-09-05 滚动回归根治）：
    /// 此前用 GeometryReader 直接包 LazyVGrid，而它位于 ScrollView > VStack 内——
    /// GeometryReader 贪婪吸收 ScrollView 的有限高度提案（= 视口高）上报为自身尺寸，
    /// VStack 总内容高 = 视口高 → 无可滚余量（主页彻底无法下滚），且 LazyVGrid 被
    /// 钳死在该高度内无法 lazy 生长。background 版不参与布局提案（Color.clear 承接
    /// 既有尺寸），只读实测宽存 @State，与 HomeCarousel pageWidth 同一 idiom。
    @ViewBuilder
    private func gameWideCards(_ games: [Game]) -> some View {
        if iPadLayout.isPad {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14, alignment: .top),
                                GridItem(.flexible(), spacing: 14, alignment: .top)],
                      spacing: 12) {
                ForEach(games) { game in
                    Button {
                        selectedGame = game
                    } label: {
                        GameWideCardView(game: game, viewWidth: wideCardGridWidth)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressFeedbackButtonStyle())
                    .contextMenu { cardMenu(for: game) }
                }
            }
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { wideCardGridWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, w in wideCardGridWidth = w }
                }
            )
        } else {
            LazyVStack(spacing: 12) {
                ForEach(games) { game in
                    Button {
                        selectedGame = game
                    } label: {
                        GameWideCardView(game: game)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressFeedbackButtonStyle())
                    .contextMenu { cardMenu(for: game) }
                }
            }
        }
    }
    #endif

    /// 排序菜单项：LibrarySortMenuItems 共享组件（iOS 更多菜单同源）。
    private var sortMenuItems: some View {
        LibrarySortMenuItems(sortRaw: $sortRaw)
    }

    /// 卡片 cell 的唯一包装：`Button` + 按压反馈 + 右键菜单。
    /// 两种网格（竖版/方形）逐字共用它，只把 `shape` 透传给 `GameCardView` ——
    /// 自建一份 cell 会丢掉右键菜单与按压反馈。
    @ViewBuilder
    private func gameCard(_ game: Game, shape: CardShape = .portrait) -> some View {
        // Button + 按压反馈样式（原 onTapGesture 点按无任何视觉响应，不符 iOS 触控预期）。
        Button {
            #if os(macOS)
            path.append(game)
            #else
            selectedGame = game
            #endif
        } label: {
            GameCardView(game: game, shape: shape)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressFeedbackButtonStyle())
        .contextMenu { cardMenu(for: game) }
    }

    /// 方形网格的 cell，就是上面那个换 `shape`。
    #if os(macOS)
    private func gameSquareCard(_ game: Game) -> some View {
        gameCard(game, shape: .square)
    }
    #endif

    @ViewBuilder
    private func gameRow(_ game: Game) -> some View {
        Button {
            #if os(macOS)
            path.append(game)
            #else
            selectedGame = game
            #endif
        } label: {
            GameRowView(game: game)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressFeedbackButtonStyle())
        .contextMenu { cardMenu(for: game) }
    }

    @ViewBuilder
    private func cardMenu(for game: Game) -> some View {
        #if os(macOS)
        // macOS 上下文菜单顶层既不渲染 SF Symbol、系统 Toggle 勾选也不落屏（用户实测）——
        // 用 Unicode 字形 ♥(实心)/♡(空心) 直接进菜单文字：文字一定渲染，实心/空心即状态。
        Button {
            game.isFavorite.toggle()
            try? context.save()
        } label: {
            Text(verbatim: (game.isFavorite ? "♥ " : "♡ ") + L10n.tr("game.favorites", lang: language))
        }
        #else
        // iOS 长按菜单渲染 SF Symbol：实心 = 已收藏、空心 = 未收藏（用户指定口径）。
        Button {
            game.isFavorite.toggle()
            try? context.save()
        } label: {
            if game.isFavorite {
                Label(L10n.tr("game.favorites", lang: language), systemImage: "heart.fill")
            } else {
                Label(L10n.tr("game.favorites", lang: language), systemImage: "heart")
            }
        }
        #endif
        Divider()
        Menu {
            ForEach(GameStatus.allCases) { s in
                Button {
                    game.statusValue = s
                    try? context.save()
                } label: {
                    if game.statusValue == s {
                        Label(L10n.tr(s.labelKey, lang: language), systemImage: "checkmark")
                    } else {
                        Text(verbatim: L10n.tr(s.labelKey, lang: language))
                    }
                }
            }
        } label: {
            Label(L10n.tr("game.status", lang: language), systemImage: "tag")
        }
        Button {
            editingGame = game
        } label: {
            Label(L10n.tr("common.edit", lang: language), systemImage: "pencil")
        }
        Button {
            groupPickerGame = game
        } label: {
            Label(L10n.tr("game.groups", lang: language), systemImage: "folder")
        }
        // 合并入口放在游戏侧：导入之前，`GameMergeSheet` 只能从「外部记录」面板进，
        // 于是用户自己的两个条目（比如手建的「艾尔登法环」与同步建的「ELDEN RING」）
        // 反而没有合并的路 —— 而那两个正是最需要合并的。语义与记录侧一致：把这条并进选中的那个。
        Button {
            mergeSourceGame = game
        } label: {
            Label(L10n.tr("account.merge.title", lang: language), systemImage: "arrow.triangle.merge")
        }
        Divider()
        Button(role: .destructive) {
            pendingDeleteGame = game
        } label: {
            Label(L10n.tr("common.delete", lang: language), systemImage: "trash")
        }
    }

    var body: some View {
        Group {
            if libraryReplacing {
                // 整库替换锁定期占位：纯静态视图，不触碰任何 Game/Group。
                // 遮罩挡手（根容器），此分支挡渲染——两者缺一不可（2026-09-08）。
                VStack(spacing: 16) {
                    ProgressView()
                    LText("backup.importing")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                #if os(macOS)
                NavigationStack(path: $path) {
                    libraryContent
                }
                #else
                // iOS：复用外层（iOSLibraryTab 的）NavigationStack，这里不再建栈，避免双导航栏。
                libraryContent
                #endif
            }
        }
        .onChange(of: groupFilter?.persistentModelID) { _, _ in
            // 切换分组即重置组内平台过滤（切换页面重置过滤状态）。
            groupPlatformFilter = ""
            resetNavigationContext()
        }
        .onChange(of: platform) { _, _ in
            // 切换平台同样重置筛选上下文：退出已打开的详情页、清空搜索词，
            // 避免同一 case 分支内切换时视图身份不变导致状态残留。
            resetNavigationContext()
        }
        .onChange(of: statusFilter) { _, _ in
            resetNavigationContext()
        }
        // 整库替换（备份导入/自动备份恢复/AirDrop 导入）后：栈上的旧 Game 引用已 detached，
        // 详情页下一帧 body 访问即 SwiftData fatal——立即退出详情页并清搜索（同族轮播崩溃的导航版）。
        .onReceive(NotificationCenter.default.publisher(for: UserCustomization.libraryReplacedNotification)) { _ in
            resetNavigationContext()
        }
        // 旧键一次性迁移（**两平台都要跑**）：新键为空时，各平台读自己的历史键折算一次。
        //
        // 为什么写在 `DispatchQueue.main.async` 里：`@AppStorage` 在视图更新周期内被同步写回会
        // 触发一次嵌套的可见性失效。`AppToolbar.swift` 记过这个教训 —— 同步写 `@AppStorage`
        // 曾把 UI 挂死。放到下一个 runloop 就绕开了。
        //
        // 旧键迁移后**不删除**：删了也读不到值（新键已写），而留着可让回退旧版本时不丢偏好。
        .onAppear {
            guard !didMigrateLibraryViewMode else { return }
            didMigrateLibraryViewMode = true
            guard UserDefaults.standard.string(forKey: UserCustomization.libraryViewModeKey) == nil else { return }
            #if os(macOS)
            // 旧键没写过时 `bool(forKey:)` 给 false（= 列表），但旧代码的**默认值是网格**
            //（`@AppStorage("useGridView") … = true`）。所以「键不存在」要按网格算，
            // 否则老用户首启会被无端改成列表视图。
            let legacy = UserDefaults.standard.object(forKey: UserCustomization.legacyMacGridViewKey) == nil
                ? true
                : UserDefaults.standard.bool(forKey: UserCustomization.legacyMacGridViewKey)
            let migrated = legacy ? LibraryViewMode.grid : LibraryViewMode.list
            #else
            // iOS 旧键不存在时同样按网格算 —— 但这里还有一个额外来源：更早的版本把 iOS 的
            // 视图模式直接写在 macOS 的 `useGridView` 上（迁移注释里记着这段历史），所以旧键也没有时
            // 再看一眼那个 Bool。
            let legacyRaw = UserDefaults.standard.string(forKey: UserCustomization.iosLibraryViewModeKey)
            let migrated: LibraryViewMode
            if let legacyRaw, let mode = LibraryViewMode(rawValue: legacyRaw) {
                migrated = LibraryViewMode.available.contains(mode) ? mode : .grid
            } else if UserDefaults.standard.object(forKey: UserCustomization.legacyMacGridViewKey) != nil {
                migrated = UserDefaults.standard.bool(forKey: UserCustomization.legacyMacGridViewKey) ? .grid : .list
            } else {
                migrated = .grid
            }
            #endif
            let raw = migrated.rawValue
            DispatchQueue.main.async { viewModeRaw = raw }
        }
        // 以下 sheet/弹窗在整库替换锁定期一律不呈现（绑定的 Game 引用已 detached，
        // 呈现即崩；上锁瞬间步骤 9 会同步清掉这些 state，此处是双保险 2026-09-08）。
        .sheet(isPresented: Binding(
            get: { showingNewGame && !libraryReplacing },
            set: { showingNewGame = $0 }
        )) {
            #if os(macOS)
            GameEditView(game: nil)
            #else
            NavigationStack { GameEditView(game: nil) }
            #endif
        }
        .sheet(isPresented: Binding(
            get: { showingShare && !libraryReplacing },
            set: { showingShare = $0 }
        )) {
            SharePanelView()
        }
        .sheet(item: Binding(
            get: { libraryReplacing ? nil : editingGame },
            set: { editingGame = $0 }
        )) { game in
            // 纵深守卫：游戏可能已被别处删掉（合并 / 清空导入数据 / 整库替换），
            // 而这张 sheet 由上面的 item 绑定撑着、未必赶在那一帧之前关掉。
            if game.isLive {
                #if os(macOS)
                GameEditView(game: game)
                #else
                NavigationStack { GameEditView(game: game) }
                #endif
            } else {
                Color.clear
            }
        }
        .sheet(item: Binding(
            get: { libraryReplacing ? nil : groupPickerGame?.isLive == true ? groupPickerGame : nil },
            set: { groupPickerGame = $0 }
        )) { game in
            GroupPickerSheet(game: game)
        }
        .sheet(item: Binding(
            get: { libraryReplacing ? nil : mergeSourceGame?.isLive == true ? mergeSourceGame : nil },
            set: { mergeSourceGame = $0 }
        )) { game in
            // 只传 ID：这张 sheet 可能在「清空账号导入数据」删游戏的同一刻开着，
            // 传引用会让它拿旧对象再渲染一帧（见 GameMergeSheet 的说明）。
            GameMergeSheet(sourceID: game.persistentModelID)
        }
        .platformConfirmDialog(
            L10n.tr("common.confirmDelete", lang: language),
            isPresented: Binding(
                get: { pendingDeleteGame != nil && !libraryReplacing },
                set: { if !$0 { pendingDeleteGame = nil } }
            ),
            // 判据是 `isLive` 而非 `isDeleted`（见 `Game.isLive`）：确认框弹出后对象仍可能
            // 被别处删掉（合并会删 source），那时读 `displayName` 就是 SwiftData fatal。
            message: pendingDeleteGame.flatMap { game in
                game.isLive ? L10n.tr("delete.confirmGame", [game.displayName(for: language)], lang: language) : nil
            },
            cancelTitle: L10n.tr("common.cancel", lang: language),
            actions: [
                ConfirmAction(
                    title: L10n.tr("common.delete", lang: language),
                    isDestructive: true
                ) {
                    if let game = pendingDeleteGame, game.isLive {
                        // 先标记再删：名下的外部记录会被设为「别再导入」，否则下次同步
                        // 会把刚删掉的游戏原样建回来（见 `GameMerger.ignoreRecords`）。
                        GameMerger.ignoreRecords(linkedTo: game, in: context)
                        context.delete(game)
                        // 缓存 key = persistentModelID+字段，pk 重用会让旧图贴到新游戏（审计 2026-09-05）。
                        ImageDecodeCache.bump()
                    }
                    pendingDeleteGame = nil
                }
            ]
        )
    }

    /// 库内容（不含 NavigationStack；macOS 由本视图自己的栈包装，iOS 复用外层栈）。
    private var libraryContent: some View {
        Group {
            if let group = groupFilter {
                groupContent(group: group)
            } else if favoritesOnly {
                favoritesContent
            } else if liveGames.isEmpty {
                ContentUnavailableView {
                    Image(systemName: "gamecontroller")
                        .font(.system(size: 48))
                } description: {
                    LText("library.noGames")
                }
            } else if visibleGames.isEmpty {
                ContentUnavailableView {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                } description: {
                    LText("library.noResult")
                }
            } else {
                #if os(iOS)
                switch viewMode {
                // `.squareGrid` 只做在 macOS（`available` 不含它，`resolved` 也拦得住），
                // 并进网格臂只为让 switch 穷尽。
                case .grid, .squareGrid:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if showsHomeCarousel { carousel }
                            // iOS 起始页标题在轮播下方（2026-09-05 用户要求）；其余态走导航大标题。
                            if showsInlineHomeTitle { inlineHomeTitle }
                            gameGrid(visibleGames)
                        }
                        .padding()
                    }
                case .wideCard:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if showsHomeCarousel { carousel }
                            if showsInlineHomeTitle { inlineHomeTitle }
                            gameWideCards(visibleGames)
                        }
                        .padding()
                    }
                case .list:
                    List {
                        if showsHomeCarousel {
                            carousel
                                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                                .listRowSeparator(.hidden)
                            // 内联标题与网格/宽卡分支同位（轮播下方、列表上方）。
                            if showsInlineHomeTitle {
                                inlineHomeTitle
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16))
                                    .listRowSeparator(.hidden)
                            }
                        }
                        ForEach(visibleGames) { game in
                            gameRow(game)
                        }
                    }
                }
                #else
                // macOS：三种视图模式（网格 / 方形网格 / 列表）。两个网格态的脚手架逐字相同、
                // 只差卡片形状，所以各写一臂而不是塞条件进一臂 —— 与上面 iOS 那份同一写法。
                switch viewMode {
                case .grid:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if showsHomeCarousel { carousel }
                            gameGrid(visibleGames)
                        }
                        .padding()
                    }
                case .squareGrid:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if showsHomeCarousel { carousel }
                            gameSquareGrid(visibleGames)
                        }
                        .padding()
                    }
                case .wideCard:
                    // iOS 专属（`available` 不含它，`resolved` 也拦得住），给网格以保持穷尽。
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if showsHomeCarousel { carousel }
                            gameGrid(visibleGames)
                        }
                        .padding()
                    }
                case .list:
                    List {
                        if showsHomeCarousel {
                            carousel
                                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                                .listRowSeparator(.hidden)
                        }
                        ForEach(visibleGames) { game in
                            gameRow(game)
                        }
                    }
                }
                #endif
            }
        }
        #if os(macOS)
        .navigationDestination(for: Game.self) { game in
            GameDetailView(game: game)
        }
        #else
        .navigationDestination(item: $selectedGame) { game in
            GameDetailView(game: game)
        }
        #endif
        .searchable(text: $searchText, placement: .toolbar, prompt: L10n.tr("library.search", lang: language))
        #if os(macOS)
        .navigationTitle(hideToolbarGlass ? "" : navigationTitleText)
        #else
        // iOS 起始页（轮播页）标题内联到轮播下方（showsInlineHomeTitle），导航标题置空；
        // 空库 / 搜索无结果 / 其他筛选态仍走系统大标题。
        .navigationTitle(showsInlineHomeTitle ? "" : navigationTitleText)
        #endif
        // 全屏毛玻璃下推 + 「隐藏上方毛玻璃」开关由全局 appToolbar() 统一处理（库/详情/统计一致）。
        .appToolbar()
        .toolbar {
            #if os(macOS)
            if groupFilter != nil {
                ToolbarItem {
                    Menu {
                        Button {
                            groupPlatformFilter = ""
                        } label: {
                            if groupPlatformFilter.isEmpty {
                                Label(L10n.tr("library.allPlatforms", lang: language), systemImage: "checkmark")
                            } else {
                                Text(verbatim: L10n.tr("library.allPlatforms", lang: language))
                            }
                        }
                        ForEach(groupPlatforms, id: \.self) { p in
                            Button {
                                groupPlatformFilter = p
                            } label: {
                                HStack(spacing: 8) {
                                    PlatformIcon(platform: p, size: 16)
                                    Text(verbatim: Presets.display(p, category: .platform, language: language))
                                    Spacer()
                                    if groupPlatformFilter == p {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                    }
                    .help(L10n.tr("library.filterPlatform", lang: language))
                }
            }
            #endif
            #if os(macOS)
            ToolbarItem {
                // 排序菜单:原生 Menu 样式——系统会给它独立的小玻璃胶囊(与右侧三连胶囊
                // 分组分开),并自带系统悬停/按压行为;自定义样式会被并进同一条玻璃。
                Menu {
                    sortMenuItems
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .help(L10n.tr("library.sort", lang: language))
            }
            ToolbarItem {
                // 视图模式（网格 / 方形网格 / 列表）：三态一个 toggle 表达不了，改成同款原生 Menu
                //（与上面排序菜单一致——系统会给独立菜单单独一条玻璃胶囊，不会并进右侧三连）。
                // **不用 `Picker`**：`Picker` 在 macOS 工具栏会渲染成下拉，与这里"分段按钮"的观感不一致。
                // 图标随当前模式变化，勾选态随 `viewMode`；候选取自 `available`（本平台可用集合）。
                Menu {
                    ForEach(LibraryViewMode.available) { mode in
                        Button {
                            viewModeRaw = mode.rawValue
                        } label: {
                            // 与排序菜单同口径：勾选态用 checkmark 陪衬而不是系统 Toggle
                            //（Toggle 勾选在 macOS 工具栏菜单里不落屏，见 `cardMenu` 同款注释）。
                            if mode == viewMode {
                                Label(L10n.tr(mode.labelKey, lang: language), systemImage: "checkmark")
                            } else {
                                Text(verbatim: L10n.tr(mode.labelKey, lang: language))
                            }
                        }
                    }
                } label: {
                    Image(systemName: viewMode.systemImage)
                }
                .help(L10n.tr("library.viewMode", lang: language))
            }
            ToolbarItem(placement: .primaryAction) {
                // 两按钮装进一整条玻璃长胶囊,右对齐(与搜索框相邻)。
                HStack(spacing: 0) {
                    Button {
                        showingShare = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: ToolbarMetrics.iconPt))
                    }
                    .toolbarSegmentStyle()
                    .help(L10n.tr("library.share", lang: language))

                    Button {
                        showingNewGame = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: ToolbarMetrics.iconPt))
                    }
                    .toolbarSegmentStyle()
                    .help(L10n.tr("library.addGame", lang: language))
                }
            }
            #else
            // iOS：仅保留「新建游戏」+ 一个「更多」菜单（排序/网格/分享收进去），
            // 避免工具栏按钮过多触发系统折叠「…」在 iOS 26 下点击无响应的问题。
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingNewGame = true
                } label: {
                    Image(systemName: "plus")
                }
                .help(L10n.tr("library.addGame", lang: language))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    LibrarySortMenuItems(sortRaw: $sortRaw)
                    Divider()
                    // 视图三选一（网格 / 单列横向卡 / 列表），勾选态随当前模式。
                    // 候选取自 `LibraryViewMode.available`（本平台可用集合：这里不含 `.squareGrid`）。
                    // 此前这里还套了一层 `#if os(iOS) … #else`——本分支整体已在 `#if os(macOS)` 的
                    // `#else` 里，那个内层判断恒真，`#else` 的旧视图开关永远不可达，已删。
                    Picker(selection: Binding(
                        get: { viewMode },
                        set: { viewModeRaw = $0.rawValue }
                    )) {
                        ForEach(LibraryViewMode.available) { m in
                            Label(L10n.tr(m.labelKey, lang: language), systemImage: m.systemImage)
                                .tag(m)
                        }
                    } label: {
                        Label(L10n.tr("library.viewMode", lang: language), systemImage: "rectangle.grid.1x2")
                    }
                    Button {
                        showingShare = true
                    } label: {
                        Label(L10n.tr("library.share", lang: language), systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            #endif
        }
    }
}
