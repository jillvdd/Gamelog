import SwiftUI
import SwiftData

/// 一条通关记录的卡片（详情页内）。
struct CompletionCardView: View {
    @Environment(\.appLanguageCode) private var language
    let completion: Completion
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(verbatim: completion.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 12, weight: .semibold))
                if !completion.platform.isEmpty {
                    chip(Presets.display(completion.platform, category: .platform, language: language))
                }
                if !completion.degree.isEmpty {
                    chip(Presets.display(completion.degree, category: .degree, language: language))
                }
                if let playtime = completion.playtime {
                    Text(verbatim: L10n.tr("completion.playtimeFormat", [playtime], lang: language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let avg = completion.displayAverage {
                    Text(verbatim: String(format: "%.1f", avg))
                        .font(.system(size: 18, weight: .bold))
                        .monospacedDigit()
                } else {
                    LText("score.unrated")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
            }

            if completion.hasScores {
                HStack(spacing: 16) {
                    ForEach(Dimension.allCases) { dimension in
                        VStack(spacing: 2) {
                            LText(dimension.labelKey)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(verbatim: completion.score(for: dimension).map { String(format: "%.1f", $0) } ?? "—")
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }
            }

            if !completion.notes.isEmpty {
                Text(verbatim: completion.notes)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor))
        )
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
    }
}

/// 游戏详情页：信息 + 评价 + 通关记录列表。
struct GameDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    @Environment(\.dismiss) private var dismiss
    let game: Game

    @State private var showingEditGame = false
    @State private var showingAddCompletion = false
    @State private var editingCompletion: Completion?
    @State private var pendingDeleteCompletion: Completion?
    @State private var showingDeleteGame = false
    @State private var showingShare = false

    private var platforms: [String] {
        game.platformList
    }

    /// 是否有评价内容（标题或正文）。
    private var hasReview: Bool {
        !game.reviewTitle.isEmpty || !game.reviewBody.isEmpty
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    if geo.size.width >= 1000 {
                        if hasReview {
                            wideContent(contentWidth: min(1500, geo.size.width) - 56)
                        } else {
                            completionsSection
                        }
                    } else {
                        reviewSection
                        completionsSection
                    }
                }
                .padding(28)
                .frame(maxWidth: 1500)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .navigationTitle(game.name)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showingShare = true
                } label: {
                    Label(L10n.tr("library.share", lang: language), systemImage: "square.and.arrow.up")
                }
                Button {
                    showingAddCompletion = true
                } label: {
                    Label(L10n.tr("completion.add", lang: language), systemImage: "plus")
                }
                Button {
                    showingEditGame = true
                } label: {
                    Label(L10n.tr("common.edit", lang: language), systemImage: "pencil")
                }
                Button(role: .destructive) {
                    showingDeleteGame = true
                } label: {
                    Label(L10n.tr("common.delete", lang: language), systemImage: "trash")
                }
            }
        }
        .sheet(isPresented: $showingEditGame) { GameEditView(game: game) }
        .sheet(isPresented: $showingAddCompletion) { CompletionEditView(game: game, completion: nil) }
        .sheet(item: $editingCompletion) { completion in
            CompletionEditView(game: game, completion: completion)
        }
        .sheet(isPresented: $showingShare) { SharePanelView(preselected: [game]) }
        .confirmationDialog(
            L10n.tr("common.confirmDelete", lang: language),
            isPresented: Binding(
                get: { pendingDeleteCompletion != nil },
                set: { if !$0 { pendingDeleteCompletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.tr("common.confirmDelete", lang: language), role: .destructive) {
                if let completion = pendingDeleteCompletion {
                    context.delete(completion)
                }
            }
        } message: {
            LText("completion.delete")
        }
        .confirmationDialog(
            L10n.tr("common.confirmDelete", lang: language),
            isPresented: $showingDeleteGame,
            titleVisibility: .visible
        ) {
            Button(L10n.tr("common.confirmDelete", lang: language), role: .destructive) {
                context.delete(game)
                dismiss()
            }
        } message: {
            Text(verbatim: L10n.tr("delete.confirmGame", [game.name], lang: language))
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .top, spacing: 24) {
            Group {
                if let image = game.coverImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Rectangle().fill(Color(nsColor: .quaternarySystemFill))
                        Image(systemName: "gamecontroller")
                            .font(.system(size: 40))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(width: 160, height: 213)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)

            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: game.name)
                    .font(.system(size: 26, weight: .bold))

                if let date = game.releaseDate {
                    Text(verbatim: date.formatted(date: .long, time: .omitted))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if !platforms.isEmpty {
                    Text(verbatim: platforms
                        .map { Presets.display($0, category: .platform, language: language) }
                        .joined(separator: " · "))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if !game.groups.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(game.groups) { group in
                            Text(verbatim: group.name)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                        }
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let score = game.libraryScore {
                        Text(verbatim: String(format: "%.1f", score))
                            .font(.system(size: 44, weight: .bold))
                            .monospacedDigit()
                        LText("score.average")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    } else {
                        LText("score.unrated")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 6)
            }
            Spacer()
        }
    }

    // MARK: - 评价

    /// 评价正文卡片（不含标题，标题由调用方按布局需要放置）。
    @ViewBuilder
    private var reviewBodySection: some View {
        if !game.reviewBody.isEmpty {
            Text(verbatim: game.reviewBody)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineSpacing(4)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        }
    }

    /// 评价区（单栏模式）：标题 + 正文卡片。
    @ViewBuilder
    private var reviewSection: some View {
        if !game.reviewTitle.isEmpty || !game.reviewBody.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if !game.reviewTitle.isEmpty {
                    Text(verbatim: game.reviewTitle)
                        .font(.title3.bold())
                }
                reviewBodySection
            }
        }
    }

    // MARK: - 通关记录

    /// 宽窗口双列：评价标题与正文占约 58% 宽度，通关记录占剩余。
    /// 评价标题与「通关记录」标题同为 title3 粗体，两列顶部天然对齐。
    private func wideContent(contentWidth: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: game.reviewTitle)
                    .font(.title3.bold())
                reviewBodySection
            }
            .frame(width: max(340, contentWidth * 0.58), alignment: .leading)
            completionsSection
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var completionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                LText("game.completions")
                    .font(.title3.bold())
                Text(verbatim: "(\(game.completions.count))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showingAddCompletion = true
                } label: {
                    Label(L10n.tr("completion.add", lang: language), systemImage: "plus.circle")
                }
            }

            if game.sortedCompletions.isEmpty {
                LText("library.noResult")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(game.sortedCompletions) { completion in
                    CompletionCardView(
                        completion: completion,
                        onEdit: { editingCompletion = completion },
                        onDelete: { pendingDeleteCompletion = completion }
                    )
                }
            }
        }
    }
}
