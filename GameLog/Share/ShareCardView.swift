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

    var canvasSize: CGSize {
        switch self {
        case .single(_, let size):
            size.pixels
        case .overview(let games, _, let size):
            ShareCardLayout.overviewSize(gameCount: games.count, size: size)
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
                        Text(verbatim: game.name)
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
                    colors: [.black.opacity(0.45), Color.black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 800)

                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: game.name)
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

                    if let latest = game.sortedCompletions.last {
                        Text(verbatim: ShareDateFormat.string(from: latest.date, language: language))
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
                .padding(.top, 24)
                .padding(.bottom, 56)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 800)
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
                Text(verbatim: game.name)
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

                if let latest = game.sortedCompletions.last {
                    Text(verbatim: ShareDateFormat.string(from: latest.date, language: language))
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

            Text(verbatim: game.name)
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

            if let latest = game.sortedCompletions.last {
                Text(verbatim: ShareDateFormat.string(from: latest.date, language: language))
                    .font(.system(size: 17))
                    .foregroundStyle(theme.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: cellSize.width, height: cellSize.height, alignment: .top)
    }
}
