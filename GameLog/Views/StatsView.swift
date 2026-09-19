import SwiftUI
import SwiftData
import Charts

/// 统计页：苹果现代高级感设计语言（Bento 栅格、Fitness 风格指标看板、Swift Charts 时长体量分布、
/// 状态流转胶囊、攻关深度与跨平台成就、常玩厂商 Top 5、收藏金库与多维动态排行榜）。
struct StatsView: View {
    @Query private var games: [Game]
    @Environment(\.appLanguageCode) private var language
    @AppStorage(UserCustomization.hideToolbarGlassKey) private var hideToolbarGlass = false
    @AppStorage(UserCustomization.collectorModeKey) private var collectorMode = false
    @State private var showingOverall = false
    @State private var rankingCategory = 0 // 0 = 评分榜, 1 = 时长榜
    @State private var selectedGame: Game?
    @State private var showAllPlatforms = false

    /// 还活着的游戏。本页所有统计、图表、榜单、封面都从这单一入口取。
    private var liveGames: [Game] { games.filter(\.isLive) }
    private var totalGames: Int { liveGames.count }

    // MARK: - 派生统计（唯一归属 = Support/LibraryStats.swift）

    private var clearedCount: Int { LibraryStats.clearedGameCount(liveGames) }
    private var completionRate: Double? { LibraryStats.completionRate(liveGames) }
    private var totalPlaytime: Double { LibraryStats.totalPlaytimeHours(liveGames) }
    private var avgPlaytime: Double? { LibraryStats.averagePlaytimeHours(liveGames) }
    private var avgScore: Double? { LibraryStats.averageScore(liveGames) }
    private var scoredCount: Int { LibraryStats.scoredGameCount(liveGames) }
    private var backlogCount: Int { LibraryStats.backlogCount(liveGames) }
    private var playingCount: Int { LibraryStats.playingCount(liveGames) }

    private var playtimeBuckets: [LibraryStats.PlaytimeBucket] {
        LibraryStats.playtimeBuckets(liveGames)
    }

    private var degreeDistribution: [(degree: String, count: Int)] {
        LibraryStats.completionDegreeDistribution(liveGames)
    }

    private var achievements: (platinumCount: Int, xboxGamerscore: Int) {
        LibraryStats.unifiedAchievements(liveGames)
    }

    private var topDevs: [(name: String, count: Int, avgScore: Double?)] {
        LibraryStats.topDevelopers(liveGames, limit: 5)
    }

    private var platformCounts: [(platform: String, count: Int)] {
        LibraryStats.platformDistribution(liveGames)
    }

    private var maxPlatformCount: Int {
        platformCounts.map(\.count).max() ?? 1
    }

    // MARK: - 收藏家派生

    private var collectorTotals: LibraryStats.CollectorTotals {
        LibraryStats.collectorTotals(liveGames.flatMap(\.copies), language: language)
    }
    private var totalCopyCount: Int { collectorTotals.editionCount }
    private var totalCopyQuantity: Int { collectorTotals.totalQuantity }
    private var totalSpent: Double? { collectorTotals.totalSpent }
    private var totalEstimate: Double? { collectorTotals.totalEstimate }

