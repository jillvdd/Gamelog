import SwiftUI
import AppKit

// MARK: - 尺寸与内容

enum ShareSize: String, CaseIterable, Identifiable {
    case phone
    case desktop

    var id: String { rawValue }

    var pixels: CGSize {
        switch self {
        case .phone: CGSize(width: 1080, height: 1920)
        case .desktop: CGSize(width: 1920, height: 1080)
        }
    }
}

enum ShareCardContent {
    case single(Game, size: ShareSize)
    case overview([Game], title: String, size: ShareSize)
    case group(GameGroup, title: String, size: ShareSize)

    var canvasSize: CGSize {
        switch self {
        case .single(_, let size):
            size.pixels
        case .overview(let games, _, let size):
            ShareCardLayout.overviewSize(gameCount: games.count, size: size)
        case .group(let group, _, let size):
            ShareCardLayout.groupSize(
                gameCount: group.games.count,
                platformCount: Set(group.games.flatMap { $0.completions.map(\.platform) }.filter { !$0.isEmpty }).count,
                size: size
            )
        }
    }
}

// MARK: - 布局数学（固定数值，便于 ImageRenderer 精确出图）

enum ShareCardLayout {
    static let gap: CGFloat = 32
    static let headerHeightPhone: CGFloat = 240
    static let headerHeightDesktop: CGFloat = 180
    static let cellCaptionHeight: CGFloat = 96

    static func overviewSize(gameCount: Int, size: ShareSize) -> CGSize {
        let count = max(gameCount, 1)
        let columns = size == .phone ? 2 : 4
        let rows = Int(ceil(Double(count) / Double(columns)))
        let cellWidth = (size.pixels.width - CGFloat(columns + 1) * gap) / CGFloat(columns)
        let cellHeight = cellWidth * 4 / 3 + cellCaptionHeight
        let header = size == .phone ? headerHeightPhone : headerHeightDesktop
        let height = header + CGFloat(rows) * cellHeight + CGFloat(rows - 1) * gap + gap
        return CGSize(width: size.pixels.width, height: height)
    }

    static func cellSize(count: Int, size: ShareSize) -> CGSize {
        let columns = size == .phone ? 2 : 4
        let cellWidth = (size.pixels.width - CGFloat(columns + 1) * gap) / CGFloat(columns)
        return CGSize(width: cellWidth, height: cellWidth * 4 / 3 + cellCaptionHeight)
    }

    // MARK: 分组分享卡布局（竖版 3 列 / 横版 5 列，超出按内容拉高画布）

    static let groupColumnsPhone: Int = 3
    static let groupColumnsDesktop: Int = 5

    static func groupTileWidth(size: ShareSize) -> CGFloat {
        if size == .phone {
            return (size.pixels.width - 2 * 72 - CGFloat(groupColumnsPhone - 1) * 24) / CGFloat(groupColumnsPhone)
        }
        return 160
    }

    /// 封面格高度：4:3 封面 + 名称行。
    static func groupCellHeight(size: ShareSize) -> CGFloat {
        groupTileWidth(size: size) * 4 / 3 + 40
    }

    static func groupRows(gameCount: Int, size: ShareSize) -> Int {
        let columns = size == .phone ? groupColumnsPhone : groupColumnsDesktop
        return Int(ceil(Double(max(gameCount, 1)) / Double(columns)))
    }

