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

    /// 降序；同原始值按游戏名升序。
    private static func rankLess(_ a: RankingEntry, _ b: RankingEntry) -> Bool {
        if a.sortScore != b.sortScore { return a.sortScore > b.sortScore }
        return a.game.name.localizedCaseInsensitiveCompare(b.game.name) == .orderedAscending
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
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, entry in
                    row(rank: index + 1, entry: entry)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(index.isMultiple(of: 2) ? Color.clear : stripeColor)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.semantic(.controlBackground))
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func row(rank: Int, entry: RankingEntry) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: "\(rank)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .leading)
            Button {
                onSelect(entry.game)
            } label: {
                Text(verbatim: entry.game.displayName(for: language))
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Text(verbatim: String(format: "%.1f", entry.score))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 整体排名页

/// 完整排名页：顶部滑块切换榜单（平均分/六维），每页最多 100 条、底部翻页；工具栏可切换平台（分数按该平台记录算）。
// MARK: - 价值排名

/// 价值榜条目：聚合实体（游戏 / 平台 / 分组）的总估值，按当前语言格式化金额展示。
struct ValueRankingEntry: Identifiable {
    let id = UUID()
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
                label: Presets.display(platform, category: .platform, language: language),
                value: total,
                valueText: PriceFormat.string(total, language: language) ?? "—",
                game: nil
            )
        }
        .sorted { ($0.value ?? -1) > ($1.value ?? -1) }
    }

    /// 按分组价值：分组下所有游戏的总估值求和排序。
    static func byGroup(groups: [GameGroup], language: String) -> [ValueRankingEntry] {
        groups.map { group in
            let total = group.games.compactMap { $0.totalEstimate(for: language) }.reduce(0, +)
            return ValueRankingEntry(
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
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.semantic(.controlBackground))
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func row(rank: Int, entry: ValueRankingEntry) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: "\(rank)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .leading)
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
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
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
    /// 顶部大类：分数榜（平均分 + 六维）/ 价值榜（三页）。
    @State private var category = 0
    /// 价值榜内页：0 游戏 / 1 机器（平台）/ 2 分组。
    @State private var valuePage = 0
    /// 点击榜单游戏名 → 编程式 push 到详情（避免推入视图内 NavigationLink 找不到目标）。
    @State private var selectedGame: Game?

    private static let pageSize = 100

    /// 库里出现过的平台（按平台预设世代倒序 + 自定义字母排后，与全 app 排序唯一源一致）。
    private var platforms: [String] {
        Presets.ordered(games.flatMap { $0.completions.map(\.platform) })
    }

    /// 榜单标题（平均分 + 六维，顺序即切换顺序）。
    private var boardTitles: [String] {
        [L10n.tr("group.avgScore", lang: language)] + Dimension.allCases.map { L10n.tr($0.labelKey, lang: language) }
    }

    private func entries(for board: Int) -> [RankingEntry] {
        if board == 0 {
            return Rankings.byAverage(games: games, platform: selectedPlatform)
        }
        return Rankings.byDimension(Dimension.allCases[board - 1], games: games, platform: selectedPlatform)
    }

    private var pageCount: Int {
        max(1, Int(ceil(Double(entries(for: selectedBoard).count) / Double(Self.pageSize))))
    }

    private var currentEntries: [RankingEntry] {
        let all = entries(for: selectedBoard)
        let start = page * Self.pageSize
        guard start < all.count else { return [] }
        return Array(all.dropFirst(start).prefix(Self.pageSize))
    }

    /// 价值榜标题（顺序即切换顺序）。
    private var valueTitles: [String] {
        [L10n.tr("stats.byGameValue", lang: language),
         L10n.tr("stats.byPlatformValue", lang: language),
         L10n.tr("stats.byGroupValue", lang: language)]
    }

    /// 全部分组（用于「按分组价值」）。
    @Query private var groups: [GameGroup]

    private var valueEntries: [ValueRankingEntry] {
        switch valuePage {
        case 0: return ValueRankings.byGame(games: games, language: language)
        case 1: return ValueRankings.byPlatform(games: games, language: language)
        default: return ValueRankings.byGroup(groups: groups, language: language)
        }
    }

    /// 顶部大类切换：分数榜（平均分 + 六维）/ 价值榜（游戏 / 机器 / 分组）。
    private var categorySwitcher: some View {
        VStack(spacing: 10) {
            #if os(macOS)
            Picker("", selection: $category) {
                Text(verbatim: L10n.tr("stats.scoreBoards", lang: language)).tag(0)
                Text(verbatim: L10n.tr("stats.valueBoards", lang: language)).tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            #else
            Menu {
                Button { category = 0 } label: {
                    if category == 0 { Label(L10n.tr("stats.scoreBoards", lang: language), systemImage: "checkmark") }
                    else { Text(verbatim: L10n.tr("stats.scoreBoards", lang: language)) }
                }
                Button { category = 1 } label: {
                    if category == 1 { Label(L10n.tr("stats.valueBoards", lang: language), systemImage: "checkmark") }
                    else { Text(verbatim: L10n.tr("stats.valueBoards", lang: language)) }
                }
            } label: {
                Label(category == 0 ? L10n.tr("stats.scoreBoards", lang: language) : L10n.tr("stats.valueBoards", lang: language), systemImage: "list.number")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.semantic(.controlBackground)))
            }
            #endif

            if category == 1 {
                #if os(macOS)
                Picker("", selection: $valuePage) {
                    ForEach(Array(valueTitles.enumerated()), id: \.offset) { index, title in
                        Text(verbatim: title).tag(index)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                #else
                Menu {
                    ForEach(Array(valueTitles.enumerated()), id: \.offset) { index, title in
                        Button { valuePage = index } label: {
                            if valuePage == index { Label(title, systemImage: "checkmark") }
                            else { Text(verbatim: title) }
                        }
                    }
                } label: {
                    Label(valueTitles[valuePage], systemImage: "list.number")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.semantic(.controlBackground)))
                }
                #endif
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部大类：分数榜 / 价值榜。
            categorySwitcher
                .padding(16)
                .onChange(of: selectedBoard) { _, _ in page = 0 }
                .onChange(of: selectedPlatform) { _, _ in page = 0 }
                .onChange(of: category) { _, _ in page = 0 }
                .onChange(of: valuePage) { _, _ in page = 0 }
                // 数据收缩（删除/改分）导致合格条目数减少时，把越界页码收回来，避免空白榜 + 错页码。
                .onChange(of: pageCount) { _, newCount in
                    if page >= newCount { page = max(0, newCount - 1) }
                }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if category == 0 {
                        RankingBoard(
                            title: boardTitles[selectedBoard],
                            entries: currentEntries,
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
        .navigationTitle(hideToolbarGlass ? "" : L10n.tr("stats.overallRanking", lang: language))
        .appToolbar()
        // 点击榜单游戏名 → 编程式 push 详情（本页由 navigationDestination(isPresented:) 推入，
        // 用 item: 在本地注册，避免父级根视图的 Game 目标对本页不可见）。
        .navigationDestination(item: $selectedGame) { GameDetailView(game: $0) }
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
