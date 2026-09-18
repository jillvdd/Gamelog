import SwiftUI

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

    /// 分组卡统计要素在内容构造时读取（UserDefaults），测试环境无存储时走默认配置。
    /// 尺寸向上取整：布局含 4/3 比例时高度常为小数，ImageRenderer 按整数像素出图，
    /// 小数画布的最底一行会留白（未绘制 → 透明 → 导出显白线）。
    var canvasSize: CGSize {
        func ceilSize(_ s: CGSize) -> CGSize {
            CGSize(width: ceil(s.width), height: ceil(s.height))
        }
        switch self {
        case .single(_, let size):
            return size.pixels
        case .overview(let games, _, let size):
            return ceilSize(ShareCardLayout.overviewSize(gameCount: games.count, size: size))
        case .group(let group, _, let size):
            return ceilSize(ShareCardLayout.groupSize(
                gameCount: group.games.count,
                platformCount: Set(group.games.flatMap(\.platformList)).count,
                size: size
            ))
        }
    }
}

// MARK: - 布局数学（固定数值，便于 ImageRenderer 精确出图）

enum ShareCardLayout {
    static let gap: CGFloat = 36
    static let headerHeightPhone: CGFloat = 300
    static let headerHeightDesktop: CGFloat = 240

    // MARK: 总览图：列数随数量自适应（少量选大格、上百款自动密排，画布高度可控）

    static func overviewColumns(gameCount: Int, size: ShareSize) -> Int {
        switch size {
        case .phone:
            if gameCount <= 4 { return 2 }
            if gameCount <= 15 { return 3 }
            return 4
        case .desktop:
            if gameCount <= 8 { return 4 }
            if gameCount <= 24 { return 5 }
            return 6
        }
    }

    /// 格子字段流式行数（两列一行）。估算用「启用数」≥ 实际（缺数据字段会隐藏）。
    static func tileFieldRows() -> Int {
        Int(ceil(Double(ShareTileFieldsConfig.load().count) / 2))
    }

    static func overviewCaptionHeight(size: ShareSize) -> CGFloat {
        let rowHeight: CGFloat = size == .phone ? 26 : 22
        let nameBlock: CGFloat = size == .phone ? 56 : 51
        return nameBlock + CGFloat(tileFieldRows()) * rowHeight
    }

    static func overviewCellWidth(columns: Int, size: ShareSize) -> CGSize {
        let width = (size.pixels.width - CGFloat(columns + 1) * gap) / CGFloat(columns)
        // 井格 2:3（SteamGridDB 竖版封面标准比例，满格无留白）。
        return CGSize(width: width, height: width * 3 / 2 + overviewCaptionHeight(size: size))
    }

    static func overviewSize(gameCount: Int, size: ShareSize) -> CGSize {
        let count = max(gameCount, 1)
        let columns = overviewColumns(gameCount: count, size: size)
        let rows = Int(ceil(Double(count) / Double(columns)))
        let cell = overviewCellWidth(columns: columns, size: size)
        let header = size == .phone ? headerHeightPhone : headerHeightDesktop
        let height = header + CGFloat(rows) * cell.height + CGFloat(rows - 1) * gap + gap
        return CGSize(width: size.pixels.width, height: height)
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

    /// 封面格高度：2:3 封面 + 名称行 + 字段行（随字段池动态）。
    static func groupCellHeight(size: ShareSize) -> CGFloat {
        groupTileWidth(size: size) * 3 / 2 + 40 + CGFloat(tileFieldRows()) * 24
    }

    static func groupRows(gameCount: Int, size: ShareSize) -> Int {
        let columns = size == .phone ? groupColumnsPhone : groupColumnsDesktop
        return Int(ceil(Double(max(gameCount, 1)) / Double(columns)))
    }

    /// 分组卡画布：宽固定，高 = max(名义高, 内容估算)。估算 ≥ 实际是硬要求——不足会把水印挤出底缘裁掉。
    static func groupSize(gameCount: Int, platformCount: Int, size: ShareSize) -> CGSize {
        let n = max(gameCount, 1)
        if size == .desktop {
            // 桌面单列全宽流估算（与 GroupShareCard.horizontal 同构）：
            // 顶52 + 标题2行/引言3行最坏 ~290 + 数字统计行 ~112 + 特殊行各 ~92 +
            // 弹性间距保底 3×20 + 水印前距 16 + 水印 30 + 底 48。
            let fixed: CGFloat = 52 + 290 + 112 + 2 * 92 + 60 + 16 + 30 + 48
            let gamesHeight: CGFloat
            if n <= 4 {
                // 特写带：大封面（行内均分、单格上限 430）
                let tileW = min(430, (1340 - CGFloat(n - 1) * 24) / CGFloat(n))
                gamesHeight = tileW * 3 / 2 + 44 + CGFloat(tileFieldRows()) * 24
            } else {
                // 全宽网格：≤8 款单行排满，更多 6 列
                let cols = n <= 8 ? n : 6
                let tileW = (1792 - CGFloat(cols - 1) * 24) / CGFloat(cols)
                let rows = Int(ceil(Double(n) / Double(cols)))
                gamesHeight = CGFloat(rows) * (tileW * 3 / 2 + 44 + CGFloat(tileFieldRows()) * 24) + CGFloat(rows - 1) * 24
            }
            // ≤4 款平台条在封面带右侧、高度被带子吸收不另计；≥5 款为全宽条区（标签 + 条）。
            let platformHeight: CGFloat = (platformCount == 0 || n <= 4)
                ? 0
                : 44 + min(CGFloat(platformCount), 6) * 48
            return CGSize(width: size.pixels.width,
                          height: max(size.pixels.height, fixed + gamesHeight + platformHeight))
        }
        // 手机分支
        let rows = gameCount == 0 ? 0 : groupRows(gameCount: n, size: .phone)
        let gamesHeight: CGFloat = rows == 0
            ? 0
            : CGFloat(rows) * groupCellHeight(size: .phone) + CGFloat(rows - 1) * 24
        let platformHeight: CGFloat = platformCount == 0
            ? 0
            // 「按平台分布」标签行(~66) + 条形区。
            : 66 + CGFloat(platformCount) * 40 + CGFloat(max(platformCount - 1, 0)) * 20
        // 固定部分估算：顶/标题(2行)/引言/统计块(默认全开)/平台标签/弹性间距保底值/水印。
        let fixed: CGFloat = 1080
        let contentHeight = fixed + platformHeight + gamesHeight
        return CGSize(width: size.pixels.width, height: max(size.pixels.height, contentHeight))
    }
}

// MARK: - 分享样式配置（三个可勾选+可排序的要素池，持久化在 UserDefaults）

/// 总览图头部汇总要素池。
enum OverviewHeaderStat: String, CaseIterable, Identifiable, Hashable {
    case gameCount
    case averageScore
    case completionCount
    case collectionValue

