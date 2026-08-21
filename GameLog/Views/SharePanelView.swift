import SwiftUI
import SwiftData

#if os(macOS)
import AppKit
#else
import Photos
#endif

/// 分享面板左栏模式：按游戏 / 按分组。
private enum ShareMode: String, CaseIterable {
    case games
    case groups
}

/// 分享面板：勾选游戏（单选→单卡，多选→总览图）或勾选分组（单选→分组分享卡），选尺寸，预览，保存/分享。
struct SharePanelView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguageCode) private var language
    @Query(sort: \Game.createdAt) private var games: [Game]
    @Query(sort: \GameGroup.name) private var groups: [GameGroup]
    var preselected: [Game] = []

    @State private var mode: ShareMode = .games
    @State private var selectedIDs: Set<PersistentIdentifier> = []
    @State private var selectedGroupID: PersistentIdentifier?
    @State private var searchText = ""
    @State private var size: ShareSize = .phone
    @State private var overviewTitle = ""
    @State private var groupTitle = ""
    @State private var renderedPNG: Data?
    @State private var shareURL: URL?
    @State private var renderTask: Task<Void, Never>?
    @State private var saveMessage: String?
    @AppStorage(UserCustomization.usernameKey) private var username = ""

    private var selectedGames: [Game] {
        games.filter { selectedIDs.contains($0.persistentModelID) }
    }

    private var selectedGroup: GameGroup? {
        guard let selectedGroupID else { return nil }
        return groups.first { $0.persistentModelID == selectedGroupID }
    }

    private var visibleGames: [Game] {
        searchText.isEmpty ? games : games.filter { $0.matches(search: searchText) }
    }

    private var isMulti: Bool { selectedGames.count > 1 }

    /// 分组标题绑定：写入时截断到用户名上限（替代 .onChange）。
    private var groupTitleBinding: Binding<String> {
        Binding(
            get: { groupTitle },
            set: { groupTitle = String(Array($0).prefix(UserCustomization.usernameMaxLength)) }
        )
    }

    /// 总览标题绑定：写入时截断到用户名上限（替代 .onChange）。
    private var overviewTitleBinding: Binding<String> {
        Binding(
            get: { overviewTitle },
            set: { overviewTitle = String(Array($0).prefix(UserCustomization.usernameMaxLength)) }
        )
    }

    var body: some View {
        Group {
            #if os(macOS)
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
            #else
            VStack(spacing: 0) {
                header
                Divider()
                previewColumn
                    .frame(minHeight: 240, maxHeight: 340)
                Divider()
                selectionList
                Divider()
                controls
            }
            #endif
        }
        .onAppear(perform: setup)
        .onChange(of: mode) { _, _ in scheduleRerender() }
        .onChange(of: selectedIDs) { _, _ in scheduleRerender() }
        .onChange(of: selectedGroupID) { _, _ in scheduleRerender() }
        .onChange(of: size) { _, _ in scheduleRerender() }
        .onChange(of: overviewTitle) { _, _ in scheduleRerender() }
        .onChange(of: groupTitle) { _, _ in scheduleRerender() }
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
            SegmentSlider(
                titles: ShareMode.allCases.map { L10n.tr($0 == .games ? "share.byGames" : "share.byGroups", lang: language) },
                selection: Binding(
                    get: { ShareMode.allCases.firstIndex(of: mode) ?? 0 },
                    set: { mode = ShareMode.allCases[$0] }
                )
            )
            .padding(10)

            BorderedTextField(text: $searchText, placeholder: L10n.tr("library.search", lang: language))
                .padding([.horizontal, .bottom], 10)

            List {
                if mode == .games {
                    ForEach(visibleGames) { game in
                        HStack(spacing: 8) {
                            Image(systemName: selectedIDs.contains(game.persistentModelID) ? "checkmark.square.fill" : "square")
                                .foregroundStyle(selectedIDs.contains(game.persistentModelID) ? Color.accentColor : Color.secondary)
                            coverThumb(game)
                            Text(verbatim: game.displayName(for: language))
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
                } else {
                    ForEach(groups) { group in
                        HStack(spacing: 8) {
                            Image(systemName: selectedGroupID == group.persistentModelID ? "checkmark.square.fill" : "square")
                                .foregroundStyle(selectedGroupID == group.persistentModelID ? Color.accentColor : Color.secondary)
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                            Text(verbatim: group.name)
                                .lineLimit(1)
                            Spacer()
                            Text(verbatim: "\(group.games.count)")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { toggleGroup(group) }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private func coverThumb(_ game: Game) -> some View {
        Group {
            if let image = game.coverImage {
                Image(appImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(Color.semantic(.quaternarySystemFill))
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

    /// 分组单选：再勾其他分组会取消当前选择；选中时同步标题默认值为分组名。
    private func toggleGroup(_ group: GameGroup) {
        if selectedGroupID == group.persistentModelID {
            selectedGroupID = nil
        } else {
            selectedGroupID = group.persistentModelID
            groupTitle = group.name
        }
    }

    // MARK: - 预览列

    private var previewColumn: some View {
        VStack(spacing: 0) {
            if let data = renderedPNG, let image = AppImage(data: data) {
                Image(appImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(16)
                    .background(Color.semantic(.textBackground))
            } else {
                ContentUnavailableView {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                } description: {
                    LText(mode == .groups ? "share.noneSelectedGroup" : "share.noneSelected")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 底部控制

    private var controls: some View {
        Group {
            #if os(macOS)
            HStack(spacing: 20) {
                SegmentSlider(
                    titles: ShareSize.allCases.map { L10n.tr($0 == .phone ? "share.phone" : "share.desktop", lang: language) },
                    selection: Binding(
                        get: { ShareSize.allCases.firstIndex(of: size) ?? 0 },
                        set: { size = ShareSize.allCases[$0] }
                    )
                )
                .frame(width: 260)

                if mode == .groups {
                    BorderedTextField(text: groupTitleBinding, placeholder: L10n.tr("share.groupTitle", lang: language))
                        .frame(width: 220)
                } else if isMulti {
                    BorderedTextField(text: overviewTitleBinding, placeholder: L10n.tr("share.overviewTitle", lang: language))
                        .frame(width: 220)
                }

                Spacer()
                exportButtons
            }
            #else
            VStack(alignment: .leading, spacing: 12) {
                SegmentSlider(
                    titles: ShareSize.allCases.map { L10n.tr($0 == .phone ? "share.phone" : "share.desktop", lang: language) },
                    selection: Binding(
                        get: { ShareSize.allCases.firstIndex(of: size) ?? 0 },
                        set: { size = ShareSize.allCases[$0] }
                    )
                )

                if mode == .groups {
                    BorderedTextField(text: groupTitleBinding, placeholder: L10n.tr("share.groupTitle", lang: language))
                } else if isMulti {
                    BorderedTextField(text: overviewTitleBinding, placeholder: L10n.tr("share.overviewTitle", lang: language))
                }

                HStack {
                    exportButtons
                    Spacer()
                }
                if let saveMessage {
                    Text(verbatim: saveMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            #endif
        }
        .padding()
    }

    /// 导出按钮组：macOS「保存图片」（NSSavePanel）；iOS「保存到相册」（直接写系统相册）+ 系统分享单。
    private var exportButtons: some View {
        Group {
            #if os(macOS)
            Button(L10n.tr("share.saveImage", lang: language)) { saveImage() }
                .disabled(renderedPNG == nil)
            if let url = shareURL {
                ShareLink(item: url) {
                    Label(L10n.tr("share.openShareSheet", lang: language), systemImage: "square.and.arrow.up")
                }
            } else {
                Button(L10n.tr("share.openShareSheet", lang: language)) {}
                    .disabled(true)
            }
            #else
            Button {
                saveImageToAlbum()
            } label: {
                Label(L10n.tr("share.saveToAlbum", lang: language), systemImage: "photo.on.rectangle.angled")
            }
            .appStandardButton()
            .disabled(renderedPNG == nil)
            if let url = shareURL {
                // iOS 26 sheet 内嵌 ShareLink 静默失败，改用 UIKit 直接 present 系统分享单。
                Button {
                    presentShareSheet(url: url)
                } label: {
                    Label(L10n.tr("share.openShareSheet", lang: language), systemImage: "square.and.arrow.up")
                }
                .appStandardButton()
            } else {
                Button(L10n.tr("share.openShareSheet", lang: language)) {}
                    .appStandardButton()
                    .disabled(true)
            }
            #endif
        }
    }

    // MARK: - 逻辑

    private func setup() {
        if !preselected.isEmpty {
            selectedIDs = Set(preselected.map(\.persistentModelID))
        }
        overviewTitle = defaultOverviewTitle()
        // 不在此直接 rerender：上面的 state 写入会触发 onChange → scheduleRerender
    }

    /// 总览图默认标题：设了用户名 →「{用户名}的游戏簿」，未设 → app 品牌名。
    private func defaultOverviewTitle() -> String {
        let name = username.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return L10n.tr("app.menu", lang: language) }
        return L10n.tr("share.brandUser", [name], lang: language)
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
        if mode == .games {
            let games = selectedGames
            guard !games.isEmpty else {
                clearPreview()
                return
            }
            if games.count == 1 {
                render(.single(games[0], size: size))
            } else {
                let title = overviewTitle.trimmingCharacters(in: .whitespaces).isEmpty
                    ? defaultOverviewTitle()
                    : overviewTitle
                render(.overview(games, title: title, size: size))
            }
        } else {
            guard let group = selectedGroup else {
                clearPreview()
                return
            }
            let title = groupTitle.trimmingCharacters(in: .whitespaces).isEmpty ? group.name : groupTitle
            render(.group(group, title: title, size: size))
        }
    }

    private func clearPreview() {
        renderedPNG = nil
        shareURL = nil
    }

    private func render(_ content: ShareCardContent) {
        guard let data = ShareCardRenderer.renderPNG(content: content, language: language) else {
            clearPreview()
            return
        }
        renderedPNG = data
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("GameLog-share.png")
        // 临时文件写失败时保持 shareURL=nil（分享按钮禁用），避免指向缺失或陈旧的旧文件。
        if (try? data.write(to: url)) != nil {
            shareURL = url
        } else {
            shareURL = nil
        }
    }

    private func saveImage() {
        guard let data = renderedPNG else { return }
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = mode == .groups
            ? "GameLog-group-\(size.rawValue).png"
            : "GameLog-\(size.rawValue).png"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
        #else
        // iOS：分享走 ShareLink（系统分享单）；如需另存文件，阶段 3 用 fileExporter。
        #endif
    }

    #if !os(macOS)
    /// iOS：把渲染好的 PNG 直接存入系统相册（仅「添加」权限，无需读取相册）。
    private func saveImageToAlbum() {
        guard let data = renderedPNG, let image = UIImage(data: data) else {
            saveMessage = L10n.tr("share.saveFailed", lang: language)
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized, .limited:
                    PHPhotoLibrary.shared().performChanges {
                        PHAssetChangeRequest.creationRequestForAsset(from: image)
                    } completionHandler: { success, _ in
                        DispatchQueue.main.async {
                            saveMessage = success
                                ? L10n.tr("share.savedToAlbum", lang: language)
                                : L10n.tr("share.saveFailed", lang: language)
                        }
                    }
                default:
                    saveMessage = L10n.tr("share.photoPermissionDenied", lang: language)
                }
            }
        }
    }
    #endif
}