    /// 分组卡画布：宽固定，高 = max(标准高, 内容高)，游戏/平台多时拉长（同总览）。
    static func groupSize(gameCount: Int, platformCount: Int, size: ShareSize) -> CGSize {
        let rows = gameCount == 0 ? 0 : groupRows(gameCount: gameCount, size: size)
        let rowGap: CGFloat = size == .phone ? 24 : 20
        let gamesHeight: CGFloat = rows == 0
            ? 0
            : CGFloat(rows) * groupCellHeight(size: size) + CGFloat(rows - 1) * rowGap
        let platformHeight: CGFloat = platformCount == 0
            ? 0
            : CGFloat(platformCount) * (size == .phone ? 36 : 30) + CGFloat(max(platformCount - 1, 0)) * 20
        // 固定部分：顶/标题/统计块/平台标签/水印等（游戏区顶部间距并入 gamesHeight）
        let fixed: CGFloat = size == .phone ? 660 : 420
        let contentHeight = fixed + platformHeight + gamesHeight
        return CGSize(width: size.pixels.width, height: max(size.pixels.height, contentHeight))
    }
}

// MARK: - 主题（跟随系统深浅色）

struct ShareTheme {
    let background: Color
    let card: Color
    let text: Color
    let secondary: Color
    let accent: Color
    let separator: Color

    static let light = ShareTheme(
        background: Color(white: 0.965),
        card: Color(white: 1.0),
        text: Color(white: 0.12),
        secondary: Color(white: 0.45),
        accent: Color(red: 0.85, green: 0.40, blue: 0.12),
        separator: Color(white: 0.85)
    )

    static let dark = ShareTheme(
        background: Color(white: 0.09),
        card: Color(white: 0.14),
        text: Color(white: 0.93),
        secondary: Color(white: 0.56),
        accent: Color(red: 1.0, green: 0.72, blue: 0.42),
        separator: Color(white: 0.30)
    )

    static func forScheme(_ scheme: ColorScheme) -> ShareTheme {
        scheme == .dark ? .dark : .light
    }
}

// MARK: - 品牌水印（用户名·游戏簿 + 圆形头像）

/// 分享图左下角品牌水印：设了用户名显示「{用户名}的游戏簿」，未设回退 app.menu；
/// 设了头像则右侧跟一个圆形头像（带主题色描边）。
private struct BrandWatermark: View {
    let theme: ShareTheme
    let fontSize: CGFloat
    /// 覆盖文字与头像描边色：竖卡内容叠在深色遮罩上时传浅色，默认随主题。
    var tint: Color? = nil
    @Environment(\.appLanguageCode) private var language
    @AppStorage(UserCustomization.usernameKey) private var username = ""
    @AppStorage(UserCustomization.avatarFileKey) private var avatarFile = ""

    private var color: Color { tint ?? theme.secondary }

    private var text: String {
        let name = username.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return L10n.tr("app.menu", lang: language) }
        return L10n.tr("share.brandUser", [name], lang: language)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: text)
                .font(.system(size: fontSize))
                .foregroundStyle(color)
            if !avatarFile.isEmpty, let avatar = UserCustomization.avatarImage() {
                Image(nsImage: avatar)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(color, lineWidth: 2))
            }
        }
    }
}

// MARK: - 分享图日期格式（跟随 app 语言，与系统区域无关）

private enum ShareDateFormat {
    static func string(from date: Date, language: String) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: language)
        if language == "zh-Hans" || language == "ja" {
            fmt.dateFormat = "yyyy年 M月 d日"
        } else {
            fmt.dateFormat = "MMM d, yyyy"
        }
        return fmt.string(from: date)
    }
}

// MARK: - 封面辅助视图

private struct CoverImage: View {
    let game: Game
    let theme: ShareTheme
    /// .fit：完整显示封面（居中、四边可能留白）；.fill：铺满容器（可能裁切）。
    var mode: ContentMode = .fill
    @Environment(\.appLanguageCode) private var language

    var body: some View {
        Group {
            if let image = game.coverImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: mode)
            } else {
                ZStack {
                    Rectangle().fill(theme.card)
                    VStack(spacing: 12) {
                        Image(systemName: "gamecontroller")
                            .font(.system(size: 60))
                        Text(verbatim: game.displayName(for: language))
                            .font(.system(size: 28, weight: .medium))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .padding(.horizontal, 16)
                    }
                    .foregroundStyle(theme.secondary)
                }
            }
        }
    }
}

