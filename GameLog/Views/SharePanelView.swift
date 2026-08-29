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

/// 导出格式：默认 JPEG（照片类内容体积小一个量级），PNG 备选无损。
private enum ShareExportFormat: String, CaseIterable, Identifiable {
    case jpeg
    case png
    var id: String { rawValue }

    var rendererFormat: ShareCardRenderer.OutputFormat {
        self == .jpeg ? .jpeg(quality: 0.9) : .png
    }
    var fileExtension: String { self == .jpeg ? "jpg" : "png" }
}

/// 分享面板：勾选游戏（单选→单卡，多选→总览图）或勾选分组（单选→分组分享卡），
/// 选尺寸与格式，实时预览（降采样提速），保存/分享时才渲全尺寸。
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
    @State private var renderedData: Data?
    @State private var shareURL: URL?
    @State private var renderTask: Task<Void, Never>?
    @State private var saveMessage: String?
    @State private var exportFormat: ShareExportFormat = .jpeg
    @State private var showingStyleEditor = false
    /// 统计要素配置变更代际：编辑器保存后 +1 触发分组卡重渲染。
    @State private var statsRevision = 0
    #if os(iOS)
    @State private var showingFullscreenPreview = false
    #endif
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

    /// 当前预览对应的内容；无有效选择则 nil。
    private var currentContent: ShareCardContent? {
        if mode == .games {
            let selected = selectedGames
            guard !selected.isEmpty else { return nil }
            if selected.count == 1 {
                return .single(selected[0], size: size)
            }
            let title = overviewTitle.trimmingCharacters(in: .whitespaces).isEmpty
                ? defaultOverviewTitle()
                : overviewTitle
            return .overview(selected, title: title, size: size)
        } else {
            guard let group = selectedGroup else { return nil }
            let title = groupTitle.trimmingCharacters(in: .whitespaces).isEmpty ? group.name : groupTitle
            return .group(group, title: title, size: size)
        }
    }

    /// 分组标题绑定：写入时截断到用户名上限。
    private var groupTitleBinding: Binding<String> {
        Binding(
            get: { groupTitle },
            set: { groupTitle = UserCustomization.truncateUsername($0) }
        )
    }

    /// 总览标题绑定：写入时截断到用户名上限。
    private var overviewTitleBinding: Binding<String> {
        Binding(
            get: { overviewTitle },
            set: { overviewTitle = UserCustomization.truncateUsername($0) }
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
            // minWidth 900：主窗最小 980（对齐 Music）下放得下——左栏 300 + 预览 ~570。
            // 此前 1060 是按主窗 minWidth 1150 定的，主窗缩小后必须跟着降。
            .frame(minWidth: 900, minHeight: 700)
            #else
            // iOS 纵向三段：① 预览 + 输出设置（尺寸/格式）置顶；② 模式+搜索一行，
            // 勾选列表吃掉全部弹性空间（最大化）；③ 标题 + 样式/导出一行收在底部拇指区。
            // 「点按查看大图」提示行已删（点预览即全屏，符合手机直觉）。macOS 三栏布局不动。
            VStack(spacing: 0) {
                header
                Divider()
                previewColumn
                    .frame(height: 200)
                HStack(spacing: 12) {
                    SegmentSlider(
                        titles: ShareSize.allCases.map { L10n.tr($0 == .phone ? "share.phone" : "share.desktop", lang: language) },
                        selection: Binding(
                            get: { ShareSize.allCases.firstIndex(of: size) ?? 0 },
                            set: { size = ShareSize.allCases[$0] }
                        )
                    )
                    .frame(width: 168)
                    formatPicker
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                Divider()
                HStack(spacing: 10) {
                    modeSegment
                        .frame(width: 168)
                    searchField
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                gameGroupList
                Divider()
                VStack(spacing: 10) {
                    if mode == .groups {
                        BorderedTextField(text: groupTitleBinding, placeholder: L10n.tr("share.groupTitle", lang: language))
                    } else if isMulti {
                        BorderedTextField(text: overviewTitleBinding, placeholder: L10n.tr("share.overviewTitle", lang: language))
                    }
                    HStack(spacing: 8) {
                        styleSettingsButton
                        exportButtons
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 12)
            }
            #endif
        }
        // 面板跟随系统明暗（2026-08-27 用户定稿，原为强制深色——浅色系统下 iOS 弹出时
        // 会闪一次暗色切换）。预览画布仍用固定品牌深底衬同样固定深色的分享卡，
        // 卡片本体全是写死颜色（ShareTheme.brand），两种外观下渲染结果一致。
        .onAppear(perform: setup)
        .onChange(of: mode) { _, _ in scheduleRerender() }
        .onChange(of: selectedIDs) { _, _ in scheduleRerender() }
        .onChange(of: selectedGroupID) { _, _ in scheduleRerender() }
        .onChange(of: size) { _, _ in scheduleRerender() }
        .onChange(of: overviewTitle) { _, _ in scheduleRerender() }
        .onChange(of: groupTitle) { _, _ in scheduleRerender() }
        .onChange(of: exportFormat) { _, _ in scheduleRerender() }
        .onChange(of: statsRevision) { _, _ in scheduleRerender() }
        .sheet(isPresented: $showingStyleEditor) {
            ShareStyleConfigurator { statsRevision += 1 }
        }
        .onDisappear { renderTask?.cancel() }
    }

    // MARK: - 头部

    @ViewBuilder
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
            .help(L10n.tr("common.close", lang: language))
        }
        #if os(macOS)
        .padding()
        #else
        // iOS sheet 顶缘到标题只有默认 16pt，视觉贴边突兀；macOS 布局不动。
        .padding(.top, 24)
        .padding(.bottom, 14)
        .padding(.horizontal, 20)
        #endif
    }

    // MARK: - 选择列表

    /// 模式分段（按游戏/按分组）。macOS 左栏与 iOS 工具行共用。
    private var modeSegment: some View {
        SegmentSlider(
            titles: ShareMode.allCases.map { L10n.tr($0 == .games ? "share.byGames" : "share.byGroups", lang: language) },
            selection: Binding(
                get: { ShareMode.allCases.firstIndex(of: mode) ?? 0 },
                set: { mode = ShareMode.allCases[$0] }
            )
        )
    }

    private var searchField: some View {
        BorderedTextField(text: $searchText, placeholder: L10n.tr("library.search", lang: language))
    }

    /// 样式设置入口。macOS 左栏通栏按钮；iOS 文字胶囊（与导出按钮同行，省宽度去图标）。
    private var styleSettingsButton: some View {
        Button {
            showingStyleEditor = true
        } label: {
            #if os(macOS)
            Label(L10n.tr("share.styleSettings", lang: language), systemImage: "slider.horizontal.3")
                .frame(maxWidth: .infinity)
            #else
            Text(verbatim: L10n.tr("share.styleSettings", lang: language))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            #endif
        }
        .appStandardButton()
        #if os(macOS)
        .controlSize(.small)
        #endif
    }

    /// 游戏/分组勾选列表本体。
    private var gameGroupList: some View {
        List {
            if mode == .games {
                ForEach(visibleGames) { game in
                    Button {
                        toggle(game)
                    } label: {
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
                    }
                    .buttonStyle(PressFeedbackButtonStyle(pressedOpacity: 0.55))
                }
            } else {
                ForEach(groups) { group in
                    Button {
                        toggleGroup(group)
                    } label: {
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
                    }
                    .buttonStyle(PressFeedbackButtonStyle(pressedOpacity: 0.55))
                }
            }
        }
        .listStyle(.plain)
    }

    /// macOS 左栏：模式 + 搜索 + 样式入口 + 列表（竖排）。iOS 面板另行组合（见 body）。
    private var selectionList: some View {
        VStack(spacing: 0) {
            modeSegment
                .padding(10)
            searchField
                .padding([.horizontal, .bottom], 10)
            styleSettingsButton
                .padding([.horizontal, .bottom], 10)
            gameGroupList
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
            if let data = renderedData, let image = AppImage(data: data) {
                Image(appImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(16)
                    .background(Color(red: 0.075, green: 0.067, blue: 0.055))
                    // iOS 点预览全屏看大图：按钮化带按压反馈（原 onTapGesture 无视觉响应）。
                    #if os(iOS)
                    .contentShape(Rectangle())
                    .onTapGesture { showingFullscreenPreview = true }
                    #endif
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
        #if os(iOS)
        .fullScreenCover(isPresented: $showingFullscreenPreview) {
            fullscreenViewer
        }
        #endif
    }

    #if os(iOS)
    /// 全屏查看预览大图（点任意处关闭）。
    private var fullscreenViewer: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let data = renderedData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
                    .onTapGesture { showingFullscreenPreview = false }
            }
            Button {
                showingFullscreenPreview = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(20)
        }
    }
    #endif

    // MARK: - 底部控制

    private var controls: some View {
        Group {
            #if os(macOS)
            HStack(spacing: 16) {
                SegmentSlider(
                    titles: ShareSize.allCases.map { L10n.tr($0 == .phone ? "share.phone" : "share.desktop", lang: language) },
                    selection: Binding(
                        get: { ShareSize.allCases.firstIndex(of: size) ?? 0 },
                        set: { size = ShareSize.allCases[$0] }
                    )
                )
                .frame(width: 240)

                formatPicker

                if mode == .groups {
                    BorderedTextField(text: groupTitleBinding, placeholder: L10n.tr("share.groupTitle", lang: language))
                        .frame(width: 200)
                } else if isMulti {
                    BorderedTextField(text: overviewTitleBinding, placeholder: L10n.tr("share.overviewTitle", lang: language))
                        .frame(width: 200)
                }

                Spacer()
                exportButtons
            }
            #else
            // iOS 控制区压缩：尺寸滑块与格式按钮并排一行（macOS 分开两处不动），
            // 省下的纵向空间全部让给上方勾选列表。
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    SegmentSlider(
                        titles: ShareSize.allCases.map { L10n.tr($0 == .phone ? "share.phone" : "share.desktop", lang: language) },
                        selection: Binding(
                            get: { ShareSize.allCases.firstIndex(of: size) ?? 0 },
                            set: { size = ShareSize.allCases[$0] }
                        )
                    )
                    formatPicker
                }

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

    private var formatPicker: some View {
        // iOS 的 Picker/Menu 系统样式都渲染成裸文字（iOS 26 忽略 .menuStyle(.button) 的边框），
        // 手动给 label 胶囊底，与相邻 bordered 按钮观感一致；macOS 保持系统菜单选框。
        #if os(iOS)
        Menu {
            Picker(L10n.tr("share.format", lang: language), selection: $exportFormat) {
                ForEach(ShareExportFormat.allCases) { f in
                    Text(verbatim: L10n.tr(f == .jpeg ? "share.format.jpeg" : "share.format.png", lang: language))
                        .tag(f)
                }
            }
        } label: {
            Text(verbatim: L10n.tr(exportFormat == .jpeg ? "share.format.jpeg" : "share.format.png", lang: language))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.semantic(.quaternarySystemFill)))
        }
        #else
        Picker(L10n.tr("share.format", lang: language), selection: $exportFormat) {
            ForEach(ShareExportFormat.allCases) { f in
                Text(verbatim: L10n.tr(f == .jpeg ? "share.format.jpeg" : "share.format.png", lang: language))
                    .tag(f)
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
        #endif
    }

    /// 导出按钮组：macOS「保存图片」（NSSavePanel）；iOS「保存到相册」+ 系统分享单。
    private var exportButtons: some View {
        Group {
            #if os(macOS)
            Button(L10n.tr("share.saveImage", lang: language)) { saveImage() }
                .disabled(currentContent == nil)
            if let url = shareURL {
                ShareLink(item: url) {
                    Label(L10n.tr("share.openShareSheet", lang: language), systemImage: "square.and.arrow.up")
                }
            } else {
                Button(L10n.tr("share.openShareSheet", lang: language)) {}
                    .disabled(true)
            }
            #else
            // iOS 与样式设置同行排布，去图标 + 可收缩文本保证三语都单行放得下。
            Button {
                saveImageToAlbum()
            } label: {
                Text(verbatim: L10n.tr("share.saveToAlbum", lang: language))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .appStandardButton()
            .disabled(currentContent == nil)
            if let url = shareURL {
                // iOS 26 sheet 内嵌 ShareLink 静默失败，改用 UIKit 直接 present 系统分享单。
                Button {
                    presentShareSheet(url: url)
                } label: {
                    Text(verbatim: L10n.tr("share.openShareSheet", lang: language))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
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

    // MARK: - 渲染管线（预览降采样、导出全尺寸）

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

    /// 防抖重渲染（250ms）：勾选/改字过程中只出降采样小图，保持流畅。
    private func scheduleRerender() {
        renderTask?.cancel()
        renderTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            rerenderPreview()
        }
    }

    private func rerenderPreview() {
        guard let content = currentContent else {
            clearPreview()
            return
        }
        if let data = ShareCardRenderer.renderData(
            content: content, language: language,
            scale: ShareCardRenderer.previewScale, format: exportFormat.rendererFormat
        ) {
            applyRendered(data)
        } else {
            clearPreview()
        }
    }

    /// 全尺寸导出数据（保存/分享时才调用）。
    private func renderFullData() -> Data? {
        guard let content = currentContent else { return nil }
        return ShareCardRenderer.renderData(
            content: content, language: language, scale: 1, format: exportFormat.rendererFormat
        )
    }

    /// 导出文件基础名（游戏名/分组名，清理非法字符）。
    private var exportBaseName: String {
        let raw: String
        if mode == .groups, let group = selectedGroup {
            raw = group.name
        } else if selectedGames.count == 1, let first = selectedGames.first {
            raw = first.displayName(for: language)
        } else {
            raw = "overview"
        }
        let clean = raw
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        return clean.isEmpty ? "share" : clean
    }

    private func applyRendered(_ data: Data) {
        renderedData = data
        // 临时文件名唯一化，避免分享目标缓存陈旧内容。
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GameLog-share-\(UUID().uuidString.prefix(6)).\(exportFormat.fileExtension)")
        if (try? data.write(to: url)) != nil {
            shareURL = url
        } else {
            shareURL = nil
        }
    }

    private func clearPreview() {
        renderedData = nil
        shareURL = nil
    }

    private func saveImage() {
        #if os(macOS)
        guard let data = renderFullData() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [exportFormat == .jpeg ? .jpeg : .png]
        panel.nameFieldStringValue = "GameLog-\(exportBaseName)-\(size.rawValue).\(exportFormat.fileExtension)"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
        #endif
    }

    #if !os(macOS)
    /// iOS：把全尺寸渲染的图片存入系统相册（仅「添加」权限）。
    private func saveImageToAlbum() {
        guard let data = renderFullData(), let image = UIImage(data: data) else {
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

// MARK: - 分享样式设置（三分区：总览头部汇总 / 游戏格子字段 / 分组统计要素）

/// 要素池条目协议：供通用配置区渲染（Toggle + 上移/下移）。
protocol ShareConfigItem: Hashable, CaseIterable, Identifiable, RawRepresentable where RawValue == String, ID == String {}

extension OverviewHeaderStat: ShareConfigItem {}
extension GameTileField: ShareConfigItem {}
extension GroupStatItem: ShareConfigItem {}

/// 单个要素池的配置区：已启用（按用户顺序）→ 未启用（canonical 序），行内 Toggle + 排序箭头。
private struct ConfigSectionView<T: ShareConfigItem>: View {
    var label: (T) -> String
    @Binding var items: [T]

    var body: some View {
        let display = items + T.allCases.filter { !items.contains($0) }
        ForEach(display, id: \.self) { item in
            let index = items.firstIndex(of: item)
            HStack(spacing: 12) {
                Toggle(label(item), isOn: Binding(
                    get: { items.contains(item) },
                    set: { on in
                        if on {
                            items.append(item)
                        } else {
                            items.removeAll { $0 == item }
                        }
                    }
                ))
                .toggleStyle(.switch)
                Spacer()
                if let index, items.count > 1 {
                    Button {
                        move(index, by: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == 0)
                    Button {
                        move(index, by: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == items.count - 1)
                }
            }
        }
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard items.indices.contains(index), items.indices.contains(target) else { return }
        items.swapAt(index, target)
    }
}

private struct ShareStyleConfigurator: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguageCode) private var language
    /// 保存后回调（面板借此触发重渲染）。
    let onSave: () -> Void
    @State private var overviewStats: [OverviewHeaderStat]
    @State private var tileFields: [GameTileField]
    @State private var groupStats: [GroupStatItem]

    init(onSave: @escaping () -> Void) {
        self.onSave = onSave
        _overviewStats = State(initialValue: ShareOverviewStatsConfig.load())
        _tileFields = State(initialValue: ShareTileFieldsConfig.load())
        _groupStats = State(initialValue: ShareGroupStatsConfig.load())
    }

    var body: some View {
        NavigationStack {
            List {
                Section(L10n.tr("share.section.header", lang: language)) {
                    ConfigSectionView(label: { Self.headerLabel($0, language: language) }, items: $overviewStats)
                }
                Section(L10n.tr("share.section.tiles", lang: language)) {
                    ConfigSectionView(label: { Self.tileLabel($0, language: language) }, items: $tileFields)
                }
                Section(L10n.tr("share.section.group", lang: language)) {
                    ConfigSectionView(label: { Self.groupLabel($0, language: language) }, items: $groupStats)
                }
            }
            .navigationTitle(L10n.tr("share.styleSettings", lang: language))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.tr("common.done", lang: language)) {
                        ShareOverviewStatsConfig.save(overviewStats)
                        ShareTileFieldsConfig.save(tileFields)
                        ShareGroupStatsConfig.save(groupStats)
                        onSave()
                        dismiss()
                    }
                }
                #if os(iOS)
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("common.cancel", lang: language)) { dismiss() }
                }
                #endif
            }
        }
        // 固定尺寸仅 macOS;iPhone 屏宽 393pt,460pt frame 会把标题/取消/完成裁出屏外。
        #if os(macOS)
        .frame(width: 460, height: 620)
        #endif
    }

    private static func headerLabel(_ item: OverviewHeaderStat, language: String) -> String {
        switch item {
        case .gameCount: return L10n.tr("share.header.gameCount", lang: language)
        case .averageScore: return L10n.tr("group.avgScore", lang: language)
        case .completionCount: return L10n.tr("stats.totalGames", lang: language)
        case .collectionValue: return L10n.tr("share.stat.collectionValue", lang: language)
        }
    }

    private static func tileLabel(_ item: GameTileField, language: String) -> String {
        switch item {
        case .platform: return L10n.tr("completion.platform", lang: language)
        case .score: return L10n.tr("share.field.score", lang: language)
        case .date: return L10n.tr("share.field.date", lang: language)
        case .releaseYear: return L10n.tr("share.field.releaseYear", lang: language)
        case .status: return L10n.tr("share.field.status", lang: language)
        }
    }

    private static func groupLabel(_ item: GroupStatItem, language: String) -> String {
        switch item {
        case .averageScore: return L10n.tr("group.avgScore", lang: language)
        case .gameCount: return L10n.tr("group.gameCount", lang: language)
        case .completionCount: return L10n.tr("group.completionCount", lang: language)
        case .topGame: return L10n.tr("share.stat.topGame", lang: language)
        case .collectionValue: return L10n.tr("share.stat.collectionValue", lang: language)
        }
    }
}
