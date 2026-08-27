import SwiftUI
import SwiftData

/// 封面解码缓存：按 coverData 哈希缓存 AppImage，避免每次视图 body 重算时重新解码
/// （状态切换、滚动、网格重排时卡顿的根因）。NSCache 自动清理内存。
private let coverImageCache = NSCache<NSNumber, AppImage>()

extension GameCardView {
    /// 清空封面解码缓存（「清除缓存」功能调用；NSCache 内存态，正常也会自动清理）。
    static func clearCoverCache() {
        coverImageCache.removeAllObjects()
    }
}

extension Game {
    var coverImage: AppImage? {
        guard let data = coverData else { return nil }
        return Self.cachedImage(forKey: data.hashValue, decode: { AppImage(data: $0) }, data: data)
    }

    /// 详情页横幅背景图（与封面共用同一解码缓存，key 用各自 data 哈希不会冲突）。
    var heroImage: AppImage? {
        guard let data = heroData else { return nil }
        return Self.cachedImage(forKey: data.hashValue, decode: { AppImage(data: $0) }, data: data)
    }

    /// 游戏 Logo（透明 PNG）。详情页在「背景图 + Logo 同时设置」时替代 2:3 封面。
    var logoImage: AppImage? {
        guard let data = logoData else { return nil }
        return Self.cachedImage(forKey: data.hashValue, decode: { AppImage(data: $0) }, data: data)
    }

    /// 共用解码路径：查缓存 → 未命中解码 → 回填。文件级私有缓存由「清除缓存」统一清空。
    private static func cachedImage(forKey key: Int, decode: (Data) -> AppImage?, data: Data) -> AppImage? {
        if let cached = coverImageCache.object(forKey: NSNumber(value: key)) {
            return cached
        }
        guard let image = decode(data) else { return nil }
        coverImageCache.setObject(image, forKey: NSNumber(value: key))
        return image
    }
}

/// 状态角标的主题色（仅网格卡片封面用；状态本体定义在 GameStatus）。
private extension GameStatus {
    var statusColor: Color {
        switch self {
        case .backlog: .blue
        case .playing: .green
        case .paused: .orange
        case .dropped: .gray
        case .longRunning: .purple
        case .completed: .primary
        }
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
                if game.isCompletedOrLongRunning {
                    // 已通关/长线游玩：右上角评分徽章（无评分不显示）。
                    if let score = game.libraryScore {
                        Text(verbatim: Self.formatScore(score))
                            .font(.system(size: 12, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .glassCapsuleBadge(tint: Color.black.opacity(0.30),
                                               fallback: Color.black.opacity(0.72))
                            .padding(6)
                    }
                } else {
                    // 想玩/在玩/搁置/弃坑：右上角状态标签。
                    // 两种徽章统一尺寸（高 22、字号 12、水平内边距 8）+ 液态玻璃（状态用品牌色染色玻璃）。
                    Text(verbatim: L10n.tr(game.statusValue.labelKey, lang: language))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .glassCapsuleBadge(tint: game.statusValue.statusColor.opacity(0.55),
                                           fallback: game.statusValue.statusColor.opacity(0.88))
                        .padding(6)
                }
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

            if game.isCompletedOrLongRunning {
                if let score = game.libraryScore {
                    Text(verbatim: GameCardView.formatScore(score))
                        .font(.system(size: 15, weight: .bold))
                        .monospacedDigit()
                } else {
                    LText("score.unrated")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            } else {
                // 想玩/在玩/搁置/弃坑：右侧显示状态标签。
                Text(verbatim: L10n.tr(game.statusValue.labelKey, lang: language))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(game.statusValue.statusColor.opacity(0.88), in: Capsule())
            }
        }
        .padding(.vertical, 4)
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
