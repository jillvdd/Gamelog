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
    @State private var degree = Presets.degrees[0]
    @State private var playtimeText = ""
    @State private var notes = ""
    @State private var skipScores = false
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
                PresetOrCustomPicker(
                    title: L10n.tr("completion.degree", lang: language),
                    presets: Presets.degrees,
                    category: .degree,
                    value: $degree
                )
                TextField(L10n.tr("completion.playtime", lang: language), text: $playtimeText)
                    .textFieldStyle(.roundedBorder)
                BorderedTextEditor(text: $notes, minHeight: 80)
            }

            Section(L10n.tr("completion.scores", lang: language)) {
                Toggle(L10n.tr("completion.skipScores", lang: language), isOn: $skipScores)
                    .disabled(isFirst)
                if !skipScores {
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
        .frame(minWidth: 520, minHeight: 520)
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
        date = completion.date
        degree = completion.degree
        playtimeText = completion.playtime.map { String($0) } ?? ""
        notes = completion.notes
        skipScores = !completion.hasScores
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
        if !t.isEmpty {
            guard let value = Double(t), value >= 0 else {
                validationError = L10n.tr("validation.playtimeInvalid", lang: language)
                return
            }
        }
        let effectiveSkip = isFirst ? false : skipScores

        if let completion {
            completion.platform = platform
            completion.date = date
            completion.degree = degree
            completion.playtime = parsedPlaytime
            completion.notes = notes
            if effectiveSkip {
                completion.scoreGameplay = nil
                completion.scoreDesign = nil
                completion.scoreStory = nil
                completion.scoreArt = nil
                completion.scoreMusic = nil
                completion.scorePerformance = nil
            } else {
                completion.scoreGameplay = sGameplay
                completion.scoreDesign = sDesign
                completion.scoreStory = sStory
                completion.scoreArt = sArt
                completion.scoreMusic = sMusic
                completion.scorePerformance = sPerformance
            }
        } else {
            let newCompletion = Completion(
                platform: platform,
                date: date,
                degree: degree,
                playtime: parsedPlaytime,
                notes: notes,
                scoreGameplay: effectiveSkip ? nil : sGameplay,
                scoreDesign: effectiveSkip ? nil : sDesign,
                scoreStory: effectiveSkip ? nil : sStory,
                scoreArt: effectiveSkip ? nil : sArt,
                scoreMusic: effectiveSkip ? nil : sMusic,
                scorePerformance: effectiveSkip ? nil : sPerformance
            )
            newCompletion.game = game
            context.insert(newCompletion)
        }
        dismiss()
    }
}
