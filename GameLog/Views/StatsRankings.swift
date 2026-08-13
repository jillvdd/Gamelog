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
        Color(nsColor: .quaternarySystemFill)
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
                .fill(Color(nsColor: .controlBackgroundColor))
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
struct OverallRankingView: View {
    @Environment(\.appLanguageCode) private var language
    @Query(sort: \Game.createdAt) private var games: [Game]
    @State private var selectedPlatform: String?
    @State private var selectedBoard = 0
    @State private var page = 0
    /// 点击榜单游戏名 → 编程式 push 到详情（避免推入视图内 NavigationLink 找不到目标）。
    @State private var selectedGame: Game?

    private static let pageSize = 100

    /// 库里出现过的平台（升序）。
    private var platforms: [String] {
        Array(Set(games.flatMap { $0.completions.map(\.platform) }.filter { !$0.isEmpty })).sorted()
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

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedBoard) {
                ForEach(Array(boardTitles.enumerated()), id: \.offset) { index, title in
                    Text(verbatim: title).tag(index)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(16)
            .onChange(of: selectedBoard) { _, _ in page = 0 }
            .onChange(of: selectedPlatform) { _, _ in page = 0 }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    RankingBoard(
                        title: boardTitles[selectedBoard],
                        entries: currentEntries,
                        onSelect: { selectedGame = $0 }
                    )
                }
                .padding(.horizontal, 28)
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
        .navigationTitle(L10n.tr("stats.overallRanking", lang: language))
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
                    if selectedPlatform == platform {
                        Label(Presets.display(platform, category: .platform, language: language), systemImage: "checkmark")
                    } else {
                        Text(verbatim: Presets.display(platform, category: .platform, language: language))
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
        }
        .help(L10n.tr("library.filterPlatform", lang: language))
    }
}
