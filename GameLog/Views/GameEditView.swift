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
                TextField(title, text: $customText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: customText) { _, newValue in
                        value = newValue
                    }
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

/// 四维评分滑块行。
struct ScoreSliderRow: View {
    let titleKey: String
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 12) {
            LText(titleKey)
                .frame(width: 64, alignment: .leading)
            Slider(value: $value, in: 1...10, step: 0.1)
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
    @State private var degree = Presets.degrees[0]
    @State private var playtimeText = ""
    @State private var notes = ""
    @State private var sStory = 7.0
    @State private var sGraphics = 7.0
    @State private var sMusic = 7.0
    @State private var sGameplay = 7.0

    @State private var validationError: String?
    @State private var showingCoverSearch = false
    @AppStorage("steamGridDBKey") private var steamGridDBKey = ""

    private var isCreating: Bool { game == nil }

    var body: some View {
        Form {
            Section(L10n.tr("game.name", lang: language)) {
                TextField(L10n.tr("game.name", lang: language), text: $name)
                    .textFieldStyle(.roundedBorder)

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
                    TextField(L10n.tr("game.aliasPlaceholder", lang: language), text: $aliasInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            let trimmed = aliasInput.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty && !aliases.contains(trimmed) {
                                aliases.append(trimmed)
                            }
                            aliasInput = ""
                        }
                }

                Toggle(L10n.tr("game.releaseDate", lang: language), isOn: $hasReleaseDate)
                if hasReleaseDate {
                    DatePicker(
                        L10n.tr("game.releaseDate", lang: language),
                        selection: $releaseDate,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.field)
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
                TextField(L10n.tr("game.reviewTitlePlaceholder", lang: language), text: $reviewTitle)
                    .textFieldStyle(.roundedBorder)
                TextEditor(text: $reviewBody)
                    .frame(height: 100)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
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
                    DatePicker(L10n.tr("completion.date", lang: language), selection: $completionDate, displayedComponents: [.date])
                    PresetOrCustomPicker(
                        title: L10n.tr("completion.degree", lang: language),
                        presets: Presets.degrees,
                        category: .degree,
                        value: $degree
                    )
                    TextField(L10n.tr("completion.playtime", lang: language), text: $playtimeText)
                        .textFieldStyle(.roundedBorder)
                    TextEditor(text: $notes)
                        .frame(height: 80)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
                }

                Section(L10n.tr("completion.scores", lang: language)) {
                    ScoreSliderRow(titleKey: "dimension.story", value: $sStory)
                    ScoreSliderRow(titleKey: "dimension.graphics", value: $sGraphics)
                    ScoreSliderRow(titleKey: "dimension.music", value: $sMusic)
                    ScoreSliderRow(titleKey: "dimension.gameplay", value: $sGameplay)
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
        guard let game else { return }
        name = game.name
        aliases = game.aliases
        hasReleaseDate = game.releaseDate != nil
        releaseDate = game.releaseDate ?? Date()
        coverData = game.coverData
        reviewTitle = game.reviewTitle
        reviewBody = game.reviewBody
        groupIDs = Set(game.groups.map(\.persistentModelID))
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

    private var parsedPlaytime: Double? {
        let t = playtimeText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        return Double(t)
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            validationError = L10n.tr("validation.nameRequired", lang: language)
            return
        }
        let playtimeTextTrimmed = playtimeText.trimmingCharacters(in: .whitespaces)
        if !playtimeTextTrimmed.isEmpty {
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
                date: completionDate,
                degree: degree,
                playtime: parsedPlaytime,
                notes: notes,
                scoreStory: sStory,
                scoreGraphics: sGraphics,
                scoreMusic: sMusic,
                scoreGameplay: sGameplay
            )
            completion.game = newGame
            context.insert(completion)
        } else {
            guard let game else { return }
            game.name = trimmedName
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
