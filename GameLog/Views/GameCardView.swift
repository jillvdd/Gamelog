import SwiftUI
import SwiftData

/// 五类图解码缓存已抽到 Support/ImageDecodeCache.swift（key = persistentModelID+字段，
/// 不再对整段图片 Data 做 O(n) 哈希）。此处保留清空入口供「清除缓存」调用。
extension GameCardView {
    /// 清空封面解码缓存（「清除缓存」功能调用；NSCache 内存态，正常也会自动清理）。
    static func clearCoverCache() {
        ImageDecodeCache.bump()
    }
}

extension Game {
    var coverImage: AppImage? {
        ImageDecodeCache.image(for: self, field: "cover", data: coverData)
    }

    /// 详情页横幅背景图。
    var heroImage: AppImage? {
        ImageDecodeCache.image(for: self, field: "hero", data: heroData)
    }

    /// 游戏 Logo（透明 PNG）。详情页在「背景图 + Logo 同时设置」时替代 2:3 封面。
    var logoImage: AppImage? {
        ImageDecodeCache.image(for: self, field: "logo", data: logoData)
    }

    /// 1:1 方形封面（SteamGridDB 方形 grid）。iOS 单列卡大图主格式。
    var squareImage: AppImage? {
        ImageDecodeCache.image(for: self, field: "square", data: squareData)
    }

    /// 横向封面（SteamGridDB 920×430 横版 grid）。iOS 详情页横幅与库横向卡共用。
    var landscapeImage: AppImage? {
        ImageDecodeCache.image(for: self, field: "landscape", data: landscapeData)
    }
}

/// 游戏名右侧的平台图标：最多显示 maxCount 个，超出显示 +N。
/// 仅作为平台符号提示，下方的平台文字行保持不变。
/// 与名字同行时整体垂直居中对齐（不用 firstTextBaseline——图标放大系数随平台不同，
/// 底对齐会让各图标顶部参差；居中后多出的高度上下均分，观感齐平）。
struct GamePlatformIcons: View {
    let platforms: [String]
    var maxCount: Int = 3
    var iconSize: CGFloat = 12

