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
    // 五类图（封面/方形/横向/背景图/Logo）：kind 字典化状态（2026-08-29 深化，接线塌缩为 ForEach）。
    // data[kind] = 当前图；gated[kind] = 门控开关（仅 isToggleGated 类型有意义，关 = 保存时清空）；
    // matching[kind] = 自动匹配进行中（spinner）。封面数据恒在、无开关。
    @State private var artworkData: [ArtworkKind: Data] = [:]
    @State private var artworkGated: [ArtworkKind: Bool] = [:]
    @State private var artworkMatching: Set<ArtworkKind> = []
    // Logo 横幅展示三档调节（详情页背景图之上的位置/大小；仅 Logo 开时有意义）。
    @State private var logoSize: LogoBannerSize = .medium
    @State private var logoVertical: LogoBannerVertical = .bottom
    @State private var logoHorizontal: LogoBannerHorizontal = .leading
    // 搜索面板 / 选图器当前服务的图类（nil = 关闭；单一 sheet/modifier 由 kind 驱动）。
    @State private var activeSearchKind: ArtworkKind?
    @State private var activePickerKind: ArtworkKind?
    @State private var reviewTitle = ""
    @State private var reviewBody = ""
    @State private var groupIDs: Set<PersistentIdentifier> = []
    /// 状态机状态（想玩/在玩等轻量状态新建时无需通关记录与评分）。
    @State private var status = GameStatus.completed
    /// 游戏版本选项（默认关闭；开启后选 demo 或 other）。
    @State private var hasCustomVersion = false
    @State private var customVersion: GameVersion = .demo

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
    @AppStorage("steamGridDBKey") private var steamGridDBKey = ""
    @AppStorage(UserCustomization.autoMatchCoverKey) private var autoMatchCover = false
    @AppStorage(UserCustomization.collectorModeKey) private var collectorMode = false

    @State private var didFinishLoading = false
    /// 加载时的游戏名：自动匹配只在名字被用户改动后才触发（避免编辑打开时误匹配）。
    @State private var nameAtLoad = ""
    /// 加载时的「搜索用名」（见 `searchName`）。**不能拿 `nameAtLoad` 顶替**：
    /// 导入进来的游戏主名可能是空的（中日文标题只落语言槽），那时 `searchName` 是中/日文名，
    /// 拿空的 `nameAtLoad` 一比就永远「不相等」→ 一打开编辑页就白搜一次。
    @State private var searchNameAtLoad = ""

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
                Toggle(L10n.tr("game.version.enable", lang: language), isOn: $hasCustomVersion)
                if hasCustomVersion {
                    Picker(L10n.tr("game.version.title", lang: language), selection: $customVersion) {
                        ForEach(GameVersion.allCases) { v in
                            Text(verbatim: L10n.tr(v.labelKey, lang: language)).tag(v)
                        }
                    }
                    #if os(macOS)
                    .pickerStyle(.segmented)
                    #else
                    .pickerStyle(.menu)
                    #endif
                }
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
                        // id 用 `searchName`（不是 `name`）：只填了中文名的游戏也要能自动匹配配图。
                        .task(id: searchName) { await debouncedAutoMatch(searchName) }
                }
                LabeledContent(L10n.tr("game.nameZh", lang: language)) {
                    BorderedTextField(text: $nameZh, placeholder: L10n.tr("game.nameZh", lang: language))
                }
                LabeledContent(L10n.tr("game.nameJa", lang: language)) {
                    BorderedTextField(text: $nameJa, placeholder: L10n.tr("game.nameJa", lang: language))
                }
                // 名称的硬要求只有「至少填一种语言」。同步下来的游戏常常只有中文名或日文名
                // （英文名那一栏本就该是空的），这句话是给用户看的说明书 —— 否则他会以为自己
                // 漏填了什么东西。（文案与 `validation.nameRequired` 同一口径。）
                LText("game.nameHint")
                    .font(.caption)
                    .foregroundStyle(.secondary)

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

                // 五类图：kind 表驱动（封面恒显示；其余 Toggle 门控，关 = 保存时清空）。
                // 接线（开关触发/改名触发自动匹配、面板与选图器、删除）全部由 kind 参数化。
                ForEach(ArtworkKind.allCases.filter { !$0.isToggleGated }) { kind in
                    artworkRow(kind)
                }
                ForEach(ArtworkKind.allCases.filter(\.isToggleGated)) { kind in
                    Toggle(L10n.tr(kind.labelKey, lang: language), isOn: gatedBinding(kind))
                        .task(id: artworkGated[kind] ?? false) {
                            await autoMatchOnToggle(kind)
                        }
                    if artworkGated[kind] == true {
                        artworkRow(kind)
                        if kind == .logo {
                            // Logo 源图尺寸比例各异：详情页横幅内的大小/位置三档可调。
                            EnumPickerRow(title: L10n.tr("game.logoSize", lang: language),
                                          cases: LogoBannerSize.allCases, selection: $logoSize, language: language)
                            EnumPickerRow(title: L10n.tr("game.logoVertical", lang: language),
                                          cases: LogoBannerVertical.allCases, selection: $logoVertical, language: language)
                            EnumPickerRow(title: L10n.tr("game.logoHorizontal", lang: language),
                                          cases: LogoBannerHorizontal.allCases, selection: $logoHorizontal, language: language)
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
        .sheet(item: $activeSearchKind) { kind in
            CoverSearchSheet(kind: kind, imageData: artworkBinding(kind), initialTerm: name)
        }
        #if !os(macOS)
        .imageSourcePicker(isPresented: pickerPresented, onImages: { datas in
            if let kind = activePickerKind, let data = datas.first {
                artworkData[kind] = data
            }
        })
        #endif
        #if os(macOS)
        // macOS 照片图库选择器：与 iOS 相册分支同口径——取 first 原样入库，不压缩。
        .photoLibraryPicker(isPresented: pickerPresented, onImages: { datas in
            if let kind = activePickerKind, let data = datas.first {
                artworkData[kind] = data
            }
        })
        #endif
        .onAppear(perform: load)
    }

    // MARK: - 五类图接线（kind 表驱动）

    /// 单类图的录入行（预览比例/缩略宽/按钮列全部查 kind 表）。
    @ViewBuilder
    private func artworkRow(_ kind: ArtworkKind) -> some View {
        ArtworkRow(
            titleKey: kind.labelKey,
            data: artworkData[kind],
            aspect: kind.previewAspect,
            thumbWidth: kind.previewThumbWidth,
            isAutoMatching: artworkMatching.contains(kind),
            onPick: {
                if ImageImport.supportsPanel {
                    pickImageFromPanel { artworkData[kind] = $0 }
                } else {
                    activePickerKind = kind
                }
            },
            onPickFromLibrary: { activePickerKind = kind },
            onSearch: { activeSearchKind = kind },
            onDelete: { artworkData[kind] = nil }
        )
    }

    /// 门控开关的双向绑定（关 = 保存时清空，数据先保留在字典里供开关重开恢复）。
    private func gatedBinding(_ kind: ArtworkKind) -> Binding<Bool> {
        Binding(
            get: { artworkGated[kind] ?? false },
            set: { artworkGated[kind] = $0 }
        )
    }

    /// 编辑页图数据的双向绑定（搜索面板直接写回对应 kind）。
    private func artworkBinding(_ kind: ArtworkKind) -> Binding<Data?> {
        Binding(
            get: { artworkData[kind] },
            set: { artworkData[kind] = $0 }
        )
    }

    /// 选图器呈现绑定：以 activePickerKind 非 nil 驱动；关闭时清 kind。
    private var pickerPresented: Binding<Bool> {
        Binding(
            get: { activePickerKind != nil },
            set: { if !$0 { activePickerKind = nil } }
        )
    }

    private var savedKey: String {
        UserDefaults.standard.string(forKey: "steamGridDBKey") ?? ""
    }

    private func load() {
        guard let game else {
            // 新建：字段全部保持默认，直接标记已加载完成，之后输入名字即可触发自动匹配。
            nameAtLoad = ""
            searchNameAtLoad = ""
            didFinishLoading = true
            return
        }
        name = game.name
        nameAtLoad = game.name
        searchNameAtLoad = game.primaryName
        status = game.statusValue
        // 游戏主平台：旧数据可能为空（已通关游戏），回退到首条记录的平台。
        platform = game.platform.isEmpty
            ? (game.sortedCompletions.first?.platform ?? Presets.platforms[0])
            : game.platform
        aliases = game.aliases
        nameZh = game.nameZh ?? ""
        nameJa = game.nameJa ?? ""
        hasCustomVersion = game.version != nil
        customVersion = game.version ?? .demo
        hasReleaseDate = game.releaseDate != nil
        releaseDate = game.releaseDate ?? Date()
        developer = game.developer ?? ""
        publisher = game.publisher ?? ""
        genre = game.genre ?? ""
        for kind in ArtworkKind.allCases {
            artworkData[kind] = game.artwork(kind)
            artworkGated[kind] = game.artwork(kind) != nil
        }
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

    /// macOS 本地选图（统一走 ImageImport seam；iOS 走 imageSourcePicker modifier + activePickerKind）。
    private func pickImageFromPanel(apply: @escaping (Data) -> Void) {
        if let data = ImageImport.pickOneFromPanel() {
            apply(data)
        }
    }

    /// 输入游戏名 → 防抖后自动匹配封面与已开开关且未设置的附加图（仅当开关开、已配 key）。
    /// 由 `.task(id: name)` 驱动：名字每次变化时取消重开、600ms 后匹配；名字未变（如编辑打开）不匹配。
    private func debouncedAutoMatch(_ newValue: String) async {
        guard newValue != searchNameAtLoad,
              autoMatchCover, !steamGridDBKey.isEmpty, didFinishLoading else { return }
        let term = newValue.trimmingCharacters(in: .whitespaces)
        // 名字过短（不足 2 字）不搜，避免输字过程中频繁命中。
        guard term.count >= 2 else { return }
        try? await Task.sleep(nanoseconds: 600_000_000)
        guard !Task.isCancelled else { return }
        // 封面（原有路径，kind=.poster 特例：无门控、恒匹配）。
        await autoFillArtwork(.poster, term: term)
        // 其余四类：开关开着且未设置的跟随改名一起匹配（防抖/静默降级与封面同款）。
        for kind in ArtworkKind.allCases where kind.isToggleGated {
            await autoFillArtwork(kind, term: term)
        }
    }

    /// 单类图的自动匹配：门控开 + 未设置才搜；静默降级；写入前复查实时值
    /// （await 期间用户可能已手动选图，不能覆盖）。
    private func autoFillArtwork(_ kind: ArtworkKind, term: String) async {
        // 封面无门控恒匹配；其余类型须开关已开。
        if kind.isToggleGated && artworkGated[kind] != true { return }
        guard artworkData[kind] == nil else { return }
        artworkMatching.insert(kind)
        defer { artworkMatching.remove(kind) }
        let client = SteamGridDBClient(apiKey: steamGridDBKey)
        do {
            if let data = try await client.autoArtwork(for: term, kind: kind), !Task.isCancelled,
               artworkData[kind] == nil {
                artworkData[kind] = data
            }
        } catch {
            // 静默降级，与封面同口径。
        }
    }

    /// 「未设置时打开某类附加图开关」→ 立即触发该类图的自动匹配（防抖 600ms 同改名路径）。
    /// 由 `.task(id: gated[kind])` 驱动；false→true 且数据为 nil 才匹配。
    private func autoMatchOnToggle(_ kind: ArtworkKind) async {
        guard (artworkGated[kind] ?? false), artworkData[kind] == nil,
              autoMatchCover, !steamGridDBKey.isEmpty, didFinishLoading else { return }
        let term = name.trimmingCharacters(in: .whitespaces)
        guard term.count >= 2 else { return }
        try? await Task.sleep(nanoseconds: 600_000_000)
        guard !Task.isCancelled else { return }
        await autoFillArtwork(kind, term: term)
    }

    private var parsedPlaytime: Double? {
        let t = playtimeText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        return Double(t)
    }

    /// 搜索配图用的名字：主名优先，**主名为空时退回任一语言槽**。
    ///
    /// 导入进来的游戏主名可以是空的（来源标题是中日文时只落语言槽，见 `Game.name` 的注释），
    /// 那种游戏直接拿 `name` 去搜会得到一个空词条、静默搜不到图。
    private var searchName: String {
        [name, nameZh, nameJa]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let nameZhTrimmed = nameZh.trimmingCharacters(in: .whitespaces)
        let nameJaTrimmed = nameJa.trimmingCharacters(in: .whitespaces)
        // 名称的硬要求是「**三种语言至少填一个**」（2026-09-16 起，不再是「必须有英文名」）：
        // 同步下来只有中文名的游戏，用户打开编辑页看到的就该是「中文名已填好、英文名空着」，
        // 而不是被逼着把中文复制一份进英文名。三个都空则库里没有任何东西能认出它，仍然拒绝。
        guard [trimmedName, nameZhTrimmed, nameJaTrimmed].contains(where: { !$0.isEmpty }) else {
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
                coverData: artworkData[.poster],
                squareData: artworkGated[.square] == true ? artworkData[.square] : nil,
                landscapeData: artworkGated[.landscape] == true ? artworkData[.landscape] : nil,
                heroData: artworkGated[.hero] == true ? artworkData[.hero] : nil,
                logoData: artworkGated[.logo] == true ? artworkData[.logo] : nil,
                logoSize: logoSize,
                logoVertical: logoVertical,
                logoHorizontal: logoHorizontal,
                // 与上方校验同口径：入库用 trim 后的标题（iOS 编辑 sheet / 写字台保存也是 trim 口径）。
                reviewTitle: reviewTitle.trimmingCharacters(in: .whitespaces),
                reviewBody: reviewBody,
                status: status,
                version: hasCustomVersion ? customVersion : nil
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
            game.version = hasCustomVersion ? customVersion : nil
            game.platform = platform
            game.aliases = aliases
            game.releaseDate = hasReleaseDate ? releaseDate : nil
            game.developer = developer.trimmingCharacters(in: .whitespaces).isEmpty ? nil : developer.trimmingCharacters(in: .whitespaces)
            game.publisher = publisher.trimmingCharacters(in: .whitespaces).isEmpty ? nil : publisher.trimmingCharacters(in: .whitespaces)
            game.genre = genre.trimmingCharacters(in: .whitespaces).isEmpty ? nil : genre.trimmingCharacters(in: .whitespaces)
            for kind in ArtworkKind.allCases {
                let gated = kind.isToggleGated ? (artworkGated[kind] == true) : true
                game.setArtwork(kind, gated ? artworkData[kind] : nil)
            }
            game.logoSizeValue = logoSize
            game.logoVerticalValue = logoVertical
            game.logoHorizontalValue = logoHorizontal
            game.reviewTitle = reviewTitle
            game.reviewBody = reviewBody
            game.groups = allGroups.filter { groupIDs.contains($0.persistentModelID) }
            game.updatedAt = .now
        }
        try? context.save()
        // 图片可能已变更（编辑写回 / 新建带图），解码缓存按模型 ID 做 key，需全量失效。
        ImageDecodeCache.bump()
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

    /// 搜索按钮文案按图类区分（复用搜索面板标题 key：搜索封面/搜索 1:1 封面/搜索横向封面/搜索背景图/搜索 Logo）。
    private var searchCoverTitleKey: String {
        switch titleKey {
        case "game.square": return "cover.titleSquare"
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
                        // 预览**所见即库内所得**：判据与库里各处共用一处
                        // `AppImage.letterboxes(inBoxAspect:)` —— 比这个槽位宽的图（导入的横图）
                        // 完整显示、上下留空，与网格卡 / 详情页一致；比槽位窄的（竖版封面、
                        // 1:1 图标）照旧填满裁切。
                        Image(appImage: image)
                            .resizable()
                            .aspectRatio(contentMode: image.letterboxes(inBoxAspect: CGFloat(aspect)) ? .fit : .fill)
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