    private var topCopies: [(copy: PhysicalCopy, value: Double)] {
        LibraryStats.topValuedCopies(liveGames.flatMap(\.copies), language: language, limit: 3)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if liveGames.isEmpty {
                            ContentUnavailableView {
                                Image(systemName: "chart.bar")
                                    .font(.system(size: 48))
                            } description: {
                                LText("stats.noData")
                            }
                        } else {
                            // 1. 核心大盘指标看板（Apple Fitness 风格）
                            heroMetricGrid(width: geo.size.width)

                            // 2. 全库六状态流动胶囊
                            statusFlowPills

                            // 3. 游玩体量分布柱状图（Swift Charts）
                            if totalPlaytime > 0 {
                                playtimeTiersSection
                            }

                            // 4. 攻关深度与跨平台成就
                            if !degreeDistribution.isEmpty || achievements.platinumCount > 0 || achievements.xboxGamerscore > 0 {
                                masterySection
                            }

                            // 5. 平台分布与常玩厂商
                            platformsAndStudiosSection(width: geo.size.width)

                            // 6. 实体收藏金库（仅在收藏家模式且有数据时展示）
                            if collectorMode && totalCopyCount > 0 {
                                collectorVaultSection(width: geo.size.width)
                            }

                            // 7. 排行榜大厅（评分榜 / 时长榜双模式）
                            rankingsSection(width: geo.size.width)
                        }
                    }
                    #if os(macOS)
                    .padding(28)
                    #else
                    .padding(16)
                    .padding(.bottom, 64)
                    #endif
                    .frame(maxWidth: 1500)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .navigationTitle(hideToolbarGlass ? "" : L10n.tr("library.stats", lang: language))
            .appToolbar()
            .navigationDestination(item: Binding(
                get: { selectedGame?.isLive == true ? selectedGame : nil },
                set: { selectedGame = $0 }
            )) { GameDetailView(game: $0) }
            .navigationDestination(isPresented: $showingOverall) { OverallRankingView() }
            .onReceive(NotificationCenter.default.publisher(for: UserCustomization.libraryReplacedNotification)) { _ in
                selectedGame = nil
            }
        }
    }

    // MARK: - 1. 核心看板 (Apple Fitness 风格 4 格指标)

    @ViewBuilder
    private func heroMetricGrid(width: CGFloat) -> some View {
        let isWide = width >= 620
        let columns: [GridItem] = isWide
            ? [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14),
               GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

        LazyVGrid(columns: columns, spacing: 12) {
            // 通关总数
            let rateText = completionRate.map { String(format: L10n.tr("stats.completionRateFmt", lang: language), $0) }
                ?? String(format: L10n.tr("stats.gamesCountFmt", lang: language), totalGames)
            appleMetricCard(
                icon: "checkmark.seal.fill",
                iconTint: Color(red: 0.35, green: 0.78, blue: 0.55),
                title: L10n.tr("stats.clearedCount", lang: language),
                value: "\(clearedCount)",
                unit: nil,
                subtitle: rateText
            )

            // 累计总时长
            appleMetricCard(
                icon: "timer",
                iconTint: BrandPalette.accent,
                title: L10n.tr("stats.totalPlaytime", lang: language),
                value: totalPlaytime > 0 ? String(format: "%.0f", totalPlaytime) : "—",
                unit: totalPlaytime > 0 ? L10n.tr("stats.hoursShort", lang: language) : nil,
                subtitle: nil
            )

            // 库平均分
            let scoredText = String(format: L10n.tr("stats.scoredCountFmt", lang: language), scoredCount)
            appleMetricCard(
                icon: "star.fill",
                iconTint: Color(red: 1.0, green: 0.8, blue: 0.25),
                title: L10n.tr("stats.avgScore", lang: language),
                value: avgScore.map { String(format: "%.1f", $0) } ?? "—",
                unit: nil,
                subtitle: scoredText
            )

            // 想玩与在玩
            let bpText = String(format: L10n.tr("stats.backlogPlayingFmt", lang: language), backlogCount, playingCount)
            appleMetricCard(
                icon: "bookmark.fill",
                iconTint: Color(red: 0.45, green: 0.65, blue: 0.98),
                title: L10n.tr("stats.backlogAndPlaying", lang: language),
                value: "\(backlogCount + playingCount)",
                unit: nil,
                subtitle: bpText
            )
        }
    }

    private func appleMetricCard(
        icon: String,
        iconTint: Color,
        title: String,
        value: String,
        unit: String?,
        subtitle: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconTint)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(iconTint.opacity(0.16)))
                Text(verbatim: title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                if let unit {
                    Text(verbatim: unit)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            if let subtitle, !subtitle.isEmpty {
                Text(verbatim: subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Spacer(minLength: 0)
                    .frame(height: 14)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCardSurface()
        .clipShape(RoundedRectangle(cornerRadius: SurfaceStyle.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: SurfaceStyle.cardRadius).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
    }

    // MARK: - 2. 全库状态胶囊行

    private var statusFlowPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(GameStatus.allCases.filter { $0 != .unclassified }) { status in
                    let count = liveGames.filter { $0.statusValue == status }.count
                    HStack(spacing: 5) {
                        Text(verbatim: L10n.tr(status.labelKey, lang: language))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(verbatim: "\(count)")
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(status.isCompletedOrLongRunning ? BrandPalette.accent : Color.primary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(Color.semantic(.quaternarySystemFill))
                    )
                }
            }
        }
    }

    // MARK: - 3. 游玩体量分布图（Swift Charts）

    private var playtimeTiersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                LText("stats.playtimeTiers")
                    .font(.title3.bold())
                Spacer()
            }

            Chart(playtimeBuckets) { bucket in
                BarMark(
                    x: .value("Tier", bucket.rangeLabel),
                    y: .value("Count", bucket.count)
                )
                .cornerRadius(5)
                .foregroundStyle(
                    LinearGradient(
                        colors: [BrandPalette.accent, BrandPalette.accent.opacity(0.60)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .annotation(position: .top, alignment: .center) {
                    if bucket.count > 0 {
                        Text(verbatim: "\(bucket.count)")
                            .font(.caption2.bold().monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                        .foregroundStyle(Color.secondary.opacity(0.18))
                    AxisValueLabel()
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 180)
            .padding(16)
            .appCardSurface()
            .clipShape(RoundedRectangle(cornerRadius: SurfaceStyle.cardRadius))
        }
    }

    // MARK: - 4. 通关数据统计与跨平台成就

    private var masterySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LText("stats.completionDepth")
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: 14) {
                // 通关程度胶囊条
                if !degreeDistribution.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(degreeDistribution.prefix(6), id: \.degree) { item in
                                    HStack(spacing: 6) {
                                        Text(verbatim: item.degree)
                                            .font(.callout)
                                            .foregroundStyle(.primary)
                                        Text(verbatim: "\(item.count)")
                                            .font(.callout.bold().monospacedDigit())
                                            .foregroundStyle(BrandPalette.accent)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.semantic(.quaternarySystemFill))
                                    )
                                }
                            }
                        }
                    }
                }

                // 跨平台成就聚合行
                if achievements.platinumCount > 0 || achievements.xboxGamerscore > 0 {
                    Divider().opacity(0.5)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 18) {
                            if achievements.platinumCount > 0 {
                                psAchievementBadge
                            }
                            if achievements.xboxGamerscore > 0 {
                                xboxAchievementBadge
                            }
                            Spacer()
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            if achievements.platinumCount > 0 {
                                psAchievementBadge
                            }
                            if achievements.xboxGamerscore > 0 {
                                xboxAchievementBadge
                            }
                        }
                    }
                }
            }
            .padding(14)
            .appCardSurface()
            .clipShape(RoundedRectangle(cornerRadius: SurfaceStyle.cardRadius))
        }
    }

    @ViewBuilder
    private var psAchievementBadge: some View {
        HStack(spacing: 6) {
            Text(verbatim: "PlayStation Network")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Image(systemName: "trophy.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color(red: 0.55, green: 0.82, blue: 0.98))
            Text(verbatim: String(format: L10n.tr("stats.platinumTotal", lang: language), achievements.platinumCount))
                .font(.callout.bold().monospacedDigit())
        }
    }

    @ViewBuilder
    private var xboxAchievementBadge: some View {
        HStack(spacing: 6) {
            Text(verbatim: "XBOX")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Image(systemName: "xbox.logo")
                .font(.system(size: 14))
                .foregroundStyle(Color(red: 0.20, green: 0.78, blue: 0.35))
            Text(verbatim: String(format: L10n.tr("stats.gamerscoreTotal", lang: language), achievements.xboxGamerscore))
                .font(.callout.bold().monospacedDigit())
        }
    }

    // MARK: - 5. 平台生态与常玩厂商

    private func platformsAndStudiosSection(width: CGFloat) -> some View {
        let isWide = width >= 620
        return Group {
            if isWide {
                HStack(alignment: .top, spacing: 16) {
                    platformsCard
                        .frame(maxWidth: .infinity)
                    topDevsCard
                        .frame(maxWidth: .infinity)
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    platformsCard
                    topDevsCard
                }
            }
        }
    }

    private var platformsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            LText("stats.byPlatform")
                .font(.title3.bold())

            if platformCounts.isEmpty {
                LText("stats.noData")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .appCardSurface()
            } else {
                let shownPlatforms = showAllPlatforms ? platformCounts : Array(platformCounts.prefix(6))
                VStack(spacing: 8) {
                    ForEach(shownPlatforms, id: \.platform) { item in
                        PlatformBarRow(
                            platform: item.platform,
                            count: item.count,
                            maxCount: maxPlatformCount,
                            language: language
                        )
                    }

                    if platformCounts.count > 6 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showAllPlatforms.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(verbatim: showAllPlatforms
                                    ? L10n.tr("stats.showLessPlatforms", lang: language)
                                    : String(format: L10n.tr("stats.showAllPlatforms", lang: language), platformCounts.count))
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(BrandPalette.accent)
                                Image(systemName: showAllPlatforms ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(BrandPalette.accent)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
                .appCardSurface()
                .clipShape(RoundedRectangle(cornerRadius: SurfaceStyle.cardRadius))
            }
        }
    }

    private var topDevsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            LText("stats.topDevelopers")
                .font(.title3.bold())

            if topDevs.isEmpty {
                LText("stats.noData")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .appCardSurface()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(topDevs.enumerated()), id: \.element.name) { idx, dev in
                        HStack(spacing: 10) {
                            Text(verbatim: "\(idx + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 16, alignment: .leading)
                            Text(verbatim: dev.name)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(verbatim: String(format: L10n.tr("stats.gamesCountFmt", lang: language), dev.count))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)

                            if let avg = dev.avgScore {
                                HStack(spacing: 2) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 9))
                                        .foregroundStyle(BrandPalette.accent)
                                    Text(verbatim: String(format: "%.1f", avg))
                                        .font(.caption.bold().monospacedDigit())
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(BrandPalette.accent.opacity(0.12)))
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(idx.isMultiple(of: 2) ? Color.clear : Color.semantic(.quaternarySystemFill))
                    }
                }
                .appCardSurface()
                .clipShape(RoundedRectangle(cornerRadius: SurfaceStyle.cardRadius))
            }
        }
    }

    // MARK: - 6. 实体收藏金库

    private func collectorVaultSection(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LText("stats.collectorValue")
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: 16) {
                // 4 大总览指标
                collectorTilesGrid(width: width)

                // 最具价值前三名
                if !topCopies.isEmpty {
                    Divider().opacity(0.5)
                    VStack(alignment: .leading, spacing: 8) {
                        LText("stats.collectorTopValued")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        ForEach(Array(topCopies.enumerated()), id: \.offset) { idx, item in
                            HStack(spacing: 10) {
                                Text(verbatim: "\(idx + 1)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 16, alignment: .leading)

                                if let g = item.copy.game {
                                    Button {
                                        selectedGame = g
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(verbatim: g.displayName(for: language))
                                                .font(.callout.weight(.medium))
                                                .lineLimit(1)
                                            Text(verbatim: L10n.tr(item.copy.media.labelKey, lang: language))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Text(verbatim: L10n.tr(item.copy.media.labelKey, lang: language))
                                        .font(.callout)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                Text(verbatim: PriceFormat.string(item.value, language: language) ?? "—")
                                    .font(.callout.bold().monospacedDigit())
                                    .foregroundStyle(BrandPalette.accent)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
            .padding(14)
            .appCardSurface()
            .clipShape(RoundedRectangle(cornerRadius: SurfaceStyle.cardRadius))
        }
    }

    @ViewBuilder
    private func collectorTilesGrid(width: CGFloat) -> some View {
        let isWide = width >= 620
        if isWide {
            HStack(spacing: 16) {
                collectorTile(value: "\(totalCopyCount)", label: L10n.tr("copy.overviewEditions", lang: language))
                collectorTile(value: "\(totalCopyQuantity)", label: L10n.tr("copy.overviewQuantity", lang: language))
                collectorTile(value: PriceFormat.string(totalSpent, language: language) ?? "—", label: L10n.tr("copy.overviewSpent", lang: language))
                collectorTile(value: PriceFormat.string(totalEstimate, language: language) ?? "—", label: L10n.tr("copy.overviewEstimate", lang: language))
            }
        } else {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                collectorTile(value: "\(totalCopyCount)", label: L10n.tr("copy.overviewEditions", lang: language))
                collectorTile(value: "\(totalCopyQuantity)", label: L10n.tr("copy.overviewQuantity", lang: language))
                collectorTile(value: PriceFormat.string(totalSpent, language: language) ?? "—", label: L10n.tr("copy.overviewSpent", lang: language))
                collectorTile(value: PriceFormat.string(totalEstimate, language: language) ?? "—", label: L10n.tr("copy.overviewEstimate", lang: language))
            }
        }
    }

    private func collectorTile(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(verbatim: label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 7. 排行榜大厅 (评分榜 / 时长榜双模式)

    private func rankingsSection(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                LText("stats.rankings")
                    .font(.title3.bold())
                Spacer()
                // 双模式切换滑块
                Picker("", selection: $rankingCategory) {
                    Text(verbatim: L10n.tr("stats.rankingsScore", lang: language)).tag(0)
                    Text(verbatim: L10n.tr("stats.rankingsPlaytime", lang: language)).tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            if rankingCategory == 0 {
                // 评分榜
                RankingBoard(
                    title: L10n.tr("group.avgScore", lang: language),
                    entries: Rankings.byAverage(games: liveGames, platform: nil),
                    limit: 10,
                    isPlaytime: false,
                    showCovers: true,
                    onSelect: { selectedGame = $0 }
                )

                LazyVGrid(columns: rankingColumns(for: width), spacing: 12) {
                    ForEach(Dimension.allCases.filter { !Rankings.byDimension($0, games: liveGames, platform: nil).isEmpty }) { dimension in
                        RankingBoard(
                            title: L10n.tr(dimension.labelKey, lang: language),
                            entries: Rankings.byDimension(dimension, games: liveGames, platform: nil),
                            limit: 5,
                            isPlaytime: false,
                            showCovers: true,
                            onSelect: { selectedGame = $0 }
                        )
                    }
                }
            } else {
                // 时长榜
                RankingBoard(
                    title: L10n.tr("stats.playtimeRankings", lang: language),
                    entries: Rankings.byPlaytime(games: liveGames, platform: nil),
                    limit: 10,
                    isPlaytime: true,
                    showCovers: true,
                    onSelect: { selectedGame = $0 }
                )
            }

            Button {
                showingOverall = true
            } label: {
                Label(L10n.tr("stats.overallRanking", lang: language), systemImage: "arrow.up.right")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .appCardSurface()
                    .clipShape(RoundedRectangle(cornerRadius: SurfaceStyle.cardRadius))
            }
            .buttonStyle(.plain)
        }
    }

    private func rankingColumns(for width: CGFloat) -> [GridItem] {
        if width >= 620 {
            return [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        }
        return [GridItem(.flexible(), spacing: 12)]
    }
}