    var body: some View {
        let shown = platforms.prefix(maxCount)
        HStack(alignment: .center, spacing: 3) {
            ForEach(shown, id: \.self) { p in
                PlatformIcon(platform: p, size: iconSize)
            }
            if platforms.count > maxCount {
                Text(verbatim: "+\(platforms.count - maxCount)")
                    .font(.system(size: iconSize * 0.85))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 网格视图中的游戏卡片：封面 + 库显示分徽章 + 名称 + 平台/日期。
struct GameCardView: View {
    @Environment(\.appLanguageCode) private var language
    let game: Game

    private var cover: some View {
        // 固定 3:4 方格锚点：用 Color.clear 占位确定尺寸，图片 scaledToFill 覆盖裁剪，
        // 避免 Image 自带比例撑高单元格导致与相邻卡片重叠（参见 §4.22 安全图案）。
        Color.clear
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay {
                if let image = game.coverImage {
                    Image(appImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Rectangle()
                            .fill(Color.semantic(.quaternarySystemFill))
                        Image(systemName: "gamecontroller")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var platformText: String {
        let list = game.platformList
        guard !list.isEmpty else { return "" }
        let shown = list.prefix(2).map { Presets.display($0, category: .platform, language: language) }
            .joined(separator: " · ")
        if list.count > 2 {
            return "\(shown) · +\(list.count - 2)"
        }
        return shown
    }

    /// 通关日期行（全部记录中最大的通关日期，与库排序同口径；无日期不显示）。
    private var clearDateText: String? {
        game.latestCompletionDate.map {
            L10n.tr("card.cleared", [Self.cardDate($0, language: language)], lang: language)
        }
    }

    /// 发售日期行（有发售日才显示）。
    private var releaseDateText: String? {
        game.releaseDate.map {
            L10n.tr("card.released", [Self.cardDate($0, language: language)], lang: language)
        }
    }

    /// 跟随界面语言的卡片日期格式。此前 `Date.formatted` 跟随系统 locale，
    /// 中文界面会显示英文日期「2 Aug 2026」。
    static func cardDate(_ date: Date, language: String) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: language)
        if language == "zh-Hans" || language == "ja" {
            fmt.dateFormat = "yyyy年M月d日"
        } else {
            fmt.dateFormat = "MMM d, yyyy"
        }
        return fmt.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                cover
                GameBadge(game: game, style: .glass)
                    .padding(6)
            }
            // 名字 + 平台图标：一行放得下就并排；放不下（多平台/超宽字标）图标换到名字下方一行，名字不被挤压省略。
            // 图标行与名字中轴对齐（各平台放大系数不同，基线/底对齐会顶部参差）。
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 4) {
                    Text(verbatim: game.displayName(for: language))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    GamePlatformIcons(platforms: game.platformList, maxCount: 3, iconSize: 12)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: game.displayName(for: language))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    GamePlatformIcons(platforms: game.platformList, maxCount: 3, iconSize: 12)
                }
            }
            if !platformText.isEmpty {
                Text(verbatim: platformText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            // 发售日期在上(有才显示),通关日期在下——按时间先后自然排列。
            if let releaseDateText {
                Text(verbatim: releaseDateText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let clearDateText {
                Text(verbatim: clearDateText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func formatScore(_ score: Double) -> String {
        String(format: "%.1f", score)
    }
}

/// 列表视图中的游戏行。
struct GameRowView: View {
    @Environment(\.appLanguageCode) private var language
    let game: Game

    private var subtitle: String {
        game.platformList
            .map { Presets.display($0, category: .platform, language: language) }
            .joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let image = game.coverImage {
                    Image(appImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Rectangle().fill(Color.semantic(.quaternarySystemFill))
                        Image(systemName: "gamecontroller").foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(width: 40, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(verbatim: game.displayName(for: language))
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    GamePlatformIcons(platforms: game.platformList, maxCount: 4, iconSize: 13)
                }
                if !subtitle.isEmpty {
                    Text(verbatim: subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            GameBadge(game: game, style: .plain)
        }
        .padding(.vertical, 4)
    }
}

/// iOS 库「单列横向卡」视图（2026-08-28 第五稿）：SwiftUI 卡片形态——玻璃材质圆角卡底
/// （.regularMaterial + 细描边 + 投影，明暗模式自适应）。左列 = **方形封面**满卡高
/// （上下左右全贴边无框，方形空间零裁切；无方图回落竖版封面等高居中透卡底），封面右上角
/// 覆盖液态玻璃评分/状态胶囊（与网格卡同一 glassCapsuleBadge）；右列整块 = 可显示文字区：
/// 标题（词边界断行，同详情页 lineBreakAwareTitle 口径）+ 平台图标行在顶端，元数据面板
/// （发售日期 / 厂商·发行商 / 游戏类型 / 通关日期，裸值带小标题，缺项跳过）贴底。
struct GameWideCardView: View {
    @Environment(\.appLanguageCode) private var language
    let game: Game

    private var clearDateValue: String? {
        game.latestCompletionDate.map { GameCardView.cardDate($0, language: language) }
    }

    private var releaseDateText: String? {
        game.releaseDate.map { GameCardView.cardDate($0, language: language) }
    }

    private var genreText: String? {
        let genre = game.genre?.trimmingCharacters(in: .whitespaces) ?? ""
        return genre.isEmpty ? nil : genre
    }

    /// 卡内标题：套详情页同款词边界断行（U+2060 禁词内断行；iOS 专属函数，macOS 原样）。
    private var titleText: String {
        #if os(iOS)
        lineBreakAwareTitle(game.displayName(for: language), language: language)
        #else
        game.displayName(for: language)
        #endif
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // 左列：方形封面满卡高（宽 = 卡高），上下左右全贴边，左缘圆角由整卡 clipShape 裁出；
            // 右上角评分/状态胶囊（覆盖在图上，网格卡同款 padding 6）。
            imageArea
                .frame(width: cardHeight, height: cardHeight)
                .overlay(alignment: .topTrailing) {
                    trailingBadge.padding(6)
                }

            // 右列：整块可显示文字区——标题+平台在顶端，元数据面板贴底（中段弹性空隙）。
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: titleText)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    GamePlatformIcons(platforms: game.platformList, maxCount: 5, iconSize: 12)
                }
                Spacer(minLength: 4)
                metaBlock
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.semantic(.quaternarySystemFill).opacity(0.45))
        }
        .frame(height: cardHeight)
        .background(.regularMaterial, in: Self.cardShape)
        .overlay(Self.cardShape.strokeBorder(.quaternary, lineWidth: 0.5))
        .clipShape(Self.cardShape)
        .shadow(color: .black.opacity(0.14), radius: 6, x: 0, y: 2)
    }

    private static let cardShape = RoundedRectangle(cornerRadius: 14, style: .continuous)
    /// 卡高 = 左列方形封面边长。标题块（两行 ~52）进右列后，为保元数据五项完整显示，
    /// 从 170 加到 215（两行长名 + 五项面板 + 内距的临界预算）。
    private let cardHeight: CGFloat = 215

    /// 右列元数据块（2026-08-27 用户追加定稿）：每项 = 小标题（game.releaseDate/developer/
    /// publisher/genre/card.clearedDate，三语现成 key）+ 值；厂商与发行商**分两行**。各缺项整组跳过。
    @ViewBuilder
    private var metaBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let releaseDateText {
                metaItem(titleKey: "game.releaseDate", value: releaseDateText, valueLimit: 1)
            }
            if let clearDateValue {
                metaItem(titleKey: "card.clearedDate", value: clearDateValue, valueLimit: 1)
            }
            if let developerText {
                metaItem(titleKey: "game.developer", value: developerText, valueLimit: 2)
            }
            if let publisherText {
                metaItem(titleKey: "game.publisher", value: publisherText, valueLimit: 2)
            }
            if let genreText {
                metaItem(titleKey: "game.genre", value: genreText, valueLimit: 1)
            }
        }
    }

    private var developerText: String? {
        let s = game.developer?.trimmingCharacters(in: .whitespaces) ?? ""
        return s.isEmpty ? nil : s
    }

    private var publisherText: String? {
        let s = game.publisher?.trimmingCharacters(in: .whitespaces) ?? ""
        return s.isEmpty ? nil : s
    }

    /// 一条元数据：8pt 次要色标题 + 12pt 紧凑值（长值在词边界处截断省略）。
    @ViewBuilder
    private func metaItem(titleKey: String, value: String, valueLimit: Int) -> some View {
        #if os(iOS)
        let valueText = lineBreakAwareTitle(value, language: language)
        #else
        let valueText = value
        #endif
        return VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: L10n.tr(titleKey, lang: language))
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Text(verbatim: valueText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(valueLimit)
                .multilineTextAlignment(.leading)
        }
    }

    /// 封面区（方形满卡高、上下左右全贴边）：1:1 图 scaledToFill 零裁切正好填满；
    /// 无 1:1 图用竖版封面 scaledToFit 等高完整展示（左右透卡底材质，不垫灰底）；
    /// 全无图手柄占位。frame 定尺寸在前、clipped 在后，防图铺出图区（§40.1 教训）。
    @ViewBuilder
    private var imageArea: some View {
        Group {
            if let image = game.squareImage {
                Image(appImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: cardHeight, height: cardHeight)
                    .clipped()
            } else if let image = game.coverImage {
                Image(appImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: cardHeight, height: cardHeight)
                    .clipped()
            } else {
                ZStack {
                    Rectangle().fill(Color.semantic(.quaternarySystemFill))
                    Image(systemName: "gamecontroller")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                }
                .frame(width: cardHeight, height: cardHeight)
            }
        }
    }

    /// 右上角徽章：GameBadge(.glass) 统一入口（规则与样式单一归属 Support/StatusStyle.swift）。
    private var trailingBadge: some View {
        GameBadge(game: game, style: .glass)
    }
}

/// 新建分组的弹窗。空名或重名不允许保存。
struct NewGroupSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \GameGroup.name) private var groups: [GameGroup]
    @State private var name = ""

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }
    private var isDuplicate: Bool {
        !trimmed.isEmpty && groups.contains { $0.name == trimmed }
    }

    var body: some View {
        VStack(spacing: 16) {
            LText("group.newGroup")
                .font(.headline)
            BorderedTextField(text: $name, placeholder: L10n.tr("group.name", lang: language))
                #if os(macOS)
                .frame(width: 280)
                #else
                .frame(maxWidth: .infinity)
                #endif
            // 固定高度占位，避免错误出现时窗口跳动
            Text(verbatim: isDuplicate ? L10n.tr("group.nameExists", lang: language) : " ")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(1)
            HStack {
                Button(L10n.tr("common.cancel", lang: language)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.tr("common.save", lang: language)) {
                    context.insert(GameGroup(name: trimmed))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmed.isEmpty || isDuplicate)
            }
        }
        .padding(24)
        #if os(macOS)
        .frame(width: 360)
        #else
        .frame(maxWidth: .infinity)
        #endif
    }
}
