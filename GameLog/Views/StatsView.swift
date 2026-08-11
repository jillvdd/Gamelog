import SwiftUI
import SwiftData

/// 统计页：总通关数、库平均分、按平台分布。
struct StatsView: View {
    @Query private var games: [Game]
    @Environment(\.appLanguageCode) private var language

    private var totalGames: Int { games.count }

    private var avgScore: Double? {
        let scores = games.compactMap(\.libraryScore)
        guard !scores.isEmpty else { return nil }
        return ScoreMath.roundToHalf(scores.reduce(0, +) / Double(scores.count))
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
                            VStack(spacing: 8) {
                                ForEach(platformCounts, id: \.platform) { item in
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
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .navigationTitle(L10n.tr("library.stats", lang: language))
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
