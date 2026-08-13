import SwiftUI
import SwiftData
import AppKit

/// 库排序选项。
enum LibrarySort: String, CaseIterable, Identifiable {
    case name
    case releaseDate
    case completionDate

    var id: String { rawValue }
}

/// 工具栏毛玻璃控制（设置「隐藏分组毛玻璃」开关）。
/// macOS 15+ 用 `.toolbarBackgroundVisibility`（能真正隐藏窗口工具栏玻璃）；
/// macOS 14 无对应 API，开启时尽力用透明背景（实际可能仍显示系统玻璃，但 app 照常可用）。
private struct ToolbarGlassModifier: ViewModifier {
    let hidden: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbarBackgroundVisibility(hidden ? .hidden : .automatic, for: .windowToolbar)
        } else if hidden {
            content.toolbarBackground(Color.clear, for: .windowToolbar)
        } else {
            content
        }
    }
}

/// 主界面：网格/列表切换、搜索、平台筛选、排序、分享、新建入口。
struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    @Query(sort: \Game.createdAt) private var games: [Game]
    let groupFilter: GameGroup?
    /// 非分组视图（全部游戏 / 侧边栏某平台）的平台过滤，由侧边栏选择驱动，切换即重置。
    var platform: String? = nil

    @State private var searchText = ""
    @AppStorage("useGridView") private var useGridView = true
    /// 分组视图内局部平台过滤（不持久化，切换分组即重置）。
    @State private var groupPlatformFilter = ""
    @AppStorage("librarySort") private var sortRaw = LibrarySort.completionDate.rawValue
    /// 隐藏工具栏毛玻璃（设置「个性化」开关）：开启 = 无标题 + 完全无毛玻璃（方案 B）。
    @AppStorage(UserCustomization.hideToolbarGlassKey) private var hideToolbarGlass = false
    /// 是否全屏：窗口模式保留毛玻璃+标题；全屏下玻璃比工具栏布局多延伸一行，需把内容往下推。
    @State private var isFullScreen = false

    @State private var path = NavigationPath()
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
            if !groupPlatformFilter.isEmpty {
                result = result.filter { game in
                    game.completions.contains { $0.platform == groupPlatformFilter }
                }
            }
        } else {
            result = games
            if let platform {
                result = result.filter { game in
                    game.completions.contains { $0.platform == platform }
                }
            }
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
        }
        return result
    }

    private var navigationTitleText: String {
        if let platform {
            return Presets.display(platform, category: .platform, language: language)
        }
        return groupFilter?.name ?? L10n.tr("library.all", lang: language)
    }

    /// 当前窗口是否全屏（启动时用于初始化状态）。
    private var windowIsFullScreen: Bool {
        let win = NSApp.windows.first(where: { $0.isVisible }) ?? NSApp.mainWindow
        return win?.styleMask.contains(.fullScreen) ?? false
    }

    /// 异步更新全屏状态：推迟到下一轮 runloop，避免在视图更新期间同步改 @State（曾导致 UI 挂死）。
    private func setFullScreen(_ value: Bool) {
        DispatchQueue.main.async {
            guard isFullScreen != value else { return }
            isFullScreen = value
        }
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
            .onTapGesture { path.append(game) }
            .contextMenu { cardMenu(for: game) }
    }

    @ViewBuilder
    private func gameRow(_ game: Game) -> some View {
        GameRowView(game: game)
            .contentShape(Rectangle())
            .onTapGesture { path.append(game) }
            .contextMenu { cardMenu(for: game) }
    }

    @ViewBuilder
    private func cardMenu(for game: Game) -> some View {
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
        NavigationStack(path: $path) {
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
            .onAppear {
                setFullScreen(windowIsFullScreen)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)) { _ in
                setFullScreen(true)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willExitFullScreenNotification)) { _ in
                setFullScreen(false)
            }
            .navigationDestination(for: Game.self) { game in
                GameDetailView(game: game)
            }
            .searchable(text: $searchText, placement: .toolbar, prompt: L10n.tr("library.search", lang: language))
            .navigationTitle(hideToolbarGlass ? "" : navigationTitleText)
            // 隐藏毛玻璃开关开启（方案 B）：无标题 + 无毛玻璃，全屏也无需下推内容。
            // 关闭（默认）：保留玻璃+标题；全屏下玻璃比工具栏布局多延伸一行（系统行为，无法压缩），
            // 把内容顶部往下推一行避开遮挡。
            .modifier(ToolbarGlassModifier(hidden: hideToolbarGlass))
            .safeAreaPadding(.top, (!hideToolbarGlass && isFullScreen) ? 24 : 0)
            .toolbar {
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
                                    if groupPlatformFilter == p {
                                        Label(Presets.display(p, category: .platform, language: language), systemImage: "checkmark")
                                    } else {
                                        Text(verbatim: Presets.display(p, category: .platform, language: language))
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease")
                        }
                        .help(L10n.tr("library.filterPlatform", lang: language))
                    }
                }

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
            }
            .sheet(isPresented: $showingNewGame) {
                GameEditView(game: nil)
            }
            .sheet(isPresented: $showingShare) {
                SharePanelView()
            }
            .sheet(item: $editingGame) { game in
                GameEditView(game: game)
            }
            .sheet(item: $groupPickerGame) { game in
                GroupPickerSheet(game: game)
            }
            .confirmationDialog(
                L10n.tr("common.confirmDelete", lang: language),
                isPresented: Binding(
                    get: { pendingDeleteGame != nil },
                    set: { if !$0 { pendingDeleteGame = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(L10n.tr("common.confirmDelete", lang: language), role: .destructive) {
                    if let game = pendingDeleteGame {
                        context.delete(game)
                    }
                    pendingDeleteGame = nil
                }
                Button(L10n.tr("common.cancel", lang: language), role: .cancel) {
                    pendingDeleteGame = nil
                }
            } message: {
                if let game = pendingDeleteGame {
                    Text(verbatim: L10n.tr("delete.confirmGame", [game.displayName(for: language)], lang: language))
                }
            }
            .onChange(of: groupFilter?.persistentModelID) { _, _ in
                // 切换分组即重置组内平台过滤（切换页面重置过滤状态）。
                groupPlatformFilter = ""
            }
        }
    }
}
