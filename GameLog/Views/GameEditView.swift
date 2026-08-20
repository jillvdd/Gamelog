import SwiftUI
import SwiftData

#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#else
import UniformTypeIdentifiers
#endif

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
                #if os(macOS)
                .buttonStyle(.link)
                #else
                .buttonStyle(.plain)
                #endif
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
                    HStack(spacing: 6) {
                        if category == .platform {
                            PlatformIcon(platform: value, size: 14)
                        }
                        Text(verbatim: Presets.display(value, category: category, language: language))
                    }
                }
                #if os(macOS)
                .menuStyle(.borderlessButton)
                #else
                .menuStyle(.button)
                #endif
            }
        }
        }
        .onAppear { sync(to: value) }
        .onChange(of: value) { _, newValue in sync(to: newValue) }
    }

    /// 单个平台选项，当前选中的右侧带对勾。
    private func option(_ p: String) -> some View {
        Button {
            value = p
        } label: {
            HStack(spacing: 8) {
                if category == .platform {
                    PlatformIcon(platform: p, size: 16)
                }
                Text(verbatim: Presets.display(p, category: category, language: language))
                Spacer()
                if value == p {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.secondary)
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
    /// 状态机状态（想玩/在玩等轻量状态新建时无需通关记录与评分）。
    @State private var status = GameStatus.completed

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

    // 持有档案（仅新建 + 收藏家模式时随游戏一起建一份实体持有）
    @State private var holdingVersion = ""
    @State private var holdingCount = 1
    @State private var holdingMedia: CopyMedia = .physicalStandard
    @State private var holdingRegional: CopyRegional = .standard
    @State private var holdingCondition: CopyCondition = .good
    @State private var holdingAcquisition: CopyAcquisition = .officialChannelOverseas
    @State private var holdingPriceText = ""
    @State private var holdingEstText = ""
    @State private var holdingHasDate = false
    @State private var holdingDate = Date()
    @State private var holdingNotes = ""
    /// 新建时是否真的拥有这份（借的/订阅的不算持有）；默认 false，勾选才展开填写并建档案。
    @State private var createHolding = false

    @State private var validationError: String?
    @State private var showingCoverSearch = false
    #if !os(macOS)
    @State private var showingCoverPicker = false
    #endif
    @AppStorage("steamGridDBKey") private var steamGridDBKey = ""
    @AppStorage(UserCustomization.autoMatchCoverKey) private var autoMatchCover = false
    @AppStorage(UserCustomization.collectorModeKey) private var collectorMode = false

    @State private var isAutoMatching = false
    @State private var didFinishLoading = false
    /// 加载时的游戏名：自动匹配只在名字被用户改动后才触发（避免编辑打开时误匹配）。
    @State private var nameAtLoad = ""

    private var isCreating: Bool { game == nil }

    var body: some View {
        Form {
            Section(L10n.tr("game.status", lang: language)) {
                Picker("", selection: $status) {
                    ForEach(GameStatus.allCases) { s in
                        Text(verbatim: L10n.tr(s.labelKey, lang: language)).tag(s)
                    }
                }
                .labelsHidden()
                #if os(macOS)
                .pickerStyle(.segmented)
                #else
                .pickerStyle(.menu)
                #endif
                // 游戏主平台：对所有状态都设置（想玩/在玩等轻量状态没有通关记录，平台挂在游戏上）。
                PresetOrCustomPicker(
                    title: L10n.tr("completion.platform", lang: language),
                    presets: Presets.platforms,
                    category: .platform,
                    collapsible: true,
                    value: $platform
                )
                if status != .completed {
                    LText("game.statusHint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

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
                    HStack(spacing: 8) {
                        BorderedTextField(
                            text: $aliasInput,
                            placeholder: L10n.tr("game.aliasPlaceholder", lang: language),
                            onSubmit: addAlias
                        )
                        Button(L10n.tr("game.aliasAdd", lang: language)) { addAlias() }
                            .disabled(aliasInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
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
                        if let data = coverData, let image = AppImage(data: data) {
                            Image(appImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            ZStack {
                                Rectangle().fill(Color.semantic(.quaternarySystemFill))
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

                    VStack(alignment: .leading, spacing: 10) {
                        Button(L10n.tr("game.chooseCover", lang: language)) {
                            #if os(macOS)
                            pickCover()
                            #else
                            showingCoverPicker = true
                            #endif
                        }
                        #if os(macOS)
                        .buttonStyle(.bordered)
                        #endif
                        .appStandardButton()
                        Button(L10n.tr("game.searchCover", lang: language)) { showingCoverSearch = true }
                            #if os(macOS)
                            .buttonStyle(.bordered)
                            #endif
                            .appStandardButton()
                            .disabled(steamGridDBKey.isEmpty)
                        if coverData != nil {
                            Button(L10n.tr("common.delete", lang: language), role: .destructive) { coverData = nil }
                                #if os(macOS)
                                .buttonStyle(.bordered)
                                #endif
                                .appStandardButton()
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
                Text(verbatim: L10n.tr("review.bodyHint", lang: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isCreating && collectorMode {
                Section {
                    Toggle(L10n.tr("game.createHolding", lang: language), isOn: $createHolding)
                    if createHolding {
                        Text(verbatim: L10n.tr("game.holdingArchiveHint", lang: language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        LabeledContent(L10n.tr("copy.version", lang: language)) {
                            BorderedTextField(text: $holdingVersion, placeholder: L10n.tr("copy.versionPlaceholder", lang: language))
                        }
                        Stepper(value: $holdingCount, in: 1...999) {
                            HStack {
                                LText("copy.count")
                                Spacer()
                                Text(verbatim: "\(holdingCount)").monospacedDigit()
                            }
                        }
                        EnumPickerRow(title: L10n.tr("copy.media", lang: language),
                                      cases: CopyMedia.allCases, selection: $holdingMedia, language: language)
                        if holdingMedia.isPhysical {
                            EnumPickerRow(title: L10n.tr("copy.condition", lang: language),
                                          cases: CopyCondition.allCases, selection: $holdingCondition, language: language)
                        }
                        EnumPickerRow(title: L10n.tr("copy.regional", lang: language),
                                      cases: CopyRegional.allCases, selection: $holdingRegional, language: language)
                        EnumPickerRow(title: L10n.tr("copy.acquisition", lang: language),
                                      cases: CopyAcquisition.allCases, selection: $holdingAcquisition, language: language)
                        LabeledContent(L10n.tr("copy.price", lang: language)) {
                            BorderedTextField(text: $holdingPriceText, placeholder: "0")
                                #if os(macOS)
                                .frame(width: 160)
                                #else
                                .frame(maxWidth: .infinity)
                                #endif
                        }
                        LabeledContent(L10n.tr("copy.estValue", lang: language)) {
                            BorderedTextField(text: $holdingEstText, placeholder: "0")
                                #if os(macOS)
                                .frame(width: 160)
                                #else
                                .frame(maxWidth: .infinity)
                                #endif
                        }
                        Toggle(L10n.tr("copy.purchaseDate", lang: language), isOn: $holdingHasDate)
                        if holdingHasDate {
                            DateMenuPicker(title: L10n.tr("copy.purchaseDate", lang: language), selection: $holdingDate)
                        }
                        LabeledContent(L10n.tr("copy.notes", lang: language)) {
                            BorderedTextField(text: $holdingNotes, placeholder: L10n.tr("copy.notesPlaceholder", lang: language))
                        }
                    }
                } header: {
                    Text(verbatim: L10n.tr("game.holdingArchive", lang: language))
                }
            }

            if isCreating && (status == .completed || status == .longRunning) {
                Section(L10n.tr("game.firstCompletion", lang: language)) {
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
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 600)
        #endif
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
        #if !os(macOS)
        .imageSourcePicker(isPresented: $showingCoverPicker, onImages: { datas in
            if let data = datas.first {
                coverData = data
            }
        })
        #endif
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
        status = game.statusValue
        // 游戏主平台：旧数据可能为空（已通关游戏），回退到首条记录的平台。
        platform = game.platform.isEmpty
            ? (game.sortedCompletions.first?.platform ?? Presets.platforms[0])
            : game.platform
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

    /// 添加别名：去首尾空格、去重，输入框清空。回车（onSubmit）与「添加」按钮共用。
    private func addAlias() {
        let trimmed = aliasInput.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty && !aliases.contains(trimmed) {
            aliases.append(trimmed)
        }
        aliasInput = ""
    }

    private func pickCover() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
            coverData = data
        }
        #else
        // iOS：阶段 3 用 PhotosPicker / fileImporter 实现选图。
        #endif
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
            // 已通关/长线游玩必须写评价标题；想玩等轻量状态不强制（也没有通关记录/评分）。
            if status == .completed || status == .longRunning {
                let trimmedTitle = reviewTitle.trimmingCharacters(in: .whitespaces)
                guard !trimmedTitle.isEmpty else {
                    validationError = L10n.tr("validation.reviewTitleRequired", lang: language)
                    return
                }
            }
            let newGame = Game(
                name: trimmedName,
                nameZh: nameZhTrimmed.isEmpty ? nil : nameZhTrimmed,
                nameJa: nameJaTrimmed.isEmpty ? nil : nameJaTrimmed,
                aliases: aliases,
                platform: platform,
                releaseDate: hasReleaseDate ? releaseDate : nil,
                coverData: coverData,
                reviewTitle: reviewTitle,
                reviewBody: reviewBody,
                status: status
            )
            context.insert(newGame)
            newGame.groups = allGroups.filter { groupIDs.contains($0.persistentModelID) }

            if status == .completed || status == .longRunning {
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
            }

            // 收藏家模式：仅当用户勾选「持有」才随新建游戏建一份实体持有（借的/订阅的不算持有）。
            if collectorMode && createHolding {
                let version = holdingVersion.trimmingCharacters(in: .whitespaces).isEmpty
                    ? L10n.tr("copy.versionAuto", [1], lang: language)
                    : holdingVersion.trimmingCharacters(in: .whitespaces)
                let trimmedPrice = holdingPriceText.trimmingCharacters(in: .whitespaces)
                let trimmedEst = holdingEstText.trimmingCharacters(in: .whitespaces)
                let copy = PhysicalCopy(
                    version: version,
                    count: max(1, holdingCount),
                    media: holdingMedia,
                    regional: holdingRegional,
                    condition: holdingCondition,
                    acquisition: holdingAcquisition,
                    priceZh: language == "zh-Hans" ? Double(trimmedPrice) : nil,
                    priceJa: language == "ja" ? Double(trimmedPrice) : nil,
                    priceEn: language == "en" ? Double(trimmedPrice) : nil,
                    estValueZh: language == "zh-Hans" ? Double(trimmedEst) : nil,
                    estValueJa: language == "ja" ? Double(trimmedEst) : nil,
                    estValueEn: language == "en" ? Double(trimmedEst) : nil,
                    purchaseDate: holdingHasDate ? holdingDate : nil,
                    notes: holdingNotes.trimmingCharacters(in: .whitespaces)
                )
                copy.game = newGame
                context.insert(copy)
            }
        } else {
            guard let game else { return }
            game.name = trimmedName
            game.nameZh = nameZhTrimmed.isEmpty ? nil : nameZhTrimmed
            game.nameJa = nameJaTrimmed.isEmpty ? nil : nameJaTrimmed
            game.statusValue = status
            game.platform = platform
            game.aliases = aliases
            game.releaseDate = hasReleaseDate ? releaseDate : nil
            game.coverData = coverData
            game.reviewTitle = reviewTitle
            game.reviewBody = reviewBody
            game.groups = allGroups.filter { groupIDs.contains($0.persistentModelID) }
            game.updatedAt = .now
        }
        dismiss()
    }
}
