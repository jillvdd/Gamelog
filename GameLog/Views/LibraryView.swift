import SwiftUI
import SwiftData

/// 库排序选项。
enum LibrarySort: String, CaseIterable, Identifiable {
    case name
    case releaseDate
    case completionDate

    var id: String { rawValue }
}

/// 主界面：网格/列表切换、搜索、平台筛选、排序、分享、新建入口。
struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    @Query(sort: \Game.createdAt) private var games: [Game]
    let groupFilter: GameGroup?

    @State private var searchText = ""
    @AppStorage("useGridView") private var useGridView = true
    @AppStorage("libraryPlatformFilter") private var platformFilter = ""
    @AppStorage("librarySort") private var sortRaw = LibrarySort.completionDate.rawValue

    @State private var path = NavigationPath()
    @State private var pendingDeleteGame: Game?
    @State private var editingGame: Game?
    @State private var groupPickerGame: Game?
    @State private var showingNewGame = false
    @State private var showingShare = false

    private var sortOption: LibrarySort { LibrarySort(rawValue: sortRaw) ?? .completionDate }

    private var allPlatforms: [String] {
        Array(Set(games.flatMap { $0.completions.map(\.platform) })).sorted()
    }

    private var visibleGames: [Game] {
        var result: [Game]
        if let groupFilter {
            // 分组视图直接以双向关系为准：关系变化（右键移出/加入）立即反映
            result = groupFilter.games
        } else {
            result = games
        }
        if !platformFilter.isEmpty {
            result = result.filter { game in
                game.completions.contains { $0.platform == platformFilter }
            }
        }
        if !searchText.isEmpty {
            result = result.filter { $0.matches(search: searchText) }
        }
        switch sortOption {
        case .name:
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .releaseDate:
            result.sort { ($0.releaseDate ?? .distantPast) > ($1.releaseDate ?? .distantPast) }
        case .completionDate:
            result.sort { ($0.latestCompletionDate ?? .distantPast) > ($1.latestCompletionDate ?? .distantPast) }
        }
        return result
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if games.isEmpty && groupFilter == nil {
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
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)], spacing: 16) {
                            ForEach(visibleGames) { game in
                                GameCardView(game: game)
                                    .contentShape(Rectangle())
                                    .onTapGesture { path.append(game) }
                                    .contextMenu {
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
                            }
                        }
                        .padding()
                    }
                } else {
                    List {
                        ForEach(visibleGames) { game in
                            GameRowView(game: game)
                                .contentShape(Rectangle())
                                .onTapGesture { path.append(game) }
                                .contextMenu {
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
                        }
                    }
                }
            }
            .navigationDestination(for: Game.self) { game in
                GameDetailView(game: game)
            }
            .searchable(text: $searchText, placement: .toolbar, prompt: L10n.tr("library.search", lang: language))
            .navigationTitle(groupFilter?.name ?? L10n.tr("library.all", lang: language))
            .toolbar {
                ToolbarItem {
                    Menu {
                        Button {
                            platformFilter = ""
                        } label: {
                            if platformFilter.isEmpty {
                                Label(L10n.tr("library.allPlatforms", lang: language), systemImage: "checkmark")
                            } else {
                                Text(verbatim: L10n.tr("library.allPlatforms", lang: language))
                            }
                        }
                        ForEach(allPlatforms, id: \.self) { p in
                            Button {
                                platformFilter = p
                            } label: {
                                if platformFilter == p {
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
                    Text(verbatim: L10n.tr("delete.confirmGame", [game.name], lang: language))
                }
            }
        }
    }
}
