import SwiftUI
import SwiftData

/// 统计页：总通关数、库平均分、按平台分布。
struct StatsView: View {
    @Query private var games: [Game]
    @Environment(\.appLanguageCode) private var language

    private var totalGames: Int { games.count }

    /// 库平均分：库内每条已评分通关记录的六维平均分之均值，取整到 0.5。
    /// 单条记录按现有六维评分求均值，一条通关记录计一次。
    private var avgScore: Double? {
        let averages = games
            .flatMap(\.completions)
            .compactMap(\.recordAverage)
        guard !averages.isEmpty else { return nil }
        return ScoreMath.roundToHalf(averages.reduce(0, +) / Double(averages.count))
    }

    private var platformCounts: [(platform: String, count: Int)] {
        var counts: [String: Int] = [:]
        for game in games {
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
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if games.isEmpty {
                        ContentUnavailableView {
                            Image(systemName: "chart.bar")
                                .font(.system(size: 48))
                        } description: {
                            LText("stats.noData")
                        }
                    } else {
                        HStack(spacing: 16) {
                            statTile(
                                value: "\(totalGames)",
                                label: L10n.tr("stats.totalGames", lang: language),
                                icon: "gamecontroller"
                            )
                            statTile(
                                value: avgScore.map { String(format: "%.1f", $0) } ?? "—",
                                label: L10n.tr("stats.avgScore", lang: language),
                                icon: "star"
                            )
                        }

                        if !platformCounts.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                LText("stats.byPlatform")
                                    .font(.title3.bold())
                                LazyVGrid(columns: platformColumns(for: geo.size.width), spacing: 8) {
                                    ForEach(platformCounts, id: \.platform) { item in
                                        platformBar(item)
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
                .padding(28)
                .frame(maxWidth: 1500)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .navigationTitle(L10n.tr("library.stats", lang: language))
    }

    /// 平台分布列数：宽窗口两列，窄窗口单列。
    private func platformColumns(for width: CGFloat) -> [GridItem] {
        if width >= 900 {
            return [GridItem(.flexible(), spacing: 24), GridItem(.flexible(), spacing: 24)]
        }
        return [GridItem(.flexible(), spacing: 8)]
    }

    /// 单行平台条形。
    private func platformBar(_ item: (platform: String, count: Int)) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: Presets.display(item.platform, category: .platform, language: language))
                .frame(width: 160, alignment: .leading)
                .lineLimit(1)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.accentColor.opacity(0.15))
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: proxy.size.width * CGFloat(item.count) / CGFloat(maxPlatformCount))
                }
            }
            .frame(height: 10)
            Text(verbatim: "\(item.count)")
                .monospacedDigit()
                .frame(width: 32, alignment: .trailing)
        }
    }

    private func statTile(value: String, label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(Color.accentColor)
                Text(verbatim: label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text(verbatim: value)
                .font(.system(size: 44, weight: .bold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}
