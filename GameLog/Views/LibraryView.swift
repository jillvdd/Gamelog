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

    @State private var showingNewGame = false
    @State private var showingShare = false

    private var sortOption: LibrarySort { LibrarySort(rawValue: sortRaw) ?? .completionDate }

    private var allPlatforms: [String] {
        Array(Set(games.flatMap { $0.completions.map(\.platform) })).sorted()
    }

    private var visibleGames: [Game] {
        var result = games
        if let groupFilter {
            result = result.filter { game in
                game.groups.contains(where: { $0.id == groupFilter.id })
            }
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
                            NavigationLink(value: game) {
                                GameCardView(game: game)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            } else {
                List {
                    ForEach(visibleGames) { game in
                        NavigationLink(value: game) {
                            GameRowView(game: game)
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
            ToolbarItemGroup {
                Picker(selection: $platformFilter) {
                    Text(verbatim: L10n.tr("library.allPlatforms", lang: language)).tag("")
                    ForEach(allPlatforms, id: \.self) { p in
                        Text(verbatim: Presets.display(p, category: .platform, language: language)).tag(p)
                    }
                } label: {
                    Label(L10n.tr("library.filterPlatform", lang: language), systemImage: "line.3.horizontal.decrease")
                }
                .pickerStyle(.menu)
                .fixedSize()

                Picker(selection: $sortRaw) {
                    Text(verbatim: L10n.tr("library.sortByName", lang: language)).tag(LibrarySort.name.rawValue)
                    Text(verbatim: L10n.tr("library.sortByRelease", lang: language)).tag(LibrarySort.releaseDate.rawValue)
                    Text(verbatim: L10n.tr("library.sortByCompletion", lang: language)).tag(LibrarySort.completionDate.rawValue)
                } label: {
                    Label(L10n.tr("library.sortByCompletion", lang: language), systemImage: "arrow.up.arrow.down")
                }
                .pickerStyle(.menu)

                Button {
                    useGridView.toggle()
                } label: {
                    Label(
                        useGridView ? L10n.tr("library.listView", lang: language) : L10n.tr("library.gridView", lang: language),
                        systemImage: useGridView ? "list.bullet" : "square.grid.2x2"
                    )
                }
                .help(useGridView ? L10n.tr("library.listView", lang: language) : L10n.tr("library.gridView", lang: language))

                Button {
                    showingShare = true
                } label: {
                    Label(L10n.tr("library.share", lang: language), systemImage: "square.and.arrow.up")
                }

                Button {
                    showingNewGame = true
                } label: {
                    Label(L10n.tr("library.addGame", lang: language), systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewGame) {
            GameEditView(game: nil)
        }
        .sheet(isPresented: $showingShare) {
            SharePanelView()
        }
    }
}
