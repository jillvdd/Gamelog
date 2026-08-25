import SwiftUI

/// 图像类型：本面板按类型决定走哪个 SGDB 端点与网格布局。
/// poster = 2:3 竖版封面（主格式，分页浏览）；landscape = 920×430 横向封面（分页）；
/// hero = 宽幅背景图；logo = 透明 Logo（后两类一次全量返回，大图优先排列）。
enum ArtworkKind: String, Identifiable {
    case poster
    case landscape
    case hero
    case logo

    var id: String { rawValue }

    /// 面板标题 key。
    var titleKey: String {
        switch self {
        case .poster: "cover.title"
        case .landscape: "cover.titleLandscape"
        case .hero: "cover.titleHero"
        case .logo: "cover.titleLogo"
        }
    }

    /// 空结果提示 key。
    var noResultKey: String {
        switch self {
        case .poster: "cover.noGrids"
        case .landscape: "cover.noLandscape"
        case .hero: "cover.noHero"
        case .logo: "cover.noLogo"
        }
    }

    /// 是否支持分页加载（grids 端点的两种尺寸过滤查询）。
    var supportsPaging: Bool { self == .poster || self == .landscape }
}

/// 图像搜索面板：SteamGridDB 按名字搜游戏 → 选游戏 → 选一张图。
/// 按 `kind` 服务四种类型（2:3 封面 / 横向封面 / 背景图 / Logo），下载结果写进 `imageData`。
struct CoverSearchSheet: View {
    let kind: ArtworkKind
    @Binding var imageData: Data?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguageCode) private var language
    @AppStorage("steamGridDBKey") private var apiKey = ""

    @State private var searchText = ""
    @State private var results: [SteamGridDBGameHit] = []
    @State private var selectedGame: SteamGridDBGameHit?
    @State private var grids: [SteamGridDBGrid] = []
    /// 封面浏览分页状态(API 每页 50;热门游戏数百张,渐进加载)。
    @State private var gridTotal = 0
    @State private var gridPage = 0
    @State private var isLoadingMoreGrids = false
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
                LText(kind.titleKey)
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
        // iOS 下滑手势关闭不经过 Close 按钮：在这里兜底失效在途请求/下载，
        // 否则慢网下载完成后仍会把封面写进已关闭面板背后的表单。
        .onDisappear {
            downloadGeneration += 1
            searchTask?.cancel()
            thumbTask?.cancel()
        }
    }

    // MARK: - 搜索结果

    private var resultsList: some View {
        List(results) { hit in
            Button {
                loadGrids(for: hit)
            } label: {
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
            }
            .buttonStyle(PressFeedbackButtonStyle(pressedOpacity: 0.55))
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
                Button {
                    downloadGeneration += 1
                    downloadingGrid = nil
                    selectedGame = nil
                    grids = []
                } label: {
                    LText("common.back")
                        .font(.callout)
                        .foregroundStyle(Color.accentColor)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressFeedbackButtonStyle())
                Spacer()
                Text(verbatim: game.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
            }

            if grids.isEmpty {
                Spacer()
                LText(kind.noResultKey)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(grids) { grid in
                            gridCell(grid)
                        }
                    }
                    // 分页加载（仅 2:3 / 920×430 两种尺寸过滤查询；heroes/logos 一次全量返回）。
                    if kind.supportsPaging && grids.count < gridTotal {
                        HStack(spacing: 8) {
                            Button {
                                loadMoreGrids()
                            } label: {
                                HStack(spacing: 6) {
                                    if isLoadingMoreGrids {
                                        ProgressView()
                                            .controlSize(.small)
                                    }
                                    Text(verbatim: L10n.tr("cover.loadMore", lang: language))
                                }
                            }
                            .appStandardButton()
                            .controlSize(.small)
                            .disabled(isLoadingMoreGrids)
                            Text(verbatim: "\(grids.count) / \(gridTotal)")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                    }
                }
            }
        }
    }

    /// 网格列布局按类型：竖版封面窄格；横向/背景图宽格；Logo 透明图配衬底方格。
    private var columns: [GridItem] {
        switch kind {
        case .poster:
            [GridItem(.adaptive(minimum: 90, maximum: 120), spacing: 10)]
        case .landscape, .hero:
            [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 10)]
        case .logo:
            // Logo 是透明 PNG，深浅色下可能看不清 → 每格垫浅灰衬底（见 gridCell）。
            [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 10)]
        }
    }

    private func gridCell(_ grid: SteamGridDBGrid) -> some View {
        // 封面格按钮化：按压缩放反馈（原 onTapGesture 无视觉响应）。
        // 浏览用 thumb 缩略图（全尺寸图数百 KB/张，数百张会拖垮带宽），点选下载才取 url 全图；
        // 宽高比用图片真实比例。
        Button {
            download(grid)
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if kind == .logo {
                        // 透明 PNG 垫固定浅灰衬底（纯白衬底上白 logo 隐形；浅灰深浅色下都衬托白/彩色 logo）。
                        AsyncImage(url: grid.thumb.flatMap(URL.init(string:)) ?? URL(string: grid.url)) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFit()
                            case .failure:
                                Rectangle().fill(Color.semantic(.quaternarySystemFill))
                                    .overlay(Image(systemName: "photo").foregroundStyle(.tertiary))
                            default:
                                Rectangle().fill(Color.semantic(.quaternarySystemFill))
                                    .overlay(ProgressView())
                            }
                        }
                        .padding(6)
                        .background(Rectangle().fill(Color(red: 0.88, green: 0.88, blue: 0.90)))
                        .overlay(Rectangle().strokeBorder(Color.semantic(.separator), lineWidth: 0.5))
                    } else {
                        AsyncImage(url: grid.thumb.flatMap(URL.init(string:)) ?? URL(string: grid.url)) { phase in
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
                    }
                }
                .aspectRatio(CGFloat(grid.width) / max(CGFloat(grid.height), 1), contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                if downloadingGrid == grid.id {
                    ProgressView()
                        .padding(4)
                        .background(.black.opacity(0.5), in: Circle())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressFeedbackButtonStyle(pressedScale: 0.94))
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
            // 主结果先渲染（不增加常见路径延迟），后台追加变体查询扩容。
            await appendVariantResults(base: term, generation: generation)
        } catch {
            guard generation == searchGeneration else { return }
            isLoading = false
            // 清掉上一轮结果：失败提示与旧结果同屏会被误认成新关键词的命中。
            results = []
            thumbURLs = [:]
            hasSearched = false
            errorMessage = L10n.tr("cover.searchFailed", lang: language)
        }
    }

    /// 变体查询扩容：autocomplete 端点单次硬上限 10 条，实测无 limit/分页参数。
    /// 多词查询时按「去尾词 → 首词」各再查一次，按 id 去重后追加（主查询命中优先排序）；
    /// 单词查询无变体，维持 10 条上限。变体失败静默（主结果不受影响）。
    private func appendVariantResults(base: String, generation: Int) async {
        let words = base.split(separator: " ").map(String.init)
        guard words.count >= 2 else { return }
        var variants: [String] = []
        if words.count >= 3 {
            variants.append(words.dropLast().joined(separator: " "))
        }
        variants.append(words[0])
        for variant in variants {
            guard !Task.isCancelled, generation == searchGeneration else { return }
            do {
                let hits = try await client.search(term: variant)
                guard !Task.isCancelled, generation == searchGeneration else { return }
                var appended = false
                for hit in hits where !results.contains(where: { $0.id == hit.id }) {
                    results.append(hit)
                    appended = true
                }
                if appended {
                    fetchThumbnails(for: results)
                }
            } catch {
                // 变体查询失败静默：主结果已足够可用。
            }
        }
    }

    /// 渐进抓取每个搜索结果的第一条封面 URL 作缩略图：按序（依赖 client 的 ~2 次/秒节流），
    /// 每抓到一条就更新一次 UI；最多 15 条，避免大批请求拖慢。搜索代际变化时放弃在途结果。
    private func fetchThumbnails(for hits: [SteamGridDBGameHit]) {
        thumbTask?.cancel()
        let gen = searchGeneration
        thumbTask = Task {
            for hit in hits.prefix(15) {
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
        let gen = downloadGeneration
        selectedGame = game
        grids = []
        gridTotal = 0
        gridPage = 0
        errorMessage = nil
        isLoading = true
        Task {
            do {
                switch kind {
                case .poster:
                    // 首页按「竖版优先」排序(2:3 是本 app 封面主格式);后续页按 API 原序追加。
                    let page = try await client.gridsPage(for: game.id, page: 0)
                    guard gen == downloadGeneration else { return }
                    grids = SteamGridDBClient.sorted(page.grids)
                    gridTotal = page.total
                case .landscape:
                    let page = try await client.landscapesPage(for: game.id, page: 0)
                    guard gen == downloadGeneration else { return }
                    grids = page.grids
                    gridTotal = page.total
                case .hero:
                    let heroes = try await client.heroes(for: game.id)
                    guard gen == downloadGeneration else { return }
                    // 无尺寸过滤参数，直接按大图优先排列。
                    grids = heroes.sorted { $0.width * $0.height > $1.width * $1.height }
                    gridTotal = heroes.count
                case .logo:
                    let logos = try await client.logos(for: game.id)
                    guard gen == downloadGeneration else { return }
                    grids = logos.sorted { $0.width * $0.height > $1.width * $1.height }
                    gridTotal = logos.count
                }
                gridPage = 0
                isLoading = false
            } catch {
                guard gen == downloadGeneration else { return }
                isLoading = false
                errorMessage = L10n.tr("cover.searchFailed", lang: language)
            }
        }
    }

    /// 加载下一页封面(热门游戏数百张,分页渐进浏览)。
    private func loadMoreGrids() {
        guard kind.supportsPaging, !isLoadingMoreGrids, grids.count < gridTotal else { return }
        isLoadingMoreGrids = true
        let gen = downloadGeneration
        let nextPage = gridPage + 1
        Task {
            do {
                let page: SteamGridDBClient.GridPage
                switch kind {
                case .poster: page = try await client.gridsPage(for: selectedGame?.id ?? 0, page: nextPage)
                case .landscape: page = try await client.landscapesPage(for: selectedGame?.id ?? 0, page: nextPage)
                case .hero, .logo: return // 不分页的类型不会走到这里（supportsPaging 已挡）。
                }
                guard gen == downloadGeneration else { return }
                grids.append(contentsOf: page.grids)
                gridPage = nextPage
                isLoadingMoreGrids = false
            } catch {
                guard gen == downloadGeneration else { return }
                isLoadingMoreGrids = false
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
                imageData = data
                // 停止在途搜索/缩略图请求：面板即将关闭，避免其在后台空跑。
                searchTask?.cancel()
                thumbTask?.cancel()
                dismiss()
            } catch {
                guard gen == downloadGeneration else { return }
                downloadingGrid = nil
                errorMessage = L10n.tr("cover.searchFailed", lang: language)
            }
        }
    }
}
