import SwiftUI
import SwiftData
import AppKit

/// 预设 + 自定义的下拉选择：选"自定义…"后变为输入框。
/// 预设选项显示本地化文案，tag 与存储值保持 canonical（中文词条）。
struct PresetOrCustomPicker: View {
    let title: String
    let presets: [String]
    let category: PresetCategory
    /// 平台类长列表：菜单顶部只放前几个快捷项，其余项收进「所有平台…」子菜单。通关程度等短列表传 false。
    var collapsible = false
    @Binding var value: String
    @Environment(\.appLanguageCode) private var language

    /// 收起时直接展示的快捷项条数。
    private static let quickCount = 5

    @State private var isCustom = false
    @State private var customText = ""

    /// 自定义输入绑定：同步写回存储值。用 Binding 替代 `.onChange`——`.onChange` 挂 TextField 在 macOS 会吞尾随空格。
    private var customTextBinding: Binding<String> {
        Binding(
            get: { customText },
            set: { newValue in
                customText = newValue
                value = newValue
            }
        )
    }

    private var quickPresets: [String] { Array(presets.prefix(Self.quickCount)) }

    /// 收起时若当前选中项不在快捷区，补一项保证选中可见（编辑旧记录时菜单里仍能高亮当前平台）。
    private var extraSelection: String? {
        guard collapsible, !isCustom,
              !quickPresets.contains(value) else { return nil }
        return value
    }

    /// 放入「所有平台…」子菜单的其余项（排除快捷项与补出的当前项，避免重复）。
    private var remainingPresets: [String] {
        presets.filter { !quickPresets.contains($0) && $0 != extraSelection }
    }

    var body: some View {
        Group {
            if isCustom {
            VStack(alignment: .leading, spacing: 4) {
                BorderedTextField(text: customTextBinding, placeholder: title)
                Button {
                    value = presets.first ?? ""
                    isCustom = false
                } label: {
                    Text(verbatim: L10n.tr("common.back", lang: language))
                }
                .buttonStyle(.link)
            }
        } else {
            LabeledContent(title) {
                Menu {
                    if collapsible {
                        ForEach(quickPresets, id: \.self) { p in
                            option(p)
                        }
                        if let extra = extraSelection {
                            option(extra)
                        }
                        Menu {
                            ForEach(remainingPresets, id: \.self) { p in
                                option(p)
                            }
                        } label: {
                            Text(verbatim: L10n.tr("preset.allPlatforms", lang: language))
                        }
                    } else {
                        ForEach(presets, id: \.self) { p in
                            option(p)
                        }
                    }
                    Divider()
                    Button {
                        isCustom = true
                        customText = ""
                        value = ""
                    } label: {
                        Text(verbatim: L10n.tr("common.custom", lang: language))
                    }
                } label: {
                    Text(verbatim: Presets.display(value, category: category, language: language))
                }
                .menuStyle(.borderlessButton)
            }
        }
        }
        .onAppear { sync(to: value) }
        .onChange(of: value) { _, newValue in sync(to: newValue) }
    }

    /// 单个平台选项，当前选中的带对勾。
    private func option(_ p: String) -> some View {
        Button {
            value = p
        } label: {
            Group {
                if value == p {
                    Label(Presets.display(p, category: category, language: language), systemImage: "checkmark")
                } else {
                    Text(verbatim: Presets.display(p, category: category, language: language))
                }
            }
        }
    }

    /// 把外部绑定值同步到内部自定义态。
    /// 子视图的 onAppear 先于父视图 load() 执行，因此仅靠 onAppear 同步不够，
    /// 编辑时父视图稍后写入 value，必须再监听 value 变化补一次同步。
    private func sync(to newValue: String) {
        if presets.contains(newValue) {
            isCustom = false
        } else {
            isCustom = true
            if !newValue.isEmpty {
                customText = newValue
            }
        }
    }
}

/// 带圆角边框的文本编辑框（NSTextView 实现）：
/// - 高度随内容增长、封顶约 20 行，超出后内部滚动；
/// - 滚动条仅在可滚动时出现（overlay scroller + autohidesScrollers，无溢出不显示）；
/// - textContainerInset 真正垫开文本，首行不会被边框压住。
/// 圆角背景与描边放在 SwiftUI 层（NSView 的 layer 属性在托管时不可靠），NSTextView 保持透明。
struct BorderedTextEditor: View {
    @Binding var text: String
    var minHeight: CGFloat
    var maxHeight: CGFloat

