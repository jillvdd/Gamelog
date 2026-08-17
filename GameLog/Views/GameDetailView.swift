import SwiftUI
import SwiftData

#if os(macOS)
import AppKit
#endif

/// 一条通关记录的卡片（详情页内）。
struct CompletionCardView: View {
    @Environment(\.appLanguageCode) private var language
    let completion: Completion
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                #if os(macOS)
                HStack(spacing: 8) {
                    if let date = completion.date {
                        Text(verbatim: date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 12, weight: .semibold))
                    }
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
                    scoreView
                    editButton
                    deleteButton
                }
                #else
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        if let date = completion.date {
                            Text(verbatim: date.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 12, weight: .semibold))
                        }
                        if let playtime = completion.playtime {
                            Text(verbatim: L10n.tr("completion.playtimeFormat", [playtime], lang: language))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        scoreView
                        editButton
                        deleteButton
                    }
                    if !completion.platform.isEmpty || !completion.degree.isEmpty {
                        HStack(spacing: 8) {
                            if !completion.platform.isEmpty {
                                chip(Presets.display(completion.platform, category: .platform, language: language))
                            }
                            if !completion.degree.isEmpty {
                                chip(Presets.display(completion.degree, category: .degree, language: language))
                            }
                        }
                    }
                }
                #endif
            }

            if completion.hasScores {
                HStack(spacing: 16) {
                    ForEach(Dimension.allCases) { dimension in
                        VStack(spacing: 2) {
                            LText(dimension.labelKey)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(verbatim: completion.score(for: dimension).map { String(format: "%.1f", $0) } ?? "—")
                                .font(.system(.body, design: .monospaced))
                        }
                        .frame(maxWidth: .infinity)
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
                .fill(Color.semantic(.controlBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.semantic(.separator))
        )
    }

    /// 平均分显示（已评分显示数字，未评分显示「未评分」）。
    @ViewBuilder
    private var scoreView: some View {
        if let avg = completion.displayAverage {
            Text(verbatim: String(format: "%.1f", avg))
                .font(.system(size: 18, weight: .bold))
                .monospacedDigit()
        } else {
            LText("score.unrated")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var editButton: some View {
        Button(action: onEdit) {
            Image(systemName: "pencil")
        }
        .buttonStyle(.borderless)
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.red)
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
    }
}

/// 详情页头部的六维评分条形图：每维度一条，颜色区分，长度按 10 分制比例。
private struct DimensionScoreBars: View {
    let game: Game

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Dimension.allCases) { dimension in
                let value = game.dimensionAverage(for: dimension)
                HStack(spacing: 8) {
                    LText(dimension.labelKey)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: 96, alignment: .leading)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.semantic(.quaternarySystemFill))
                        if let value {
                            Capsule()
                                .fill(dimension.barColor)
                                .frame(width: 150 * (value / 10))
                        }
                    }
                    .frame(width: 150, height: 6)
                    Text(verbatim: value.map { String(format: "%.1f", $0) } ?? "—")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 26, alignment: .trailing)
                }
            }
        }
    }
}

private extension Dimension {
    /// 六维条形图的颜色（详情页用）。
    var barColor: Color {
        switch self {
        case .gameplay: .orange
        case .design: .teal
        case .story: .blue
        case .art: .purple
        case .music: .pink
        case .performance: .green
        }
    }
}

/// 详情页名字下方的其他语言名小字：不带语言标记、上下并排，只显示设置了的，且去掉与主名重复的。
private struct LocalizedNamesSubtitle: View {
    let game: Game
    let currentLanguage: String

    private var names: [String] {
        let others: [String]
        switch currentLanguage {
        case "zh-Hans": others = [game.name, game.nameJa].compactMap { $0 }
        case "ja": others = [game.nameZh, game.name].compactMap { $0 }
        default: others = [game.nameZh, game.nameJa].compactMap { $0 }
        }
        let display = game.displayName(for: currentLanguage)
        return others.filter { $0 != display }
    }