    var id: String { rawValue }
}

/// 游戏格子字段池（总览格与分组卡格共用一份配置，按顺序流式两列排布）。
enum GameTileField: String, CaseIterable, Identifiable, Hashable {
    case platform
    case score
    case date
    case releaseYear
    case status

    var id: String { rawValue }
}

/// 分组卡统计要素池。
enum GroupStatItem: String, CaseIterable, Identifiable, Hashable {
    case averageScore
    case gameCount
    case completionCount
    case topGame
    case collectionValue

    var id: String { rawValue }
}

/// 要素池的 JSON 编解码：存储 = 已启用项 rawValue 的有序数组（顺序即显示顺序），
/// 未出现的即禁用；key 缺失回退默认；未知值（如已删除的要素）静默过滤。
enum ShareConfigCodec {
    static func load<T: RawRepresentable & Hashable>(_ key: String, default defaultValue: [T]) -> [T]
    where T.RawValue == String {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let data = raw.data(using: .utf8),
              let names = try? JSONDecoder().decode([String].self, from: data) else {
            return defaultValue
        }
        var seen = Set<T>()
        var out: [T] = []
        for name in names {
            if let item = T(rawValue: name), seen.insert(item).inserted {
                out.append(item)
            }
        }
        return out
    }

    static func save<T: RawRepresentable>(_ items: [T], key: String) where T.RawValue == String {
        guard let data = try? JSONEncoder().encode(items.map(\.rawValue)),
              let json = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(json, forKey: key)
    }
}

enum ShareOverviewStatsConfig {
    private static let defaultValue: [OverviewHeaderStat] = [.gameCount, .averageScore]

    static func load() -> [OverviewHeaderStat] {
        ShareConfigCodec.load(UserCustomization.shareOverviewStatsKey, default: defaultValue)
    }
    static func save(_ items: [OverviewHeaderStat]) {
        ShareConfigCodec.save(items, key: UserCustomization.shareOverviewStatsKey)
    }
}

enum ShareTileFieldsConfig {
    private static let defaultValue: [GameTileField] = [.platform, .score, .date]

    static func load() -> [GameTileField] {
        ShareConfigCodec.load(UserCustomization.shareTileFieldsKey, default: defaultValue)
    }
    static func save(_ items: [GameTileField]) {
        ShareConfigCodec.save(items, key: UserCustomization.shareTileFieldsKey)
    }
}

enum ShareGroupStatsConfig {
    private static let defaultValue: [GroupStatItem] =
        [.averageScore, .gameCount, .completionCount, .topGame]

    static func load() -> [GroupStatItem] {
        ShareConfigCodec.load(UserCustomization.shareGroupStatsKey, default: defaultValue)
    }
    static func save(_ items: [GroupStatItem]) {
        ShareConfigCodec.save(items, key: UserCustomization.shareGroupStatsKey)
    }
}

// MARK: - 主题（品牌化固定深色，不再跟随系统）

struct ShareTheme {
    let background: Color
    let surface: Color
    let text: Color
    let secondary: Color
    let accent: Color
    let separator: Color

    /// 固定深色品牌主题：暖调近黑底 + 琥珀橙强调（沿用原深色主题 accent）。
    static let brand = ShareTheme(
        background: BrandPalette.background,
        surface: BrandPalette.surface,
        text: Color(white: 0.95),
        secondary: Color(white: 0.60),
        accent: BrandPalette.accent,
        separator: Color(white: 0.22)
    )
}

private extension Dimension {
    /// 六维条形色（与详情页条形图同一套系统色，深浅底皆可读）。
    var shareBarColor: Color {
        switch self {
        case .gameplay: .orange
        case .design: .teal
        case .story: .blue
        case .art: .purple
        case .music: .pink
        case .performance: .green
        }
    }
}

private extension GameStatus {
    /// 状态徽章色（分享卡专用映射）。
    var shareStatusColor: Color {
        switch self {
        case .backlog: .yellow
        case .playing: .green
        case .paused: .orange
        case .dropped: .red
        case .longRunning: .purple
        case .completed: .teal
        // 自动建库的条目（用户还没分类）在分享卡上也保持中性色，不伪装成任何一种进度。
        case .unclassified: .gray
        }
    }
}

// MARK: - 文案格式化助手

private enum ShareFormat {
    /// 按语言的三语日期（与旧版一致）。
    static func date(_ date: Date, language: String) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: language)
        if language == "zh-Hans" || language == "ja" {
            fmt.dateFormat = "yyyy年 M月 d日"
        } else {
            fmt.dateFormat = "MMM d, yyyy"
        }
        return fmt.string(from: date)
    }

    /// 发售年份（无则 nil）。
    static func releaseYear(_ date: Date?) -> String? {
        guard let date else { return nil }
        return String(Calendar.current.component(.year, from: date))
    }

    /// 时长数值文本：去尾零（150 → "150"，128.5 → "128.5"）。
    /// （时长已从全部分享线移除，暂留实现备未来要素池复用。）
    static func hours(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.1f", value)
    }
}

// MARK: - 封面比例助手

