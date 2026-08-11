import SwiftUI
import SwiftData
import AppKit

/// 分享面板：勾选游戏（单选→单卡，多选→总览图），选尺寸，预览，保存/分享。
struct SharePanelView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguageCode) private var language
    @Query(sort: \Game.createdAt) private var games: [Game]
    var preselected: [Game] = []

    @State private var selectedIDs: Set<PersistentIdentifier> = []
    @State private var searchText = ""
    @State private var size: ShareSize = .phone
    @State private var overviewTitle = ""
    @State private var renderedPNG: Data?
    @State private var shareURL: URL?
    @State private var renderTask: Task<Void, Never>?

    private var selectedGames: [Game] {
        games.filter { selectedIDs.contains($0.persistentModelID) }
    }

    private var visibleGames: [Game] {
        searchText.isEmpty ? games : games.filter { $0.matches(search: searchText) }
    }

    private var isMulti: Bool { selectedGames.count > 1 }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                selectionList
                    .frame(width: 300)
                Divider()
                previewColumn
            }
            Divider()
            controls
        }
        .frame(width: 1040, height: 680)
        .onAppear(perform: setup)
        .onChange(of: selectedIDs) { _, _ in scheduleRerender() }
        .onChange(of: size) { _, _ in scheduleRerender() }
        .onChange(of: overviewTitle) { _, _ in scheduleRerender() }
        .onDisappear { renderTask?.cancel() }
    }

    // MARK: - 头部

    private var header: some View {
        HStack {
            LText("share.selectGames")
                .font(.headline)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: - 游戏选择列表

    private var selectionList: some View {
        VStack(spacing: 0) {
            TextField(L10n.tr("library.search", lang: language), text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(10)

            List {
                ForEach(visibleGames) { game in
                    HStack(spacing: 8) {
                        Image(systemName: selectedIDs.contains(game.persistentModelID) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(selectedIDs.contains(game.persistentModelID) ? Color.accentColor : Color.secondary)
                        coverThumb(game)
                        Text(verbatim: game.name)
                            .lineLimit(1)
                        Spacer()
                        if let score = game.libraryScore {
                            Text(verbatim: String(format: "%.1f", score))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { toggle(game) }
                }
            }
            .listStyle(.plain)
        }
    }

    private func coverThumb(_ game: Game) -> some View {
        Group {
            if let image = game.coverImage {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(Color(nsColor: .quaternarySystemFill))
                    Image(systemName: "gamecontroller").font(.system(size: 8)).foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: 26, height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func toggle(_ game: Game) {
        if selectedIDs.contains(game.persistentModelID) {
            selectedIDs.remove(game.persistentModelID)
        } else {
            selectedIDs.insert(game.persistentModelID)
        }
    }

    // MARK: - 预览列

    private var previewColumn: some View {
        VStack(spacing: 0) {
            if let data = renderedPNG, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(16)
                    .background(Color(nsColor: .textBackgroundColor))
            } else {
                ContentUnavailableView {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                } description: {
                    LText("share.noneSelected")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 底部控制

    private var controls: some View {
        HStack(spacing: 20) {
            Picker(L10n.tr("share.size", lang: language), selection: $size) {
                Text(verbatim: L10n.tr("share.phone", lang: language)).tag(ShareSize.phone)
                Text(verbatim: L10n.tr("share.desktop", lang: language)).tag(ShareSize.desktop)
            }
            .pickerStyle(.segmented)
            .frame(width: 260)

            if isMulti {
                TextField(L10n.tr("share.overviewTitle", lang: language), text: $overviewTitle)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }

            Spacer()

            let canExport = renderedPNG != nil

            Button(L10n.tr("share.saveImage", lang: language)) { saveImage() }
                .disabled(!canExport)

            if let url = shareURL {
                ShareLink(item: url) {
                    Label(L10n.tr("share.openShareSheet", lang: language), systemImage: "square.and.arrow.up")
                }
            } else {
                Button(L10n.tr("share.openShareSheet", lang: language)) {}
                    .disabled(true)
            }
        }
        .padding()
    }

    // MARK: - 逻辑

    private func setup() {
        if !preselected.isEmpty {
            selectedIDs = Set(preselected.map(\.persistentModelID))
        }
        overviewTitle = L10n.tr("share.overviewTitleDefault", lang: language)
        // 不在此直接 rerender：上面的 state 写入会触发 onChange → scheduleRerender
    }

    /// 防抖重渲染：大尺寸 ImageRenderer 较慢，避免标题逐键触发全尺寸出图。
    private func scheduleRerender() {
        renderTask?.cancel()
        renderTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            rerender()
        }
    }

    private func rerender() {
        let games = selectedGames
        guard !games.isEmpty else {
            renderedPNG = nil
            shareURL = nil
            return
        }
        let content: ShareCardContent
        if games.count == 1 {
            content = .single(games[0], size: size)
        } else {
            let title = overviewTitle.trimmingCharacters(in: .whitespaces).isEmpty
                ? L10n.tr("share.overviewTitleDefault", lang: language)
                : overviewTitle
            content = .overview(games, title: title, size: size)
        }
        guard let data = ShareCardRenderer.renderPNG(content: content, language: language) else {
            renderedPNG = nil
            shareURL = nil
            return
        }
        renderedPNG = data
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("GameLog-share.png")
        try? data.write(to: url)
        shareURL = url
    }

    private func saveImage() {
        guard let data = renderedPNG else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "GameLog-\(size.rawValue).png"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }
}