    var body: some View {
        if !names.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                    Text(verbatim: name)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// 详情页状态选择器：自定义滑动条（图标 + 文字），选中滑块用 offset 定位滑动。
/// 滑块位置由内部独立 @State 驱动——点击立即在本视图内动画，不依赖父视图重算（保证流畅）。
private struct DetailStatusPicker: View {
    @Environment(\.appLanguageCode) private var language
    @Binding var status: GameStatus
    let onChanged: (GameStatus) -> Void
    /// 紧凑模式（只图标，窄屏如 iPhone 用）；macOS 显示图标 + 小字。
    var compact: Bool = false

    /// 滑块当前列（内部状态，点击立即动画，父重算不影响）。
    @State private var sliderIndex: Int

    init(status: Binding<GameStatus>, compact: Bool = false, onChanged: @escaping (GameStatus) -> Void) {
        _status = status
        self.compact = compact
        self.onChanged = onChanged
        _sliderIndex = State(initialValue: GameStatus.allCases.firstIndex(of: status.wrappedValue) ?? 0)
    }

    var body: some View {
        GeometryReader { geo in
            let all = GameStatus.allCases
            let cellWidth = geo.size.width / CGFloat(all.count)
            ZStack(alignment: .topLeading) {
                // 选中滑块：内部 sliderIndex 驱动，offset + spring 动画，独立于父视图重算。
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.accentColor.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1)
                    )
                    .frame(width: cellWidth, height: geo.size.height)
                    .offset(x: CGFloat(sliderIndex) * cellWidth)
                    .animation(.spring(response: 0.3, dampingFraction: 0.78), value: sliderIndex)
                // 按钮层：每个状态一列，整格可点。
                HStack(spacing: 0) {
                    ForEach(all) { s in
                        Button {
                            let idx = all.firstIndex(of: s) ?? 0
                            guard idx != sliderIndex else { return }
                            sliderIndex = idx
                            status = s
                            onChanged(s)
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: s.statusIcon)
                                    .font(.system(size: compact ? 13 : 14, weight: .semibold))
                                if !compact {
                                    Text(verbatim: L10n.tr(s.labelKey, lang: language))
                                        .font(.system(size: 10))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.6)
                                }
                            }
                            .foregroundStyle(status == s ? Color.accentColor : Color.secondary)
                            .frame(width: cellWidth, height: geo.size.height)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(L10n.tr(s.labelKey, lang: language))
                    }
                }
            }
        }
        .frame(height: compact ? 42 : 56)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.thinMaterial)
        }
    }
}

/// 状态图标（状态条用）。
private extension GameStatus {
    var statusIcon: String {
        switch self {
        case .backlog: "bookmark"
        case .playing: "play.circle"
        case .paused: "pause.circle"
        case .dropped: "xmark.circle"
        case .longRunning: "infinity"
        case .completed: "checkmark.circle"
        }
    }
}

/// 详情页内部页签（收藏家模式开启时显示分段切换）：详情 = 现有内容，持有 = 收藏记录。
private enum DetailTab: Hashable {
    case details
    case holdings
}

