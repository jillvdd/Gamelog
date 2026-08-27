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
                .appStandardButton()
                .controlSize(.small)
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
    /// 维度评分开关（nil = 无开关、恒可用）。关 = 该维度不评分：滑块禁用、数值显示 —。
    /// 数据语义 = 该维分数为 nil（平均分/统计口径天然只算非 nil 维度）。
    var isEnabled: Binding<Bool>? = nil

    private var enabled: Bool { isEnabled?.wrappedValue ?? true }

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
                .foregroundStyle(enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            if let isEnabled {
                Toggle("", isOn: isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
            Slider(value: snapped, in: 1...10)
                .disabled(!enabled)
                .opacity(enabled ? 1 : 0.35)
            Text(verbatim: enabled ? String(format: "%.1f", value) : "—")
                .font(.system(.body, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
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
    // 厂商/发行商/游戏类型（可选自由文本）。
    @State private var developer = ""
    @State private var publisher = ""
    @State private var genre = ""
    @State private var coverData: Data?
    // 三类附加图（可选，展示位置待设计，先只做录入与存储）：开关关 = 不使用该图（保存时清空）。
    @State private var hasLandscape = false
    @State private var landscapeData: Data?
    @State private var hasHero = false
    @State private var heroData: Data?
    @State private var hasLogo = false
    @State private var logoData: Data?
    // 附加图自动匹配进行中（各图独立 spinner；开关触发与改名触发共用）。
    @State private var isAutoMatchingLandscape = false
    @State private var isAutoMatchingHero = false
    @State private var isAutoMatchingLogo = false
    // Logo 横幅展示三档调节（详情页背景图之上的位置/大小；仅 hasLogo 开时有意义）。
    @State private var logoSize: LogoBannerSize = .medium
    @State private var logoVertical: LogoBannerVertical = .center
    @State private var logoHorizontal: LogoBannerHorizontal = .leading
    // 各图像的搜索面板开关。
    @State private var showingLandscapeSearch = false
    // 照片图库选择器开关（macOS 走 photoLibraryPicker；iOS 走 imageSourcePicker 的相册分支）。
    @State private var showingLandscapePicker = false
    @State private var showingHeroPicker = false
    @State private var showingLogoPicker = false
    @State private var showingHeroSearch = false
    @State private var showingLogoSearch = false
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
    /// 每维评分开关（新建首条记录默认全开；关 = 该维分数存 nil）。
    @State private var eGameplay = true
    @State private var eDesign = true
    @State private var eStory = true
    @State private var eArt = true
    @State private var eMusic = true
    @State private var ePerformance = true

    // 持有档案（仅新建 + 收藏家模式时随游戏一起建一份实体持有）
    @State private var holdingVersion = ""
    @State private var holdingCount = 1
    @State private var holdingMedia: CopyMedia = .physicalStandard
    @State private var holdingRegional: CopyRegional = .jp
    @State private var holdingCondition: CopyCondition = .used
    @State private var holdingAcquisition: CopyAcquisition = .officialChannelOverseas
    @State private var holdingPlatform = Presets.platforms[0]
    @State private var holdingPriceText = ""
    @State private var holdingEstText = ""
    @State private var holdingHasDate = false
    @State private var holdingDate = Date()
    @State private var holdingNotes = ""
    /// 新建时是否真的拥有这份（借的/订阅的不算持有）；默认 false，勾选才展开填写并建档案。
    @State private var createHolding = false

    @State private var validationError: String?
    @State private var showingCoverSearch = false
    @State private var showingCoverPicker = false
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

                BorderedTextField(text: $developer, placeholder: L10n.tr("game.developer", lang: language))
                BorderedTextField(text: $publisher, placeholder: L10n.tr("game.publisher", lang: language))
                BorderedTextField(text: $genre, placeholder: L10n.tr("game.genre", lang: language))

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

                // 封面（2:3 主格式，恒显示）
                ArtworkRow(
                    titleKey: "game.cover",
                    data: coverData,
                    aspect: 0.75,
                    thumbWidth: 72,
                    isAutoMatching: isAutoMatching,
                    onPick: {
                        #if os(macOS)
                        pickImageFromPanel { coverData = $0 }
                        #else
                        showingCoverPicker = true
                        #endif
                    },
                    onPickFromLibrary: { showingCoverPicker = true },
                    onSearch: { showingCoverSearch = true },
                    onDelete: { coverData = nil }
                )

                // 三类附加图像：各自开关，默认关；开 = 展开预览与录入按钮。
                Toggle(L10n.tr("game.landscape", lang: language), isOn: $hasLandscape)
                    .task(id: hasLandscape) {
                        await autoMatchOnToggle(kind: .landscape, enabled: hasLandscape,
                                                isSet: { landscapeData != nil },
                                                assign: { landscapeData = $0 }, active: $isAutoMatchingLandscape)
                    }
                if hasLandscape {
                    ArtworkRow(
                        titleKey: "game.landscape",
                        data: landscapeData,
                        aspect: 2.14,
                        thumbWidth: 128,
                        isAutoMatching: isAutoMatchingLandscape,
                        onPick: {
                            #if os(macOS)
                            pickImageFromPanel { landscapeData = $0 }
                            #else
                            showingLandscapePicker = true
                            #endif
                        },
                        onPickFromLibrary: { showingLandscapePicker = true },
                        onSearch: { showingLandscapeSearch = true },
                        onDelete: { landscapeData = nil }
                    )
                }
                Toggle(L10n.tr("game.hero", lang: language), isOn: $hasHero)
                    .task(id: hasHero) {
                        await autoMatchOnToggle(kind: .hero, enabled: hasHero,
                                                isSet: { heroData != nil },
                                                assign: { heroData = $0 }, active: $isAutoMatchingHero)
                    }
                if hasHero {
                    ArtworkRow(
                        titleKey: "game.hero",
                        data: heroData,
                        aspect: 3.1,
                        thumbWidth: 168,
                        isAutoMatching: isAutoMatchingHero,
                        onPick: {
                            #if os(macOS)
                            pickImageFromPanel { heroData = $0 }
                            #else
                            showingHeroPicker = true
                            #endif
                        },
                        onPickFromLibrary: { showingHeroPicker = true },
                        onSearch: { showingHeroSearch = true },
                        onDelete: { heroData = nil }
                    )
                }
                Toggle(L10n.tr("game.logo", lang: language), isOn: $hasLogo)
                    .task(id: hasLogo) {
                        await autoMatchOnToggle(kind: .logo, enabled: hasLogo,
                                                isSet: { logoData != nil },
                                                assign: { logoData = $0 }, active: $isAutoMatchingLogo)
                    }
                if hasLogo {
                    ArtworkRow(
                        titleKey: "game.logo",
                        data: logoData,
                        aspect: nil,
                        thumbWidth: 128,
                        isAutoMatching: isAutoMatchingLogo,
                        onPick: {
                            #if os(macOS)
                            pickImageFromPanel { logoData = $0 }
                            #else
                            showingLogoPicker = true
                            #endif
                        },
                        onPickFromLibrary: { showingLogoPicker = true },
                        onSearch: { showingLogoSearch = true },
                        onDelete: { logoData = nil }
                    )
                    // Logo 源图尺寸比例各异：详情页横幅内的大小/位置三档可调。
                    EnumPickerRow(title: L10n.tr("game.logoSize", lang: language),
                                  cases: LogoBannerSize.allCases, selection: $logoSize, language: language)
                    EnumPickerRow(title: L10n.tr("game.logoVertical", lang: language),
                                  cases: LogoBannerVertical.allCases, selection: $logoVertical, language: language)
                    EnumPickerRow(title: L10n.tr("game.logoHorizontal", lang: language),
                                  cases: LogoBannerHorizontal.allCases, selection: $logoHorizontal, language: language)
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
                        PresetOrCustomPicker(
                            title: L10n.tr("completion.platform", lang: language),
                            presets: Presets.platforms,
                            category: .platform,
                            collapsible: true,
                            value: $holdingPlatform
                        )
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
                    ScoreSliderRow(titleKey: "dimension.gameplay", value: $sGameplay, isEnabled: $eGameplay)
                    ScoreSliderRow(titleKey: "dimension.design", value: $sDesign, isEnabled: $eDesign)
                    ScoreSliderRow(titleKey: "dimension.story", value: $sStory, isEnabled: $eStory)
                    ScoreSliderRow(titleKey: "dimension.art", value: $sArt, isEnabled: $eArt)
                    ScoreSliderRow(titleKey: "dimension.music", value: $sMusic, isEnabled: $eMusic)
                    ScoreSliderRow(titleKey: "dimension.performance", value: $sPerformance, isEnabled: $ePerformance)
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
            CoverSearchSheet(kind: .poster, imageData: $coverData)
        }
        .sheet(isPresented: $showingLandscapeSearch) {
            CoverSearchSheet(kind: .landscape, imageData: $landscapeData)
        }
        .sheet(isPresented: $showingHeroSearch) {
            CoverSearchSheet(kind: .hero, imageData: $heroData)
        }
        .sheet(isPresented: $showingLogoSearch) {
            CoverSearchSheet(kind: .logo, imageData: $logoData)
        }
        #if !os(macOS)
        .imageSourcePicker(isPresented: $showingCoverPicker, onImages: { datas in
            if let data = datas.first {
                coverData = data
            }
        })
        .imageSourcePicker(isPresented: $showingLandscapePicker, onImages: { datas in
            if let data = datas.first {
                landscapeData = data
            }
        })
        .imageSourcePicker(isPresented: $showingHeroPicker, onImages: { datas in
            if let data = datas.first {
                heroData = data
            }
        })
        .imageSourcePicker(isPresented: $showingLogoPicker, onImages: { datas in
            if let data = datas.first {
                logoData = data
            }
        })
        #endif
        #if os(macOS)
        // macOS 照片图库选择器：与 iOS 相册分支同口径——取 first 原样入库，不压缩。
        .photoLibraryPicker(isPresented: $showingCoverPicker, onImages: { datas in
            if let data = datas.first {
                coverData = data
            }
        })
        .photoLibraryPicker(isPresented: $showingLandscapePicker, onImages: { datas in
            if let data = datas.first {
                landscapeData = data
            }
        })
        .photoLibraryPicker(isPresented: $showingHeroPicker, onImages: { datas in
            if let data = datas.first {
                heroData = data
            }
        })
        .photoLibraryPicker(isPresented: $showingLogoPicker, onImages: { datas in
            if let data = datas.first {
                logoData = data
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
        developer = game.developer ?? ""
        publisher = game.publisher ?? ""
        genre = game.genre ?? ""
        coverData = game.coverData
        landscapeData = game.landscapeData
        heroData = game.heroData
        logoData = game.logoData
        hasLandscape = game.landscapeData != nil
        hasHero = game.heroData != nil
        hasLogo = game.logoData != nil
        logoSize = game.logoSizeValue
        logoVertical = game.logoVerticalValue
        logoHorizontal = game.logoHorizontalValue
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

    // MARK: - 自动匹配封面

    /// macOS 本地选图（iOS 走 imageSourcePicker modifier，回调里写对应 @State）。
    private func pickImageFromPanel(apply: @escaping (Data) -> Void) {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
            apply(data)
        }
        #endif
    }

    /// 输入游戏名 → 防抖后自动匹配封面与已开开关且未设置的附加图（仅当开关开、已配 key）。
    /// 由 `.task(id: name)` 驱动：名字每次变化时取消重开、600ms 后匹配；名字未变（如编辑打开）不匹配。
    private func debouncedAutoMatch(_ newValue: String) async {
        guard newValue != nameAtLoad,
              autoMatchCover, !steamGridDBKey.isEmpty, didFinishLoading else { return }
        let term = newValue.trimmingCharacters(in: .whitespaces)
        // 名字过短（不足 2 字）不搜，避免输字过程中频繁命中。
        guard term.count >= 2 else { return }
        try? await Task.sleep(nanoseconds: 600_000_000)
        guard !Task.isCancelled else { return }
        let client = SteamGridDBClient(apiKey: steamGridDBKey)
        // 封面（原有路径）。
        if coverData == nil {
            isAutoMatching = true
            defer { isAutoMatching = false }
            do {
                // 复查 isCancelled：快速连续改名时旧名字的响应若已在取消生效前返回，不能写入。
                if let data = try await client.autoCover(for: term), !Task.isCancelled, coverData == nil {
                    coverData = data
                }
            } catch {
                // 匹配失败静默降级：不打断录入，封面保持为空，可随时手动搜索。
            }
        }
        // 三类附加图：开关开着且未设置的跟随改名一起匹配（防抖/静默降级与封面同款）。
        await autoFillArtwork(kind: .landscape, term: term, enabled: hasLandscape,
                              isSet: { landscapeData != nil }, assign: { landscapeData = $0 }, active: $isAutoMatchingLandscape)
        await autoFillArtwork(kind: .hero, term: term, enabled: hasHero,
                              isSet: { heroData != nil }, assign: { heroData = $0 }, active: $isAutoMatchingHero)
        await autoFillArtwork(kind: .logo, term: term, enabled: hasLogo,
                              isSet: { logoData != nil }, assign: { logoData = $0 }, active: $isAutoMatchingLogo)
    }

    /// 单类附加图的自动匹配：开关开 + 未设置才搜；静默降级；写入前经 isSet 复查实时值
    /// （await 期间用户可能已手动选图，不能覆盖）。
    private func autoFillArtwork(kind: ArtworkKind, term: String, enabled: Bool,
                                 isSet: () -> Bool, assign: @escaping (Data) -> Void, active: Binding<Bool>) async {
        guard enabled, !isSet() else { return }
        active.wrappedValue = true
        defer { active.wrappedValue = false }
        let client = SteamGridDBClient(apiKey: steamGridDBKey)
        do {
            if let data = try await client.autoArtwork(for: term, kind: kind), !Task.isCancelled, !isSet() {
                assign(data)
            }
        } catch {
            // 静默降级，与封面同口径。
        }
    }

    /// 「未设置时打开某类附加图开关」→ 立即触发该类图的自动匹配（防抖 600ms 同改名路径）。
    /// 由三处 `.task(id: hasXxx)` 驱动；false→true 且数据为 nil 才匹配。
    private func autoMatchOnToggle(kind: ArtworkKind, enabled: Bool,
                                   isSet: @escaping () -> Bool, assign: @escaping (Data) -> Void, active: Binding<Bool>) async {
        guard enabled, !isSet(), autoMatchCover, !steamGridDBKey.isEmpty, didFinishLoading else { return }
        let term = name.trimmingCharacters(in: .whitespaces)
        guard term.count >= 2 else { return }
        try? await Task.sleep(nanoseconds: 600_000_000)
        guard !Task.isCancelled else { return }
        await autoFillArtwork(kind: kind, term: term, enabled: enabled, isSet: isSet, assign: assign, active: active)
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
                // 六维至少评一维（视觉小说等可只评剧情/音乐/美术，但不能全不评）。
                if !(eGameplay || eDesign || eStory || eArt || eMusic || ePerformance) {
                    validationError = L10n.tr("validation.scoreRequired", lang: language)
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
                developer: developer.trimmingCharacters(in: .whitespaces).isEmpty ? nil : developer.trimmingCharacters(in: .whitespaces),
                publisher: publisher.trimmingCharacters(in: .whitespaces).isEmpty ? nil : publisher.trimmingCharacters(in: .whitespaces),
                genre: genre.trimmingCharacters(in: .whitespaces).isEmpty ? nil : genre.trimmingCharacters(in: .whitespaces),
                coverData: coverData,
                landscapeData: hasLandscape ? landscapeData : nil,
                heroData: hasHero ? heroData : nil,
                logoData: hasLogo ? logoData : nil,
                logoSize: logoSize,
                logoVertical: logoVertical,
                logoHorizontal: logoHorizontal,
                // 与上方校验同口径：入库用 trim 后的标题（iOS 编辑 sheet / 写字台保存也是 trim 口径）。
                reviewTitle: reviewTitle.trimmingCharacters(in: .whitespaces),
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
                    scoreGameplay: eGameplay ? sGameplay : nil,
                    scoreDesign: eDesign ? sDesign : nil,
                    scoreStory: eStory ? sStory : nil,
                    scoreArt: eArt ? sArt : nil,
                    scoreMusic: eMusic ? sMusic : nil,
                    scorePerformance: ePerformance ? sPerformance : nil
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
                    platform: holdingPlatform.trimmingCharacters(in: .whitespaces),
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
            game.developer = developer.trimmingCharacters(in: .whitespaces).isEmpty ? nil : developer.trimmingCharacters(in: .whitespaces)
            game.publisher = publisher.trimmingCharacters(in: .whitespaces).isEmpty ? nil : publisher.trimmingCharacters(in: .whitespaces)
            game.genre = genre.trimmingCharacters(in: .whitespaces).isEmpty ? nil : genre.trimmingCharacters(in: .whitespaces)
            game.coverData = coverData
            game.landscapeData = hasLandscape ? landscapeData : nil
            game.heroData = hasHero ? heroData : nil
            game.logoData = hasLogo ? logoData : nil
            game.logoSizeValue = logoSize
            game.logoVerticalValue = logoVertical
            game.logoHorizontalValue = logoHorizontal
            game.reviewTitle = reviewTitle
            game.reviewBody = reviewBody
            game.groups = allGroups.filter { groupIDs.contains($0.persistentModelID) }
            game.updatedAt = .now
        }
        dismiss()
    }
}

// MARK: - 图像录入行（封面 / 横向封面 / 背景图 / Logo 四类共用）

/// 图像录入行：左侧按类型比例的缩略预览（无图显示占位），右侧标题 + 选择图片 / 搜索 / 删除按钮。
/// `aspect` = 宽高比（nil = Logo 等不定比例，contain 显示 + 衬底，避免透明 PNG 深色模式隐形）。
struct ArtworkRow: View {
    let titleKey: String
    let data: Data?
    let aspect: Double?
    var thumbWidth: CGFloat = 72
    /// 仅封面行用：自动匹配进行中在缩略图上盖 spinner（由 GameEditView 传入其 @State）。
    var isAutoMatching = false
    let onPick: () -> Void
    /// 「照片图库…」按钮（nil = 不显示）。仅 macOS 渲染：iOS 编辑页保持原三按钮不变。
    var onPickFromLibrary: (() -> Void)? = nil
    let onSearch: () -> Void
    let onDelete: () -> Void

    /// 搜索按钮文案按图类区分（复用搜索面板标题 key：搜索封面/搜索横向封面/搜索背景图/搜索 Logo）。
    private var searchCoverTitleKey: String {
        switch titleKey {
        case "game.landscape": return "cover.titleLandscape"
        case "game.hero": return "cover.titleHero"
        case "game.logo": return "cover.titleLogo"
        default: return "cover.title"
        }
    }

    @Environment(\.appLanguageCode) private var language
    @AppStorage("steamGridDBKey") private var steamGridDBKey = ""

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let data, let image = AppImage(data: data) {
                    if let aspect {
                        Image(appImage: image)
                            .resizable()
                            .scaledToFill()
                            .aspectRatio(aspect, contentMode: .fit)
                    } else {
                        // Logo 等透明 PNG：contain 显示 + 固定浅灰衬底（白 logo 在纯白衬底上会隐形，
                        // 浅灰在深浅色模式下都能衬托白/彩色 logo），描边标出边界。
                        // 宽高必须同时给定：只给高度时宽度无约束，宽幅 logo 会溢出被居中裁掉两侧。
                        Image(appImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(6)
                            .background(Rectangle().fill(Color(red: 0.88, green: 0.88, blue: 0.90)))
                            .overlay(Rectangle().strokeBorder(Color.semantic(.separator), lineWidth: 0.5))
                            .frame(width: thumbWidth, height: thumbWidth)
                    }
                } else {
                    ZStack {
                        Rectangle().fill(Color.semantic(.quaternarySystemFill))
                        Image(systemName: "photo")
                            .foregroundStyle(.tertiary)
                    }
                    .aspectRatio(aspect ?? 1, contentMode: .fit)
                }
            }
            .frame(width: thumbWidth)
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
                LText(titleKey)
                    .font(.callout.weight(.medium))
                Button(L10n.tr("game.chooseCover", lang: language), action: onPick)
                    .appStandardButton()
                    .controlSize(.small)
                #if os(macOS)
                if let onPickFromLibrary {
                    Button(L10n.tr("image.photoLibrary", lang: language), action: onPickFromLibrary)
                        .appStandardButton()
                        .controlSize(.small)
                }
                #endif
                Button(L10n.tr(searchCoverTitleKey, lang: language), action: onSearch)
                    .appStandardButton()
                    .controlSize(.small)
                    .disabled(steamGridDBKey.isEmpty)
                if data != nil {
                    Button(L10n.tr("common.delete", lang: language), role: .destructive, action: onDelete)
                        .appStandardButton()
                        .controlSize(.small)
                }
            }
        }
    }
}
