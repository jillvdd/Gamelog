import SwiftUI
import SwiftData

#if os(macOS)
import AppKit
#endif

/// 库排序选项。
enum LibrarySort: String, CaseIterable, Identifiable {
    case name
    case releaseDate
    case completionDate
    case scoreAscending
    case scoreDescending
    case recentEdit
    case valueDescending

    var id: String { rawValue }
}

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

    @State private var searchText = ""
    @AppStorage("useGridView") private var useGridView = true
    /// 分组视图内局部平台过滤（不持久化，切换分组即重置）。
    @State private var groupPlatformFilter = ""
    @AppStorage("librarySort") private var sortRaw = LibrarySort.completionDate.rawValue
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

    /// 分组模式下工具栏平台菜单的候选：本组内出现的平台（预设世代倒序 + 自定义排最后）。
    private var groupPlatforms: [String] {
        guard let group = groupFilter else { return [] }
        return Presets.ordered(group.games.flatMap { $0.completions.map(\.platform) })
    }

    private var visibleGames: [Game] {
        var result: [Game]
        if let groupFilter {
            // 分组视图直接以双向关系为准：关系变化（右键移出/加入）立即反映
            result = groupFilter.games
            #if os(macOS)
            if !groupPlatformFilter.isEmpty {
                result = result.filter { game in
                    game.platformList.contains(groupPlatformFilter)
                }
            }
            #endif
        } else {
            result = games
        }
        // 平台过滤在分组/非分组两种模式下都生效（iOS 由分组/平台两个菜单驱动；macOS 分组模式用 groupPlatformFilter）。
        if let platform {
            result = result.filter { game in
                game.platformList.contains(platform)
            }
        }
        if let statusFilter {
            result = result.filter { $0.statusValue == statusFilter }
        }
        if !searchText.isEmpty {
            result = result.filter { $0.matches(search: searchText) }
        }
        switch sortOption {
        case .name:
            result.sort { $0.displayName(for: language).localizedCaseInsensitiveCompare($1.displayName(for: language)) == .orderedAscending }
        case .releaseDate:
            result.sort { ($0.releaseDate ?? .distantPast) > ($1.releaseDate ?? .distantPast) }
        case .completionDate:
            result.sort { ($0.latestCompletionDate ?? .distantPast) > ($1.latestCompletionDate ?? .distantPast) }
        case .scoreAscending:
            // 未评分（nil）按无穷大处理，排在已评分之后。
            result.sort { ($0.rawLibraryScore(platform: nil) ?? .greatestFiniteMagnitude) < ($1.rawLibraryScore(platform: nil) ?? .greatestFiniteMagnitude) }
        case .scoreDescending:
            // 未评分（nil）按 -1 处理，排在已评分之后。
            result.sort { ($0.rawLibraryScore(platform: nil) ?? -1) > ($1.rawLibraryScore(platform: nil) ?? -1) }
        case .recentEdit:
            // 最近编辑：无编辑记录退回创建时间；越新越靠前。
            result.sort { $0.lastEditedAt > $1.lastEditedAt }
        case .valueDescending:
            // 价值最高（总估值，按当前语言）；无估值（nil）排最后。
            result.sort { ($0.totalEstimate(for: language) ?? -1) > ($1.totalEstimate(for: language) ?? -1) }
        }
        return result
    }

    private var navigationTitleText: String {
        if let statusFilter {
            return L10n.tr(statusFilter.labelKey, lang: language)
        }
        if let platform {
            return Presets.display(platform, category: .platform, language: language)
        }
        return groupFilter?.name ?? L10n.tr("library.all", lang: language)
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
                } else if useGridView {
                    gameGrid(visibleGames)
                } else {
                    gameList(visibleGames)
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

    /// 网格：自适应列，卡片可点击进详情、右键菜单。
    @ViewBuilder
    private func gameGrid(_ games: [Game]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)], spacing: 16) {
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

    @ViewBuilder
    private func gameCard(_ game: Game) -> some View {
        GameCardView(game: game)
            .contentShape(Rectangle())
            .onTapGesture {
                #if os(macOS)
                path.append(game)
                #else
                selectedGame = game
                #endif
            }
            .contextMenu { cardMenu(for: game) }
    }

    @ViewBuilder
    private func gameRow(_ game: Game) -> some View {
        GameRowView(game: game)
            .contentShape(Rectangle())
            .onTapGesture {
                #if os(macOS)
                path.append(game)
                #else
                selectedGame = game
                #endif
            }
            .contextMenu { cardMenu(for: game) }
    }

    @ViewBuilder
    private func cardMenu(for game: Game) -> some View {
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
                    title: L10n.tr("common.confirmDelete", lang: language),
                    isDestructive: true
                ) {
                    if let game = pendingDeleteGame {
                        context.delete(game)
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
            } else if useGridView {
                ScrollView {
                    gameGrid(visibleGames)
                        .padding()
                }
            } else {
                List {
                    ForEach(visibleGames) { game in
                        gameRow(game)
                    }
                }
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
        .navigationTitle(navigationTitleText)
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
                Menu {
                    Button {
                        sortRaw = LibrarySort.name.rawValue
                    } label: {
                        if sortOption == .name {
                            Label(L10n.tr("library.sortByName", lang: language), systemImage: "checkmark")
                        } else {
                            Text(verbatim: L10n.tr("library.sortByName", lang: language))
                        }
                    }
                    Button {
                        sortRaw = LibrarySort.releaseDate.rawValue
                    } label: {
                        if sortOption == .releaseDate {
                            Label(L10n.tr("library.sortByRelease", lang: language), systemImage: "checkmark")
                        } else {
                            Text(verbatim: L10n.tr("library.sortByRelease", lang: language))
                        }
                    }
                    Button {
                        sortRaw = LibrarySort.completionDate.rawValue
                    } label: {
                        if sortOption == .completionDate {
                            Label(L10n.tr("library.sortByCompletion", lang: language), systemImage: "checkmark")
                        } else {
                            Text(verbatim: L10n.tr("library.sortByCompletion", lang: language))
                        }
                    }
                    Button {
                        sortRaw = LibrarySort.scoreAscending.rawValue
                    } label: {
                        if sortOption == .scoreAscending {
                            Label(L10n.tr("library.sortByScoreAsc", lang: language), systemImage: "checkmark")
                        } else {
                            Text(verbatim: L10n.tr("library.sortByScoreAsc", lang: language))
                        }
                    }
                    Button {
                        sortRaw = LibrarySort.scoreDescending.rawValue
                    } label: {
                        if sortOption == .scoreDescending {
                            Label(L10n.tr("library.sortByScoreDesc", lang: language), systemImage: "checkmark")
                        } else {
                            Text(verbatim: L10n.tr("library.sortByScoreDesc", lang: language))
                        }
                    }
                    Button {
                        sortRaw = LibrarySort.recentEdit.rawValue
                    } label: {
                        if sortOption == .recentEdit {
                            Label(L10n.tr("library.sortByRecentEdit", lang: language), systemImage: "checkmark")
                        } else {
                            Text(verbatim: L10n.tr("library.sortByRecentEdit", lang: language))
                        }
                    }
                    Button {
                        sortRaw = LibrarySort.valueDescending.rawValue
                    } label: {
                        if sortOption == .valueDescending {
                            Label(L10n.tr("library.sortByValueDesc", lang: language), systemImage: "checkmark")
                        } else {
                            Text(verbatim: L10n.tr("library.sortByValueDesc", lang: language))
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .help(L10n.tr("library.sort", lang: language))
            }
            ToolbarItem {
                Button {
                    useGridView.toggle()
                } label: {
                    Image(systemName: useGridView ? "list.bullet" : "square.grid.2x2")
                }
                .help(useGridView ? L10n.tr("library.listView", lang: language) : L10n.tr("library.gridView", lang: language))
            }
            ToolbarItem {
                Button {
                    showingShare = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .help(L10n.tr("library.share", lang: language))
            }
            ToolbarItem {
                Button {
                    showingNewGame = true
                } label: {
                    Image(systemName: "plus")
                }
                .help(L10n.tr("library.addGame", lang: language))
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
                    Button {
                        sortRaw = LibrarySort.name.rawValue
                    } label: {
                        if sortOption == .name {
                            Label(L10n.tr("library.sortByName", lang: language), systemImage: "checkmark")
                        } else {
                            Text(verbatim: L10n.tr("library.sortByName", lang: language))
                        }
                    }
                    Button {
                        sortRaw = LibrarySort.releaseDate.rawValue
                    } label: {
                        if sortOption == .releaseDate {
                            Label(L10n.tr("library.sortByRelease", lang: language), systemImage: "checkmark")
                        } else {
                            Text(verbatim: L10n.tr("library.sortByRelease", lang: language))
                        }
                    }
                    Button {
                        sortRaw = LibrarySort.completionDate.rawValue
                    } label: {
                        if sortOption == .completionDate {
                            Label(L10n.tr("library.sortByCompletion", lang: language), systemImage: "checkmark")
                        } else {
                            Text(verbatim: L10n.tr("library.sortByCompletion", lang: language))
                        }
                    }
                    Button {
                        sortRaw = LibrarySort.scoreAscending.rawValue
                    } label: {
                        if sortOption == .scoreAscending {
                            Label(L10n.tr("library.sortByScoreAsc", lang: language), systemImage: "checkmark")
                        } else {
                            Text(verbatim: L10n.tr("library.sortByScoreAsc", lang: language))
                        }
                    }
                    Button {
                        sortRaw = LibrarySort.scoreDescending.rawValue
                    } label: {
                        if sortOption == .scoreDescending {
                            Label(L10n.tr("library.sortByScoreDesc", lang: language), systemImage: "checkmark")
                        } else {
                            Text(verbatim: L10n.tr("library.sortByScoreDesc", lang: language))
                        }
                    }
                    Divider()
                    Button {
                        useGridView.toggle()
                    } label: {
                        Label(
                            L10n.tr(useGridView ? "library.listView" : "library.gridView", lang: language),
                            systemImage: useGridView ? "list.bullet" : "square.grid.2x2"
                        )
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
