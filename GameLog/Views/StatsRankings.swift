import SwiftUI
import SwiftData

// MARK: - 排名计算

/// 榜单条目：游戏 + 分数。
struct RankingEntry: Identifiable {
    let game: Game
    /// 展示用分数（平均分榜为取整到 0.1 的值，维度榜为原始均值）。
    let score: Double
    /// 排序用原始值（平均分榜与展示值可不同，实现「按原始值排、显示取整值」）。
    let sortScore: Double
    var id: PersistentIdentifier { game.persistentModelID }
}

/// 排行榜计算：平均分榜 + 六维榜。
/// 口径：平均分按库显示分（`rawLibraryScore` 排序、展示取整到 0.1）、维度按该维度均值（原始值）；
/// `platform` 非 nil 时只按该平台下的通关记录算（统计页榜单恒为整体，完整榜页可切换平台）。
/// 无该维度/无评分的游戏不进入对应榜；同原始值按游戏名升序、名次连续。
enum Rankings {

    static func byAverage(games: [Game], platform: String?) -> [RankingEntry] {
        games.compactMap { game in
            game.rawLibraryScore(platform: platform).map { raw in
                RankingEntry(game: game, score: ScoreMath.roundScore(raw), sortScore: raw)
            }
        }
        .sorted(by: rankLess)
    }

    static func byDimension(_ dimension: Dimension, games: [Game], platform: String?) -> [RankingEntry] {
        games.compactMap { game in
            game.dimensionAverage(for: dimension, platform: platform).map { raw in
                RankingEntry(game: game, score: raw, sortScore: raw)
            }
        }
        .sorted(by: rankLess)
    }

    static func byPlaytime(games: [Game], platform: String?) -> [RankingEntry] {
        games.compactMap { game in
            let hours: Double? = {
                if let platform {
                    let comps = game.completions.filter { $0.platform == platform }
                    let logged = comps.compactMap(\.playtime).reduce(0, +)
                    return logged > 0 ? logged : nil
                } else {
                    return LibraryStats.gamePlaytime(game)
                }
            }()
            guard let hours, hours > 0 else { return nil }
            let rounded = (hours * 10).rounded() / 10
            return RankingEntry(game: game, score: rounded, sortScore: hours)
        }
        .sorted(by: rankLess)
    }

    /// 降序；同原始值按游戏名升序。
    private static func rankLess(_ a: RankingEntry, _ b: RankingEntry) -> Bool {
        if a.sortScore != b.sortScore { return a.sortScore > b.sortScore }
        // 主名可能为空（导入的中日文标题只落语言槽），用解析后的名字做并列裁决。
        return a.game.primaryName.localizedCaseInsensitiveCompare(b.game.primaryName) == .orderedAscending
    }
}

// MARK: - 榜单卡片

/// 排名卡片：标题 + 名次行；游戏名可点进详情。`limit` 为 nil 时显示全部。行背景隔行铺色（斑马纹）。
/// 点击游戏名走 `onSelect` 回调（由父视图决定导航方式，避免推入视图内 NavigationLink 找不到目标）。
struct RankingBoard: View {
    @Environment(\.appLanguageCode) private var language
    let title: String
    let entries: [RankingEntry]
    var limit: Int? = nil
    var isPlaytime: Bool = false
    var showCovers: Bool = true
    /// 点击游戏名的回调。
    var onSelect: (Game) -> Void = { _ in }

    /// 隔行强调色：偶数行铺在卡片底色上加深一档。
    private var stripeColor: Color {
        Color.semantic(.quaternarySystemFill)
    }