// MARK: - 主视图

struct ShareCardView: View {
    let content: ShareCardContent
    let theme: ShareTheme
    @Environment(\.appLanguageCode) private var language

    var body: some View {
        switch content {
        case .single(let game, let size):
            switch size {
            case .phone: SingleCardVertical(game: game, theme: theme)
            case .desktop: SingleCardHorizontal(game: game, theme: theme)
            }
        case .overview(let games, let title, let size):
            OverviewCard(games: games, title: title, size: size, theme: theme)
        case .group(let group, let title, let size):
            GroupShareCard(group: group, title: title, size: size, theme: theme)
        }
    }
}

// MARK: - 单卡 · 竖版 9:16

private struct SingleCardVertical: View {
    let game: Game
    let theme: ShareTheme

    /// 深色半透明内容条的文案用色：封面明暗随机，固定浅色保证可读。
    private let contentText = Color.white
    private let contentSecondary = Color.white.opacity(0.82)
    private let contentAccent = Color(red: 1.0, green: 0.82, blue: 0.55)

    var body: some View {
        ZStack(alignment: .top) {
            // 封面：按卡宽完整显示、顶端对齐，作为整卡背景。
            CoverImage(game: game, theme: theme, mode: .fit)
                .frame(width: 1080, height: 1920, alignment: .top)
                .clipped()

            // 内容条：贴卡底，半透明渐变遮罩铺满整条（标题区也有明显遮罩），封面完整透出。
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [.black.opacity(0.45), Color.black.opacity(0.80), Color.black.opacity(0.95)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 812)

                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: game.displayName(for: language))
                        .font(.system(size: 78, weight: .bold))
                        .foregroundStyle(contentText)
                        .lineLimit(2)

                    let platforms = game.completions.map(\.platform).filter { !$0.isEmpty }
                    if !platforms.isEmpty {
                        Text(verbatim: Array(Set(platforms)).sorted()
                            .map { Presets.display($0, category: .platform, language: language) }
                            .joined(separator: " · "))
                            .font(.system(size: 40, weight: .medium))
                            .foregroundStyle(contentSecondary)
                            .padding(.top, 20)
                    }

                    if let latest = game.sortedCompletions.last, let date = latest.date {
                        Text(verbatim: ShareDateFormat.string(from: date, language: language))
                            .font(.system(size: 30))
                            .foregroundStyle(contentSecondary)
                            .padding(.top, 12)
                    }

                    if !game.reviewTitle.isEmpty {
                        Text(verbatim: game.reviewTitle)
                            .font(.system(size: 38)).italic()
                            .foregroundStyle(contentAccent)
                            .padding(.top, 28)
                    }

                    if let averages = dimensionValues {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 28), count: 3),
                            spacing: 18
                        ) {
                            ForEach(Dimension.allCases) { dimension in
                                VStack(spacing: 8) {
                                    Text(verbatim: L10n.tr(dimension.labelKey, lang: language))
                                        .font(.system(size: 30, weight: .medium))
                                        .foregroundStyle(contentSecondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                    Text(verbatim: averages[dimension].map { String(format: "%.1f", $0) } ?? "—")
                                        .font(.system(size: 40, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(contentText)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.top, 32)
                    }

                    HStack(spacing: 24) {
                        Rectangle().fill(Color.white.opacity(0.35)).frame(height: 2)
                        if let score = game.libraryScore {
                            Text(verbatim: String(format: "%.1f", score))
                                .font(.system(size: 96, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(contentText)
                        } else {
                            Text(verbatim: L10n.tr("score.unrated", lang: language))
                                .font(.system(size: 56, weight: .medium))
                                .foregroundStyle(contentSecondary)
                        }
                        Rectangle().fill(Color.white.opacity(0.35)).frame(height: 2)
                    }
                    .padding(.vertical, 44)

                    BrandWatermark(theme: theme, fontSize: 28, tint: contentSecondary)
                }
                .padding(.horizontal, 72)
                .padding(.top, 36)
                .padding(.bottom, 56)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 812)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

            // 右上角分数胶囊。
            if let score = game.libraryScore {
                Text(verbatim: String(format: "%.1f", score))
                    .font(.system(size: 52, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .frame(width: 1080, height: 1920)
        .background(theme.background)
    }

    @Environment(\.appLanguageCode) private var language

    private var dimensionValues: [Dimension: Double]? {
        let c = game.sortedCompletions.last
        guard let c, c.hasScores else { return nil }
        return Dictionary(uniqueKeysWithValues: Dimension.allCases.compactMap { dimension in
            c.score(for: dimension).map { (dimension, $0) }
        })
    }
}

// MARK: - 单卡 · 横版 16:9

private struct SingleCardHorizontal: View {
    let game: Game
    let theme: ShareTheme

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                CoverImage(game: game, theme: theme, mode: .fit)
                    .frame(width: 820, height: 1080)
                    .background(theme.card)
                    .clipped()
                if let score = game.libraryScore {
                    Text(verbatim: String(format: "%.1f", score))
                        .font(.system(size: 46, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(32)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 40)
                Text(verbatim: game.displayName(for: language))
                    .font(.system(size: 76, weight: .bold))
                    .foregroundStyle(theme.text)
                    .lineLimit(2)

                let platforms = game.completions.map(\.platform).filter { !$0.isEmpty }
                if !platforms.isEmpty {
                    Text(verbatim: Array(Set(platforms)).sorted()
                        .map { Presets.display($0, category: .platform, language: language) }
                        .joined(separator: " · "))
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(theme.secondary)
                        .padding(.top, 18)
                }

                if let latest = game.sortedCompletions.last, let date = latest.date {
                    Text(verbatim: ShareDateFormat.string(from: date, language: language))
                        .font(.system(size: 27))
                        .foregroundStyle(theme.secondary)
                        .padding(.top, 10)
                }

                if !game.reviewTitle.isEmpty {
                    Text(verbatim: game.reviewTitle)
                        .font(.system(size: 34)).italic()
                        .foregroundStyle(theme.accent)
                        .padding(.top, 24)
                }

                Spacer()

                if let averages = dimensionValues {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 28), count: 3),
                        spacing: 16
                    ) {
                        ForEach(Dimension.allCases) { dimension in
                            VStack(spacing: 6) {
                                Text(verbatim: L10n.tr(dimension.labelKey, lang: language))
                                    .font(.system(size: 28, weight: .medium))
                                    .foregroundStyle(theme.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Text(verbatim: averages[dimension].map { String(format: "%.1f", $0) } ?? "—")
                                    .font(.system(size: 36, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(theme.text)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.top, 32)
                }

                HStack(spacing: 20) {
                    Rectangle().fill(theme.separator).frame(height: 2)
                    if let score = game.libraryScore {
                        Text(verbatim: String(format: "%.1f", score))
                            .font(.system(size: 84, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(theme.text)
                    } else {
                        Text(verbatim: L10n.tr("score.unrated", lang: language))
                            .font(.system(size: 48, weight: .medium))
                            .foregroundStyle(theme.secondary)
                    }
                    Rectangle().fill(theme.separator).frame(height: 2)
                }
                .padding(.vertical, 36)

                BrandWatermark(theme: theme, fontSize: 26)
            }
            .padding(.horizontal, 68)
            .padding(.bottom, 44)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(theme.background)
        }
        .frame(width: 1920, height: 1080)
    }

    @Environment(\.appLanguageCode) private var language

    private var dimensionValues: [Dimension: Double]? {
        let c = game.sortedCompletions.last
        guard let c, c.hasScores else { return nil }
        return Dictionary(uniqueKeysWithValues: Dimension.allCases.compactMap { dimension in
            c.score(for: dimension).map { (dimension, $0) }
        })
    }
}

// MARK: - 分组分享卡（分组名 + 统计 + 平台分布，不含评价）

private struct GroupShareCard: View {
    let group: GameGroup
    let title: String
    let size: ShareSize
    let theme: ShareTheme
    @Environment(\.appLanguageCode) private var language

    /// 组内游戏按名称排序（展示稳定）。
    private var games: [Game] {
        group.games.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// 平均分：组内各游戏库显示分的均值（按游戏聚合），无已评分则 nil。
    private var averageScore: Double? {
        let scores = games.compactMap(\.libraryScore)
        guard !scores.isEmpty else { return nil }
        return ScoreMath.roundScore(scores.reduce(0, +) / Double(scores.count))
    }

    private var completionCount: Int {
        games.flatMap(\.completions).count
    }

    /// 平台分布：组内所有通关记录按平台计数（与统计页同口径）。
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

    private var maxPlatformCount: Int { platformCounts.map(\.count).max() ?? 1 }

    var body: some View {
        let canvas = ShareCardLayout.groupSize(gameCount: games.count, platformCount: platformCounts.count, size: size)
        return Group {
            if size == .phone {
                vertical
            } else {
                horizontal
            }
        }
        .frame(width: canvas.width, height: canvas.height)
        .background(theme.background)
    }

    // MARK: 竖版 9:16

    private var vertical: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: title)
                .font(.system(size: 84, weight: .bold))
                .foregroundStyle(theme.text)
                .lineLimit(2)

            HStack(spacing: 24) {
                ShareStatTile(label: L10n.tr("group.avgScore", lang: language),
                              value: averageScore.map { String(format: "%.1f", $0) } ?? "—",
                              theme: theme)
                ShareStatTile(label: L10n.tr("group.gameCount", lang: language),
                              value: "\(games.count)",
                              theme: theme)
                ShareStatTile(label: L10n.tr("group.completionCount", lang: language),
                              value: "\(completionCount)",
                              theme: theme)
            }
            .padding(.top, 40)

            if !platformCounts.isEmpty {
                Text(verbatim: L10n.tr("stats.byPlatform", lang: language))
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(theme.secondary)
                    .padding(.top, 48)

                VStack(spacing: 20) {
                    ForEach(platformCounts, id: \.platform) { item in
                        SharePlatformBarRow(platform: item.platform, count: item.count,
                                            maxCount: maxPlatformCount, language: language, theme: theme)
                    }
                }
                .padding(.top, 20)
            }

            if !games.isEmpty {
                verticalGames
                    .padding(.top, 48)
            }

            Spacer(minLength: 20)
            BrandWatermark(theme: theme, fontSize: 30)
                .padding(.bottom, 96)
        }
        .padding(.top, 56)
        .padding(.horizontal, 72)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// 竖版游戏封面格：一行 3 个，全部显示（画布按内容拉高）。
    private var verticalGames: some View {
        let cols = ShareCardLayout.groupColumnsPhone
        let rows = ShareCardLayout.groupRows(gameCount: games.count, size: .phone)
        let tile = ShareCardLayout.groupTileWidth(size: .phone)
        return VStack(spacing: 24) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 24) {
                    ForEach(0..<cols, id: \.self) { col in
                        let index = row * cols + col
                        if index < games.count {
                            GroupGameTile(game: games[index], tileSize: tile, theme: theme)
                        } else {
                            Color.clear
                                .frame(width: tile, height: tile * 4 / 3 + 40)
                        }
                    }
                }
            }
        }
    }

    /// 横版游戏封面格：一行 5 个，全部显示（画布按内容拉高）。
    private var horizontalGames: some View {
        let cols = ShareCardLayout.groupColumnsDesktop
        let rows = ShareCardLayout.groupRows(gameCount: games.count, size: .desktop)
        let tile = ShareCardLayout.groupTileWidth(size: .desktop)
        return VStack(spacing: 20) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 16) {
                    ForEach(0..<cols, id: \.self) { col in
                        let index = row * cols + col
                        if index < games.count {
                            GroupGameTile(game: games[index], tileSize: tile, theme: theme, nameSize: 24)
                        } else {
                            Color.clear
                                .frame(width: tile, height: tile * 4 / 3 + 40)
                        }
                    }
                }
            }
        }
    }

    // MARK: 横版 16:9

    private var horizontal: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: title)
                    .font(.system(size: 68, weight: .bold))
                    .foregroundStyle(theme.text)
                    .lineLimit(2)

                HStack(spacing: 20) {
                    ShareStatTile(label: L10n.tr("group.avgScore", lang: language),
                                  value: averageScore.map { String(format: "%.1f", $0) } ?? "—",
                                  theme: theme, labelSize: 22, valueSize: 44, padding: 20)
                    ShareStatTile(label: L10n.tr("group.gameCount", lang: language),
                                  value: "\(games.count)",
                                  theme: theme, labelSize: 22, valueSize: 44, padding: 20)
                    ShareStatTile(label: L10n.tr("group.completionCount", lang: language),
                                  value: "\(completionCount)",
                                  theme: theme, labelSize: 22, valueSize: 44, padding: 20)
                }
                .padding(.top, 28)

                if !games.isEmpty {
                    horizontalGames
                        .padding(.top, 32)
                }

                Spacer()
                BrandWatermark(theme: theme, fontSize: 26)
            }
            .frame(maxWidth: .infinity)
            .padding(.leading, 64)
            .padding(.trailing, 40)
            .padding(.top, 48)
            .padding(.bottom, 96)

            if !platformCounts.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer()
                    Text(verbatim: L10n.tr("stats.byPlatform", lang: language))
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(theme.secondary)
                    VStack(spacing: 16) {
                        ForEach(platformCounts, id: \.platform) { item in
                            SharePlatformBarRow(platform: item.platform, count: item.count,
                                                maxCount: maxPlatformCount, language: language, theme: theme,
                                                labelWidth: 200, fontSize: 26, barHeight: 12)
                        }
                    }
                    .padding(.top, 22)
                    Spacer()
                }
                .frame(width: 780)
                .padding(.trailing, 64)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// 分组分享卡里的单个游戏封面格（封面 + 名称）。
