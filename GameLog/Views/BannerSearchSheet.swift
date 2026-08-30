import SwiftUI

/// 主页横幅背景图搜索面板（beta 2.8）：SteamGridDB 按名字搜游戏 → 选游戏 →
/// 列出该游戏的 **hero + 342×482 + 660×930** 背景候选 → 点一张下载 → 弹 `BannerCropSheet`
/// 小窗自行裁切要作为背景的区域 → 保存为横幅背景并关闭。
struct BannerSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguageCode) private var language
    @AppStorage("steamGridDBKey") private var apiKey = ""

    @State private var searchText = ""
    @State private var results: [SteamGridDBGameHit] = []
    @State private var selectedGame: SteamGridDBGameHit?
    @State private var candidates: [SteamGridDBGrid] = []
    @State private var isLoading = false
    @State private var downloadingURL: String?
    @State private var errorMessage: String?
    @State private var hasSearched = false
    @State private var generation = 0
    @State private var searchTask: Task<Void, Never>?
    /// 选中的候选图（下载后进裁切小窗；nil = 无）。
    @State private var pendingCrop: AppImage?

    private var client: SteamGridDBClient { SteamGridDBClient(apiKey: apiKey) }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                LText("cover.titleHero")
                    .font(.headline)
                Spacer()
                Button(L10n.tr("cover.close", lang: language)) {
                    generation += 1
                    searchTask?.cancel()
                    pendingCrop = nil
                    dismiss()
                }
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
                candidatesSection(selectedGame)
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
        .frame(width: 640, height: 520, alignment: .top)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #endif
        .onDisappear {
            generation += 1
            searchTask?.cancel()
        }
        .sheet(isPresented: Binding(
            get: { pendingCrop != nil },
            set: { if !$0 { pendingCrop = nil } }
        )) {
            if let image = pendingCrop {
                BannerCropSheet(
                    sourceImage: image,
                    onCancel: { pendingCrop = nil },
                    onConfirm: { cropped in
                        pendingCrop = nil
                        if let data = cropped.pngData() {
                            try? UserCustomization.saveBannerBackgroundPNG(data)
                        }
                        generation += 1
                        searchTask?.cancel()
                        dismiss()
                    }
                )
            }
        }
    }

    // MARK: - 搜索结果（名 + 类型）

    private var resultsList: some View {
        List(results) { hit in
            Button {
                loadCandidates(for: hit)
            } label: {
                HStack(spacing: 12) {
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

    // MARK: - 背景候选（hero / 342×482 / 660×930，混排网格）

    private func candidatesSection(_ game: SteamGridDBGameHit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    generation += 1
                    downloadingURL = nil
                    selectedGame = nil
                    candidates = []
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

            if candidates.isEmpty {
                Spacer()
                LText("cover.noHero")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 260), spacing: 10)], spacing: 10) {
                        ForEach(candidates) { grid in
                            candidateCell(grid)
                        }
                    }
                }
            }
        }
    }

    private func candidateCell(_ grid: SteamGridDBGrid) -> some View {
        Button {
            download(grid)
        } label: {
            ZStack(alignment: .bottomTrailing) {
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
                .aspectRatio(CGFloat(grid.width) / max(CGFloat(grid.height), 1), contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                if downloadingURL == grid.url {
                    ProgressView()
                        .padding(4)
                        .background(.black.opacity(0.5), in: Circle())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressFeedbackButtonStyle(pressedScale: 0.94))
    }

    // MARK: - 逻辑（防抖即时搜索 + 代际守卫）

    private func searchNow() {
        searchTask?.cancel()
        generation += 1
        isLoading = false
        let term = searchText.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        let gen = generation
        searchTask = Task { await performSearch(term: term, generation: gen) }
    }

    private func scheduleSearch(_ newValue: String) {
        searchTask?.cancel()
        generation += 1
        isLoading = false
        selectedGame = nil
        candidates = []
        let term = newValue.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else {
            hasSearched = false
            results = []
            errorMessage = nil
            return
        }
        let gen = generation
        let task = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, gen == generation else { return }
            await performSearch(term: term, generation: gen)
        }
        searchTask = task
    }

    private func performSearch(term: String, generation: Int) async {
        errorMessage = nil
        isLoading = true
        do {
            let hits = try await client.search(term: term)
            guard generation == self.generation else { return }
            isLoading = false
            hasSearched = true
            results = hits
        } catch {
            guard generation == self.generation else { return }
            isLoading = false
            results = []
            hasSearched = false
            errorMessage = L10n.tr("cover.searchFailed", lang: language)
        }
    }

    private func loadCandidates(for game: SteamGridDBGameHit) {
        generation += 1
        let gen = generation
        selectedGame = game
        candidates = []
        errorMessage = nil
        isLoading = true
        Task {
            do {
                let list = try await client.bannerCandidates(for: game.id)
                guard gen == generation else { return }
                candidates = SteamGridDBClient.sorted(list)
                isLoading = false
            } catch {
                guard gen == generation else { return }
                isLoading = false
                errorMessage = L10n.tr("cover.searchFailed", lang: language)
            }
        }
    }

    /// 下载选中图 → 进裁切小窗（不直接存：让用户自选背景区域，裁完比例才与横幅一致）。
    private func download(_ grid: SteamGridDBGrid) {
        downloadingURL = grid.url
        generation += 1
        let gen = generation
        Task {
            do {
                let data = try await client.fetchImage(urlString: grid.url)
                guard gen == generation else { return }
                downloadingURL = nil
                guard let image = AppImage(data: data) else { return }
                pendingCrop = image
            } catch {
                guard gen == generation else { return }
                downloadingURL = nil
                errorMessage = L10n.tr("cover.searchFailed", lang: language)
            }
        }
    }
}