    private var shown: [RankingEntry] {
        guard let limit else { return entries }
        return Array(entries.prefix(limit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(verbatim: title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if let count = entries.count as Int?, count > 0 {
                    Text(verbatim: "\(count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if entries.isEmpty {
                LText("stats.noData")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, entry in
                    row(rank: index + 1, entry: entry)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(index.isMultiple(of: 2) ? Color.clear : stripeColor)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCardSurface()
        .clipShape(RoundedRectangle(cornerRadius: SurfaceStyle.cardRadius))
    }

    @ViewBuilder
    private func rankBadge(rank: Int) -> some View {
        if rank == 1 {
            Text(verbatim: "1")
                .font(.system(size: 11, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.black)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color(red: 1.0, green: 0.8, blue: 0.25)))
        } else if rank == 2 {
            Text(verbatim: "2")
                .font(.system(size: 11, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.black)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color(white: 0.78)))
        } else if rank == 3 {
            Text(verbatim: "3")
                .font(.system(size: 11, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color(red: 0.82, green: 0.52, blue: 0.35)))
        } else {
            Text(verbatim: "\(rank)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .center)
        }
    }

    private func row(rank: Int, entry: RankingEntry) -> some View {
        Button {
            onSelect(entry.game)
        } label: {
            HStack(spacing: 10) {
                rankBadge(rank: rank)
                    .frame(width: 24, alignment: .center)

                if showCovers {
                    coverThumbnail(for: entry.game)
                }

                Text(verbatim: entry.game.displayName(for: language))
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isPlaytime {
                    HStack(spacing: 2) {
                        Text(verbatim: String(format: "%.1f", entry.score))
                            .font(.callout.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(verbatim: "h")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(verbatim: String(format: "%.1f", entry.score))
                        .font(.callout.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func coverThumbnail(for game: Game) -> some View {
        Group {
            if let img = game.coverImage {
                Image(appImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.semantic(.quaternarySystemFill)
                    .overlay {
                        Image(systemName: "gamecontroller")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .frame(width: 20, height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
    }
}

// MARK: - 整体排名页

/// 完整排名页：顶部滑块切换榜单（平均分/六维），每页最多 100 条、底部翻页；工具栏可切换平台（分数按该平台记录算）。
// MARK: - 价值排名

/// 价值榜条目：聚合实体（游戏 / 平台 / 分组）的总估值，按当前语言格式化金额展示。
struct ValueRankingEntry: Identifiable {
    /// 稳定身份（实体标识派生）：此前每次重算生成新 UUID，ForEach 全量换身份、失去增量 diff。
    let id: String
    let label: String
    /// 总估值（按当前语言）；nil = 无估值，排末位。
    let value: Double?
    /// 币种展示文本（无估值显示「—」）。
    let valueText: String
    /// 关联游戏（仅「按游戏价值」页有，可点进详情）；机器/分组页为 nil。
    var game: Game?
}

/// 价值榜计算：游戏 / 平台（机器）/ 分组 三种口径的总估值排名。
enum ValueRankings {

    /// 按游戏价值：每个游戏的总估值排序（无持有/无估值排末）。
    static func byGame(games: [Game], language: String) -> [ValueRankingEntry] {
        games.map { game in
            let v = game.totalEstimate(for: language)
            return ValueRankingEntry(
                id: "game:\(game.persistentModelID.hashValue)",
                label: game.displayName(for: language),
                value: v,
                valueText: PriceFormat.string(v, language: language) ?? "—",
                game: game
            )
        }
        .sorted { ($0.value ?? -1) > ($1.value ?? -1) }
    }

    /// 按机器（平台）价值：平台下所有游戏的总估值求和排序。
    static func byPlatform(games: [Game], language: String) -> [ValueRankingEntry] {
        var byPlatform: [String: Double] = [:]
        for game in games {
            guard let v = game.totalEstimate(for: language) else { continue }
            for p in game.platformList {
                byPlatform[p, default: 0] += v
            }
        }
        return byPlatform.map { (platform, total) in
            ValueRankingEntry(
                id: "platform:\(platform)",
                label: Presets.display(platform, category: .platform, language: language),
                value: total,
                valueText: PriceFormat.string(total, language: language) ?? "—",
                game: nil
            )
        }
        .sorted { ($0.value ?? -1) > ($1.value ?? -1) }
    }

    /// 按分组价值：分组下所有游戏的总估值求和排序。
    /// 全组都无估值（含空分组）→ value = nil 显示「—」，与按游戏/按机器口径一致（此前空组显示 ¥0）。
    static func byGroup(groups: [GameGroup], language: String) -> [ValueRankingEntry] {
        groups.map { group in
            let vals = group.games.compactMap { $0.totalEstimate(for: language) }
            let total: Double? = vals.isEmpty ? nil : vals.reduce(0, +)
            return ValueRankingEntry(
                id: "group:\(group.persistentModelID.hashValue)",
                label: group.name,
                value: total,
                valueText: PriceFormat.string(total, language: language) ?? "—",
                game: nil
            )
        }
        .sorted { ($0.value ?? -1) > ($1.value ?? -1) }
    }
}

/// 价值榜卡片：标题 + 名次行（名称 + 估值金额）；仅「游戏价值」页的条目可点进详情。
struct ValueRankingBoard: View {
    @Environment(\.appLanguageCode) private var language
    let title: String
    let entries: [ValueRankingEntry]
    var onSelect: (Game) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: title)
                .font(.headline)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            if entries.isEmpty {
                LText("stats.noData")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    row(rank: index + 1, entry: entry)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(index.isMultiple(of: 2) ? Color.clear : Color.semantic(.quaternarySystemFill))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCardSurface()
        .clipShape(RoundedRectangle(cornerRadius: SurfaceStyle.cardRadius))
    }

    private func row(rank: Int, entry: ValueRankingEntry) -> some View {
        HStack(spacing: 10) {
            rankBadge(rank: rank)
                .frame(width: 24, alignment: .center)
            if let game = entry.game {
                Button {
                    onSelect(game)
                } label: {
                    Text(verbatim: entry.label)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            } else {
                Text(verbatim: entry.label)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(verbatim: entry.valueText)
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(Color.accentColor)
        }
    }

    @ViewBuilder
    private func rankBadge(rank: Int) -> some View {
        if rank == 1 {
            Text(verbatim: "1")
                .font(.system(size: 11, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.black)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color(red: 1.0, green: 0.8, blue: 0.25)))
        } else if rank == 2 {
            Text(verbatim: "2")
                .font(.system(size: 11, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.black)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color(white: 0.78)))
        } else if rank == 3 {
            Text(verbatim: "3")
                .font(.system(size: 11, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color(red: 0.82, green: 0.52, blue: 0.35)))
        } else {
            Text(verbatim: "\(rank)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .center)
        }
    }
}

/// 通用分段滑块（liquid glass 胶囊 + 内部色块 offset + spring 动画），双端通用。
/// 与详情页「详情/持有」滑块同款视觉，统计页分数榜/价值榜与分享面板共用。
struct SegmentSlider: View {
    let titles: [String]
    @Binding var selection: Int

    var body: some View {
        GeometryReader { geo in
            let cellWidth = geo.size.width / CGFloat(titles.count)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 9)
                    .fill(SurfaceStyle.segmentHighlight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(SurfaceStyle.segmentTrack, lineWidth: 1)
                    )
                    .frame(width: cellWidth, height: geo.size.height)
                    .offset(x: CGFloat(selection) * cellWidth)
                    .animation(SurfaceStyle.segmentSpring, value: selection)
                HStack(spacing: 0) {
                    ForEach(Array(titles.enumerated()), id: \.offset) { idx, title in
                        Button {
                            guard selection != idx else { return }
                            selection = idx
                        } label: {
                            Text(verbatim: title)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.55)
                                .foregroundStyle(selection == idx ? Color.accentColor : Color.secondary)
                                .frame(width: cellWidth, height: geo.size.height)
                                .contentShape(Rectangle())
                        }
                        // 分段本体按压形变（选中滑块另有 spring 动画）。
                        .buttonStyle(PressFeedbackButtonStyle(pressedScale: 0.94, pressedOpacity: 0.55))
                    }
                }
            }
        }
        .frame(height: 44)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.thinMaterial)
        }
    }
}

struct OverallRankingView: View {
    @Environment(\.appLanguageCode) private var language
    @AppStorage(UserCustomization.hideToolbarGlassKey) private var hideToolbarGlass = false
    @Query(sort: \Game.createdAt) private var games: [Game]
    @State private var selectedPlatform: String?
    @State private var selectedBoard = 0
    @State private var page = 0
    /// 顶部大类：0 分数榜 / 1 时长榜 / 2 价值榜。
    @State private var category = 0
    /// 价值榜内页：0 游戏 / 1 机器（平台）/ 2 分组。
    @State private var valuePage = 0
    @State private var selectedGame: Game?

    private static let pageSize = 100

    private var liveGames: [Game] { games.filter(\.isLive) }
    private var liveGroups: [GameGroup] { groups.filter(\.isLive) }

    private var platforms: [String] {
        Presets.ordered(liveGames.flatMap { $0.completions.map(\.platform) })
    }

    private var boardTitles: [String] {
        [L10n.tr("group.avgScore", lang: language)] + Dimension.allCases.map { L10n.tr($0.labelKey, lang: language) }
    }

    private func entries(for board: Int) -> [RankingEntry] {
        if board == 0 {
            return Rankings.byAverage(games: liveGames, platform: selectedPlatform)
        }
        return Rankings.byDimension(Dimension.allCases[board - 1], games: liveGames, platform: selectedPlatform)
    }

    private var pageCount: Int {
        let total: Int
        if category == 0 {
            total = entries(for: selectedBoard).count
        } else if category == 1 {
            total = Rankings.byPlaytime(games: liveGames, platform: selectedPlatform).count
        } else {
            total = 1
        }
        return max(1, Int(ceil(Double(total) / Double(Self.pageSize))))
    }

    private var currentEntries: [RankingEntry] {
        let all: [RankingEntry]
        if category == 0 {
            all = entries(for: selectedBoard)
        } else if category == 1 {
            all = Rankings.byPlaytime(games: liveGames, platform: selectedPlatform)
        } else {
            all = []
        }
        let start = page * Self.pageSize
        guard start < all.count else { return [] }
        return Array(all.dropFirst(start).prefix(Self.pageSize))
    }

    private var valueTitles: [String] {
        [L10n.tr("stats.byGameValue", lang: language),
         L10n.tr("stats.byPlatformValue", lang: language),
         L10n.tr("stats.byGroupValue", lang: language)]
    }

    @Query private var groups: [GameGroup]

    private var valueEntries: [ValueRankingEntry] {
        switch valuePage {
        case 0: return ValueRankings.byGame(games: liveGames, language: language)
        case 1: return ValueRankings.byPlatform(games: liveGames, language: language)
        default: return ValueRankings.byGroup(groups: liveGroups, language: language)
        }
    }

    private var categorySwitcher: some View {
        VStack(spacing: 10) {
            SegmentSlider(
                titles: [L10n.tr("stats.scoreBoards", lang: language),
                         L10n.tr("stats.rankingsPlaytime", lang: language),
                         L10n.tr("stats.valueBoards", lang: language)],
                selection: $category
            )
            if category == 0 {
                SegmentSlider(titles: boardTitles, selection: $selectedBoard)
            } else if category == 2 {
                SegmentSlider(titles: valueTitles, selection: $valuePage)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            categorySwitcher
                .padding(16)
                .onChange(of: selectedBoard) { _, _ in page = 0 }
                .onChange(of: selectedPlatform) { _, _ in page = 0 }
                .onChange(of: category) { _, _ in page = 0 }
                .onChange(of: valuePage) { _, _ in page = 0 }
                .onChange(of: pageCount) { _, newCount in
                    if page >= newCount { page = max(0, newCount - 1) }
                }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if category == 0 {
                        RankingBoard(
                            title: boardTitles[selectedBoard],
                            entries: currentEntries,
                            isPlaytime: false,
                            onSelect: { selectedGame = $0 }
                        )
                    } else if category == 1 {
                        RankingBoard(
                            title: L10n.tr("stats.playtimeRankings", lang: language),
                            entries: currentEntries,
                            isPlaytime: true,
                            onSelect: { selectedGame = $0 }
                        )
                    } else {
                        ValueRankingBoard(
                            title: valueTitles[valuePage],
                            entries: valueEntries,
                            onSelect: { selectedGame = $0 }
                        )
                    }
                }
                #if os(macOS)
                .padding(.horizontal, 28)
                #else
                .padding(.horizontal, 16)
                #endif
                .padding(.top, 8)
                .padding(.bottom, 20)
                .frame(maxWidth: 1500)
                .frame(maxWidth: .infinity, alignment: .top)
            }

            Divider()
            if category == 0 || category == 1 {
                HStack(spacing: 20) {
                    Spacer()
                    Button {
                        page = max(0, page - 1)
                    } label: {
                        Label(L10n.tr("stats.prevPage", lang: language), systemImage: "chevron.left")
                    }
                    .disabled(page == 0)
                    Text(verbatim: "\(page + 1) / \(pageCount)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Button {
                        page = min(pageCount - 1, page + 1)
                    } label: {
                        Label(L10n.tr("stats.nextPage", lang: language), systemImage: "chevron.right")
                    }
                    .disabled(page >= pageCount - 1)
                    Spacer()
                }
                .padding(.vertical, 10)
            }
        }
        .navigationTitle(hideToolbarGlass ? "" : L10n.tr("stats.overallRanking", lang: language))
        .appToolbar()
        // 点击榜单游戏名 → 编程式 push 详情（本页由 navigationDestination(isPresented:) 推入，
        // 用 item: 在本地注册，避免父级根视图的 Game 目标对本页不可见）。
        // `isLive` 守卫：整库替换的通知与状态清空之间有一帧缝隙（判据见 `Game.isLive`）。
        .navigationDestination(item: Binding(
            get: { selectedGame?.isLive == true ? selectedGame : nil },
            set: { selectedGame = $0 }
        )) { GameDetailView(game: $0) }
        // 整库替换后栈上旧 Game 已 detached：退出详情防悬空访问（2026-09-08）。
        .onReceive(NotificationCenter.default.publisher(for: UserCustomization.libraryReplacedNotification)) { _ in
            selectedGame = nil
        }
        .toolbar {
            ToolbarItem {
                platformMenu
            }
        }
    }

    private var platformMenu: some View {
        Menu {
            Button {
                selectedPlatform = nil
            } label: {
                if selectedPlatform == nil {
                    Label(L10n.tr("library.allPlatforms", lang: language), systemImage: "checkmark")
                } else {
                    Text(verbatim: L10n.tr("library.allPlatforms", lang: language))
                }
            }
            ForEach(platforms, id: \.self) { platform in
                Button {
                    selectedPlatform = platform
                } label: {
                    HStack(spacing: 8) {
                        PlatformIcon(platform: platform, size: 16)
                        Text(verbatim: Presets.display(platform, category: .platform, language: language))
                        Spacer()
                        if selectedPlatform == platform {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
        }
        .help(L10n.tr("library.filterPlatform", lang: language))
    }
}