    init(text: Binding<String>, minHeight: CGFloat, maxHeight: CGFloat? = nil) {
        self._text = text
        self.minHeight = minHeight
        self.maxHeight = maxHeight ?? Self.defaultMaxHeight
    }

    /// 约 20 行的最大高度：系统正文字号行高 × 20 + 上下内边距。
    static var defaultMaxHeight: CGFloat {
        let lineHeight = NSLayoutManager().defaultLineHeight(for: NSFont.systemFont(ofSize: NSFont.systemFontSize))
        return lineHeight * 20 + 12
    }

    var body: some View {
        TextEditorNSView(text: $text, minHeight: minHeight, maxHeight: maxHeight)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor))
            )
    }
}

/// 单行输入框（NSTextField 封装）。
/// 规避 macOS SwiftUI TextField 在父视图重渲染时丢失尾随空格的 bug（空格输入不显示、直到下一字符才出现）：
/// 只在外部绑定值真正变化时才回写字段文本，用户输入过程中（绑定已同步、值相同）不重置字段。
struct BorderedTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var isEnabled: Bool = true
    /// 回车提交回调（NSTextField 的 action，替代可能对 representable 失效的 `.onSubmit`）。
    var onSubmit: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.placeholderString = placeholder
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.usesSingleLineMode = true
        field.isEnabled = isEnabled
        if onSubmit != nil {
            field.target = context.coordinator
            field.action = #selector(Coordinator.commit(_:))
        }
        // 让字段在 Form 行/父级提案下横向撑满（与 SwiftUI TextField 行为一致）。
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        nsView.isEnabled = isEnabled
        // 关键：仅外部值变化才回写，避免输入途中被重置。
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: BorderedTextField

        init(_ parent: BorderedTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        @objc func commit(_ sender: NSTextField) {
            parent.text = sender.stringValue
            parent.onSubmit?()
        }
    }
}

/// 透明的 NSTextView 滚动容器，背景由外层 BorderedTextEditor 提供。
private struct TextEditorNSView: NSViewRepresentable {
    @Binding var text: String
    var minHeight: CGFloat
    var maxHeight: CGFloat

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TextEditorNSView
        weak var textView: NSTextView?
        var frameObservation: NSKeyValueObservation?

        init(_ parent: TextEditorNSView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = AutoGrowScrollView(minHeight: minHeight, maxHeight: maxHeight)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 0, height: 0))
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: minHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.drawsBackground = false
        textView.delegate = context.coordinator

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.hasHorizontalScroller = false

        context.coordinator.textView = textView
        context.coordinator.frameObservation = textView.observe(\.frame, options: [.new]) { [weak scrollView] _, _ in
            scrollView?.invalidateIntrinsicContentSize()
        }
        textView.string = text
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        if let scroll = nsView as? AutoGrowScrollView {
            scroll.minHeight = minHeight
            scroll.maxHeight = maxHeight
        }
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            textView.string = text
        }
    }
}

/// 高度随文档内容自适应、封顶 maxHeight 的 NSScrollView。
private final class AutoGrowScrollView: NSScrollView {
    var minHeight: CGFloat
    var maxHeight: CGFloat

    init(minHeight: CGFloat, maxHeight: CGFloat) {
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        let docHeight = documentView?.frame.height ?? 0
        let h = min(maxHeight, max(minHeight, docHeight))
        return NSSize(width: NSView.noIntrinsicMetric, height: h)
    }
}

/// 六维评分滑块行。
struct ScoreSliderRow: View {
    let titleKey: String
    @Binding var value: Double

    /// 去掉 step 以避免滑块下方的刻度点点，写入时仍取整到 0.1 保证数据步进。
    private var snapped: Binding<Double> {
        Binding(
            get: { value },
            set: { value = ($0 * 10).rounded() / 10 }
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            LText(titleKey)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 96, alignment: .leading)
            Slider(value: snapped, in: 1...10)
            Text(verbatim: String(format: "%.1f", value))
                .font(.system(.body, design: .monospaced))
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
    }
}

