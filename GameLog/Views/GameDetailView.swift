import SwiftUI
import SwiftData

#if os(macOS)
import AppKit
#endif

#if os(iOS)
import NaturalLanguage
#endif

/// iOS 详情页大标题的词边界断行排版：NLTokenizer 按当前语言分词，词内字符间插入
/// U+2060（WORD JOINER，Unicode 断行算法的禁断点）——换行只允许落在词边界，
/// 修掉「死神的遺|言」「戰役|進化」这类 CJK 大标题无视词语的硬折行（用户定稿 2026-08-27）。
/// 实现注记：NLTokenizer 的 token 是 Range<String.Index>，拼串时用 range 映射保词序与空白原样。
#if os(iOS)
func lineBreakAwareTitle(_ raw: String, language: String) -> String {
    guard !raw.isEmpty else { return raw }
    let tokenizer = NLTokenizer(unit: .word)
    tokenizer.setLanguage(NLLanguage(language))
    tokenizer.string = raw
    var out = ""
    var cursor = raw.startIndex
    tokenizer.enumerateTokens(in: raw.startIndex..<raw.endIndex) { range, _ in
        out += raw[cursor..<range.lowerBound]
        let word = String(raw[range])
        out += word.map { String($0) }.joined(separator: "\u{2060}")
        cursor = range.upperBound
        return true
    }
    out += raw[cursor...]
    return out
}
#endif

/// 一条通关记录的卡片（详情页内）。
struct CompletionCardView: View {
    @Environment(\.appLanguageCode) private var language
    let completion: Completion
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                #if os(macOS)
                // 头部自适应：整行放得下就单行（原样式）；放不下（窄列如宽窗评价右栏）
                // 信息项走流式换行、分数与按钮独立成行靠右——避免无谓溢出把卡片内容挤出右边。
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        headerInfoItems
                        Spacer()
                        scoreView
                        editButton
                        deleteButton
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        WrappingLayout(spacing: 6, lineSpacing: 6) {
                            headerInfoItems
                        }
                        HStack {
                            Spacer()
                            scoreView
                            editButton
                            deleteButton
                        }
                    }
                }
                #else
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        if let date = completion.date {
                            Text(verbatim: date.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 12, weight: .semibold))
                        }
                        if let playtime = completion.playtime {
                            Text(verbatim: L10n.tr("completion.playtimeFormat", [playtime], lang: language))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        scoreView
                        editButton
                        deleteButton
                    }
                    if !completion.platform.isEmpty || !completion.degree.isEmpty {
                        HStack(spacing: 8) {
                            if !completion.platform.isEmpty {
                                chip(Presets.display(completion.platform, category: .platform, language: language))
                            }
                            if !completion.degree.isEmpty {
                                chip(Presets.display(completion.degree, category: .degree, language: language))
                            }
                        }
                    }
                }
                #endif
            }

            if completion.hasScores {
                // 只显示该记录评了的维度（未评维度不占位）。
                HStack(spacing: 16) {
                    ForEach(Dimension.allCases.filter { completion.score(for: $0) != nil }) { dimension in
                        VStack(spacing: 2) {
                            LText(dimension.labelKey)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(verbatim: completion.score(for: dimension).map { String(format: "%.1f", $0) } ?? "—")
                                .font(.system(.body, design: .monospaced))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }

            if !completion.notes.isEmpty {
                Text(verbatim: completion.notes)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.semantic(.controlBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.semantic(.separator))
        )
    }

    /// 头部信息项：通关日期 / 平台胶囊 / 通关程度胶囊 / 时长（各缺项跳过）。
    /// macOS 头部单行与流式换行两个分支共用，iOS 分支也用它保持同一样式源。
    @ViewBuilder
    private var headerInfoItems: some View {
        if let date = completion.date {
            Text(verbatim: date.formatted(date: .abbreviated, time: .omitted))
                .font(.system(size: 12, weight: .semibold))
        }
        if !completion.platform.isEmpty {
            chip(Presets.display(completion.platform, category: .platform, language: language))
        }
        if !completion.degree.isEmpty {
            chip(Presets.display(completion.degree, category: .degree, language: language))
        }
        if let playtime = completion.playtime {
            Text(verbatim: L10n.tr("completion.playtimeFormat", [playtime], lang: language))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// 平均分显示（已评分显示数字，未评分显示「未评分」）。
    @ViewBuilder
    private var scoreView: some View {
        if let avg = completion.displayAverage {
            Text(verbatim: String(format: "%.1f", avg))
                .font(.system(size: 18, weight: .bold))
                .monospacedDigit()
        } else {
            LText("score.unrated")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var editButton: some View {
        Button(action: onEdit) {
            Image(systemName: "pencil")
                // iOS 触控目标补足 44×44（HIG）；macOS 保持紧凑。
                #if os(iOS)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                #endif
        }
        .buttonStyle(.borderless)
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "trash")
                #if os(iOS)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                #endif
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.red)
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
    }
}

/// 详情页头部的六维评分条形图：每维度一条，颜色区分，长度按 10 分制比例。
private struct DimensionScoreBars: View {
    let game: Game
    /// 维度标签列宽：默认 96（旧单列布局），评分卡内用 64 紧凑变体。
    var labelWidth: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 只显示有评分的维度（每维可选评/不评，未评维度均值 nil）。
            ForEach(Dimension.allCases.filter { game.dimensionAverage(for: $0) != nil }) { dimension in
                let value = game.dimensionAverage(for: dimension)
                HStack(spacing: 8) {
                    LText(dimension.labelKey)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: labelWidth, alignment: .leading)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.semantic(.quaternarySystemFill))
                        if let value {
                            Capsule()
                                .fill(dimension.barColor)
                                .frame(width: 150 * (value / 10))
                        }
                    }
                    .frame(width: 150, height: 6)
                    Text(verbatim: value.map { String(format: "%.1f", $0) } ?? "—")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 26, alignment: .trailing)
                }
            }
        }
    }
}

