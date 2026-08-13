import SwiftUI

/// 单行平台条形（分组统计 / 全局统计共用）。
struct PlatformBarRow: View {
    let platform: String
    let count: Int
    let maxCount: Int
    let language: String

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: Presets.display(platform, category: .platform, language: language))
                .frame(width: 160, alignment: .leading)
                .lineLimit(1)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.accentColor.opacity(0.15))
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: proxy.size.width * CGFloat(count) / CGFloat(maxCount))
                }
            }
            .frame(height: 10)
            Text(verbatim: "\(count)")
                .monospacedDigit()
                .frame(width: 32, alignment: .trailing)
        }
    }
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
        return counts.sorted { $0.value > $1.value }
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
                    .fill(Color(nsColor: .controlBackgroundColor))
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
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            }
        }
    }
}

/// 分组视图底部的评价区块：展示分组评价，点「编辑」弹窗修改。
struct GroupReviewSection: View {
    @Environment(\.appLanguageCode) private var language
    let group: GameGroup

    @State private var showingEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                LText("group.review")
                    .font(.title3.bold())
                Spacer()
                Button {
                    showingEditor = true
                } label: {
                    Label(L10n.tr("common.edit", lang: language), systemImage: "pencil")
                }
            }
            Text(verbatim: group.review.isEmpty ? L10n.tr("group.reviewEmpty", lang: language) : group.review)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
        }
        .sheet(isPresented: $showingEditor) {
            GroupReviewEditSheet(group: group)
        }
    }
}

/// 编辑分组评价的弹窗（显式保存）。
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
        VStack(spacing: 16) {
            LText("group.reviewEdit")
                .font(.headline)
            BorderedTextEditor(text: $text, minHeight: 180)
                .frame(width: 460)
            HStack {
                Button(L10n.tr("common.cancel", lang: language)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.tr("common.save", lang: language)) {
                    group.review = text
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 540)
    }
}