/// 封面真实宽高比（无封面回退 3:4）。海报框贴合封面比例——SteamGridDB 竖版封面是 2:3，
/// 固定 3:4 框会让封面两侧留白（2026-08-24 封面尺寸审计）。
private func coverAspect(_ game: Game) -> CGFloat {
    guard let img = game.coverImage else { return 3 / 4 }
    let s = img.size
    guard s.width > 0, s.height > 0 else { return 3 / 4 }
    return s.width / s.height
}

// MARK: - 品牌水印（用户名·游戏簿 + 圆形头像）

private struct BrandWatermark: View {
    let theme: ShareTheme
    let fontSize: CGFloat
    @Environment(\.appLanguageCode) private var language
    @AppStorage(UserCustomization.usernameKey) private var username = ""
    @AppStorage(UserCustomization.avatarFileKey) private var avatarFile = ""

    private var text: String {
        let name = username.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return L10n.tr("app.menu", lang: language) }
        return L10n.tr("share.brandUser", [name], lang: language)
    }

    var body: some View {
        HStack(spacing: 14) {
            Text(verbatim: text)
                .font(.system(size: fontSize))
                .foregroundStyle(theme.secondary)
            if !avatarFile.isEmpty, let avatar = UserCustomization.avatarImage() {
                Image(appImage: avatar)
                    .resizable()
                    .frame(width: fontSize * 1.75, height: fontSize * 1.75)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(theme.secondary.opacity(0.7), lineWidth: 2))
            }
        }
    }
}

// MARK: - 封面辅助视图

private struct CoverImage: View {
    let game: Game
    let theme: ShareTheme
    /// .fit：完整显示封面；.fill：铺满容器（可能裁切）。
    var mode: ContentMode = .fill
    @Environment(\.appLanguageCode) private var language