private struct GroupGameTile: View {
    let game: Game
    let tileSize: CGFloat
    let theme: ShareTheme
    var nameSize: CGFloat = 26
    @Environment(\.appLanguageCode) private var language

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let image = game.coverImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ZStack {
                        Rectangle().fill(theme.card)
                        Image(systemName: "gamecontroller")
                            .foregroundStyle(theme.secondary)
                    }
                }
            }
            .frame(width: tileSize, height: tileSize * 4 / 3)
            .background(theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(verbatim: game.displayName(for: language))
                .font(.system(size: nameSize, weight: .medium))
                .foregroundStyle(theme.text)
                .lineLimit(1)
        }
        .frame(width: tileSize)
    }
}

/// 分享卡统计小方块（平均分 / 游戏数 / 通关数）。
private struct ShareStatTile: View {
    let label: String
    let value: String
    let theme: ShareTheme
    var labelSize: CGFloat = 28
    var valueSize: CGFloat = 64
    var padding: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: label)
                .font(.system(size: labelSize, weight: .medium))
                .foregroundStyle(theme.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(verbatim: value)
                .font(.system(size: valueSize, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(padding)
        .background(RoundedRectangle(cornerRadius: 20).fill(theme.card))
    }
}

/// 分享卡平台条（主题色，非系统 accent）。
private struct SharePlatformBarRow: View {
    let platform: String
    let count: Int
    let maxCount: Int
    let language: String
    let theme: ShareTheme
    var labelWidth: CGFloat = 220
    var fontSize: CGFloat = 30
    var barHeight: CGFloat = 14

    var body: some View {
        HStack(spacing: 16) {
            Text(verbatim: Presets.display(platform, category: .platform, language: language))
                .font(.system(size: fontSize, weight: .medium))
                .foregroundStyle(theme.secondary)
                .frame(width: labelWidth, alignment: .leading)
                .lineLimit(1)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.card)
                    Capsule()
                        .fill(theme.accent)
                        .frame(width: proxy.size.width * CGFloat(count) / CGFloat(maxCount))
                }
            }
            .frame(height: barHeight)
            Text(verbatim: "\(count)")
                .font(.system(size: fontSize, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(theme.text)
                .frame(width: 48, alignment: .trailing)
        }
    }
}

