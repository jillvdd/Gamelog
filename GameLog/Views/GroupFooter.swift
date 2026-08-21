import SwiftUI

/// 单行平台条形（分组统计 / 全局统计共用）。
struct PlatformBarRow: View {
    let platform: String
    let count: Int
    let maxCount: Int
    let language: String

    /// 平台名字号：图标放大后（非白底 ×1.5）文字随之放大，视觉协调。
    private let nameFontSize: CGFloat = 14

    /// 条形可视部分的最小宽度（极窄单元格时）。
    private let barMinWidth: CGFloat = 30

    /// 整行宽度（背景测量填充，不影响行自然高度）。
    @State private var rowWidth: CGFloat = 0

    var body: some View {
        let iconW = PlatformIcon.displayWidth(platform: platform, size: 14)
        let name = Presets.display(platform, category: .platform, language: language)
        return HStack(spacing: 12) {
            // 图标固定宽度区域：放大图标不挤压、不与文字重叠。
            PlatformIcon(platform: platform, size: 14)
                .frame(width: iconW, alignment: .leading)
            // 平台名：占满剩余宽度，过长自动缩放（不省略、不溢出重叠）。
            Text(verbatim: name)
                .font(.system(size: nameFontSize))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
            // 条形图：固定宽度（整行的 38%，不随名字伸缩），保底 barMinWidth。
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.accentColor.opacity(0.15))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(barWidth, barMinWidth) * CGFloat(count) / CGFloat(maxCount))
            }
            .frame(width: max(barWidth, barMinWidth))
            .frame(height: 12)
            // 计数。
            Text(verbatim: "\(count)")
                .font(.system(size: nameFontSize))
                .monospacedDigit()
                .frame(width: 32, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { rowWidth = proxy.size.width }
            }
        )
    }

    /// 条形固定宽度：整行可用宽度的 38%，与名字长短无关。
    private var barWidth: CGFloat { rowWidth * 0.38 }
}

/// 分组视图底部的统计区块：平均分（按游戏聚合）+ 平台分布（按通关记录计数）。
/// 统计始终反映整个分组，不受搜索/平台筛选影响。
struct GroupStatsSection: View {
    @Environment(\.appLanguageCode) private var language
    let group: GameGroup

    /// 分组内各游戏的库显示分（按游戏聚合，取整到 0.5）；未评分游戏不计入。
    private var gameScores: [Double] {
        group.games.compactMap(\.libraryScore)
    }

    /// 平均分：已评分游戏的库分均值，再取整到 0.1；无已评分游戏则 nil。
    private var averageScore: Double? {
        guard !gameScores.isEmpty else { return nil }
        return ScoreMath.roundScore(gameScores.reduce(0, +) / Double(gameScores.count))
    }

    /// 平台分布：分组内所有通关记录按平台计数（与全局统计页同口径）。
    private var platformCounts: [(platform: String, count: Int)] {
        var counts: [String: Int] = [:]
        for game in group.games {
            for completion in game.completions where !completion.platform.isEmpty {
                counts[completion.platform, default: 0] += 1
            }
        }
        // 计数降序；数量相同时按平台名升序，保证排序稳定、相同数量不反复横跳。
        return counts.sorted {
            $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
        }
        .map { (platform: $0.key, count: $0.value) }
    }

    private var maxPlatformCount: Int {
        platformCounts.map(\.count).max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LText("group.stats")
                .font(.title3.bold())

            // 平均分方块（与全局统计页样式一致）。
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "star")
                        .foregroundStyle(Color.accentColor)
                    LText("group.avgScore")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text(verbatim: averageScore.map { String(format: "%.1f", $0) } ?? "—")
                    .font(.system(size: 44, weight: .bold))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.semantic(.controlBackground))
            )

            if !platformCounts.isEmpty {
                LText("stats.byPlatform")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                VStack(spacing: 8) {
                    ForEach(platformCounts, id: \.platform) { item in
                        PlatformBarRow(
                            platform: item.platform,
                            count: item.count,
                            maxCount: maxPlatformCount,
                            language: language
                        )
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.semantic(.controlBackground))
                )
            }
        }
    }
}

/// 分组视图底部的评价区块：展示分组评价，点「编辑」修改。
/// macOS 用与游戏同款的独立写字台窗口（ReviewEditorSession + reviewEditor 窗口）；
/// iOS 弹出纯文本编辑 sheet（与游戏 iOS 编辑一致）。
struct GroupReviewSection: View {
    @Environment(\.appLanguageCode) private var language
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    let group: GameGroup

    @State private var showingEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                LText("group.review")
                    .font(.title3.bold())
                Spacer()
                Button {
                    #if os(macOS)
                    ReviewEditorSession.shared.groupID = group.persistentModelID
                    ReviewEditorSession.shared.gameID = nil
                    openWindow(id: "reviewEditor")
                    #else
                    showingEditor = true
                    #endif
                } label: {
                    Label(L10n.tr("common.edit", lang: language), systemImage: "pencil")
                }
            }
            if group.review.isEmpty {
                Text(verbatim: L10n.tr("group.reviewEmpty", lang: language))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.semantic(.controlBackground))
                    )
            } else {
                MarkdownReviewView(markdown: group.review)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.semantic(.controlBackground))
                    )
            }
        }
        .sheet(isPresented: $showingEditor) {
            groupReviewEditSheet
        }
    }

    /// 分组评价编辑 sheet：仅 iOS 使用（macOS 走独立写字台窗口）。
    @ViewBuilder
    private var groupReviewEditSheet: some View {
        #if os(iOS)
        GroupReviewEditSheet(group: group)
        #else
        EmptyView()
        #endif
    }
}

/// iOS 编辑分组评价的 sheet：纯文本 Markdown 输入（与游戏 iOS 编辑一致，无内置预览）。
/// macOS 走独立写字台窗口（ReviewEditorView），不使用此 sheet。
#if os(iOS)
struct GroupReviewEditSheet: View {
    @Environment(\.appLanguageCode) private var language
    @Environment(\.dismiss) private var dismiss
    let group: GameGroup
    @State private var text: String

    init(group: GameGroup) {
        self.group = group
        _text = State(initialValue: group.review)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                TextEditor(text: $text)
                    .font(.body)
                    .padding(4)
            }
            .navigationTitle(L10n.tr("group.reviewEdit", lang: language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("common.cancel", lang: language)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.tr("review.save", lang: language)) {
                        group.review = text
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
#endif