/// 游戏详情页：信息 + 评价 + 通关记录列表（收藏家模式开启时多一个「持有」页签）。
struct GameDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UserCustomization.collectorModeKey) private var collectorMode = false
    let game: Game

    @State private var detailTab: DetailTab = .details
    @State private var showingEditGame = false
    @State private var showingAddCompletion = false
    @State private var editingCompletion: Completion?
    @State private var pendingDeleteCompletion: Completion?
    @State private var showingDeleteGame = false
    @State private var showingShare = false
    /// 状态机选中值：绑定局部 @State 隔离，避免每次点击时因 game 模型变化导致 Picker 重绘重载。
    @State private var detailStatus = GameStatus.completed

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
                    if collectorMode {
                        detailTabPicker
                    }
                    if collectorMode && detailTab == .holdings {
                        HoldingsView(game: game)
                    } else {
                        detailsContent(width: geo.size.width)
                    }
                }
                #if os(macOS)
                .padding(28)
                #else
                .padding(16)
                #endif
                .frame(maxWidth: 1500)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .navigationTitle(game.displayName(for: language))
        .onAppear { detailStatus = game.statusValue }
        // 全屏毛玻璃下推 + 「隐藏上方毛玻璃」开关由全局 appToolbar() 统一处理。
        .appToolbar()
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showingShare = true
                } label: {
                    Label(L10n.tr("library.share", lang: language), systemImage: "square.and.arrow.up")
                }
                if game.isCompletedOrLongRunning {
                    Button {
                        showingAddCompletion = true
                    } label: {
                        Label(L10n.tr("completion.add", lang: language), systemImage: "plus")
                    }
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
        .sheet(isPresented: $showingEditGame) {
            #if os(macOS)
            GameEditView(game: game)
            #else
            NavigationStack { GameEditView(game: game) }
            #endif
        }
        .sheet(isPresented: $showingAddCompletion) {
            #if os(macOS)
            CompletionEditView(game: game, completion: nil)
            #else
            NavigationStack { CompletionEditView(game: game, completion: nil) }
            #endif
        }
        .sheet(item: $editingCompletion) { completion in
            #if os(macOS)
            CompletionEditView(game: game, completion: completion)
            #else
            NavigationStack { CompletionEditView(game: game, completion: completion) }
            #endif
        }
        .sheet(isPresented: $showingShare) { SharePanelView(preselected: [game]) }
        .platformConfirmDialog(
            L10n.tr("common.confirmDelete", lang: language),
            isPresented: Binding(
                get: { pendingDeleteCompletion != nil },
                set: { if !$0 { pendingDeleteCompletion = nil } }
            ),
            message: L10n.tr("completion.delete", lang: language),
            cancelTitle: L10n.tr("common.cancel", lang: language),
            actions: [
                ConfirmAction(
                    title: L10n.tr("common.confirmDelete", lang: language),
                    isDestructive: true
                ) {
                    if let completion = pendingDeleteCompletion {
                        context.delete(completion)
                    }
                }
            ]
        )
        .platformConfirmDialog(
            L10n.tr("common.confirmDelete", lang: language),
            isPresented: $showingDeleteGame,
            message: L10n.tr("delete.confirmGame", [game.displayName(for: language)], lang: language),
            cancelTitle: L10n.tr("common.cancel", lang: language),
            actions: [
                ConfirmAction(
                    title: L10n.tr("common.confirmDelete", lang: language),
                    isDestructive: true
                ) {
                    context.delete(game)
                    dismiss()
                }
            ]
        )
    }

    // MARK: - 头部

    private var header: some View {
        Group {
            #if os(macOS)
            HStack(alignment: .top, spacing: 24) {
                coverBlock
                infoBlock
                Spacer()
            }
            #else
            VStack(alignment: .leading, spacing: 16) {
                coverBlock
                infoBlock
            }
            #endif
        }
    }

    /// 封面块：160×213 竖版封面（无封面时占位图标）。
    private var coverBlock: some View {
        Group {
            if let image = game.coverImage {
                Image(appImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    Rectangle().fill(Color.semantic(.quaternarySystemFill))
                    Image(systemName: "gamecontroller")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: 160, height: 213)
        .background(Rectangle().fill(Color.semantic(.quaternarySystemFill)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }

    /// 信息块：主名/其他语言名/发售日/平台/分组/评分与条形图。
    private var infoBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 名字 + 平台图标：一行放得下就并排；放不下（尤其多平台+超宽字标）自动换行成两行，避免撑宽整页布局。
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: game.displayName(for: language))
                        .font(.system(size: 26, weight: .bold))
                    GamePlatformIcons(platforms: platforms, maxCount: 10, iconSize: 18)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: game.displayName(for: language))
                        .font(.system(size: 26, weight: .bold))
                    GamePlatformIcons(platforms: platforms, maxCount: 10, iconSize: 18)
                }
            }
            LocalizedNamesSubtitle(game: game, currentLanguage: language)

            // 状态机：自定义滑动条（offset 滑块），点击即切换并保存。
            // 图标 + 文字同显（含 iOS：只有图标用户会看不懂含义）。
            DetailStatusPicker(status: $detailStatus) { newValue in
                guard newValue != game.statusValue else { return }
                game.statusValue = newValue
                try? context.save()
            }

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

            VStack(alignment: .leading, spacing: 10) {
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
                if game.libraryScore != nil {
                    DimensionScoreBars(game: game)
                }
            }
            .padding(.top, 6)
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
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.semantic(.controlBackground)))
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

    /// 详情页内容（现有评价 + 通关记录）。收藏家模式关时直接显示；开时在「详情」页签显示。
    @ViewBuilder
    private func detailsContent(width: CGFloat) -> some View {
        if width >= 1000 {
            if hasReview {
                wideContent(contentWidth: min(1500, width) - 56)
            } else {
                completionsSection
            }
        } else {
            reviewSection
            completionsSection
        }
    }

    /// 「详情 / 持有」分段切换（收藏家模式开启时显示在分数下方）。
    private var detailTabPicker: some View {
        Picker("", selection: $detailTab) {
            Text(verbatim: L10n.tr("detail.details", lang: language)).tag(DetailTab.details)
            Text(verbatim: L10n.tr("detail.holdings", lang: language)).tag(DetailTab.holdings)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        #if os(macOS)
        .frame(maxWidth: 280, alignment: .leading)
        #else
        .frame(maxWidth: .infinity)
        #endif
    }

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

    @ViewBuilder
    private var completionsSection: some View {
        // 已通关/长线游玩显示通关记录区；想玩等在玩轻量状态隐藏（数据保留，切回已通关恢复显示）。
        if game.isCompletedOrLongRunning {
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
}