// MARK: - 总览图（多选）

private struct OverviewCard: View {
    let games: [Game]
    let title: String
    let size: ShareSize
    let theme: ShareTheme
    @Environment(\.appLanguageCode) private var language
    @AppStorage(UserCustomization.avatarFileKey) private var avatarFile = ""

    private var columns: Int { size == .phone ? 2 : 4 }
    private var cellSize: CGSize { ShareCardLayout.cellSize(count: games.count, size: size) }
    private var headerHeight: CGFloat { size == .phone ? ShareCardLayout.headerHeightPhone : ShareCardLayout.headerHeightDesktop }
    private var rows: Int { Int(ceil(Double(max(games.count, 1)) / Double(columns))) }
    private var gap: CGFloat { ShareCardLayout.gap }

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: gap) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<columns, id: \.self) { column in
                            let index = row * columns + column
                            if index < games.count {
                                OverviewCell(game: games[index], cellSize: cellSize, theme: theme)
                            } else {
                                Color.clear.frame(width: cellSize.width, height: cellSize.height)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, gap)
            .padding(.bottom, gap)
        }
        .frame(width: size.pixels.width, height: ShareCardLayout.overviewSize(gameCount: games.count, size: size).height)
        .background(theme.background)
        .overlay(alignment: .topLeading) {
            if !avatarFile.isEmpty, let avatar = UserCustomization.avatarImage() {
                Image(nsImage: avatar)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(theme.secondary, lineWidth: 2))
                    .padding(28)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text(verbatim: title)
                .font(.system(size: size == .phone ? 64 : 54, weight: .bold))
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(verbatim: L10n.tr("share.count", [games.count as CVarArg], lang: language))
                .font(.system(size: 32))
                .foregroundStyle(theme.secondary)
        }
        .frame(height: headerHeight)
    }
}

private struct OverviewCell: View {
    let game: Game
    let cellSize: CGSize
    let theme: ShareTheme
    @Environment(\.appLanguageCode) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let image = game.coverImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ZStack {
                        Rectangle().fill(theme.card)
                        Image(systemName: "gamecontroller")
                            .foregroundStyle(theme.secondary)
                    }
                }
            }
            .frame(width: cellSize.width, height: cellSize.width * 4 / 3)
            .background(theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(verbatim: game.displayName(for: language))
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(theme.text)
                .lineLimit(1)

            HStack {
                let platform = game.sortedCompletions.last?.platform ?? ""
                Text(verbatim: Presets.display(platform, category: .platform, language: language))
                    .font(.system(size: 20))
                    .foregroundStyle(theme.secondary)
                    .lineLimit(1)
                Spacer()
                if let score = game.libraryScore {
                    Text(verbatim: String(format: "%.1f", score))
                        .font(.system(size: 22, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(theme.accent)
                }
            }

            if let latest = game.sortedCompletions.last, let date = latest.date {
                Text(verbatim: ShareDateFormat.string(from: date, language: language))
                    .font(.system(size: 17))
                    .foregroundStyle(theme.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: cellSize.width, height: cellSize.height, alignment: .top)
    }
}
