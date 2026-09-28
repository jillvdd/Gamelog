import SwiftUI
import SwiftData

#if os(macOS)
import AppKit
#else
import Photos
#endif

/// 分享面板左栏模式：按游戏 / 按分组 / 全库统计卡。
private enum ShareMode: String, CaseIterable {
    case games
    case groups
    case stats
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

/// 移动端分流标签：效果预览 vs 挑选游戏。
private enum CompactShareTab: Int, CaseIterable {
    case preview = 0
    case select = 1
}

/// 按钮位置 PreferenceKey，供 iPadOS 系统分享 Popover 精准锚定。
private struct ShareButtonRectKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let n = nextValue()
        if n != .zero { value = n }
    }
}

/// 分享面板：
/// - macOS / iPadOS 宽屏下展现双栏大屏工作台；
/// - iPhone 紧凑屏展现单列自适应流；
/// - 支持 4 种尺寸（9:16 / 16:9 / 1:1 / 4:5）、双质感主题、总览排序、快速过滤与批量选择。
struct SharePanelView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguageCode) private var language
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @Query(sort: \Game.createdAt) private var games: [Game]
    @Query(sort: \GameGroup.name) private var groups: [GameGroup]
    var preselected: [Game] = []

    @State private var mode: ShareMode = .games
    @State private var compactTab: CompactShareTab = .preview
    /// 真实点击顺序的选择数组（梯1.3：`.selection` 排序按此顺序出图，不再是入库序）。
    @State private var selectionOrder: [PersistentIdentifier] = []
    @State private var selectedGroupID: PersistentIdentifier?
    @State private var searchText = ""
    @State private var platformFilter: String? = nil
    // 梯1.2：画幅/主题/格式/排序跨会话记忆上次使用。
    @AppStorage(UserCustomization.shareLastSizeKey) private var size: ShareSize = .phone
    @AppStorage(UserCustomization.shareLastThemeKey) private var themeMode: ShareThemeMode = .brandDark
    @AppStorage(UserCustomization.shareLastFormatKey) private var exportFormat: ShareExportFormat = .jpeg
    @AppStorage(UserCustomization.shareLastQualityKey) private var exportQuality: ShareQuality = .uhd
    @AppStorage(UserCustomization.shareLastSortKey) private var sortOption: ShareSortOption = .selection
    // 梯3.11：出图语言与 app 语言解耦（默认跟随）。
    @AppStorage(UserCustomization.shareLanguageFollowKey) private var languageFollow = true
    @AppStorage(UserCustomization.shareLanguageKey) private var languageOverride = ""
    @State private var overviewTitle = ""
    @State private var groupTitle = ""
    @State private var renderedData: Data?
    @State private var shareURL: URL?
    @State private var renderTask: Task<Void, Never>?
    @State private var saveMessage: String?
    @State private var showingStyleEditor = false
    /// 统计要素配置变更代际：编辑器保存后 +1 触发分组卡重渲染。
    @State private var statsRevision = 0
    #if !os(macOS)
    @State private var showingFullscreenPreview = false
    @State private var shareButtonRect: CGRect = .zero
    #endif
    @AppStorage(UserCustomization.usernameKey) private var username = ""

    private var isRegularScreen: Bool {
        #if os(macOS)
        return true
        #else
        return horizontalSizeClass == .regular
        #endif
    }

    private var liveGames: [Game] { games.filter(\.isLive) }
    private var liveGroups: [GameGroup] { groups.filter(\.isLive) }

    private var allPlatforms: [String] {
        Array(Set(liveGames.flatMap(\.platformList))).sorted()
    }

    private var visibleGames: [Game] {
        searchText.isEmpty ? liveGames : liveGames.filter { $0.matches(search: searchText) }
    }

    private var filteredGames: [Game] {
        var list = visibleGames
        if let platformFilter {
            if platformFilter == "completed" {
                list = list.filter(\.isCompletedOrLongRunning)
            } else {
                list = list.filter { $0.platformList.contains(platformFilter) }
            }
        }
        return list
    }

    private var selectedGames: [Game] {
        let byID = Dictionary(liveGames.map { ($0.persistentModelID, $0) }, uniquingKeysWith: { first, _ in first })
        let raw = selectionOrder.compactMap { byID[$0] }
        return sortOption.sort(games: raw, language: renderLanguage)
    }

    private var selectedGroup: GameGroup? {
        guard let selectedGroupID else { return nil }
        return liveGroups.first { $0.persistentModelID == selectedGroupID }
    }

    private var isMulti: Bool { selectedGames.count > 1 }
    private var isSingleShare: Bool { preselected.count == 1 && mode == .games }

    /// 出图语言：跟随模式用 app 语言，否则用独立选择（梯3.11）。
    private var renderLanguage: String {
        languageFollow || languageOverride.isEmpty ? language : languageOverride
    }

    /// 主题求值：封面取色主题按当前内容封面派生（梯2.8）。
    private var gamesForTheme: [Game] {
        switch mode {
        case .games: return selectedGames
        case .groups: return selectedGroup?.games ?? []
        case .stats: return Array(liveGames.prefix(4))
        }
    }

    private var resolvedTheme: ShareTheme { themeMode.resolvedTheme(for: gamesForTheme) }

    /// 统计摘要卡内容（梯3.10，全部走 LibraryStats 同源口径）。
    private var statsContent: ShareStatsContent {
        let pool = liveGames
        var statusCounts: [GameStatus: Int] = [:]
        for game in pool { statusCounts[game.statusValue, default: 0] += 1 }
        let statusRows = GameStatus.allCases.compactMap { status -> ShareStatsContent.StatusRow? in
            guard let count = statusCounts[status], count > 0 else { return nil }
            return ShareStatsContent.StatusRow(status: status, count: count)
        }
        let topGames = pool.compactMap { game -> ShareStatsContent.TopGame? in
            guard let score = game.libraryScore else { return nil }
            return ShareStatsContent.TopGame(name: game.displayName(for: renderLanguage), score: score)
        }
        .sorted { $0.score > $1.score }
        .prefix(3)
        let achievements = LibraryStats.unifiedAchievements(pool)
        let collector = LibraryStats.collectorTotals(pool.flatMap(\.copies), language: renderLanguage)
        return ShareStatsContent(
            title: defaultOverviewTitle(),
            totalGames: pool.count,
            clearedGames: LibraryStats.clearedGameCount(pool),
            totalPlaytime: LibraryStats.totalPlaytimeHours(pool),
            averageScore: LibraryStats.averageScore(pool),
            statusRows: statusRows,
            topGames: Array(topGames),
            platinumCount: achievements.platinumCount,
            xboxGamerscore: achievements.xboxGamerscore,
            spentTotal: collector.totalSpent,
            estimateTotal: collector.totalEstimate
        )
    }

    /// 当前预览对应的内容；无有效选择则 nil。
    private var currentContent: ShareCardContent? {
        switch mode {
        case .games:
            let selected = selectedGames
            guard !selected.isEmpty else { return nil }
            if selected.count == 1 {
                return .single(selected[0], size: size)
            }
            let title = overviewTitle.trimmingCharacters(in: .whitespaces).isEmpty
                ? defaultOverviewTitle()
                : overviewTitle
            return .overview(selected, title: title, size: size)
        case .groups:
            guard let group = selectedGroup else { return nil }
            let title = groupTitle.trimmingCharacters(in: .whitespaces).isEmpty ? group.name : groupTitle
            return .group(group, title: title, size: size)
        case .stats:
            return .stats(statsContent, size: size)
        }
    }

    /// 大选择护栏（梯1.4）：超限自动降倍率时明确提示，不再无声出糊图。
    private var downscaleWarning: String? {
        guard mode == .games, selectedGames.count > 9, let content = currentContent else { return nil }
        let eff = ShareCardRenderer.effectiveScale(canvas: content.canvasSize, scale: exportQuality.scale)
        guard eff < 0.9 * exportQuality.scale else { return nil }
        return L10n.tr("share.downscaleWarning", [selectedGames.count], lang: language)
    }

    /// 分组标题绑定：写入时截断到分享标题上限。
    private var groupTitleBinding: Binding<String> {
        Binding(
            get: { groupTitle },
            set: { groupTitle = UserCustomization.truncateShareTitle($0) }
        )
    }

    /// 总览标题绑定：写入时截断到分享标题上限。
    private var overviewTitleBinding: Binding<String> {
        Binding(
            get: { overviewTitle },
            set: { overviewTitle = UserCustomization.truncateShareTitle($0) }
        )
    }

    var body: some View {
        Group {
            if isRegularScreen {
                regularSplitLayout
            } else {
                compactShareBody
            }
        }
        .onAppear(perform: setup)
        .onChange(of: mode) { _, _ in scheduleRerender() }
        .onChange(of: selectionOrder) { _, _ in
            scheduleRerender()
        }
        .onChange(of: selectedGroupID) { _, _ in scheduleRerender() }
        .onChange(of: size) { _, _ in scheduleRerender() }
        .onChange(of: themeMode) { _, _ in scheduleRerender() }
        .onChange(of: sortOption) { _, _ in scheduleRerender() }
        .onChange(of: overviewTitle) { _, _ in scheduleRerender() }
        .onChange(of: groupTitle) { _, _ in scheduleRerender() }
        .onChange(of: language) { _, _ in scheduleRerender() }
        .onChange(of: languageFollow) { _, _ in scheduleRerender() }
        .onChange(of: languageOverride) { _, _ in scheduleRerender() }
        .onChange(of: games) { _, newGames in
            if selectionOrder.isEmpty && CommandLine.arguments.contains("-ShareSelectTop") {
                let top = Array(newGames.filter(\.isLive).prefix(6))
                selectionOrder = top.map(\.persistentModelID)
            }
        }
        .onChange(of: exportFormat) { _, _ in scheduleRerender() }
        .onChange(of: exportQuality) { _, _ in scheduleRerender() }
        .onChange(of: statsRevision) { _, _ in scheduleRerender() }
        .sheet(isPresented: $showingStyleEditor) {
            ShareStyleConfigurator { statsRevision += 1 }
        }
        .onDisappear { renderTask?.cancel() }
        #if !os(macOS)
        .onPreferenceChange(ShareButtonRectKey.self) { shareButtonRect = $0 }
        #endif
    }


    // MARK: - 大屏双栏工作台布局 (macOS / iPadOS regular)

    private var regularSplitLayout: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                selectionList
                    .frame(width: 310)
                Divider()
                VStack(spacing: 0) {
                    previewColumn
                    Divider()
                    regularControls
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 920, minHeight: 700)
        #endif
    }

    // MARK: - 移动端紧凑布局 (iPhone / compact)

    @ViewBuilder
    private var compactShareBody: some View {
        if isSingleShare || mode == .stats {
            compactSingleLayout
        } else {
            compactOverviewLayout
        }
    }

    /// 单游戏分享专属纯净流：居中沉浸式大预览，无任何多余列表与检索噪音
    private var compactSingleLayout: some View {
        VStack(spacing: 0) {
            HStack {
                if mode == .stats {
                    Text(verbatim: L10n.tr("share.mode.stats", lang: language))
                        .font(.headline)
                        .lineLimit(1)
                } else if !preselected.isEmpty, let game = preselected.first {
                    Text(verbatim: game.displayName(for: language))
                        .font(.headline)
                        .lineLimit(1)
                } else if mode == .groups {
                    LText("share.byGroups")
                        .font(.headline)
                        .lineLimit(1)
                } else {
                    LText("share.preview")
                        .font(.headline)
                }
                Spacer()
                if preselected.isEmpty {
                    // 从库面板进入（统计/分组单卡流）：保留模式切换胶囊可切回。
                    modeSegment
                        .frame(width: 196)
                }
                closeButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            previewColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    sizePillsRow
                    Spacer(minLength: 0)
                    themePillToggle
                    styleSettingsMenuButton
                }

                #if os(macOS)
                exportButtons
                #else
                compactActionButtons
                #endif

                if let downscaleWarning {
                    Text(verbatim: downscaleWarning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if let saveMessage {
                    Text(verbatim: saveMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
    }

    /// 多游戏总览分享：分流「效果预览」与「挑选游戏」双 Tab
    private var compactOverviewLayout: some View {
        VStack(spacing: 0) {
            compactOverviewHeader
            Divider()

            if compactTab == .preview {
                compactOverviewPreviewTab
            } else {
                compactOverviewSelectionTab
            }
        }
    }

    private var compactOverviewHeader: some View {
        HStack(spacing: 12) {
            SegmentSlider(
                titles: [
                    L10n.tr("share.tab.preview", lang: language),
                    overviewSelectTabTitle
                ],
                selection: Binding(
                    get: { compactTab.rawValue },
                    set: {
                        compactTab = CompactShareTab(rawValue: $0) ?? .preview
                        triggerSelectionHaptic()
                    }
                )
            )
            .frame(maxWidth: .infinity)

            closeButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var overviewSelectTabTitle: String {
        let count = mode == .groups ? (selectedGroup != nil ? 1 : 0) : selectionOrder.count
        if count == 0 {
            return L10n.tr("share.tab.select", lang: language)
        } else {
            return L10n.tr("share.tab.selectWithCount", [count], lang: language)
        }
    }

    /// 效果预览 Tab：聚焦大图与画幅/主题调整，带快速跳回挑选的指示胶囊
    private var compactOverviewPreviewTab: some View {
        VStack(spacing: 0) {
            previewColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            VStack(spacing: 10) {
                Button {
                    compactTab = .select
                    triggerSelectionHaptic()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: mode == .groups ? "folder.fill" : "checkmark.circle.fill")
                            .font(.system(size: 11))
                        Text(verbatim: jumpToSelectionLinkText)
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                }
                .buttonStyle(.plain)

                if mode == .groups {
                    BorderedTextField(text: groupTitleBinding, placeholder: L10n.tr("share.groupTitle", lang: language))
                } else if isMulti {
                    BorderedTextField(text: overviewTitleBinding, placeholder: L10n.tr("share.overviewTitle", lang: language))
                }

                HStack(spacing: 8) {
                    sizePillsRow
                    Spacer(minLength: 0)
                    themePillToggle
                    styleSettingsMenuButton
                }

                #if os(macOS)
                exportButtons
                #else
                compactActionButtons
                #endif

                if let downscaleWarning {
                    Text(verbatim: downscaleWarning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if let saveMessage {
                    Text(verbatim: saveMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
    }

    private var jumpToSelectionLinkText: String {
        if mode == .groups {
            if let group = selectedGroup {
                return "\(group.name) (\(group.games.count))"
            } else {
                return L10n.tr("share.noneSelectedGroup", lang: language)
            }
        } else {
            return L10n.tr("share.selectedCountLink", [selectionOrder.count], lang: language)
        }
    }

    /// 挑选游戏 Tab：专属全屏高度流畅列表与完整过滤
    private var compactOverviewSelectionTab: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    if !liveGroups.isEmpty {
                        modeSegment
                            .frame(width: 156)
                    }
                    searchField
                }
                if mode == .games {
                    filterChips
                    listToolbar
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Divider()

            gameGroupList
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Text(verbatim: selectionCountFooterText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Button {
                    compactTab = .preview
                    triggerSelectionHaptic()
                } label: {
                    HStack(spacing: 5) {
                        Text(verbatim: L10n.tr("share.viewPreview", lang: language))
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.accentColor)
                    .foregroundStyle(Color.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(PressFeedbackButtonStyle(pressedOpacity: 0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.thinMaterial)
            .overlay(Divider(), alignment: .top)
        }
    }

    private var selectionCountFooterText: String {
        if mode == .groups {
            if let group = selectedGroup {
                return "\(group.name) (\(group.games.count))"
            } else {
                return L10n.tr("share.noneSelectedGroup", lang: language)
            }
        } else {
            return L10n.tr("share.selectedCount", [selectionOrder.count], lang: language)
        }
    }

    // MARK: - 扁平微胶囊控制组件

    private var sizePillsRow: some View {
        HStack(spacing: 4) {
            ForEach([ShareSize.phone, .portrait, .square, .desktop]) { s in
                sizePillButton(s)
            }
        }
    }

    private func sizePillButton(_ s: ShareSize) -> some View {
        Button {
            size = s
            triggerSelectionHaptic()
        } label: {
            Text(verbatim: sizeShortTitle(s))
                .font(.system(size: 11, weight: size == s ? .semibold : .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(size == s ? Color.accentColor : Color.semantic(.quaternarySystemFill))
                )
                .foregroundStyle(size == s ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func sizeShortTitle(_ s: ShareSize) -> String {
        switch s {
        case .phone: return L10n.tr("share.size.short.phone", lang: language)
        case .portrait: return L10n.tr("share.size.short.portrait", lang: language)
        case .square: return L10n.tr("share.size.short.square", lang: language)
        case .desktop: return L10n.tr("share.size.short.desktop", lang: language)
        }
    }

    private var themePillToggle: some View {
        Button {
            let all = ShareThemeMode.allCases
            themeMode = all[(all.firstIndex(of: themeMode)! + 1) % all.count]
            triggerSelectionHaptic()
        } label: {
            // 占位隐藏的最宽候选：胶囊宽度恒定，点选后不带动同排按钮位移（2026-09-21 用户反馈）。
            ZStack {
                ForEach(ShareThemeMode.allCases) { t in
                    HStack(spacing: 4) {
                        Image(systemName: themeIcon(t))
                            .font(.system(size: 11))
                        Text(verbatim: themeShortTitle(t))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .hidden()
                }
                HStack(spacing: 4) {
                    Image(systemName: themeIcon(themeMode))
                        .font(.system(size: 11))
                        .foregroundStyle(themeIconColor(themeMode))
                    Text(verbatim: themeShortTitle(themeMode))
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.semantic(.quaternarySystemFill)))
        }
        .buttonStyle(.plain)
    }

    private func themeIcon(_ t: ShareThemeMode) -> String {
        switch t {
        case .brandDark: return "moon.stars.fill"
        case .editorialLight: return "sun.max.fill"
        case .coverTint: return "paintpalette.fill"
        }
    }

    private func themeIconColor(_ t: ShareThemeMode) -> Color {
        switch t {
        case .brandDark: return Color.orange
        case .editorialLight: return Color.yellow
        case .coverTint: return Color.pink
        }
    }

    private func themeShortTitle(_ t: ShareThemeMode) -> String {
        switch t {
        case .brandDark: return L10n.tr("share.theme.short.dark", lang: language)
        case .editorialLight: return L10n.tr("share.theme.short.light", lang: language)
        case .coverTint: return L10n.tr("share.theme.short.cover", lang: language)
        }
    }

    private var styleSettingsMenuButton: some View {
        Menu {
            Section(L10n.tr("share.format", lang: language)) {
                Picker(L10n.tr("share.format", lang: language), selection: $exportFormat) {
                    ForEach(ShareExportFormat.allCases) { f in
                        Text(verbatim: L10n.tr(f == .jpeg ? "share.format.jpeg" : "share.format.png", lang: language))
                            .tag(f)
                    }
                }
            }
            Section(L10n.tr("share.quality", lang: language)) {
                Picker(L10n.tr("share.quality", lang: language), selection: $exportQuality) {
                    Text(verbatim: "FHD").tag(ShareQuality.fhd)
                    Text(verbatim: "UHD").tag(ShareQuality.uhd)
                }
            }
            Section(L10n.tr("share.language", lang: language)) {
                Picker(L10n.tr("share.language", lang: language), selection: shareLanguageSelection) {
                    Text(verbatim: L10n.tr("share.language.follow", lang: language)).tag("")
                    ForEach(AppLanguage.allCases) { lang in
                        Text(verbatim: lang.displayName).tag(lang.localeCode)
                    }
                }
            }
            Section {
                Button {
                    showingStyleEditor = true
                } label: {
                    Label(L10n.tr("share.styleSettings", lang: language), systemImage: "slider.horizontal.3")
                }
            }
            if showGrid9Action {
                Section {
                    Button {
                        exportGrid9()
                    } label: {
                        Label(L10n.tr("share.grid9.action", lang: language), systemImage: "square.grid.3x3.fill")
                    }
                    #if !os(macOS)
                    Button {
                        saveGrid9ToAlbum()
                    } label: {
                        Label(L10n.tr("share.grid9.save", lang: language), systemImage: "arrow.down.to.line")
                    }
                    #endif
                }
            }
        } label: {
            // 占位隐藏 JPEG/PNG 两态：切格式时胶囊宽度恒定（同 themePillToggle 的纪律）。
            ZStack {
                HStack(spacing: 3) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                    Text(verbatim: "JPEG")
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                }
                .hidden()
                HStack(spacing: 3) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                    Text(verbatim: exportFormat == .jpeg ? "JPEG" : "PNG")
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.semantic(.quaternarySystemFill)))
        }
        .buttonStyle(.plain)
    }

    #if !os(macOS)
    private var compactActionButtons: some View {
        HStack(spacing: 12) {
            Button {
                saveImageToAlbum()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 13, weight: .medium))
                    Text(verbatim: L10n.tr("share.saveToAlbum", lang: language))
                        .font(.system(size: 14, weight: .medium))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.semantic(.controlBackground))
                .foregroundStyle(Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(PressFeedbackButtonStyle(pressedOpacity: 0.7))
            .disabled(currentContent == nil)

            if let url = shareURL {
                Button {
                    presentShareSheet(url: url, sourceRect: shareButtonRect)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .semibold))
                        Text(verbatim: L10n.tr("share.shareAction", lang: language))
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.accentColor)
                    .foregroundStyle(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(PressFeedbackButtonStyle(pressedOpacity: 0.7))
                .background(GeometryReader { geo in
                    Color.clear.preference(key: ShareButtonRectKey.self, value: geo.frame(in: .global))
                })
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                    Text(verbatim: L10n.tr("share.shareAction", lang: language))
                        .font(.system(size: 14, weight: .semibold))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.accentColor.opacity(0.35))
                .foregroundStyle(Color.white.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
    #endif

    // MARK: - 头部组件

    @ViewBuilder
    private var header: some View {
        HStack {
            LText("share.selectGames")
                .font(.headline)
            Spacer()
            closeButton
        }
        .padding(.horizontal, 20)
        .padding(.top, isRegularScreen ? 16 : 20)
        .padding(.bottom, 12)
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 20))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(L10n.tr("common.close", lang: language))
    }

    // MARK: - 左栏组件

    private var selectionList: some View {
        VStack(spacing: 0) {
            modeSegment
                .padding(10)
            if mode != .stats {
                searchField
                    .padding([.horizontal, .bottom], 10)
                if mode == .games {
                    filterChips
                    listToolbar
                }
            }
            gameGroupList
        }
    }

    private var modeSegment: some View {
        SegmentSlider(
            titles: ShareMode.allCases.map { mode in
                switch mode {
                case .games: return L10n.tr("share.byGames", lang: language)
                case .groups: return L10n.tr("share.byGroups", lang: language)
                case .stats: return L10n.tr("share.mode.stats", lang: language)
                }
            },
            selection: Binding(
                get: { ShareMode.allCases.firstIndex(of: mode) ?? 0 },
                set: {
                    mode = ShareMode.allCases[$0]
                    triggerSelectionHaptic()
                }
            )
        )
    }

    private var searchField: some View {
        BorderedTextField(text: $searchText, placeholder: L10n.tr("library.search", lang: language))
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterChip(title: L10n.tr("share.filter.all", lang: language), isSelected: platformFilter == nil) {
                    platformFilter = nil
                    triggerSelectionHaptic()
                }
                filterChip(title: L10n.tr("share.filter.completed", lang: language), isSelected: platformFilter == "completed") {
                    platformFilter = platformFilter == "completed" ? nil : "completed"
                    triggerSelectionHaptic()
                }
                ForEach(allPlatforms, id: \.self) { plat in
                    filterChip(
                        title: Presets.display(plat, category: .platform, language: language),
                        isSelected: platformFilter == plat
                    ) {
                        platformFilter = platformFilter == plat ? nil : plat
                        triggerSelectionHaptic()
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
    }

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor.opacity(0.2) : Color.semantic(.quaternarySystemFill))
                )
                .overlay(
                    Capsule().stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
                )
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private var listToolbar: some View {
        HStack(spacing: 6) {
            Menu {
                Picker(L10n.tr("share.sort", lang: language), selection: $sortOption) {
                    ForEach(ShareSortOption.allCases) { opt in
                        Text(verbatim: sortTitle(opt)).tag(opt)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 10))
                    Text(verbatim: sortTitle(sortOption))
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.semantic(.quaternarySystemFill)))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button {
                selectAllFiltered()
            } label: {
                Text(verbatim: L10n.tr("share.selectAll", lang: language))
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)

            Button {
                deselectAll()
            } label: {
                Text(verbatim: L10n.tr("share.deselectAll", lang: language))
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .disabled(selectionOrder.isEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private var styleSettingsButton: some View {
        Button {
            showingStyleEditor = true
        } label: {
            #if os(macOS)
            Label(L10n.tr("share.styleSettings", lang: language), systemImage: "slider.horizontal.3")
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

    private var gameGroupList: some View {
        List {
            if mode == .stats {
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "chart.bar.doc.horizontal")
                            .font(.system(size: 34))
                            .foregroundStyle(.secondary)
                        Text(verbatim: L10n.tr("share.mode.stats.hint", lang: language))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 60)
                    Spacer()
                }
                .listRowSeparator(.hidden)
            } else if mode == .games {
                ForEach(filteredGames) { game in
                    Button {
                        toggle(game)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: selectionOrder.contains(game.persistentModelID) ? "checkmark.square.fill" : "square")
                                .foregroundStyle(selectionOrder.contains(game.persistentModelID) ? Color.accentColor : Color.secondary)
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
                ForEach(liveGroups) { group in
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

    private static let coverThumbSize = CGSize(width: 26, height: 34)
    private static var coverThumbAspect: CGFloat { coverThumbSize.width / coverThumbSize.height }

    private func coverThumb(_ game: Game) -> some View {
        Group {
            if let image = game.coverImage {
                Image(appImage: image).resizable()
                    .aspectRatio(contentMode: image.letterboxes(inBoxAspect: Self.coverThumbAspect) ? .fit : .fill)
            } else {
                ZStack {
                    Rectangle().fill(Color.semantic(.quaternarySystemFill))
                    Image(systemName: "gamecontroller").font(.system(size: 8)).foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: Self.coverThumbSize.width, height: Self.coverThumbSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func toggle(_ game: Game) {
        triggerSelectionHaptic()
        if let idx = selectionOrder.firstIndex(of: game.persistentModelID) {
            selectionOrder.remove(at: idx)
        } else {
            selectionOrder.append(game.persistentModelID)
        }
    }

    private func toggleGroup(_ group: GameGroup) {
        triggerSelectionHaptic()
        if selectedGroupID == group.persistentModelID {
            selectedGroupID = nil
        } else {
            selectedGroupID = group.persistentModelID
            groupTitle = UserCustomization.truncateShareTitle(group.name)
        }
    }

    private func selectAllFiltered() {
        triggerSelectionHaptic()
        if mode == .games {
            for game in filteredGames where !selectionOrder.contains(game.persistentModelID) {
                selectionOrder.append(game.persistentModelID)
            }
        }
    }

    private func deselectAll() {
        triggerSelectionHaptic()
        if mode == .games {
            selectionOrder.removeAll()
        } else {
            selectedGroupID = nil
            groupTitle = ""  // 清空旧标题，防止换选分组时带入上一个分组的自定义标题
        }
    }

    // MARK: - 预览工作台

    private var previewColumn: some View {
        VStack(spacing: 0) {
            if let data = renderedData, let image = AppImage(data: data) {
                Image(appImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 3)
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(BrandPalette.background)
                    #if !os(macOS)
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(BrandPalette.background)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if !os(macOS)
        .fullScreenCover(isPresented: $showingFullscreenPreview) {
            fullscreenViewer
        }
        #endif
    }

    #if !os(macOS)
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

    // MARK: - 控制栏组件

    private var regularControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                sizePicker
                themePicker
                formatPicker
                languageMenuButton
                styleSettingsButton
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                if mode == .groups {
                    BorderedTextField(text: groupTitleBinding, placeholder: L10n.tr("share.groupTitle", lang: language))
                } else if isMulti {
                    BorderedTextField(text: overviewTitleBinding, placeholder: L10n.tr("share.overviewTitle", lang: language))
                }
                Spacer(minLength: 0)
                if showGrid9Action {
                    Button {
                        exportGrid9()
                    } label: {
                        Text(verbatim: L10n.tr("share.grid9.action", lang: language))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .appStandardButton()
                }
                exportButtons
            }
            if let downscaleWarning {
                Text(verbatim: downscaleWarning)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let saveMessage {
                Text(verbatim: saveMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var languageMenuButton: some View {
        Menu {
            Picker(L10n.tr("share.language", lang: language), selection: shareLanguageSelection) {
                Text(verbatim: L10n.tr("share.language.follow", lang: language)).tag("")
                ForEach(AppLanguage.allCases) { lang in
                    Text(verbatim: lang.displayName).tag(lang.localeCode)
                }
            }
        } label: {
            ZStack {
                ForEach([L10n.tr("share.language.follow", lang: language)] + AppLanguage.allCases.map(\.displayName), id: \.self) { label in
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .font(.system(size: 11))
                        Text(verbatim: label)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .hidden()
                }
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                        .font(.system(size: 11))
                    Text(verbatim: renderLanguageLabel)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.semantic(.quaternarySystemFill)))
        }
        .buttonStyle(.plain)
    }

    private var renderLanguageLabel: String {
        if languageFollow || languageOverride.isEmpty {
            return L10n.tr("share.language.follow", lang: language)
        }
        return AppLanguage(localeCode: languageOverride).displayName
    }

    /// 出图语言选择绑定：空串 = 跟随 app 语言。
    private var shareLanguageSelection: Binding<String> {
        Binding(
            get: { languageFollow ? "" : languageOverride },
            set: { newValue in
                if newValue.isEmpty {
                    languageFollow = true
                    languageOverride = ""
                } else {
                    languageFollow = false
                    languageOverride = newValue
                }
            }
        )
    }

    private var sizePicker: some View {
        Menu {
            Picker(L10n.tr("share.size", lang: language), selection: $size) {
                ForEach(ShareSize.allCases) { s in
                    Text(verbatim: sizeTitle(s)).tag(s)
                }
            }
        } label: {
            // 候选最宽占位：点选后胶囊宽度恒定，同排控件不位移。
            ZStack {
                ForEach(ShareSize.allCases) { s in
                    HStack(spacing: 4) {
                        Image(systemName: sizeIcon(s))
                            .font(.system(size: 11))
                        Text(verbatim: sizeTitle(s))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .hidden()
                }
                HStack(spacing: 4) {
                    Image(systemName: sizeIcon(size))
                        .font(.system(size: 11))
                    Text(verbatim: sizeTitle(size))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.semantic(.quaternarySystemFill)))
        }
        .buttonStyle(.plain)
    }

    private var themePicker: some View {
        Menu {
            Picker(L10n.tr("share.theme", lang: language), selection: $themeMode) {
                ForEach(ShareThemeMode.allCases) { tm in
                    Text(verbatim: themeTitle(tm)).tag(tm)
                }
            }
        } label: {
            ZStack {
                ForEach(ShareThemeMode.allCases) { t in
                    HStack(spacing: 4) {
                        Image(systemName: themeIcon(t))
                            .font(.system(size: 11))
                        Text(verbatim: themeTitle(t))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .hidden()
                }
                HStack(spacing: 4) {
                    Image(systemName: themeIcon(themeMode))
                        .font(.system(size: 11))
                        .foregroundStyle(themeIconColor(themeMode))
                    Text(verbatim: themeTitle(themeMode))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.semantic(.quaternarySystemFill)))
        }
        .buttonStyle(.plain)
    }

    private var formatPicker: some View {
        Menu {
            Picker(L10n.tr("share.format", lang: language), selection: $exportFormat) {
                ForEach(ShareExportFormat.allCases) { f in
                    Text(verbatim: L10n.tr(f == .jpeg ? "share.format.jpeg" : "share.format.png", lang: language))
                        .tag(f)
                }
            }
            Picker(L10n.tr("share.quality", lang: language), selection: $exportQuality) {
                Text(verbatim: "FHD").tag(ShareQuality.fhd)
                Text(verbatim: "UHD").tag(ShareQuality.uhd)
            }
        } label: {
            ZStack {
                Text(verbatim: L10n.tr("share.format.jpeg", lang: language))
                    .hidden()
                Text(verbatim: L10n.tr("share.format.png", lang: language))
                    .hidden()
                Text(verbatim: L10n.tr(exportFormat == .jpeg ? "share.format.jpeg" : "share.format.png", lang: language))
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.semantic(.quaternarySystemFill)))
        }
        .buttonStyle(.plain)
    }

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
                Button {
                    presentShareSheet(url: url, sourceRect: shareButtonRect)
                } label: {
                    Text(verbatim: L10n.tr("share.openShareSheet", lang: language))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .appStandardButton()
                .background(GeometryReader { geo in
                    Color.clear.preference(key: ShareButtonRectKey.self, value: geo.frame(in: .global))
                })
            } else {
                Button(L10n.tr("share.openShareSheet", lang: language)) {}
                    .appStandardButton()
                    .disabled(true)
            }
            #endif
        }
    }

    // MARK: - 文案与图标助手

    private func sizeTitle(_ s: ShareSize) -> String {
        switch s {
        case .phone: return L10n.tr("share.phone", lang: language)
        case .desktop: return L10n.tr("share.desktop", lang: language)
        case .square: return L10n.tr("share.square", lang: language)
        case .portrait: return L10n.tr("share.portrait", lang: language)
        }
    }

    private func sizeIcon(_ s: ShareSize) -> String {
        switch s {
        case .phone: return "iphone"
        case .desktop: return "display"
        case .square: return "square"
        case .portrait: return "rectangle.portrait"
        }
    }

    private func themeTitle(_ t: ShareThemeMode) -> String {
        switch t {
        case .brandDark: return L10n.tr("share.theme.brandDark", lang: language)
        case .editorialLight: return L10n.tr("share.theme.editorialLight", lang: language)
        case .coverTint: return L10n.tr("share.theme.coverTint", lang: language)
        }
    }

    private func sortTitle(_ s: ShareSortOption) -> String {
        switch s {
        case .selection: return L10n.tr("share.sort.default", lang: language)
        case .score: return L10n.tr("share.sort.score", lang: language)
        case .date: return L10n.tr("share.sort.date", lang: language)
        case .releaseYear: return L10n.tr("share.sort.releaseYear", lang: language)
        case .title: return L10n.tr("share.sort.title", lang: language)
        }
    }

    private func triggerSelectionHaptic() {
        #if !os(macOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    private func triggerSuccessHaptic() {
        #if !os(macOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    // MARK: - 渲染管线（预览降采样、导出全尺寸）

    private func setup() {
        if !preselected.isEmpty {
            selectionOrder = preselected.map(\.persistentModelID)
        } else if CommandLine.arguments.contains("-ShareSelectTop") {
            let topGames = Array(liveGames.prefix(6))
            selectionOrder = topGames.map(\.persistentModelID)
        }
        if let idx = CommandLine.arguments.firstIndex(of: "-ShareSize"), idx + 1 < CommandLine.arguments.count {
            let val = CommandLine.arguments[idx + 1]
            if let matched = ShareSize.allCases.first(where: { $0.rawValue == val }) {
                size = matched
            }
        }
        if let idx = CommandLine.arguments.firstIndex(of: "-ShareTheme"), idx + 1 < CommandLine.arguments.count {
            let val = CommandLine.arguments[idx + 1]
            if let matched = ShareThemeMode.allCases.first(where: { $0.rawValue == val }) {
                themeMode = matched
            }
        }
        if CommandLine.arguments.contains("-ShareTabSelect") {
            compactTab = .select
        }
        overviewTitle = defaultOverviewTitle()
        scheduleRerender()

        Task { @MainActor in
            for _ in 0..<15 {
                if !liveGames.isEmpty {
                    if CommandLine.arguments.contains("-ShareSelectTop") && selectionOrder.isEmpty {
                        let topGames = Array(liveGames.prefix(6))
                        selectionOrder = topGames.map(\.persistentModelID)
                        scheduleRerender()
                    }
                    break
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    private func defaultOverviewTitle() -> String {
        let name = username.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return L10n.tr("app.menu", lang: language) }
        return L10n.tr("share.brandUser", [name], lang: language)
    }

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
            NSLog("GameLog: rerenderPreview guard currentContent failed, selectedGames count: %d", selectedGames.count)
            clearPreview()
            return
        }
        NSLog("GameLog: rerenderPreview starting render for %d games, size: %@, theme: %@", selectedGames.count, size.rawValue, themeMode.rawValue)
        // 单一高分辨率出图同时供预览显示与分享文件（超采样位图在预览框内由系统降采样，
        // 排版与全尺寸一致）；旧版分享的是 0.5 预览小图，故手机上发出去发糊。
        if let data = ShareCardRenderer.renderData(
            content: content, language: renderLanguage, theme: resolvedTheme,
            scale: exportQuality.scale, format: exportFormat.rendererFormat
        ) {
            NSLog("GameLog: rerenderPreview success, bytes: %d", data.count)
            applyRendered(data)
        } else {
            NSLog("GameLog: rerenderPreview ShareCardRenderer returned nil")
            clearPreview()
        }
    }

    private func renderFullData() -> Data? {
        guard let content = currentContent else { return nil }
        return ShareCardRenderer.renderData(
            content: content, language: renderLanguage, theme: resolvedTheme, scale: exportQuality.scale, format: exportFormat.rendererFormat
        )
    }

    private var exportBaseName: String {
        let raw: String
        if mode == .groups, let group = selectedGroup {
            raw = group.name
        } else if selectedGames.count == 1, let first = selectedGames.first {
            raw = first.displayName(for: renderLanguage)
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

    // MARK: - 朋友圈九宫格（梯3.9）

    /// 九宫格可用：按游戏模式且勾选 ≥2（1 张就是普通单卡，无需多图流程）。
    private var showGrid9Action: Bool { mode == .games && selectedGames.count >= 2 }

    /// 渲染 ≤9 张方图并落临时文件：iOS 弹系统分享面板（多选一次全部带出），
    /// macOS 无程序化分享锚点，改为在访达中选中这批文件 + 完成提示。
    private func exportGrid9() {
        let trimmed = overviewTitle.trimmingCharacters(in: .whitespaces)
        let title = trimmed.isEmpty ? defaultOverviewTitle() : trimmed
        let datas = ShareCardRenderer.renderGrid9Data(
            games: selectedGames, title: title, language: renderLanguage,
            theme: resolvedTheme, scale: exportQuality.scale, format: exportFormat.rendererFormat
        )
        let urls = writeGrid9Files(datas)
        guard !urls.isEmpty else {
            saveMessage = L10n.tr("share.saveFailed", lang: language)
            return
        }
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting(urls)
        saveMessage = L10n.tr("share.grid9.done", [urls.count], lang: language)
        #else
        presentShareSheet(urls: urls, sourceRect: shareButtonRect)
        #endif
    }

    private func writeGrid9Files(_ datas: [Data]) -> [URL] {
        guard !datas.isEmpty else { return [] }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GameLog-grid9-\(UUID().uuidString.prefix(6))", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ext = exportFormat.fileExtension
        var urls: [URL] = []
        for (i, data) in datas.enumerated() {
            let url = dir.appendingPathComponent("GameLog-9grid-\(i + 1).\(ext)")
            if (try? data.write(to: url)) != nil { urls.append(url) }
        }
        return urls
    }

    #if !os(macOS)
    /// 九宫格整批存相册（朋友圈场景先存再发最常见）。
    private func saveGrid9ToAlbum() {
        let trimmed = overviewTitle.trimmingCharacters(in: .whitespaces)
        let title = trimmed.isEmpty ? defaultOverviewTitle() : trimmed
        let datas = ShareCardRenderer.renderGrid9Data(
            games: selectedGames, title: title, language: renderLanguage,
            theme: resolvedTheme, scale: exportQuality.scale, format: exportFormat.rendererFormat
        )
        let images = datas.compactMap { UIImage(data: $0) }
        guard !images.isEmpty else {
            saveMessage = L10n.tr("share.saveFailed", lang: language)
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized, .limited:
                    PHPhotoLibrary.shared().performChanges {
                        for image in images {
                            PHAssetChangeRequest.creationRequestForAsset(from: image)
                        }
                    } completionHandler: { success, _ in
                        DispatchQueue.main.async {
                            if success {
                                triggerSuccessHaptic()
                                saveMessage = L10n.tr("share.grid9.done", [images.count], lang: language)
                            } else {
                                saveMessage = L10n.tr("share.saveFailed", lang: language)
                            }
                        }
                    }
                default:
                    saveMessage = L10n.tr("share.photoPermissionDenied", lang: language)
                }
            }
        }
    }
    #endif

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
                            if success {
                                triggerSuccessHaptic()
                                saveMessage = L10n.tr("share.savedToAlbum", lang: language)
                            } else {
                                saveMessage = L10n.tr("share.saveFailed", lang: language)
                            }
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

// MARK: - 分享样式设置（四分区：总览头部汇总 / 游戏格子字段 / 分组统计要素 / 水印显示方式）

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
                } else {
                    // 占位：与启用行等宽，开关启停时位置不跳动
                    Button {} label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(true)
                    .opacity(0)
                    Button {} label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(true)
                    .opacity(0)
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
    @State private var watermarkStyle: ShareWatermarkStyle
    @State private var watermarkText: String
    @AppStorage(UserCustomization.usernameKey) private var username = ""

    /// 输入框 prompt：与 `BrandWatermark` 默认拼接逻辑同源的预览文案。
    private var defaultWatermarkText: String {
        let name = username.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return L10n.tr("app.menu", lang: language) }
        return L10n.tr("share.brandUser", [name], lang: language)
    }

    init(onSave: @escaping () -> Void) {
        self.onSave = onSave
        _overviewStats = State(initialValue: ShareOverviewStatsConfig.load())
        _tileFields = State(initialValue: ShareTileFieldsConfig.load())
        _groupStats = State(initialValue: ShareGroupStatsConfig.load())
        _watermarkStyle = State(initialValue: ShareWatermarkStyle.current)
        _watermarkText = State(initialValue: UserDefaults.standard.string(forKey: UserCustomization.shareWatermarkTextKey) ?? "")
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
                Section {
                    TextField(text: $watermarkText, prompt: Text(verbatim: defaultWatermarkText)) {
                        Text(verbatim: L10n.tr("share.watermark.text", lang: language))
                    }
                    .onChange(of: watermarkText) { _, new in
                        watermarkText = UserCustomization.truncateShareTitle(new)
                    }
                    Picker(L10n.tr("share.section.watermark", lang: language), selection: $watermarkStyle) {
                        ForEach(ShareWatermarkStyle.allCases) { style in
                            Text(verbatim: Self.watermarkLabel(style, language: language)).tag(style)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text(verbatim: L10n.tr("share.section.watermark", lang: language))
                } footer: {
                    Text(verbatim: L10n.tr("share.watermark.text.hint", lang: language))
                }
            }
            .navigationTitle(L10n.tr("share.styleSettings", lang: language))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.tr("common.done", lang: language)) {
                        ShareOverviewStatsConfig.save(overviewStats)
                        ShareTileFieldsConfig.save(tileFields)
                        ShareGroupStatsConfig.save(groupStats)
                        ShareWatermarkStyle.save(watermarkStyle)
                        UserDefaults.standard.set(
                            watermarkText.trimmingCharacters(in: .whitespaces),
                            forKey: UserCustomization.shareWatermarkTextKey
                        )
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

    private static func watermarkLabel(_ style: ShareWatermarkStyle, language: String) -> String {
        switch style {
        case .full: return L10n.tr("share.watermark.full", lang: language)
        case .textOnly: return L10n.tr("share.watermark.textOnly", lang: language)
        case .avatarOnly: return L10n.tr("share.watermark.avatarOnly", lang: language)
        case .hidden: return L10n.tr("share.watermark.hidden", lang: language)
        }
    }
}