private extension Dimension {
    /// 六维条形图的颜色（详情页用）。
    var barColor: Color {
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

/// 详情页名字下方的其他语言名小字：不带语言标记、上下并排，只显示设置了的，且去掉与主名重复的。
private struct LocalizedNamesSubtitle: View {
    let game: Game
    let currentLanguage: String
    /// 字体：默认 callout（旧单列布局）；宽窗头部传 body 与评分卡平衡。
    var font: Font = .callout

    private var names: [String] {
        let others: [String]
        switch currentLanguage {
        case "zh-Hans": others = [game.name, game.nameJa].compactMap { $0 }
        case "ja": others = [game.nameZh, game.name].compactMap { $0 }
        default: others = [game.nameZh, game.nameJa].compactMap { $0 }
        }
        let display = game.displayName(for: currentLanguage)
        return others.filter { $0 != display }
    }

    var body: some View {
        if !names.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                    Text(verbatim: name)
                        .font(font)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// 详情页状态选择器：自定义滑动条（图标 + 文字），选中滑块用 offset 定位滑动。
/// 滑块位置由内部独立 @State 驱动——点击立即在本视图内动画，不依赖父视图重算（保证流畅）。
private struct DetailStatusPicker: View {
    @Environment(\.appLanguageCode) private var language
    @Binding var status: GameStatus
    /// 紧凑模式（只图标，窄屏如 iPhone 用）；macOS 显示图标 + 小字。
    var compact: Bool = false

    /// 滑块当前列：由 `status` 派生（点击与 onAppear 同步都经 status 驱动），
    /// 不另存独立状态，避免初始化时因默认值错位而卡在「已通关」。
    private var sliderIndex: Int {
        GameStatus.allCases.firstIndex(of: status) ?? 0
    }

    /// 单个状态格（图标 + 非紧凑时的文字标签）。抽出为方法降低 body 表达式复杂度。
    private func statusCell(_ s: GameStatus, cellWidth: CGFloat, height: CGFloat, compact: Bool) -> some View {
        VStack(spacing: 3) {
            let iconFont = Font.system(size: compact ? 13 : 14, weight: .semibold)
            Image(systemName: s.statusIcon)
                .font(iconFont)
            if !compact {
                Text(verbatim: L10n.tr(s.labelKey, lang: language))
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .foregroundStyle(status == s ? Color.accentColor : Color.secondary)
        .frame(width: cellWidth, height: height)
        .contentShape(Rectangle())
    }

    var body: some View {
        GeometryReader { geo in
            let all = GameStatus.allCases
            let cellWidth = geo.size.width / CGFloat(all.count)
            ZStack(alignment: .topLeading) {
                // 选中滑块：内部 sliderIndex 驱动，offset + spring 动画，独立于父视图重算。
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.accentColor.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1)
                    )
                    .frame(width: cellWidth, height: geo.size.height)
                    .offset(x: CGFloat(sliderIndex) * cellWidth)
                    .animation(.spring(response: 0.3, dampingFraction: 0.78), value: status)
                // 按钮层：每个状态一列，整格可点；分段本体带按压形变（选中滑块另有 spring 动画）。
                HStack(spacing: 0) {
                    ForEach(all) { s in
                        Button {
                            guard status != s else { return }
                            status = s
                        } label: {
                            statusCell(s, cellWidth: cellWidth, height: geo.size.height, compact: compact)
                        }
                        .buttonStyle(PressFeedbackButtonStyle(pressedScale: 0.94, pressedOpacity: 0.55))
                        .help(L10n.tr(s.labelKey, lang: language))
                    }
                }
            }
        }
        .frame(height: compact ? 42 : 56)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.thinMaterial)
        }
    }
}

/// 详情页内部页签（收藏家模式开启时显示分段切换）：详情 = 现有内容，持有 = 收藏记录。
private enum DetailTab: Hashable {
    case details
    case holdings
}

/// 游戏详情页：信息 + 评价 + 通关记录列表（收藏家模式开启时多一个「持有」页签）。
struct GameDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UserCustomization.collectorModeKey) private var collectorMode = false
    /// 隐藏上方毛玻璃（全局开关）：开启 = 无标题 + 无毛玻璃，与 Library / 统计一致。
    @AppStorage(UserCustomization.hideToolbarGlassKey) private var hideToolbarGlass = false
    let game: Game

    @State private var detailTab: DetailTab = .details
    /// 详情/持有滑块当前列（内部状态驱动，点击即时动画，不依赖父视图重算）。
    @State private var tabSliderIndex: Int = 0
    @State private var showingEditGame = false
    @State private var showingAddCompletion = false
    @State private var editingCompletion: Completion?
    @State private var pendingDeleteCompletion: Completion?
    @State private var showingDeleteGame = false
    @State private var showingShare = false
    /// 状态机选中值：绑定局部 @State 隔离，避免每次点击时因 game 模型变化导致 Picker 重绘重载。
    /// 初始值在 init 中取自 game.statusValue，确保首帧即正确（不闪一下「已通关」再滑过去）。
    @State private var detailStatus: GameStatus
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #else
    /// iOS 评价编辑 sheet 开关。
    @State private var showingReviewEditor = false
    #endif

    private var platforms: [String] {
        game.platformList
    }

    /// 是否有评价内容（标题或正文）。
    private var hasReview: Bool {
        !game.reviewTitle.isEmpty || !game.reviewBody.isEmpty
    }

    /// 仅在离开详情页时把本地选中的状态写回模型；未变更则跳过（避免无谓的 SwiftData 写入）。
    /// 游戏被删除（删除确认 → dismiss → onDisappear）时模型已删，写回会访问失效对象。
    private func persistStatusIfChanged() {
        guard !game.isDeleted else { return }
        guard detailStatus != game.statusValue else { return }
        game.statusValue = detailStatus
        try? context.save()
    }

