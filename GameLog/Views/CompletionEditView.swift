import SwiftUI
import SwiftData

/// 追加/编辑一条通关记录。首条记录评分必填（不可跳过），后续记录可跳过评分。
struct CompletionEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    @Environment(\.dismiss) private var dismiss
    let game: Game
    let completion: Completion?   // nil = 追加

    @State private var platform = Presets.platforms[0]
    @State private var date = Date()
    @State private var dateIsNone = false
    @State private var degree = Presets.degrees[0]
    @State private var playtimeText = ""
    @State private var playtimeIsNone = false
    @State private var notes = ""
    /// 每维评分开关：关 = 该维分数存 nil（平均分只算开启的维度）。全关 = 跳过评分。
    /// 首条记录至少开一维。
    @State private var eGameplay = true
    @State private var eDesign = true
    @State private var eStory = true
    @State private var eArt = true
    @State private var eMusic = true
    @State private var ePerformance = true
    @State private var sGameplay = 7.0
    @State private var sDesign = 7.0
    @State private var sStory = 7.0
    @State private var sArt = 7.0
    @State private var sMusic = 7.0
    @State private var sPerformance = 7.0

    @State private var validationError: String?

    /// 是否是游戏的首条记录（首条评分必填）。
    private var isFirst: Bool {
        guard let completion else { return game.sortedCompletions.isEmpty }
        return game.sortedCompletions.first?.persistentModelID == completion.persistentModelID
    }

    private var isEditing: Bool { completion != nil }

    var body: some View {
        Form {
            Section {
                PresetOrCustomPicker(
                    title: L10n.tr("completion.platform", lang: language),
                    presets: Presets.platforms,
                    category: .platform,
                    collapsible: true,
                    value: $platform
                )
                DateMenuPicker(title: L10n.tr("completion.date", lang: language), selection: $date)
                    .disabled(dateIsNone)
                Toggle(L10n.tr("completion.noDate", lang: language), isOn: $dateIsNone)
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
        .formStyle(.grouped)
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 520)
        #endif
        .navigationTitle(isEditing ? L10n.tr("title.editCompletion", lang: language) : L10n.tr("title.addCompletion", lang: language))
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
        .onAppear(perform: load)
    }

    private func load() {
        guard let completion else { return }
        platform = completion.platform
        date = completion.date ?? Date()
        dateIsNone = completion.date == nil
        degree = completion.degree
        playtimeText = completion.playtime.map { String($0) } ?? ""
        playtimeIsNone = completion.playtime == nil
        notes = completion.notes
        // 开关 = 该维是否有分；无分记录（历史跳过评分的）全维关闭，滑块值保持默认 7 备用。
        eGameplay = completion.scoreGameplay != nil
        eDesign = completion.scoreDesign != nil
        eStory = completion.scoreStory != nil
        eArt = completion.scoreArt != nil
        eMusic = completion.scoreMusic != nil
        ePerformance = completion.scorePerformance != nil
        if let v = completion.scoreGameplay { sGameplay = v }
        if let v = completion.scoreDesign { sDesign = v }
        if let v = completion.scoreStory { sStory = v }
        if let v = completion.scoreArt { sArt = v }
        if let v = completion.scoreMusic { sMusic = v }
        if let v = completion.scorePerformance { sPerformance = v }
    }

    private var parsedPlaytime: Double? {
        let t = playtimeText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        return Double(t)
    }

    private func save() {
        let t = playtimeText.trimmingCharacters(in: .whitespaces)
        if !playtimeIsNone && !t.isEmpty {
            guard let value = Double(t), value >= 0 else {
                validationError = L10n.tr("validation.playtimeInvalid", lang: language)
                return
            }
        }
        // 首条记录至少评一维；后续记录全关 = 跳过评分（合法）。
        let anyEnabled = eGameplay || eDesign || eStory || eArt || eMusic || ePerformance
        if isFirst && !anyEnabled {
            validationError = L10n.tr("validation.scoreRequired", lang: language)
            return
        }

        if let completion {
            completion.platform = platform
            completion.date = dateIsNone ? nil : date
            completion.degree = degree
            completion.playtime = playtimeIsNone ? nil : parsedPlaytime
            completion.notes = notes
            completion.scoreGameplay = eGameplay ? sGameplay : nil
            completion.scoreDesign = eDesign ? sDesign : nil
            completion.scoreStory = eStory ? sStory : nil
            completion.scoreArt = eArt ? sArt : nil
            completion.scoreMusic = eMusic ? sMusic : nil
            completion.scorePerformance = ePerformance ? sPerformance : nil
        } else {
            let newCompletion = Completion(
                platform: platform,
                date: dateIsNone ? nil : date,
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
            newCompletion.game = game
            context.insert(newCompletion)
        }
        try? context.save()
        dismiss()
    }
}