/// 新建游戏（game == nil，含首条通关记录 + 评价标题必填）或编辑游戏。
struct GameEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    @Environment(\.dismiss) private var dismiss
    let game: Game?

    @Query(sort: \GameGroup.name) private var allGroups: [GameGroup]

    // 游戏信息
    @State private var name = ""
    @State private var nameZh = ""
    @State private var nameJa = ""
    @State private var aliases: [String] = []
    @State private var aliasInput = ""
    @State private var hasReleaseDate = false
    @State private var releaseDate = Date()
    @State private var coverData: Data?
    @State private var reviewTitle = ""
    @State private var reviewBody = ""
    @State private var groupIDs: Set<PersistentIdentifier> = []

    // 首条通关记录（仅新建时）
    @State private var platform = Presets.platforms[0]
    @State private var completionDate = Date()
    @State private var completionDateIsNone = false
    @State private var degree = Presets.degrees[0]
    @State private var playtimeText = ""
    @State private var playtimeIsNone = false
    @State private var notes = ""
    @State private var sGameplay = 7.0
    @State private var sDesign = 7.0
    @State private var sStory = 7.0
    @State private var sArt = 7.0
    @State private var sMusic = 7.0
    @State private var sPerformance = 7.0

    @State private var validationError: String?
    @State private var showingCoverSearch = false
    @AppStorage("steamGridDBKey") private var steamGridDBKey = ""
    @AppStorage(UserCustomization.autoMatchCoverKey) private var autoMatchCover = false

    @State private var isAutoMatching = false
    @State private var didFinishLoading = false
    /// 加载时的游戏名：自动匹配只在名字被用户改动后才触发（避免编辑打开时误匹配）。
    @State private var nameAtLoad = ""

    private var isCreating: Bool { game == nil }

    var body: some View {
        Form {
            Section(L10n.tr("game.name", lang: language)) {
                LabeledContent(L10n.tr("game.nameEn", lang: language)) {
                    BorderedTextField(text: $name, placeholder: L10n.tr("game.nameEn", lang: language))
                        // 用 `.task(id:)` 而非 `.onChange`：输入框重渲染会丢尾随空格，NSTextField 封装已规避。
                        .task(id: name) { await debouncedAutoMatch(name) }
                }
                LabeledContent(L10n.tr("game.nameZh", lang: language)) {
                    BorderedTextField(text: $nameZh, placeholder: L10n.tr("game.nameZh", lang: language))
                }
                LabeledContent(L10n.tr("game.nameJa", lang: language)) {
                    BorderedTextField(text: $nameJa, placeholder: L10n.tr("game.nameJa", lang: language))
                }

                // 别名
                VStack(alignment: .leading, spacing: 6) {
                    LText("game.aliases")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !aliases.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(aliases, id: \.self) { alias in
                                    HStack(spacing: 4) {
                                        Text(verbatim: alias)
                                        Button {
                                            aliases.removeAll { $0 == alias }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.secondary)
                                    }
                                    .font(.system(size: 12))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                                }
                            }
                        }
                    }
                    BorderedTextField(
                        text: $aliasInput,
                        placeholder: L10n.tr("game.aliasPlaceholder", lang: language),
                        onSubmit: {
                            let trimmed = aliasInput.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty && !aliases.contains(trimmed) {
                                aliases.append(trimmed)
                            }
                            aliasInput = ""
                        }
                    )
                }

                Toggle(L10n.tr("game.releaseDate", lang: language), isOn: $hasReleaseDate)
                if hasReleaseDate {
                    DateMenuPicker(title: L10n.tr("game.releaseDate", lang: language), selection: $releaseDate)
                }

                // 分组
                if !allGroups.isEmpty {
                    Section {
                        ForEach(allGroups) { group in
                            Toggle(group.name, isOn: Binding(
                                get: { groupIDs.contains(group.persistentModelID) },
                                set: { on in
                                    if on { groupIDs.insert(group.persistentModelID) }
                                    else { groupIDs.remove(group.persistentModelID) }
                                }
                            ))
                        }
                    } header: {
                        Text(verbatim: L10n.tr("game.groups", lang: language))
                    }
                }

                // 封面
                HStack(alignment: .top, spacing: 12) {
                    Group {
                        if let data = coverData, let image = NSImage(data: data) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            ZStack {
                                Rectangle().fill(Color(nsColor: .quaternarySystemFill))
                                Image(systemName: "photo")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .frame(width: 72, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        if isAutoMatching {
                            ZStack {
                                Color.black.opacity(0.35)
                                ProgressView()
                                    .controlSize(.small)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Button(L10n.tr("game.chooseCover", lang: language)) { pickCover() }
                        Button(L10n.tr("game.searchCover", lang: language)) { showingCoverSearch = true }
                            .disabled(steamGridDBKey.isEmpty)
                        if coverData != nil {
                            Button(L10n.tr("common.delete", lang: language), role: .destructive) { coverData = nil }
                        }
                    }
                }
            }

            // 评价
            Section(L10n.tr("game.reviewTitle", lang: language)) {
                LabeledContent(L10n.tr("game.reviewTitlePlaceholder", lang: language)) {
                    BorderedTextField(text: $reviewTitle, placeholder: L10n.tr("game.reviewTitlePlaceholder", lang: language))
                }
                BorderedTextEditor(text: $reviewBody, minHeight: 140)
            }

            if isCreating {
                Section(L10n.tr("game.firstCompletion", lang: language)) {
                    PresetOrCustomPicker(
                        title: L10n.tr("completion.platform", lang: language),
                        presets: Presets.platforms,
                        category: .platform,
                        collapsible: true,
                        value: $platform
                    )
                    DateMenuPicker(title: L10n.tr("completion.date", lang: language), selection: $completionDate)
                        .disabled(completionDateIsNone)
                    Toggle(L10n.tr("completion.noDate", lang: language), isOn: $completionDateIsNone)
                    PresetOrCustomPicker(
                        title: L10n.tr("completion.degree", lang: language),
                        presets: Presets.degrees,
                        category: .degree,
                        value: $degree
                    )
                    LabeledContent(L10n.tr("completion.playtime", lang: language)) {
                        BorderedTextField(
                            text: $playtimeText,
                            placeholder: L10n.tr("completion.playtime", lang: language),
                            isEnabled: !playtimeIsNone
                        )
                    }
                    Toggle(L10n.tr("completion.noPlaytime", lang: language), isOn: $playtimeIsNone)
                    BorderedTextEditor(text: $notes, minHeight: 80)
                }

                Section(L10n.tr("completion.scores", lang: language)) {
                    ScoreSliderRow(titleKey: "dimension.gameplay", value: $sGameplay)
                    ScoreSliderRow(titleKey: "dimension.design", value: $sDesign)
                    ScoreSliderRow(titleKey: "dimension.story", value: $sStory)
                    ScoreSliderRow(titleKey: "dimension.art", value: $sArt)
                    ScoreSliderRow(titleKey: "dimension.music", value: $sMusic)
                    ScoreSliderRow(titleKey: "dimension.performance", value: $sPerformance)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 560, minHeight: 600)
        .navigationTitle(isCreating ? L10n.tr("title.newGame", lang: language) : L10n.tr("title.editGame", lang: language))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.tr("common.cancel", lang: language)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.tr("common.save", lang: language)) { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .alert(
            L10n.tr("common.confirm", lang: language),
            isPresented: Binding(get: { validationError != nil }, set: { if !$0 { validationError = nil } })
        ) {
            Button(L10n.tr("common.confirm", lang: language)) { validationError = nil }
        } message: {
            Text(verbatim: validationError ?? "")
        }
        .sheet(isPresented: $showingCoverSearch) {
            CoverSearchSheet(coverData: $coverData)
        }
        .onAppear(perform: load)
    }

    private var savedKey: String {
        UserDefaults.standard.string(forKey: "steamGridDBKey") ?? ""
    }

    private func load() {
        guard let game else {
            // 新建：字段全部保持默认，直接标记已加载完成，之后输入名字即可触发自动匹配。
            nameAtLoad = ""
            didFinishLoading = true
            return
        }
        name = game.name
        nameAtLoad = game.name
        aliases = game.aliases
        nameZh = game.nameZh ?? ""
        nameJa = game.nameJa ?? ""
        hasReleaseDate = game.releaseDate != nil
        releaseDate = game.releaseDate ?? Date()
        coverData = game.coverData
        reviewTitle = game.reviewTitle
        reviewBody = game.reviewBody
        groupIDs = Set(game.groups.map(\.persistentModelID))
        // 放在所有字段写入之后：避免上面给 name 赋值那一次 onChange 触发自动匹配。
        didFinishLoading = true
    }

    private func pickCover() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
            coverData = data
        }
    }

    // MARK: - 自动匹配封面

    /// 输入游戏名 → 防抖后自动匹配封面（仅当开关开、已配 key、且尚无封面时）。
    /// 由 `.task(id: name)` 驱动：名字每次变化时取消重开、600ms 后匹配；名字未变（如编辑打开）不匹配。
    private func debouncedAutoMatch(_ newValue: String) async {
        guard newValue != nameAtLoad,
              autoMatchCover, !steamGridDBKey.isEmpty, coverData == nil, didFinishLoading else { return }
        let term = newValue.trimmingCharacters(in: .whitespaces)
        // 名字过短（不足 2 字）不搜，避免输字过程中频繁命中。
        guard term.count >= 2 else { return }
        try? await Task.sleep(nanoseconds: 600_000_000)
        guard !Task.isCancelled else { return }
        isAutoMatching = true
        defer { isAutoMatching = false }
        guard coverData == nil else { return }
        let client = SteamGridDBClient(apiKey: steamGridDBKey)
        do {
            if let data = try await client.autoCover(for: term), coverData == nil {
                coverData = data
            }
        } catch {
            // 匹配失败静默降级：不打断录入，封面保持为空，可随时手动搜索。
        }
    }

    private var parsedPlaytime: Double? {
        let t = playtimeText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        return Double(t)
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let nameZhTrimmed = nameZh.trimmingCharacters(in: .whitespaces)
        let nameJaTrimmed = nameJa.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            validationError = L10n.tr("validation.nameRequired", lang: language)
            return
        }
        let playtimeTextTrimmed = playtimeText.trimmingCharacters(in: .whitespaces)
        if !playtimeIsNone && !playtimeTextTrimmed.isEmpty {
            guard let value = Double(playtimeTextTrimmed), value >= 0 else {
                validationError = L10n.tr("validation.playtimeInvalid", lang: language)
                return
            }
        }

        if isCreating {
            let trimmedTitle = reviewTitle.trimmingCharacters(in: .whitespaces)
            guard !trimmedTitle.isEmpty else {
                validationError = L10n.tr("validation.reviewTitleRequired", lang: language)
                return
            }
            let newGame = Game(
                name: trimmedName,
                nameZh: nameZhTrimmed.isEmpty ? nil : nameZhTrimmed,
                nameJa: nameJaTrimmed.isEmpty ? nil : nameJaTrimmed,
                aliases: aliases,
                releaseDate: hasReleaseDate ? releaseDate : nil,
                coverData: coverData,
                reviewTitle: trimmedTitle,
                reviewBody: reviewBody
            )
            context.insert(newGame)
            newGame.groups = allGroups.filter { groupIDs.contains($0.persistentModelID) }

            let completion = Completion(
                platform: platform,
                date: completionDateIsNone ? nil : completionDate,
                degree: degree,
                playtime: playtimeIsNone ? nil : parsedPlaytime,
                notes: notes,
                scoreGameplay: sGameplay,
                scoreDesign: sDesign,
                scoreStory: sStory,
                scoreArt: sArt,
                scoreMusic: sMusic,
                scorePerformance: sPerformance
            )
            completion.game = newGame
            context.insert(completion)
        } else {
            guard let game else { return }
            game.name = trimmedName
            game.nameZh = nameZhTrimmed.isEmpty ? nil : nameZhTrimmed
            game.nameJa = nameJaTrimmed.isEmpty ? nil : nameJaTrimmed
            game.aliases = aliases
            game.releaseDate = hasReleaseDate ? releaseDate : nil
            game.coverData = coverData
            game.reviewTitle = reviewTitle
            game.reviewBody = reviewBody
            game.groups = allGroups.filter { groupIDs.contains($0.persistentModelID) }
        }
        dismiss()
    }
}
