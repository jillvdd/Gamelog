import SwiftUI
import SwiftData

/// 统计页：总通关数、库平均分、按平台分布、榜单（平均分 + 六维排名）、整体排名入口。
struct StatsView: View {
    @Query private var games: [Game]
    @Environment(\.appLanguageCode) private var language
    @State private var showingOverall = false
    /// 点击榜单游戏名 → 编程式 push 到详情。
    @State private var selectedGame: Game?

    private var totalGames: Int { games.count }

    /// 想玩清单数量（状态机：status == backlog 的游戏数）。
    private var backlogCount: Int {
        games.filter { $0.statusValue == .backlog }.count
    }

    /// 库平均分：库内每条已评分通关记录的六维平均分之均值，取整到 0.5。
    /// 单条记录按现有六维评分求均值，一条通关记录计一次。
    private var avgScore: Double? {
        let averages = games
            .flatMap(\.completions)
            .compactMap(\.recordAverage)
        guard !averages.isEmpty else { return nil }
        return ScoreMath.roundScore(averages.reduce(0, +) / Double(averages.count))
    }

    private var platformCounts: [(platform: String, count: Int)] {
        var counts: [String: Int] = [:]
        for game in games {
            for platform in game.platformList {
                counts[platform, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }
            .map { (platform: $0.key, count: $0.value) }
    }

    private var maxPlatformCount: Int {
        platformCounts.map(\.count).max() ?? 1
    }

    var body: some View {
        NavigationStack {
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
                            Group {
                                #if os(macOS)
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
                                    statTile(
                                        value: "\(backlogCount)",
                                        label: L10n.tr("stats.backlogCount", lang: language),
                                        icon: "bookmark"
                                    )
                                }
                                #else
                                VStack(spacing: 16) {
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
                                    statTile(
                                        value: "\(backlogCount)",
                                        label: L10n.tr("stats.backlogCount", lang: language),
                                        icon: "bookmark"
                                    )
                                }
                                #endif
                            }

                            if !platformCounts.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    LText("stats.byPlatform")
                                        .font(.title3.bold())
                                    LazyVGrid(columns: platformColumns(for: geo.size.width), spacing: 8) {
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

                            rankingsSection(width: geo.size.width)
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
            .navigationTitle(L10n.tr("library.stats", lang: language))
            .appToolbar()
            .navigationDestination(item: $selectedGame) { GameDetailView(game: $0) }
            .navigationDestination(isPresented: $showingOverall) { OverallRankingView() }
        }
    }

    /// 榜单区：平均分榜（整行前 10）+ 六维榜（2 列 × 3 行，各前 5）+ 整体排名入口。
    private func rankingsSection(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LText("stats.rankings")
                .font(.title3.bold())

            RankingBoard(
                title: L10n.tr("group.avgScore", lang: language),
                entries: Rankings.byAverage(games: games, platform: nil),
                limit: 10,
                onSelect: { selectedGame = $0 }
            )

            LazyVGrid(columns: rankingColumns(for: width), spacing: 12) {
                ForEach(Dimension.allCases) { dimension in
                    RankingBoard(
                        title: L10n.tr(dimension.labelKey, lang: language),
                        entries: Rankings.byDimension(dimension, games: games, platform: nil),
                        limit: 5,
                        onSelect: { selectedGame = $0 }
                    )
                }
            }

            Button {
                showingOverall = true
            } label: {
                Label(L10n.tr("stats.overallRanking", lang: language), systemImage: "arrow.up.right")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.semantic(.controlBackground))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    /// 榜单列数：宽窗口两列，窄窗口单列。
    private func rankingColumns(for width: CGFloat) -> [GridItem] {
        if width >= 900 {
            return [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        }
        return [GridItem(.flexible(), spacing: 12)]
    }

    /// 平台分布列数：宽窗口两列，窄窗口单列。
    private func platformColumns(for width: CGFloat) -> [GridItem] {
        if width >= 900 {
            return [GridItem(.flexible(), spacing: 24), GridItem(.flexible(), spacing: 24)]
        }
        return [GridItem(.flexible(), spacing: 8)]
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
                .fill(Color.semantic(.controlBackground))
        )
    }
}