    var body: some View {
        Group {
            if let image = game.coverImage {
                Image(appImage: image)
                    .resizable()
                    .aspectRatio(contentMode: mode)
            } else {
                ZStack {
                    Rectangle().fill(theme.surface)
                    VStack(spacing: 12) {
                        Image(systemName: "gamecontroller")
                            .font(.system(size: 56))
                        Text(verbatim: game.displayName(for: language))
                            .font(.system(size: 26, weight: .medium))
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

/// 模糊封面垫底：封面铺满放大 + 高斯模糊 + 深色压暗层，消灭灰边、统一暗调。
/// 无封面时退化为纯背景色的微渐变。
/// ⚠️ 装饰层全部放 overlay（不参与布局）——直接放 ZStack 子层会把布局撑到超出画布，
/// 导致整卡内容偏移裁切（§32.4 P1）。
private struct BlurredCoverBackdrop: View {
    let game: Game
    let theme: ShareTheme

    var body: some View {
        ZStack {
            theme.background
        }
        .overlay {
            if game.coverImage != nil {
                CoverImage(game: game, theme: theme, mode: .fill)
                    // 2000×2400 同时盖满 1080×1920 与 1920×1080 两种画布（小了会露出底色边带）。
                    .frame(width: 2000, height: 2400, alignment: .center)
                    .blur(radius: 70, opaque: true)
                    .scaleEffect(1.08)
            }
        }
        .overlay {
            LinearGradient(
                colors: [theme.background.opacity(0.45), theme.background.opacity(0.88)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipped()
    }
}

// MARK: - 主视图

struct ShareCardView: View {
    let content: ShareCardContent
    let theme: ShareTheme

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

// MARK: - 单卡共用信息组件

/// 元数据行：发售年 · 总时长 · 通关次数（各自可缺省）。
private struct MetaLine: View {
    let game: Game
    let theme: ShareTheme
    let fontSize: CGFloat
    @Environment(\.appLanguageCode) private var language

    private var segments: [String] {
        // 单卡信息行只保留发售年（时长/通关次数经 grill 评定为冗余，2026-08-24）。
        var segs: [String] = []
        if let year = ShareFormat.releaseYear(game.releaseDate) {
            segs.append(L10n.tr("share.releasedIn", [year], lang: language))
        }
        return segs
    }

    var body: some View {
        if !segments.isEmpty {
            Text(verbatim: segments.joined(separator: " · "))
                .font(.system(size: fontSize))
                .monospacedDigit()
                .foregroundStyle(theme.secondary)
        }
    }
}

/// 通关程度胶囊（最新一条记录的程度）。
private struct DegreePill: View {
    let game: Game
    let theme: ShareTheme
    let fontSize: CGFloat
    @Environment(\.appLanguageCode) private var language

    var body: some View {
        if let degree = game.sortedCompletions.last?.degree {
            Text(verbatim: Presets.display(degree, category: .degree, language: language))
                .font(.system(size: fontSize, weight: .medium))
                .foregroundStyle(theme.text.opacity(0.92))
                .padding(.horizontal, fontSize * 0.7)
                .padding(.vertical, fontSize * 0.3)
                .background(Capsule().fill(Color.white.opacity(0.10)))
                .overlay(Capsule().stroke(theme.secondary.opacity(0.55), lineWidth: 1.5))
        }
    }
}

/// 未通关状态大徽章：替代六维/分数区。仿真玻璃（状态色半透明底 + 同色描边 + 白字，
/// 保留颜色语义；原因同 ScoreCapsule——ImageRenderer 不渲染 glassEffect）。
private struct StatusHeroBadge: View {
    let game: Game
    let theme: ShareTheme
    @Environment(\.appLanguageCode) private var language

    var body: some View {
        let status = game.statusValue
        let color = status.shareStatusColor
        HStack(spacing: 16) {
            Image(systemName: status.statusIcon)
                .font(.system(size: 44, weight: .semibold))
            Text(verbatim: L10n.tr(status.labelKey, lang: language))
                .font(.system(size: 46, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 44)
        .padding(.vertical, 24)
        .background(Capsule().fill(color.opacity(0.26)))
        .overlay(Capsule().stroke(color.opacity(0.50), lineWidth: 2))
    }

}

/// 六维均值迷你条形（全部已评分记录的维度均值，与库显示分同口径）。
private struct DimensionBars: View {
    let game: Game
    let theme: ShareTheme
    let labelSize: CGFloat
    let valueSize: CGFloat
    let barHeight: CGFloat
    @Environment(\.appLanguageCode) private var language

    private var averages: [(dimension: Dimension, value: Double)] {
        Dimension.allCases.compactMap { d in
            game.dimensionAverage(for: d).map { (d, $0) }
        }
    }

    var body: some View {
        if !averages.isEmpty {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 36), GridItem(.flexible(), spacing: 36)],
                spacing: barHeight * 1.8
            ) {
                ForEach(averages, id: \.dimension) { item in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(verbatim: L10n.tr(item.dimension.labelKey, lang: language))
                                .font(.system(size: labelSize, weight: .medium))
                                .foregroundStyle(theme.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Spacer()
                            Text(verbatim: String(format: "%.1f", item.value))
                                .font(.system(size: valueSize, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(theme.text)
                        }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.13))
                                Capsule()
                                    .fill(item.dimension.shareBarColor)
                                    .frame(width: max(6, proxy.size.width * item.value / 10))
                            }
                        }
                        .frame(height: barHeight)
                    }
                }
            }
        }
    }
}

/// 分数行：细线 + 大数字（琥珀橙强调）+ 细线。
private struct ScoreRow: View {
    let game: Game
    let theme: ShareTheme
    let numberSize: CGFloat
    @Environment(\.appLanguageCode) private var language

    var body: some View {
        HStack(spacing: 26) {
            Rectangle().fill(theme.separator).frame(height: 2)
            if let score = game.libraryScore {
                Text(verbatim: String(format: "%.1f", score))
                    .font(.system(size: numberSize, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(theme.accent)
            } else {
                Text(verbatim: L10n.tr("score.unrated", lang: language))
                    .font(.system(size: numberSize * 0.58, weight: .medium))
                    .foregroundStyle(theme.secondary)
            }
            Rectangle().fill(theme.separator).frame(height: 2)
        }
    }
}

/// 库分右上角胶囊：仿真玻璃（分享卡经 ImageRenderer 出图，`.glassEffect` 在渲染管线中
/// 不产出内容——实测整枚胶囊消失；用半透明深底 + 高光描边在模糊垫底上呈现玻璃质感）。
private struct ScoreCapsule: View {
    let game: Game
    let theme: ShareTheme
    let fontSize: CGFloat

    var body: some View {
        if let score = game.libraryScore {
            Text(verbatim: String(format: "%.1f", score))
                .font(.system(size: fontSize, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, fontSize * 0.55)
                .frame(height: fontSize * 1.6)
                .background(Capsule().fill(Color.black.opacity(0.38)))
                .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
        }
    }
}

// MARK: - 单卡 · 竖版 9:16

private struct SingleCardVertical: View {
    let game: Game
    let theme: ShareTheme

    var body: some View {
        ZStack {
            BlurredCoverBackdrop(game: game, theme: theme)

            // 清晰海报：上部居中，框贴合封面真实比例（上限宽 720 / 高 990），任何比例都满框无留白。
            CoverImage(game: game, theme: theme, mode: .fit)
                .aspectRatio(coverAspect(game), contentMode: .fit)
                .frame(maxWidth: 720, maxHeight: 990)
                .clipShape(RoundedRectangle(cornerRadius: 26))
                .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
                .padding(.top, 72)
                .frame(maxHeight: .infinity, alignment: .top)

            ScoreCapsule(game: game, theme: theme, fontSize: 50)
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            // 信息面板贴底。
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: game.displayName(for: language))
                    .font(.system(size: 66, weight: .bold))
                    .foregroundStyle(theme.text)
                    .lineLimit(2)

                if !game.platformList.isEmpty {
                    Text(verbatim: game.platformList
                        .map { Presets.display($0, category: .platform, language: language) }
                        .joined(separator: " · "))
                        .font(.system(size: 29, weight: .medium))
                        .foregroundStyle(theme.secondary)
                        .lineLimit(2)
                        .padding(.top, 16)
                }

                MetaLine(game: game, theme: theme, fontSize: 27)
                    .padding(.top, 12)

                if game.isCompletedOrLongRunning {
                    DegreePill(game: game, theme: theme, fontSize: 24)
                        .padding(.top, 18)
                }

                if !game.reviewTitle.isEmpty {
                    Text(verbatim: game.reviewTitle)
                        .font(.system(size: 33, weight: .medium))
                        .foregroundStyle(theme.accent)
                        .lineLimit(3)
                        .padding(.top, 24)
                }

                if game.isCompletedOrLongRunning {
                    DimensionBars(game: game, theme: theme, labelSize: 24, valueSize: 26, barHeight: 11)
                        .padding(.top, 28)
                    ScoreRow(game: game, theme: theme, numberSize: 86)
                        .padding(.vertical, 30)
                } else {
                    StatusHeroBadge(game: game, theme: theme)
                        .padding(.top, 34)
                        .padding(.bottom, 24)
                }

                BrandWatermark(theme: theme, fontSize: 25)
            }
            .padding(.horizontal, 64)
            .padding(.bottom, 46)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(width: 1080, height: 1920)
        .background(theme.background)
    }

    @Environment(\.appLanguageCode) private var language
}

// MARK: - 单卡 · 横版 16:9

private struct SingleCardHorizontal: View {
    let game: Game
    let theme: ShareTheme

    var body: some View {
        ZStack {
            BlurredCoverBackdrop(game: game, theme: theme)

            HStack(spacing: 0) {
                // 左：清晰海报，框贴合封面真实比例。
                CoverImage(game: game, theme: theme, mode: .fit)
                    .aspectRatio(coverAspect(game), contentMode: .fit)
                    .frame(maxHeight: 920)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .shadow(color: .black.opacity(0.5), radius: 26, y: 10)
                    .padding(.leading, 84)

                // 右：信息栏。内容顶对齐海报上缘，水印钉在栏底。
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: game.displayName(for: language))
                        .font(.system(size: 62, weight: .bold))
                        .foregroundStyle(theme.text)
                        .lineLimit(2)
                        .padding(.top, 44)

                    if !game.platformList.isEmpty {
                        Text(verbatim: game.platformList
                            .map { Presets.display($0, category: .platform, language: language) }
                            .joined(separator: " · "))
                            .font(.system(size: 27, weight: .medium))
                            .foregroundStyle(theme.secondary)
                            .lineLimit(2)
                            .padding(.top, 14)
                    }

                    MetaLine(game: game, theme: theme, fontSize: 25)
                        .padding(.top, 10)

                    if game.isCompletedOrLongRunning {
                        DegreePill(game: game, theme: theme, fontSize: 22)
                            .padding(.top, 16)
                    }

                    if !game.reviewTitle.isEmpty {
                        Text(verbatim: game.reviewTitle)
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(theme.accent)
                            .lineLimit(2)
                            .padding(.top, 20)
                    }

                    if game.isCompletedOrLongRunning {
                        // 区块间用弹性间距：内容少时余量均匀分布在段与段之间，
                        // 不再全部堆积在水印上方形成死空档（§32.6 横版和谐度）。
                        Spacer(minLength: 24)
                        DimensionBars(game: game, theme: theme, labelSize: 21, valueSize: 23, barHeight: 9)
                        ScoreRow(game: game, theme: theme, numberSize: 72)
                            .padding(.vertical, 24)
                    } else {
                        Spacer(minLength: 24)
                        StatusHeroBadge(game: game, theme: theme)
                    }

                    Spacer(minLength: 24)
                    BrandWatermark(theme: theme, fontSize: 23)
                }
                .padding(.leading, 64)
                .padding(.trailing, 72)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.vertical, 56)

            ScoreCapsule(game: game, theme: theme, fontSize: 44)
                .padding(30)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .frame(width: 1920, height: 1080)
        .background(theme.background)
    }

    @Environment(\.appLanguageCode) private var language
}

// MARK: - 总览图（多选收藏清单）

private struct OverviewCard: View {
    let games: [Game]
    let title: String
    let size: ShareSize
    let theme: ShareTheme
    @Environment(\.appLanguageCode) private var language
    @AppStorage(UserCustomization.avatarFileKey) private var avatarFile = ""

    private var columns: Int { ShareCardLayout.overviewColumns(gameCount: max(games.count, 1), size: size) }
    private var cellSize: CGSize {
        ShareCardLayout.overviewCellWidth(columns: columns, size: size)
    }
    private var headerHeight: CGFloat {
        size == .phone ? ShareCardLayout.headerHeightPhone : ShareCardLayout.headerHeightDesktop
    }
    private var rows: Int { Int(ceil(Double(max(games.count, 1)) / Double(columns))) }

    /// 头部汇总：按要素池顺序渲染（款数/均分默认开；通关总数/收藏价值默认关）。
    private var averageScore: Double? {
        let scores = games.compactMap(\.libraryScore)
        guard !scores.isEmpty else { return nil }
        return ScoreMath.roundScore(scores.reduce(0, +) / Double(scores.count))
    }

    /// 收藏价值段文本（花费/估值，有其一即显示）。
    private var collectionValueText: String? {
        let copies = games.flatMap(\.copies)
        let spent = copies.compactMap { $0.price(for: language) }
        let estimate = copies.compactMap { $0.estValue(for: language) }
        let s = spent.isEmpty ? nil : PriceFormat.string(spent.reduce(0, +), language: language)
        let e = estimate.isEmpty ? nil : PriceFormat.string(estimate.reduce(0, +), language: language)
        switch (s, e) {
        case let (s?, e?): return "\(s) / \(e)"
        case let (s?, nil): return s
        case let (nil, e?): return e
        default: return nil
        }
    }

    private var summaryText: String {
        let totalClears = games.flatMap(\.completions).count
        return ShareOverviewStatsConfig.load().compactMap { item -> String? in
            switch item {
            case .gameCount:
                return L10n.tr("share.count", [games.count], lang: language)
            case .averageScore:
                return averageScore.map { String(format: "%.1f", $0) }
            case .completionCount:
                return totalClears > 0 ? L10n.tr("share.clearTimes", [totalClears], lang: language) : nil
            case .collectionValue:
                return collectionValueText
            }
        }
        .joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: ShareCardLayout.gap) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: ShareCardLayout.gap) {
                        ForEach(0..<columns, id: \.self) { column in
                            let index = row * columns + column
                            if index < games.count {
                                OverviewCell(game: games[index], cellSize: cellSize, size: size, theme: theme)
                            } else {
                                Color.clear.frame(width: cellSize.width, height: cellSize.height)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, ShareCardLayout.gap)
            .padding(.bottom, ShareCardLayout.gap)
        }
        .frame(width: size.pixels.width, height: ShareCardLayout.overviewSize(gameCount: games.count, size: size).height)
        .background(theme.background)
        // 头像放右上角：标题/汇总居中且让位后角落恒空，不会像贴底那样与末行格子内容重叠。
        .overlay(alignment: .topTrailing) {
            if !avatarFile.isEmpty, let avatar = UserCustomization.avatarImage() {
                Image(appImage: avatar)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(theme.separator, lineWidth: 2))
                    .padding(30)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            Text(verbatim: title)
                .font(.system(size: size == .phone ? 62 : 54, weight: .bold))
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(verbatim: summaryText)
                .font(.system(size: size == .phone ? 28 : 25))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(theme.secondary)
        }
        // 左右各让 150：右上角头像的净空区。
        .padding(.horizontal, 150)
        .frame(maxWidth: .infinity)
        .padding(.top, size == .phone ? 64 : 52)
        .padding(.bottom, 36)
        .frame(height: headerHeight, alignment: .top)
    }
}

private struct OverviewCell: View {
    let game: Game
    let cellSize: CGSize
    let size: ShareSize
    let theme: ShareTheme
    @Environment(\.appLanguageCode) private var language

    private var nameSize: CGFloat { size == .phone ? 28 : 24 }
    private var metaSize: CGFloat { size == .phone ? 21 : 18 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let image = game.coverImage {
                    Image(appImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ZStack {
                        Rectangle().fill(theme.surface)
                        Image(systemName: "gamecontroller")
                            .font(.system(size: nameSize * 1.8))
                            .foregroundStyle(theme.secondary)
                    }
                }
            }
            .frame(width: cellSize.width, height: cellSize.width * 3 / 2)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            Text(verbatim: game.displayName(for: language))
                .font(.system(size: nameSize, weight: .semibold))
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 12)

            TileFieldFlow(game: game, theme: theme, fontSize: metaSize)
                .padding(.top, 6)
        }
        .frame(width: cellSize.width, height: cellSize.height, alignment: .top)
    }
}

// MARK: - 分组分享卡（统计叙事：标题 + 引言 + 可配置统计要素 + 平台分布 + 封面格）

private struct GroupShareCard: View {
    let group: GameGroup
    let title: String
    let size: ShareSize
    let theme: ShareTheme
    @Environment(\.appLanguageCode) private var language

    private var isPhone: Bool { size == .phone }

    /// 组内游戏按当前语言显示名排序（与库排序一致）。
    private var games: [Game] {
        group.games.sorted {
            $0.displayName(for: language).localizedCaseInsensitiveCompare($1.displayName(for: language)) == .orderedAscending
        }
    }

    /// 一句话分组评价：去 Markdown 记号取首段，截断约 60 字。
    private var reviewQuote: String? {
        let trimmed = group.review.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let blocks = MarkdownReview.parse(trimmed)
        let plain = blocks.map { block -> String in
            switch block {
            case .heading(_, let text): return text
            case .list(let items): return items.joined(separator: "、")
            case .paragraph(let text): return text
            }
        }
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else { return nil }
        if plain.count <= 60 { return plain }
        return String(plain.prefix(60)) + "……"
    }

    private var averageScore: Double? {
        let scores = games.compactMap(\.libraryScore)
        guard !scores.isEmpty else { return nil }
        return ScoreMath.roundScore(scores.reduce(0, +) / Double(scores.count))
    }

    private var completionCount: Int { games.flatMap(\.completions).count }

    /// 最高分游戏（并列取先）。
    private var topGame: (game: Game, score: Double)? {
        games.compactMap { g in g.libraryScore.map { (g, $0) } }.max { $0.score < $1.score }
    }

    /// 收藏价值（与统计页同口径：组内全部持有档案的价格/估值求和）。
    private var totalSpent: Double? {
        let vals = games.flatMap(\.copies).compactMap { $0.price(for: language) }
        return vals.isEmpty ? nil : vals.reduce(0, +)
    }
    private var totalEstimate: Double? {
        let vals = games.flatMap(\.copies).compactMap { $0.estValue(for: language) }
        return vals.isEmpty ? nil : vals.reduce(0, +)
    }

    /// 平台分布：计数降序、同数量按名升序（稳定，不横跳）。
    private var platformCounts: [(platform: String, count: Int)] {
        var counts: [String: Int] = [:]
        for game in games {
            for platform in game.platformList {
                counts[platform, default: 0] += 1
            }
        }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { (platform: $0.key, count: $0.value) }
    }

    private var maxPlatformCount: Int { platformCounts.map(\.count).max() ?? 1 }

    var body: some View {
        let canvas = ShareCardLayout.groupSize(gameCount: games.count, platformCount: platformCounts.count, size: size)
        return Group {
            if isPhone {
                vertical
            } else {
                horizontal
            }
        }
        .frame(width: canvas.width, height: canvas.height)
        .background(theme.background)
    }

    // MARK: 标题 + 引言（双端共用头部块）

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(verbatim: title)
                .font(.system(size: isPhone ? 78 : 64, weight: .bold))
                .foregroundStyle(theme.text)
                .lineLimit(2)
            if let quote = reviewQuote {
                HStack(alignment: .top, spacing: 16) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(theme.accent)
                        .frame(width: 5)
                    Text(verbatim: quote)
                        .font(.system(size: isPhone ? 30 : 26))
                        .foregroundStyle(theme.secondary)
                        .lineSpacing(5)
                        .lineLimit(3)
                }
                .padding(.trailing, 40)
            }
        }
    }

    // MARK: 统计要素（按用户配置的顺序渲染已启用项）

    @ViewBuilder
    private func statItemView(_ item: GroupStatItem) -> some View {
        switch item {
        case .averageScore:
            ShareStatTile(label: L10n.tr("group.avgScore", lang: language),
                          value: averageScore.map { String(format: "%.1f", $0) } ?? "—",
                          theme: theme, isPhone: isPhone)
        case .gameCount:
            ShareStatTile(label: L10n.tr("group.gameCount", lang: language),
                          value: "\(games.count)", theme: theme, isPhone: isPhone)
        case .completionCount:
            ShareStatTile(label: L10n.tr("group.completionCount", lang: language),
                          value: "\(completionCount)", theme: theme, isPhone: isPhone)
        case .topGame:
            ShareTopGameTile(game: topGame?.game, score: topGame?.score,
                             theme: theme, isPhone: isPhone)
        case .collectionValue:
            ShareCollectionValueTile(spent: PriceFormat.string(totalSpent, language: language),
                                    estimate: PriceFormat.string(totalEstimate, language: language),
                                    theme: theme, isPhone: isPhone)
        }
    }

    private var enabledStats: [GroupStatItem] { ShareGroupStatsConfig.load() }

    /// 数字类要素（小格，网格排布）；特殊要素单独整行。
    private var numericStats: [GroupStatItem] {
        enabledStats.filter { $0 != .topGame && $0 != .collectionValue }
    }
    private var specialStats: [GroupStatItem] {
        enabledStats.filter { $0 == .topGame || $0 == .collectionValue }
    }

    @ViewBuilder
    private var statsSection: some View {
        if !enabledStats.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                LazyVGrid(
                    // 列数跟随数字要素实际个数（数字池上限 3：均分/游戏数/通关数）：
                    // 3 项 3 列单行、2 项 2 列，恒无「N+1 孤行 / 末位空位」。
                    // 固定 2（手机）/4（电脑）会在默认 3 项时出现孤行——§32.4 修复时把 topGame
                    // 误算进数字块（它本就是整行特殊要素），2026-08-24 实测样图纠正。
                    columns: Array(repeating: GridItem(.flexible(), spacing: 20),
                                   count: max(1, min(numericStats.count, isPhone ? 3 : 4))),
                    spacing: 18
                ) {
                    ForEach(numericStats) { item in
                        statItemView(item)
                    }
                }
                ForEach(specialStats) { item in
                    statItemView(item)
                }
            }
        }
    }

    // MARK: 竖版

    private var vertical: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBlock
                .padding(.top, 60)

            // 区块间用弹性间距：内容少时均匀铺满画布（minLength 保底呼吸位），
            // 内容多时收紧到 minLength，不再出现「水印孤悬底部 + 中段死白」。
            Spacer(minLength: 32)

            statsSection

            Spacer(minLength: 36)

            if !platformCounts.isEmpty {
                Text(verbatim: L10n.tr("stats.byPlatform", lang: language))
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(theme.secondary)

                VStack(spacing: 20) {
                    ForEach(platformCounts, id: \.platform) { item in
                        SharePlatformBarRow(platform: item.platform, count: item.count,
                                            maxCount: maxPlatformCount, language: language, theme: theme,
                                            isPhone: true)
                    }
                }
                .padding(.top, 20)

                Spacer(minLength: 40)
            }

            if !games.isEmpty {
                gamesGrid
            }

            Spacer(minLength: 28)
            BrandWatermark(theme: theme, fontSize: 27)
                .padding(.bottom, 52)
        }
        .padding(.horizontal, 72)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var gamesGrid: some View {
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
                                .frame(width: tile, height: tile * 3 / 2 + 40)
                        }
                    }
                }
            }
        }
    }

    // MARK: 桌面版：单列全宽流（与手机版同一结构逻辑，仅尺寸放大——自洽）。
    // ≤4 款：大封面带（左）+ 平台条列（右）并排铺满整行；≥5 款：全宽封面网格 + 全宽平台条。
    // 区块间弹性间距，内容少时均匀铺满画布、不留死白。

    private var horizontal: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBlock
                .padding(.top, 52)

            Spacer(minLength: 20)

            statsSection

            Spacer(minLength: 20)

            if games.count <= 4 {
                featuredBand
            } else {
                desktopGamesGrid
                Spacer(minLength: 20)
                if !platformCounts.isEmpty {
                    platformBarsSection
                }
            }

            Spacer(minLength: 16)
            BrandWatermark(theme: theme, fontSize: 24)
                .padding(.bottom, 48)
        }
        .padding(.horizontal, 64)
    }

    /// ≤4 款的特写封面带：大封面（左，行内均分、单格上限 430）+ 平台条列（右，吸收剩余宽度）。
    private var featuredBand: some View {
        let n = games.count
        let tileWidth = min(430, (1340 - CGFloat(max(n - 1, 0)) * 24) / CGFloat(max(n, 1)))
        return HStack(alignment: .top, spacing: 32) {
            HStack(spacing: 24) {
                ForEach(0..<n, id: \.self) { idx in
                    GroupGameTile(game: games[idx], tileSize: tileWidth, theme: theme, nameSize: 26)
                }
            }
            Spacer(minLength: 0)
            if !platformCounts.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text(verbatim: L10n.tr("stats.byPlatform", lang: language))
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(theme.secondary)
                    ForEach(platformCounts.prefix(4), id: \.platform) { item in
                        SharePlatformBarRow(platform: item.platform, count: item.count,
                                            maxCount: maxPlatformCount, language: language, theme: theme,
                                            isPhone: false)
                    }
                }
                // 吸收封面带剩余宽度（条形拉长、顶对齐封面），不再固定 420——
                // 固定宽会把余量全挤进 Spacer，款少时中部出现大空洞、平台列悬空。
                .frame(minWidth: 300, maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// ≥5 款的全宽封面网格：≤8 款单行排满（列数=款数），更多用 6 列。
    private var desktopGamesGrid: some View {
        let count = games.count
        let cols = count <= 8 ? count : 6
        let tile = (size.pixels.width - 128 - CGFloat(cols - 1) * 24) / CGFloat(cols)
        let rows = Int(ceil(Double(count) / Double(cols)))
        return VStack(spacing: 24) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 24) {
                    ForEach(0..<cols, id: \.self) { col in
                        let index = row * cols + col
                        if index < count {
                            GroupGameTile(game: games[index], tileSize: tile, theme: theme, nameSize: 22)
                        } else {
                            Color.clear.frame(width: tile, height: tile * 3 / 2 + 40)
                        }
                    }
                }
            }
        }
    }

    /// 全宽平台条（≥5 款布局用，最多 6 条）。
    private var platformBarsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: L10n.tr("stats.byPlatform", lang: language))
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(theme.secondary)
            ForEach(platformCounts.prefix(6), id: \.platform) { item in
                SharePlatformBarRow(platform: item.platform, count: item.count,
                                    maxCount: maxPlatformCount, language: language, theme: theme,
                                    isPhone: false)
            }
        }
    }
}

