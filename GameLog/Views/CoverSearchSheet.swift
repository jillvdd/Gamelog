import SwiftUI

/// 封面搜索面板：SteamGridDB 按名字搜游戏 → 选游戏 → 选一张封面。
struct CoverSearchSheet: View {
    @Binding var coverData: Data?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguageCode) private var language
    @AppStorage("steamGridDBKey") private var apiKey = ""

    @State private var searchText = ""
    @State private var results: [SteamGridDBGameHit] = []
    @State private var selectedGame: SteamGridDBGameHit?
    @State private var grids: [SteamGridDBGrid] = []
    @State private var isLoading = false
    @State private var downloadingGrid: Int?
    @State private var errorMessage: String?
    @State private var hasSearched = false
    @State private var searchGeneration = 0
    @State private var searchTask: Task<Void, Never>?
    /// 搜索结果各命中抓到的第一条封面缩略图 URL（key = 游戏 id）；抓取中为占位。
    @State private var thumbURLs: [Int: String] = [:]
    @State private var thumbTask: Task<Void, Never>?
    /// 封面下载代际：返回/关闭/换游戏时 +1，使在途下载结果失效（防下载完成后仍应用封面或关面板）。
    @State private var downloadGeneration = 0

    private var client: SteamGridDBClient { SteamGridDBClient(apiKey: apiKey) }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                LText("cover.title")
                    .font(.headline)
                Spacer()
                Button(L10n.tr("cover.close", lang: language)) { downloadGeneration += 1; searchTask?.cancel(); thumbTask?.cancel(); dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            BorderedTextField(text: $searchText, placeholder: L10n.tr("library.search", lang: language), onSubmit: { searchNow() })
                .onChange(of: searchText) { _, newValue in
                    scheduleSearch(newValue)
                }

            if let errorMessage {
                Text(verbatim: errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if let selectedGame {
                gridsSection(selectedGame)
            } else if hasSearched {
                if results.isEmpty {
                    LText("library.noResult")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    resultsList
                }
            }
        }
        .padding(16)
        #if os(macOS)
        .frame(width: 620, height: 500, alignment: .top)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #endif
    }

    // MARK: - 搜索结果

    private var resultsList: some View {
        List(results) { hit in
            HStack(spacing: 12) {
                resultThumb(hit)
                VStack(alignment: .leading) {
                    Text(verbatim: hit.name)
                    if let types = hit.types, !types.isEmpty {
                        Text(verbatim: types.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .onTapGesture { loadGrids(for: hit) }
        }
    }

    /// 搜索结果行的封面缩略图：已抓到的显示，未抓到的显示占位。
    private func resultThumb(_ hit: SteamGridDBGameHit) -> some View {
        Group {
            if let urlString = thumbURLs[hit.id], let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        resultThumbPlaceholder
                    default:
                        resultThumbPlaceholder
                    }
                }
            } else {
                resultThumbPlaceholder
            }
        }
        .frame(width: 48, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var resultThumbPlaceholder: some View {
        Rectangle()
            .fill(Color.semantic(.quaternarySystemFill))
            .overlay(Image(systemName: "photo").foregroundStyle(.tertiary))
    }

    // MARK: - 封面网格

    private func gridsSection(_ game: SteamGridDBGameHit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                LText("common.back")
                    .font(.callout)
                    .foregroundStyle(Color.accentColor)
                    .onTapGesture {
                        downloadGeneration += 1
                        downloadingGrid = nil
                        selectedGame = nil
                        grids = []
                    }
                Spacer()
                Text(verbatim: game.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
            }

            if grids.isEmpty {
                Spacer()
                LText("cover.noGrids")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90, maximum: 120), spacing: 10)], spacing: 10) {
                        ForEach(grids) { grid in
                            gridCell(grid)
                        }
                    }
                }
            }
        }
    }

    private func gridCell(_ grid: SteamGridDBGrid) -> some View {
        ZStack(alignment: .bottomTrailing) {
            AsyncImage(url: URL(string: grid.url)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Rectangle().fill(Color.semantic(.quaternarySystemFill))
                        .overlay(Image(systemName: "photo").foregroundStyle(.tertiary))
                default:
                    Rectangle().fill(Color.semantic(.quaternarySystemFill))
                        .overlay(ProgressView())
                }
            }
            .aspectRatio(grid.height > grid.width ? 3.0 / 4.0 : 16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            if downloadingGrid == grid.id {
                ProgressView()
                    .padding(4)
                    .background(.black.opacity(0.5), in: Circle())
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { download(grid) }
    }

    // MARK: - 逻辑

    /// 即时搜索（点按钮 / 回车）。
    private func searchNow() {
        searchTask?.cancel()
        thumbTask?.cancel()
        searchGeneration += 1
        isLoading = false
        let term = searchText.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        let gen = searchGeneration
        searchTask = Task { await performSearch(term: term, generation: gen) }
    }

    /// 输入防抖：停止输入约 300ms 后才真正搜索；连发请求只保留最后一个生效。
    private func scheduleSearch(_ newValue: String) {
        searchTask?.cancel()
        thumbTask?.cancel()
        searchGeneration += 1
        isLoading = false
        // 改动搜索词说明要重新搜索，退回结果视图
        selectedGame = nil
        grids = []
        let term = newValue.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else {
            hasSearched = false
            results = []
            thumbURLs = [:]
            errorMessage = nil
            return
        }
        let gen = searchGeneration
        let task = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, gen == searchGeneration else { return }
            await performSearch(term: term, generation: gen)
        }
        searchTask = task
    }

    private func performSearch(term: String, generation: Int) async {
        errorMessage = nil
        isLoading = true
        do {
            let hits = try await client.search(term: term)
            guard generation == searchGeneration else { return }
            isLoading = false
            hasSearched = true
            thumbURLs = [:]
            results = hits
            fetchThumbnails(for: hits)
        } catch {
            guard generation == searchGeneration else { return }
            isLoading = false
            errorMessage = L10n.tr("cover.searchFailed", lang: language)
        }
    }

    /// 渐进抓取每个搜索结果的第一条封面 URL 作缩略图：按序（依赖 client 的 ~2 次/秒节流），
    /// 每抓到一条就更新一次 UI；最多 10 条，避免大批请求拖慢。搜索代际变化时放弃在途结果。
    private func fetchThumbnails(for hits: [SteamGridDBGameHit]) {
        thumbTask?.cancel()
        let gen = searchGeneration
        thumbTask = Task {
            for hit in hits.prefix(10) {
                if Task.isCancelled || gen != searchGeneration { return }
                if thumbURLs[hit.id] != nil { continue }
                do {
                    let all = try await client.grids(for: hit.id)
                    guard !Task.isCancelled, gen == searchGeneration else { return }
                    if let first = SteamGridDBClient.sorted(all).first {
                        thumbURLs[hit.id] = first.url
                    }
                } catch {
                    // 单个失败静默，保持占位。
                }
            }
        }
    }

    private func loadGrids(for game: SteamGridDBGameHit) {
        downloadGeneration += 1
        selectedGame = game
        grids = []
        errorMessage = nil
        isLoading = true
        Task {
            do {
                let all = try await client.grids(for: game.id)
                grids = SteamGridDBClient.sorted(all)
                isLoading = false
            } catch {
                isLoading = false
                errorMessage = L10n.tr("cover.searchFailed", lang: language)
            }
        }
    }

    private func download(_ grid: SteamGridDBGrid) {
        downloadingGrid = grid.id
        downloadGeneration += 1
        let gen = downloadGeneration
        Task {
            do {
                let data = try await client.fetchImage(urlString: grid.url)
                guard gen == downloadGeneration else { return }
                downloadingGrid = nil
                coverData = data
                dismiss()
            } catch {
                guard gen == downloadGeneration else { return }
                downloadingGrid = nil
                errorMessage = L10n.tr("cover.searchFailed", lang: language)
            }
        }
    }
}
