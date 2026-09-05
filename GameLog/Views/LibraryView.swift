import SwiftUI
import SwiftData

#if os(macOS)
import AppKit
#endif

#if os(iOS)
/// iOS 库视图三态：网格 / 单列横向卡 / 列表（macOS 不受影响，仍用 useGridView Bool）。
enum IOSLibraryViewMode: String, CaseIterable, Identifiable {
    case grid
    case wideCard
    case list

    var id: String { rawValue }

    var labelKey: String {
        switch self {
        case .grid: "library.gridView"
        case .wideCard: "library.wideCardView"
        case .list: "library.listView"
        }
    }
}
#endif

/// 主界面：网格/列表切换、搜索、平台筛选、排序、分享、新建入口。
struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    @Query(sort: \Game.createdAt) private var games: [Game]
    let groupFilter: GameGroup?
    /// 非分组视图（全部游戏 / 侧边栏某平台）的平台过滤，由侧边栏选择驱动，切换即重置。
    var platform: String? = nil
    /// 状态过滤（想玩/在玩/搁置/弃坑/已通关），由侧边栏/iOS 筛选菜单选择驱动，与 groupFilter/platform 互斥。
    var statusFilter: GameStatus? = nil
    /// 虚拟分组「我的最爱」：仅显示 isFavorite 游戏（侧边栏/iOS 筛选菜单进入，与分组/平台/状态互斥）。
    var favoritesOnly: Bool = false

    @State private var searchText = ""
    @AppStorage("useGridView") private var useGridView = true
    #if os(iOS)
    // iOS 库视图三态（网格/单列横向卡/列表），与 macOS 的 Bool 键互不干扰。
    // 旧值迁移：首次读取时无新键 → 按 useGridView 折算（onAppear 里 migratelibraryViewModeIfNeeded）。
    @AppStorage(UserCustomization.iosLibraryViewModeKey) private var iosViewModeRaw = ""
    @State private var didMigrateLibraryViewMode = false
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
    @State private var showingNewGame = false
    @State private var showingShare = false

    private var sortOption: LibrarySort { LibrarySort(rawValue: sortRaw) ?? .completionDate }

    #if os(iOS)
    /// 当前 iOS 视图模式（迁移未跑或值为空时兜底网格——onAppear 迁移会立即写上真实值）。
    private var iosViewMode: IOSLibraryViewMode {
        IOSLibraryViewMode(rawValue: iosViewModeRaw) ?? .grid
    }
    /// iOS 渲染分支判定：true = 网格；false = 横向卡或列表（由 iOS 渲染分支细化）。
    #endif

    /// 分组模式下工具栏平台菜单的候选：本组内出现的平台（预设世代倒序 + 自定义排最后）。
    private var groupPlatforms: [String] {
        guard let group = groupFilter else { return [] }
        return Presets.ordered(group.games.flatMap { $0.completions.map(\.platform) })
    }

    private var visibleGames: [Game] {
        // 平台过滤在分组/非分组两种模式下都生效（iOS 由分组/平台两个菜单驱动；macOS 分组模式叠加 groupPlatformFilter）。
        var result = LibraryQuery.filter(
            games: games, group: groupFilter,
            platform: platform, status: statusFilter, search: searchText
        )
        if favoritesOnly {
            result = result.filter(\.isFavorite)
        }
        #if os(macOS)
        if let groupFilter, !groupPlatformFilter.isEmpty {
            result = result.filter { $0.platformList.contains(groupPlatformFilter) }
        }
        #endif
        return LibraryQuery.sorted(result, by: sortOption, language: language)
    }

    /// 虚拟分组「我的最爱」的全体成员（统计区块依据——不受搜索/排序影响）。
    private var allFavorites: [Game] {
        games.filter(\.isFavorite)
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
        return groupFilter?.name ?? L10n.tr("library.all", lang: language)
    }

    /// iOS 起始页内联标题开关（2026-09-05 用户要求）：「全部游戏」+ 轮播页的标题不再占
    /// 导航大标题，改渲染在五页轮播下方、游戏列表上方。仅在实际显示轮播内容页时生效——
    /// 空库 / 搜索无结果（轮播不显示）与其他筛选态（最爱/状态/平台/分组）仍走系统大标题。
    private var showsInlineHomeTitle: Bool {
        showsHomeCarousel && !games.isEmpty && !visibleGames.isEmpty
    }

    /// 轮播下方的内联标题：字号对齐系统大标题，与其他页标题视觉一致。
    private var inlineHomeTitle: some View {
        Text(verbatim: L10n.tr("library.all", lang: language))
            .font(.largeTitle.weight(.bold))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 切换分组/平台筛选时重置导航上下文：退出已打开的详情页、清空搜索词。
    /// 否则同 case 分支内切换（如平台 A → 平台 B）视图身份不变，path/selectedGame/searchText 会残留。
    private func resetNavigationContext() {
        #if os(macOS)
        path = NavigationPath()
        #else
        selectedGame = nil
        #endif
        searchText = ""
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
                    #if os(iOS)
                    switch iosViewMode {
                    case .grid: gameGrid(visibleGames)
                    case .wideCard: gameWideCards(visibleGames)
                    case .list: gameList(visibleGames)
                    }
                    #else
                    if useGridView {
                        gameGrid(visibleGames)
                    } else {
                        gameList(visibleGames)
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
    private var carousel: some View {
        HomeCarousel(games: games, onSelect: openDetail)
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
                    #if os(iOS)
                    switch iosViewMode {
                    case .grid: gameGrid(visibleGames)
                    case .wideCard: gameWideCards(visibleGames)
                    case .list: gameList(visibleGames)
                    }
                    #else
                    if useGridView {
                        gameGrid(visibleGames)
                    } else {
                        gameList(visibleGames)
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

    @ViewBuilder
    private func gameCard(_ game: Game) -> some View {
        // Button + 按压反馈样式（原 onTapGesture 点按无任何视觉响应，不符 iOS 触控预期）。
        Button {
            #if os(macOS)
            path.append(game)
            #else
            selectedGame = game
            #endif
        } label: {
            GameCardView(game: game)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressFeedbackButtonStyle())
        .contextMenu { cardMenu(for: game) }
    }

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
        Divider()
        Button(role: .destructive) {
            pendingDeleteGame = game
        } label: {
            Label(L10n.tr("common.delete", lang: language), systemImage: "trash")
        }
    }

    var body: some View {
        Group {
            #if os(macOS)
            NavigationStack(path: $path) {
                libraryContent
            }
            #else
            // iOS：复用外层（iOSLibraryTab 的）NavigationStack，这里不再建栈，避免双导航栏。
            libraryContent
            #endif
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
        #if os(iOS)
        .onAppear {
            // 旧键一次性迁移：无新键 → 按 useGridView（网格 true / 列表 false）折算三态值。
            // 写入后旧键留着不动（无害；macOS 还在用）。
            if !didMigrateLibraryViewMode {
                didMigrateLibraryViewMode = true
                if UserDefaults.standard.string(forKey: UserCustomization.iosLibraryViewModeKey) == nil {
                    iosViewModeRaw = useGridView
                        ? IOSLibraryViewMode.grid.rawValue
                        : IOSLibraryViewMode.list.rawValue
                }
            }
        }
        #endif
        .sheet(isPresented: $showingNewGame) {
            #if os(macOS)
            GameEditView(game: nil)
            #else
            NavigationStack { GameEditView(game: nil) }
            #endif
        }
        .sheet(isPresented: $showingShare) {
            SharePanelView()
        }
        .sheet(item: $editingGame) { game in
            #if os(macOS)
            GameEditView(game: game)
            #else
            NavigationStack { GameEditView(game: game) }
            #endif
        }
        .sheet(item: $groupPickerGame) { game in
            GroupPickerSheet(game: game)
        }
        .platformConfirmDialog(
            L10n.tr("common.confirmDelete", lang: language),
            isPresented: Binding(
                get: { pendingDeleteGame != nil },
                set: { if !$0 { pendingDeleteGame = nil } }
            ),
            message: pendingDeleteGame.map {
                L10n.tr("delete.confirmGame", [$0.displayName(for: language)], lang: language)
            },
            cancelTitle: L10n.tr("common.cancel", lang: language),
            actions: [
                ConfirmAction(
                    title: L10n.tr("common.delete", lang: language),
                    isDestructive: true
                ) {
                    if let game = pendingDeleteGame {
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
            } else if games.isEmpty {
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
                switch iosViewMode {
                case .grid:
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
                if useGridView {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if showsHomeCarousel { carousel }
                            gameGrid(visibleGames)
                        }
                        .padding()
                    }
                } else {
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
            ToolbarItem(placement: .primaryAction) {
                // 三按钮装进一整条玻璃长胶囊,右对齐(与搜索框相邻)。
                HStack(spacing: 0) {
                    Button {
                        useGridView.toggle()
                    } label: {
                        // 自定义按钮样式会丢掉系统工具栏的自动图标放大,显式给到原生尺寸(15pt)。
                        Image(systemName: useGridView ? "list.bullet" : "square.grid.2x2")
                            .font(.system(size: 15))
                    }
                    .toolbarSegmentStyle()
                    .help(useGridView ? L10n.tr("library.listView", lang: language) : L10n.tr("library.gridView", lang: language))

                    Button {
                        showingShare = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15))
                    }
                    .toolbarSegmentStyle()
                    .help(L10n.tr("library.share", lang: language))

                    Button {
                        showingNewGame = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15))
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
                    #if os(iOS)
                    // 视图三选一（网格 / 单列横向卡 / 列表），勾选态随当前模式。
                    Picker(selection: Binding(
                        get: { iosViewMode },
                        set: { iosViewModeRaw = $0.rawValue }
                    )) {
                        ForEach(IOSLibraryViewMode.allCases) { m in
                            Label(
                                L10n.tr(m.labelKey, lang: language),
                                systemImage: m == .grid ? "square.grid.2x2" : (m == .wideCard ? "rectangle.ratio.16.to.9" : "list.bullet")
                            )
                            .tag(m)
                        }
                    } label: {
                        Label(L10n.tr("library.viewMode", lang: language), systemImage: "rectangle.grid.1x2")
                    }
                    #else
                    Button {
                        useGridView.toggle()
                    } label: {
                        Label(
                            L10n.tr(useGridView ? "library.listView" : "library.gridView", lang: language),
                            systemImage: useGridView ? "list.bullet" : "square.grid.2x2"
                        )
                    }
                    #endif
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