/// 格子字段流式排布（总览格与分组卡格共用）：按字段池顺序两列一行，
/// 数据缺失的字段自动隐藏（不显示占位符）；状态标签仅未通关游戏渲染。
private struct TileFieldFlow: View {
    let game: Game
    let theme: ShareTheme
    var fontSize: CGFloat
    @Environment(\.appLanguageCode) private var language

    private var availableFields: [GameTileField] {
        ShareTileFieldsConfig.load().filter { field in
            switch field {
            case .platform: game.platformList.first != nil
            case .score: game.libraryScore != nil
            case .date: game.latestCompletionDate != nil
            case .releaseYear: game.releaseDate != nil
            case .status: !game.isCompletedOrLongRunning
            }
        }
    }

    var body: some View {
        let fs = availableFields
        VStack(alignment: .leading, spacing: 3) {
            ForEach(stride(from: 0, to: fs.count, by: 2).map { (lo: $0, hi: min($0 + 2, fs.count)) }, id: \.lo) { pair in
                HStack(spacing: 10) {
                    fieldView(fs[pair.lo])
                    if pair.hi - pair.lo > 1 {
                        Spacer(minLength: 10)
                        fieldView(fs[pair.lo + 1])
                    }
                }
                .font(.system(size: fontSize))
                .foregroundStyle(theme.secondary)
            }
        }
    }