    /// 构造时即把状态滑块初始值设为游戏当前状态，避免首帧先用默认值画「已通关」再弹簧滑过去。
    init(game: Game) {
        self.game = game
        _detailStatus = State(initialValue: game.statusValue)
    }

    var body: some View {
        // 纵深守卫：整库替换后若此页仍被渲染（如通知时序缝隙），game 已 detached，
        // 直接访问属性即 SwiftData fatal——画空视图等导航重置把它弹走（2026-09-08）。
        if game.isDeleted {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
        // 单 ScrollView 内联铺开：游戏信息 → (详情|持有) 滑块 → 详情内容 / 持有档案内联在信息下方。
        // 不再整页替换（§29.9：HoldingsView 已去掉自带 ScrollView，作为内联子视图承载于本 ScrollView）。
        // macOS 已设背景图时走独立分支：heroBanner 提出内边距层外——左右满幅、顶边零间隙贴住
        // 详情页顶端，下方内容保持原 28 边距与原行距；无背景图分支与历史版本逐像素一致。
        GeometryReader { geo in
            ScrollView {
                #if os(macOS)
                if game.heroImage != nil {
                    VStack(alignment: .leading, spacing: 0) {
                        heroBanner(width: geo.size.width)
                            // 横幅与下方内容的距离（2026-08-27 用户反馈逐步收紧：24 → 12 → 6，
                            // 内容区顶部 padding 也从 28 减到 10，合计约 16pt）。
                            .padding(.bottom, 6)
                        VStack(alignment: .leading, spacing: 28) {
                            header(width: geo.size.width - 56, hideCoverBand: true)
                            if collectorMode {
                                detailTabPicker
                            }
                            if !collectorMode || detailTab == .details {
                                detailsContent(width: geo.size.width - 56)
                            }
                            if collectorMode && detailTab == .holdings {
                                HoldingsView(game: game)
                            }
                        }
                        .padding(.top, 10)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 28)
                    }
                    .frame(maxWidth: 1500)
                    .frame(maxWidth: .infinity, alignment: .top)
                } else {
                    VStack(alignment: .leading, spacing: 28) {
                        header(width: geo.size.width)
                        if collectorMode {
                            detailTabPicker
                        }
                        if !collectorMode || detailTab == .details {
                            detailsContent(width: geo.size.width)
                        }
                        if collectorMode && detailTab == .holdings {
                            HoldingsView(game: game)
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: 1500)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                #else
                // iPad 三分支（2026-09-05 五项适配，需求③横屏 + 需求②竖屏）：
                // ① 横屏（宽 ≥ 阈值）+ 已设背景图 → **macOS 同款 hero 版式**（heroBanner
                //    铺满 + Logo/封面前景 + 描边圆角，内容 28 边距同 mac）。
                // ② 其余情况走 iPhone 版式，但 iPad 把横幅 260pt 上限放宽到 560——
                //    竖屏 744pt 宽 920×430 横图满宽显示高 ~347pt（需求②：占满屏宽
                //    不留白边），此前被压到 260 缩小居中左右透白边。
                // iPhone 分支原样保留（isPad=false 时与旧版逐像素一致）。
                if iPadLayout.isPad,
                   game.heroImage != nil,
                   geo.size.width >= iPadLayout.wideThreshold {
                    VStack(alignment: .leading, spacing: 0) {
                        heroBanner(width: geo.size.width)
                            .padding(.bottom, 6)
                        VStack(alignment: .leading, spacing: 28) {
                            header(width: geo.size.width - 56, hideCoverBand: true)
                            if collectorMode {
                                detailTabPicker
                            }
                            if !collectorMode || detailTab == .details {
                                detailsContent(width: geo.size.width - 56)
                            }
                            if collectorMode && detailTab == .holdings {
                                HoldingsView(game: game)
                            }
                        }
                        .padding(.top, 10)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 28)
                    }
                    .frame(maxWidth: 1500)
                    .frame(maxWidth: .infinity, alignment: .top)
                } else if game.landscapeImage != nil {
                    VStack(alignment: .leading, spacing: 0) {
                        if iPadLayout.isPad {
                            iPadLandscapeBanner(width: geo.size.width)
                        } else {
                            landscapeBanner(width: geo.size.width)
                        }
                        VStack(alignment: .leading, spacing: 28) {
                            header(width: geo.size.width, hideCover: true)
                            if collectorMode {
                                detailTabPicker
                            }
                            if !collectorMode || detailTab == .details {
                                detailsContent(width: geo.size.width)
                            }
                            if collectorMode && detailTab == .holdings {
                                HoldingsView(game: game)
                            }
                        }
                        .padding(.top, 12)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 28) {
                        header(width: geo.size.width)
                        if collectorMode {
                            detailTabPicker
                        }
                        if !collectorMode || detailTab == .details {
                            detailsContent(width: geo.size.width)
                        }
                        if collectorMode && detailTab == .holdings {
                            HoldingsView(game: game)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 1500)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                #endif
            }
        }
        #if os(macOS)
        .navigationTitle(hideToolbarGlass ? "" : game.displayName(for: language))
        #else
        // iOS：内容头部已有带平台图标的大名字，导航大标题置空并切 inline，
        // 免得同一名字顶部出现两次（2026-08-27 用户反馈）；顶栏只留返回键与操作钮。
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { detailStatus = game.statusValue }
        // 模型状态变化（编辑 sheet 保存、右键菜单改状态等）回同步局部 @State——sheet 收起
        // 不触发本视图 onDisappear，若不回同步，离开详情页时 persistStatusIfChanged 会把
        // 旧状态写回模型，静默回滚用户的编辑（2026-09-05 审计实锤）。滑块拖动只改 detailStatus
        // 不写模型，不会触发本回调，延迟写入设计（§29.14）不受影响。
        .onChange(of: game.statusValue) { _, newValue in
            if detailStatus != newValue { detailStatus = newValue }
        }
        // 离开详情页时才把状态变更持久化到模型（§29.14 差异 A：避免点击即时写 SwiftData 触发整页重算卡顿）。
        .onDisappear { persistStatusIfChanged() }
        // 全屏毛玻璃下推 + 「隐藏上方毛玻璃」开关由全局 appToolbar() 统一处理。
        .appToolbar()
        .toolbar {
            #if os(macOS)
            ToolbarItem {
                // .help tooltip 是 §34.5 补的 macOS 悬停提示，iOS 无此诉求。
                HStack(spacing: 0) {
                    toolFavoriteButton
                        .toolbarSegmentStyle()
                        .help(L10n.tr("game.favorites", lang: language))
                    toolShareButton
                        .toolbarSegmentStyle()
                        .help(L10n.tr("library.share", lang: language))
                    if detailStatus.isCompletedOrLongRunning {
                        toolAddCompletionButton
                            .toolbarSegmentStyle()
                            .help(L10n.tr("completion.add", lang: language))
                    }
                    toolEditButton
                        .toolbarSegmentStyle()
                        .help(L10n.tr("common.edit", lang: language))
                    toolDeleteButton
                        .toolbarSegmentStyle()
                        .help(L10n.tr("common.delete", lang: language))
                }
            }
            #else
            // iOS：四钮用相邻的独立 ToolbarItem——系统会把相邻条目融进同一条玻璃胶囊，
            // 每钮保留自己的圆形分区与内部间距（与库主页右上角新建/更多两钮同款形态，
            // 2026-08-27 用户指定）。之前单 ToolbarItem 塞一个 HStack 才会挤成无分区的长条。
            // 旧系统（<26）无液态玻璃合并行为，回退单条分组 + 手动间距。
            if #available(iOS 26.0, *) {
                ToolbarItem { toolFavoriteButton }
                ToolbarItem { toolShareButton }
                if detailStatus.isCompletedOrLongRunning {
                    ToolbarItem { toolAddCompletionButton }
                }
                ToolbarItem { toolEditButton }
                ToolbarItem { toolDeleteButton }
            } else {
                ToolbarItem {
                    HStack(spacing: 12) {
                        toolFavoriteButton
                        toolShareButton
                        if detailStatus.isCompletedOrLongRunning {
                            toolAddCompletionButton
                        }
                        toolEditButton
                        toolDeleteButton
                    }
                }
            }
            #endif
        }
        .sheet(isPresented: $showingEditGame) {
            #if os(macOS)
            GameEditView(game: game)
            #else
            NavigationStack { GameEditView(game: game) }
            #endif
        }
        .sheet(isPresented: $showingAddCompletion) {
            #if os(macOS)
            CompletionEditView(game: game, completion: nil)
            #else
            NavigationStack { CompletionEditView(game: game, completion: nil) }
            #endif
        }
        .sheet(item: $editingCompletion) { completion in
            #if os(macOS)
            CompletionEditView(game: game, completion: completion)
            #else
            NavigationStack { CompletionEditView(game: game, completion: completion) }
            #endif
        }
        .sheet(isPresented: $showingShare) { SharePanelView(preselected: [game]) }
        #if os(iOS)
        .sheet(isPresented: $showingReviewEditor) {
            ReviewEditSheet(game: game)
        }
        #endif
        .platformConfirmDialog(
            L10n.tr("common.confirmDelete", lang: language),
            isPresented: Binding(
                get: { pendingDeleteCompletion != nil },
                set: { if !$0 { pendingDeleteCompletion = nil } }
            ),
            message: L10n.tr("completion.deleteConfirm", lang: language),
            cancelTitle: L10n.tr("common.cancel", lang: language),
            actions: [
                ConfirmAction(
                    title: L10n.tr("common.delete", lang: language),
                    isDestructive: true
                ) {
                    if let completion = pendingDeleteCompletion {
                        context.delete(completion)
                    }
                }
            ]
        )
        .platformConfirmDialog(
            L10n.tr("common.confirmDelete", lang: language),
            isPresented: $showingDeleteGame,
            message: L10n.tr("delete.confirmGame", [game.displayName(for: language)], lang: language),
            cancelTitle: L10n.tr("common.cancel", lang: language),
            actions: [
                ConfirmAction(
                    title: L10n.tr("common.delete", lang: language),
                    isDestructive: true
                ) {
                    context.delete(game)
                    // 缓存 key = persistentModelID+字段，pk 删除后可能被新插入行重用——
                    // 不清缓存旧图会贴到新游戏上（2026-09-05 审计）。
                    ImageDecodeCache.bump()
                    dismiss()
                }
            ]
        )
        } // else（isDeleted 纵深守卫）：替换后残留渲染走空分支
    }

    // MARK: - 工具栏按钮

    /// 顶部四钮（分享/加通关/编辑/删除）的 label 定义，macOS 分段长条与 iOS 独立圆钮共用。
    /// 按钮本体不挂 .help——那是 macOS 专属修饰符，iOS 无需。
    private var toolShareButton: some View {
        Button {
            showingShare = true
        } label: {
            Label(L10n.tr("library.share", lang: language), systemImage: "square.and.arrow.up")
                .labelStyle(.iconOnly)
                .font(.system(size: 15))
        }
    }

    private var toolAddCompletionButton: some View {
        Button {
            showingAddCompletion = true
        } label: {
            Label(L10n.tr("completion.add", lang: language), systemImage: "plus")
                .labelStyle(.iconOnly)
            .font(.system(size: 15))
        }
    }

    private var toolEditButton: some View {
        Button {
            showingEditGame = true
        } label: {
            Label(L10n.tr("common.edit", lang: language), systemImage: "pencil")
                .labelStyle(.iconOnly)
                .font(.system(size: 15))
        }
    }

    private var toolDeleteButton: some View {
        Button(role: .destructive) {
            showingDeleteGame = true
        } label: {
            Label(L10n.tr("common.delete", lang: language), systemImage: "trash")
                .labelStyle(.iconOnly)
                .font(.system(size: 15))
                .foregroundStyle(.red)
        }
    }

    /// 「我的最爱」爱心开关：标记/取消收藏（库卡片角标、轮播第 2 页、虚拟分组同步）。
    private var toolFavoriteButton: some View {
        Button {
            game.isFavorite.toggle()
            try? context.save()
        } label: {
            Label(L10n.tr("game.favorites", lang: language),
                  systemImage: game.isFavorite ? "heart.fill" : "heart")
                .labelStyle(.iconOnly)
                .font(.system(size: 15))
                .foregroundStyle(game.isFavorite ? Color.pink : Color.primary)
        }
    }

    // MARK: - 头部

    /// macOS 头部布局阈值：内容宽 ≥ 此值走「封面顶带 + 信息行 + 评分卡」新布局，低于回落单列。
    /// 窗口 minWidth 980 − 侧边栏最宽 320 − 页面 padding 56 ≈ 604，取 640 留余量。
    private static let wideHeaderThreshold: CGFloat = 640

    private func header(width: CGFloat, hideCoverBand: Bool = false, hideCover: Bool = false) -> some View {
        Group {
            #if os(macOS)
            if width >= Self.wideHeaderThreshold {
                wideHeader(width: width, hideCoverBand: hideCoverBand)
            } else if hideCoverBand {
                // 有背景图：横幅已在 body 层铺满视口，窄布局这里只出信息列。
                infoBlock
                Spacer(minLength: 0)
            } else {
                HStack(alignment: .top, spacing: 24) {
                    coverBlock
                    infoBlock
                    Spacer()
                }
            }
            #else
            // iPad 宽版式（需求④→用户追加竖屏同款，2026-09-05）：只要 iPad 且已评分，
            // 横竖屏都把评分卡放信息右侧（macOS wideHeader 同款双栏）。竖屏有横幅时
            // 信息列 ~378pt 容纳名字/元数据/状态滑块；未评分回落旧分支。iPhone 不变。
            if iPadLayout.isPad, game.libraryScore != nil, !hideCover {
                // 无横幅版式（无横向封面/无背景图）：封面 + 信息 + 评分卡三栏。
                HStack(alignment: .top, spacing: 24) {
                    coverBlock
                    VStack(alignment: .leading, spacing: 12) {
                        nameRow
                        LocalizedNamesSubtitle(game: game, currentLanguage: language, font: .body)
                        metadataFlowRow
                        DetailStatusPicker(status: $detailStatus)
                            .frame(maxWidth: 720, alignment: .leading)
                    }
                    scoreCard
                    Spacer(minLength: 0)
                }
            } else if iPadLayout.isPad, game.libraryScore != nil {
                // 有横幅（hideCover）：横幅已在 body 层铺满，信息 + 评分卡双栏。
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        nameRow
                        LocalizedNamesSubtitle(game: game, currentLanguage: language, font: .body)
                        metadataFlowRow
                        DetailStatusPicker(status: $detailStatus)
                            .frame(maxWidth: 720, alignment: .leading)
                    }
                    scoreCard
                    Spacer(minLength: 0)
                }
            } else if hideCover {
                // iOS 横向封面横幅版式：横幅已在 body 层贴屏满宽，这里只出信息列。
                infoBlock
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    coverBlock
                    infoBlock
                }
            }
            #endif
        }
    }

    /// iOS 横向封面横幅（2026-08-27 grill 定稿）：设了 landscapeData 时启用。
    /// 宽度铺满屏幕、顶贴导航栏下方，高 = 屏宽 ÷ 图片宽高比；上限 260pt——超竖长图
    /// 等比缩小居中留透明边，绝不裁切不拉伸。纯图无前景无圆角无描边（贴屏通栏）。
    fileprivate func landscapeBanner(width: CGFloat) -> some View {
        let capHeight: CGFloat = 260
        let imageAspect = game.landscapeImage.map { $0.size.width / max($0.size.height, 1) } ?? (920.0 / 430.0)
        let imageHeight = min(capHeight, width / max(imageAspect, 0.5))
        return Group {
            if let image = game.landscapeImage {
                Image(appImage: image)
                    .resizable()
                    .scaledToFit()
                    // 超竖长图在框内等比缩小、默认居中留透明边（scaledToFit 行为即所需）。
                    .frame(width: width, height: imageHeight)
            }
        }
        .frame(width: width, height: imageHeight)
    }
    /// iPad 横向封面横幅（需求②，2026-09-05）：iPhone 版 landscapeBanner 去掉 260pt
    /// 高度上限——iPad 竖屏宽 744pt，920×430 横图全宽显示高 ~347pt，正合「提升高度、
    /// 占满屏宽不留白边」；上限只在横屏 hero 分支接管后才需要（横屏不再走此函数）。
    /// 横屏无背景图回落此分支时宽 1133 高 530 略高，仍完整显示不裁切，可接受。
    fileprivate func iPadLandscapeBanner(width: CGFloat) -> some View {
        let imageAspect = game.landscapeImage.map { $0.size.width / max($0.size.height, 1) } ?? (920.0 / 430.0)
        let imageHeight = min(560, width / max(imageAspect, 0.5))
        return Group {
            if let image = game.landscapeImage {
                Image(appImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: width, height: imageHeight)
            }
        }
        .frame(width: width, height: imageHeight)
    }

    /// macOS 宽窗头部（2026-08-26 用户定稿）：封面单独在顶带（右移 48pt、左右全留白）；
    /// 名字/其他语言名/元数据行贴内容左缘；评分卡在名字块右侧、顶端与游戏名平齐；
    /// 状态滑块限宽 720 独占一行（在左列内、元数据下方）。未评分（想玩等）不渲染评分卡。
    /// 左列字号/间距按「与右侧评分卡视觉平衡」调校：名字 30pt、行距 12/8。
    /// 2026-08-27 追加：已设背景图时顶带换为 heroBanner——hero 作无虚化背景铺满横幅、
    /// 位于名字行与评分卡上方；同设 Logo 时横幅前景以 Logo 替代 2:3 封面。
    @ViewBuilder
    private func wideHeader(width: CGFloat, hideCoverBand: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if !hideCoverBand {
                coverBlock
                    .padding(.leading, 48)
            }

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    nameRow
                    LocalizedNamesSubtitle(game: game, currentLanguage: language, font: .body)
                    metadataFlowRow
                }
                if game.libraryScore != nil {
                    scoreCard
                }
                Spacer(minLength: 0)
            }

            DetailStatusPicker(status: $detailStatus)
                .frame(maxWidth: 720, alignment: .leading)
        }
    }

    /// 宽窗头部横幅：已设背景图时启用。2026-08-27 用户定稿口径：
    /// **整幅背景图无裁切显示**——宽度铺满内容区、顶边钉在详情页内容最顶端，
    /// 高度 = 内容宽 ÷ 图片自身宽高比（随窗口联动伸缩）；窄高比之外的超宽图到不了
    /// 预设横幅高度也接受（底部留白不强行拉伸）。仅对病态竖长图按 maxHeight 上限
    /// 整体等比缩小留边，绝不裁切。前景贴左缘 48 缩进、垂直居中于图片实际高度。
    /// Logo 与背景锁死为同一元素：宽度 = 横幅宽度 × 三档尺寸系数（logoSizeValue，默认
    /// medium = 0.195），与背景同源于横幅宽度——缩窗时两者等比联动不脱节。水平/垂直
    /// 位置各三档（logoHorizontalValue/logoVerticalValue）：垂直在剩余空白中锚定
    /// 上/中/下，水平左 48 / 居中 / 右 48。源 logo 尺寸比例各异，用户按游戏微调。
    fileprivate func heroBanner(width: CGFloat) -> some View {
        // 病态竖长图兜底上限：SGDB heroes 正常都 ≥2.3:1 触不到；防手动上传竖图把首屏撑爆。
        let capHeight: CGFloat = 560
        let imageAspect = game.heroImage.map { $0.size.width / max($0.size.height, 1) } ?? 3.1
        let imageHeight = min(capHeight, width / max(imageAspect, 0.5))
        return ZStack(alignment: .leading) {
            Color.clear
                .overlay(alignment: .topLeading) {
                    if let hero = game.heroImage {
                        Image(appImage: hero)
                            .resizable()
                            .scaledToFit()
                            .frame(width: width, height: imageHeight, alignment: .topLeading)
                    }
                }
            heroForeground(bannerHeight: imageHeight, bannerWidth: width)
        }
        .frame(width: width, height: imageHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.semantic(.separator), lineWidth: 1)
        )
    }

    /// 横幅前景：背景图 + Logo 同设时用 Logo 取代 2:3 封面——宽度按三档尺寸定比随背景
    /// 等比缩放；水平/垂直按三档选项锚定。无 Logo 时回退 2:3 封面块（矮横幅内等比缩小
    /// 防出界，仍垂直居中）。
    @ViewBuilder
    private func heroForeground(bannerHeight: CGFloat, bannerWidth: CGFloat) -> some View {
        if let logo = game.logoImage {
            let logoWidth = bannerWidth * game.logoSizeValue.widthRatio
            let logoHeight = logo.size.height / max(logo.size.width, 1) * logoWidth
            let vPad = max(0, bannerHeight - logoHeight)
            let hPad = max(0, bannerWidth - logoWidth)
            let topInset: CGFloat = switch game.logoVerticalValue {
            case .top: 0
            case .center: vPad / 2
            case .bottom: vPad * 0.75   // 贴底观感：底部留白 = 顶部 1/3，不真贴死底缘
            }
            let leadingInset: CGFloat = switch game.logoHorizontalValue {
            case .leading: 48
            case .center: hPad / 2
            case .trailing: hPad - 48
            }
            Image(appImage: logo)
                .resizable()
                .scaledToFit()
                .frame(width: logoWidth)
                .shadow(color: .black.opacity(0.35), radius: 7, y: 2)
                .padding(.top, topInset)
                .padding(.leading, leadingInset)
                .frame(width: bannerWidth, height: bannerHeight, alignment: .topLeading)
        } else {
            // 无 Logo：2:3 封面前景。与背景锁死等比联动——高度 = 横幅高度 × 0.85（上下留少量
            // 呼吸边），宽度按封面框比例换算；横幅随窗变窄时封面同步缩小不脱节。左 48 + 垂直居中。
            let coverHeight = bannerHeight * 0.85
            HStack(spacing: 0) {
                coverBlock(height: coverHeight)
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                Spacer(minLength: 0)
            }
            .padding(.leading, 48)
            .frame(width: bannerWidth, height: bannerHeight, alignment: .center)
        }
    }

    /// 游戏名 + 平台图标（宽窄两种布局共用的名字行，保留 ViewThatFits 换行）。
    /// 图标行与名字中轴对齐：各平台图标放大系数不同（白底字标原尺寸 / PS 1.2× / 其余 1.5×），
    /// firstTextBaseline 对图片等效底对齐、顶部参差；居中后多出的高度上下均分。
    private var nameRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 6) {
                Text(verbatim: game.displayName(for: language))
                    .font(.system(size: 30, weight: .bold))
                GamePlatformIcons(platforms: platforms, maxCount: 10, iconSize: 20)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: game.displayName(for: language))
                    .font(.system(size: 30, weight: .bold))
                GamePlatformIcons(platforms: platforms, maxCount: 10, iconSize: 20)
            }
        }
    }

    /// 元数据区（宽窗）：平台行 → 发售日期行 → 厂商/发行商/游戏类型行，各自缺项跳过。
    @ViewBuilder
    private var metadataFlowRow: some View {
        let platformText = platforms
            .map { Presets.display($0, category: .platform, language: language) }
            .joined(separator: " · ")
        VStack(alignment: .leading, spacing: 8) {
            if !platforms.isEmpty {
                Text(verbatim: platformText)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            if let date = game.releaseDate {
                Text(verbatim: date.formatted(date: .long, time: .omitted))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            factPieces(font: .body)
            if !game.groups.isEmpty {
                HStack(spacing: 6) {
                    ForEach(game.groups) { group in
                        Text(verbatim: group.name)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    /// 厂商 · 发行商（一段式小字）；游戏类型独立成行。各自缺项跳过，全空整行不占位。
    /// 字体参数：宽窗传 body 与评分卡平衡，窄布局保持 callout。
    @ViewBuilder
    private func factPieces(font: Font = .callout) -> some View {
        let house = [game.developer, game.publisher].compactMap { $0 }.filter { !$0.isEmpty }
        let genre = game.genre?.trimmingCharacters(in: .whitespaces) ?? ""
        if !house.isEmpty {
            Text(verbatim: house.joined(separator: " · "))
                .font(font)
                .foregroundStyle(.secondary)
        }
        if !genre.isEmpty {
            Text(verbatim: genre)
                .font(font)
                .foregroundStyle(.secondary)
        }
    }

    /// 宽窗头部右侧评分卡：库显示分 + 六维条形图，玻璃底 + 描边（与状态滑块同材质语言）。
    /// 未评分（libraryScore == nil，含想玩等轻量状态）时调用方整卡不渲染、右侧留白。
    private var scoreCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: game.libraryScore.map { String(format: "%.1f", $0) } ?? "")
                    .font(.system(size: 44, weight: .bold))
                    .monospacedDigit()
                LText("score.average")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Divider()
            DimensionScoreBars(game: game, labelWidth: 72)
        }
        .padding(18)
        .frame(width: 310, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(.thinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.semantic(.separator), lineWidth: 1))
    }

    /// 封面块：160×213 竖版封面（无封面时占位图标）；height 可调版本供 heroBanner 前景
    /// 在矮横幅里等比缩小使用（宽高比锁定原框比例）。
    fileprivate func coverBlock(height: CGFloat) -> some View {
        let w = height * 160 / 213
        return Group {
            if let image = game.coverImage {
                Image(appImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    Rectangle().fill(Color.semantic(.quaternarySystemFill))
                    Image(systemName: "gamecontroller")
                        .font(.system(size: 40 * height / 213))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: w, height: height)
        .background(Rectangle().fill(Color.semantic(.quaternarySystemFill)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }

    private var coverBlock: some View {
        coverBlock(height: 213)
    }

    /// 信息块：主名/其他语言名/发售日/平台/分组/评分与条形图。
    private var infoBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 大标题走词边界断行排版（iOS；U+2060 禁词内断行，见 lineBreakAwareTitle）。
            #if os(iOS)
            let titleText = lineBreakAwareTitle(game.displayName(for: language), language: language)
            #else
            let titleText = game.displayName(for: language)
            #endif
            // 名字 + 平台图标：一行放得下就并排；放不下（尤其多平台+超宽字标）自动换行成两行，避免撑宽整页布局。
            // 图标行与名字中轴对齐（各平台放大系数不同，基线/底对齐会顶部参差，同宽窗 nameRow 口径）。
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 6) {
                    Text(verbatim: titleText)
                        .font(.system(size: 26, weight: .bold))
                    GamePlatformIcons(platforms: platforms, maxCount: 10, iconSize: 18)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: titleText)
                        .font(.system(size: 26, weight: .bold))
                    GamePlatformIcons(platforms: platforms, maxCount: 10, iconSize: 18)
                }
            }
            LocalizedNamesSubtitle(game: game, currentLanguage: language)

            if !platforms.isEmpty {
                Text(verbatim: platforms
                    .map { Presets.display($0, category: .platform, language: language) }
                    .joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let date = game.releaseDate {
                Text(verbatim: date.formatted(date: .long, time: .omitted))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            factPieces()

            if !game.groups.isEmpty {
                HStack(spacing: 6) {
                    ForEach(game.groups) { group in
                        Text(verbatim: group.name)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let score = game.libraryScore {
                        Text(verbatim: String(format: "%.1f", score))
                            .font(.system(size: 44, weight: .bold))
                            .monospacedDigit()
                        LText("score.average")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    } else {
                        LText("score.unrated")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
                if game.libraryScore != nil {
                    DimensionScoreBars(game: game)
                }
            }
            .padding(.top, 6)

            // 状态机滑块：全局移到分数区下方（2026-08-27 用户定稿，双平台所有头部布局统一）。
            // 自定义滑动条（offset 滑块），点击即切换本地选中态并即时动画；模型写入延后到
            // 离开详情页（.onDisappear）才持久化，避免点击即同步写 SwiftData 触发整页 body
            // 重算导致的滑块卡顿（§29.14 差异 A）。图标 + 文字同显。
            DetailStatusPicker(status: $detailStatus)
        }
    }

    // MARK: - 评价

    /// 一句话评价（tagline）作为长评正文首段前的大号引言（方案②）：
    /// 与正文同流、更强——比正文大一号、半粗斜体。
    @ViewBuilder
    private var taglineView: some View {
        if !game.reviewTitle.isEmpty {
            Text(verbatim: game.reviewTitle)
                .font(.system(size: 21, weight: .semibold))
                .italic()
                .foregroundStyle(.primary)
                .lineSpacing(3)
                .textSelection(.enabled)
        }
    }

    /// 长评正文：Markdown 渲染（标题 / 加粗 / 斜体 / 列表），像一篇文章。
    @ViewBuilder
    private var reviewBodySection: some View {
        if !game.reviewBody.isEmpty {
            MarkdownReviewView(markdown: game.reviewBody)
                .textSelection(.enabled)
        }
    }

    /// 「编辑评价」入口：macOS 打开独立编辑窗口（写字台），iOS 弹出编辑 sheet。
    /// iOS 端只留编辑图标（square.and.pencil），不带文字。
    private var reviewEditButton: some View {
        Button {
            openReviewEditor()
        } label: {
            #if os(macOS)
            Label(L10n.tr("review.edit", lang: language), systemImage: "square.and.pencil")
            #else
            Image(systemName: "square.and.pencil")
            #endif
        }
        #if os(macOS)
        // macOS 分支带文字：必须是看得出来是按钮的形态（borderless 会渲染成可点文字）。
        .buttonStyle(.bordered)
        .controlSize(.small)
        #else
        .buttonStyle(.borderless)
        #endif
        .foregroundStyle(.secondary)
    }

    private func openReviewEditor() {
        #if os(macOS)
        // game / group 互斥：GroupFooter 设 groupID 时会清 gameID，这里对称清 groupID——
        // 否则编辑过分组评价后再开任一游戏的写字台，load() 先查 groupID 会载入上次的分组。
        ReviewEditorSession.shared.groupID = nil
        ReviewEditorSession.shared.gameID = game.persistentModelID
        openWindow(id: "reviewEditor")
        #else
        showingReviewEditor = true
        #endif
    }

    /// 评价区（单栏模式）：顶部工具行（含编辑入口）+ tagline 大号引言 + Markdown 长评正文。
    @ViewBuilder
    private var reviewSection: some View {
        if !game.reviewTitle.isEmpty || !game.reviewBody.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L10n.tr("review.header", lang: language))
                        .font(.title3.bold())
                    Spacer()
                    reviewEditButton
                }
                taglineView
                if !game.reviewBody.isEmpty && !game.reviewTitle.isEmpty {
                    reviewBodySection.padding(.top, 14)
                } else {
                    reviewBodySection
                }
            }
        }
    }

    // MARK: - 通关记录

    /// 详情页内容（现有评价 + 通关记录）。收藏家模式关时直接显示；开时在「详情」页签显示。
    @ViewBuilder
    private func detailsContent(width: CGFloat) -> some View {
        if width >= 1000 {
            if hasReview {
                wideContent(contentWidth: min(1500, width) - 56)
            } else {
                completionsSection
            }
        } else {
            reviewSection
            completionsSection
        }
    }

    /// 「详情 / 持有」液态玻璃滑块切换（收藏家模式开启时显示在信息下方）。
    /// 复刻 DetailStatusPicker 视觉：.thinMaterial 底 + accent 半透明滑块 + spring 动画；切到持有时档案内联铺在信息下方。
    private var detailTabPicker: some View {
        GeometryReader { geo in
            let all: [DetailTab] = [.details, .holdings]
            let cellWidth = geo.size.width / CGFloat(all.count)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.accentColor.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1)
                    )
                    .frame(width: cellWidth, height: geo.size.height)
                    .offset(x: CGFloat(tabSliderIndex) * cellWidth)
                    .animation(.spring(response: 0.3, dampingFraction: 0.78), value: tabSliderIndex)
                HStack(spacing: 0) {
                    ForEach(Array(all.enumerated()), id: \.offset) { _, tab in
                        Button {
                            let idx = all.firstIndex(of: tab) ?? 0
                            guard idx != tabSliderIndex else { return }
                            tabSliderIndex = idx
                            detailTab = tab
                        } label: {
                            Text(verbatim: L10n.tr(tab == .details ? "detail.details" : "detail.holdings", lang: language))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(detailTab == tab ? Color.accentColor : Color.secondary)
                                .frame(width: cellWidth, height: geo.size.height)
                                .contentShape(Rectangle())
                        }
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
        #if os(macOS)
        .frame(maxWidth: 280, alignment: .leading)
        #else
        .frame(maxWidth: .infinity)
        #endif
    }

    /// 宽窗口双列：评价标题与正文占约 58% 宽度，通关记录占剩余。
    /// 评价标题与「通关记录」标题同为 title3 粗体，两列顶部天然对齐。
    private func wideContent(contentWidth: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L10n.tr("review.header", lang: language))
                        .font(.title3.bold())
                    Spacer()
                    reviewEditButton
                }
                taglineView
                if !game.reviewBody.isEmpty && !game.reviewTitle.isEmpty {
                    reviewBodySection.padding(.top, 14)
                } else {
                    reviewBodySection
                }
            }
            .frame(width: max(340, contentWidth * 0.58), alignment: .leading)
            completionsSection
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var completionsSection: some View {
        // 已通关/长线游玩显示通关记录区；想玩等在玩轻量状态隐藏（数据保留，切回已通关恢复显示）。
        // 用本地 detailStatus 即时反映点击，避免依赖 game.statusValue（模型写入延后到 onDisappear）。
        if detailStatus.isCompletedOrLongRunning {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    LText("game.completions")
                        .font(.title3.bold())
                    Text(verbatim: "(\(game.completions.count))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        showingAddCompletion = true
                    } label: {
                        Label(L10n.tr("completion.add", lang: language), systemImage: "plus.circle")
                    }
                }

                if game.sortedCompletions.isEmpty {
                    LText("library.noResult")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(game.sortedCompletions) { completion in
                        CompletionCardView(
                            completion: completion,
                            onEdit: { editingCompletion = completion },
                            onDelete: { pendingDeleteCompletion = completion }
                        )
                    }
                }
            }
        }
    }
}