    @ViewBuilder
    private func fieldView(_ field: GameTileField) -> some View {
        switch field {
        case .platform:
            if let platform = game.platformList.first {
                Text(verbatim: Presets.display(platform, category: .platform, language: language))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        case .score:
            if let score = game.libraryScore {
                Text(verbatim: String(format: "%.1f", score))
                    .font(.system(size: fontSize + 3, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(theme.accent)
            }
        case .date:
            if let date = game.latestCompletionDate {
                Text(verbatim: ShareFormat.date(date, language: language))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        case .releaseYear:
            if let year = ShareFormat.releaseYear(game.releaseDate) {
                Text(verbatim: year)
                    .monospacedDigit()
            }
        case .status:
            if !game.isCompletedOrLongRunning {
                Text(verbatim: L10n.tr(game.statusValue.labelKey, lang: language))
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(game.statusValue.shareStatusColor)
            }
        }
    }
}

/// 分组分享卡里的单个游戏封面格（封面 + 名称 + 字段流）。
private struct GroupGameTile: View {
    let game: Game
    let tileSize: CGFloat
    let theme: ShareTheme
    var nameSize: CGFloat = 24
    @Environment(\.appLanguageCode) private var language

    var body: some View {
        // 左对齐与总览格（OverviewCell）一致：名称居中、字段流左对齐会互相错位。
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let image = game.coverImage {
                    Image(appImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ZStack {
                        Rectangle().fill(theme.surface)
                        Image(systemName: "gamecontroller")
                            .foregroundStyle(theme.secondary)
                    }
                }
            }
            .frame(width: tileSize, height: tileSize * 3 / 2)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(verbatim: game.displayName(for: language))
                .font(.system(size: nameSize, weight: .medium))
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            TileFieldFlow(game: game, theme: theme, fontSize: max(14, nameSize - 6))
        }
        .frame(width: tileSize)
    }
}

/// 数字类统计小方块。
private struct ShareStatTile: View {
    let label: String
    let value: String
    let theme: ShareTheme
    let isPhone: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: label)
                .font(.system(size: isPhone ? 25 : 21, weight: .medium))
                .foregroundStyle(theme.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(verbatim: value)
                .font(.system(size: isPhone ? 54 : 42, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(isPhone ? 24 : 20)
        .background(RoundedRectangle(cornerRadius: 20).fill(theme.surface))
    }
}

/// 最高分游戏整行块。
private struct ShareTopGameTile: View {
    let game: Game?
    let score: Double?
    let theme: ShareTheme
    let isPhone: Bool
    @Environment(\.appLanguageCode) private var language

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text(verbatim: L10n.tr("share.stat.topGame", lang: language))
                .font(.system(size: isPhone ? 25 : 21, weight: .medium))
                .foregroundStyle(theme.secondary)
            if let game, let score {
                Text(verbatim: game.displayName(for: language))
                    .font(.system(size: isPhone ? 32 : 27, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 16)
                Text(verbatim: String(format: "%.1f", score))
                    .font(.system(size: isPhone ? 40 : 34, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(theme.accent)
            } else {
                Text(verbatim: "—")
                    .font(.system(size: isPhone ? 32 : 27, weight: .semibold))
                    .foregroundStyle(theme.secondary)
                Spacer(minLength: 0)
            }
        }
        .padding(isPhone ? 24 : 20)
        .background(RoundedRectangle(cornerRadius: 20).fill(theme.surface))
    }
}

/// 收藏价值整行块：总花费 · 总估值。
private struct ShareCollectionValueTile: View {
    let spent: String?
    let estimate: String?
    let theme: ShareTheme
    let isPhone: Bool
    @Environment(\.appLanguageCode) private var language

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 36) {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: L10n.tr("copy.overviewSpent", lang: language))
                    .font(.system(size: isPhone ? 25 : 21, weight: .medium))
                    .foregroundStyle(theme.secondary)
                Text(verbatim: spent ?? "—")
                    .font(.system(size: isPhone ? 40 : 33, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(theme.text)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: L10n.tr("copy.overviewEstimate", lang: language))
                    .font(.system(size: isPhone ? 25 : 21, weight: .medium))
                    .foregroundStyle(theme.secondary)
                Text(verbatim: estimate ?? "—")
                    .font(.system(size: isPhone ? 40 : 33, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(theme.accent)
            }
            Spacer(minLength: 0)
        }
        .padding(isPhone ? 24 : 20)
        .background(RoundedRectangle(cornerRadius: 20).fill(theme.surface))
    }
}

/// 分享卡平台条。
private struct SharePlatformBarRow: View {
    let platform: String
    let count: Int
    let maxCount: Int
    let language: String
    let theme: ShareTheme
    let isPhone: Bool

    var body: some View {
        HStack(spacing: 16) {
            Text(verbatim: Presets.display(platform, category: .platform, language: language))
                .font(.system(size: isPhone ? 28 : 24, weight: .medium))
                .foregroundStyle(theme.secondary)
                .frame(width: isPhone ? 220 : 190, alignment: .leading)
                .lineLimit(1)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule()
                        .fill(theme.accent)
                        .frame(width: proxy.size.width * CGFloat(count) / CGFloat(maxCount))
                }
            }
            .frame(height: isPhone ? 14 : 12)
            Text(verbatim: "\(count)")
                .font(.system(size: isPhone ? 28 : 24, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(theme.text)
                .frame(width: 48, alignment: .trailing)
        }
    }
}
