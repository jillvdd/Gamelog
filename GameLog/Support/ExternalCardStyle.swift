import SwiftUI

// =============================================================================
//  三张外部来源卡共用的**版式常数**与**百分比环**
//
//  PSN 奖杯卡（`TrophyProgressView`）/ Xbox 成就卡（`XboxAchievementView`）/
//  Nintendo 游玩记录卡（`PlayActivityView`）在详情页里上下紧挨着摆（有时还并排），
//  长得必须是「一家人」—— 所以「多宽」「环怎么画」这两件跨卡一致的事只有一份实现。
//  单卡自己的东西（奖杯 / 成就那四格怎么排）仍留在各自的视图文件里。
// =============================================================================

/// 三张外部来源卡共用的宽度口径。
enum ExternalCardStyle {

    /// 三张卡的**统一宽度上限**。
    ///
    /// 2026-09-18 之前三张卡各有一个宽度（Nintendo 380 / Xbox 510 / PSN 铺满整宽）。
    /// 那个「各按内容量定宽」的思路本身没错，但三张卡是**上下紧挨着**摆的：
    /// 宽度不一致读起来就不是「同一个游戏在三家的存档」，而是「三块不一样的面板」。
    /// 用户的原话是「我希望他们的内容密度，空白程度，宽度相当，但是高度可以有所不同，
    /// 特别是收窄 playstation 的卡片宽度」。**高度不统一是有意的** ——
    /// 三家的字段数本来就不同（PSN 环 + 四格 + 三项 / Xbox 环 + 四格 / Nintendo 三格），
    /// 为了凑高度去补空格子是把版面做假。
    ///
    /// **412 的来历**（2026-09-18 第二次收窄，510 → 412）：用户的原话是
    /// 「保持在我目前这个窗口尺寸里的宽度（**双卡并列的最窄尺寸**）就可以了」——
    /// 并排时每列 =（840 − 16）÷ 2 = **412**，所以这不是一个另取的数，
    /// 而是**并排阈值的直接推论**：卡片宽度 == 并排列宽。于是两张卡在阈值处**正好铺满一行**
    /// —— 卡比列窄会留下一条缝，卡比列宽则要求窗口再宽一点才敢并排。
    ///
    /// ⚠️ `maxWidth` 与 `twoUpMinWidth` 从此**绑在一起**（412 × 2 + 16 = 840），
    /// 改一个必须同时改另一个，否则并排那一行会出现上面两种毛病之一。
    ///
    /// ⚠️ 510 那一版三张卡**都是四列栅格**（Nintendo 只有三项，靠 `PlayActivityStatsRow`
    /// 的 `trailingPlaceholder` 补出第四列来与其他两张对齐）。412 这一版**四列栅格没了**：
    /// 奖杯卡与成就卡都改成「环在左、四格 2×2 在右」，Nintendo 的三项因此**铺满整宽**
    /// （用户：「任天堂卡片的三项数据在卡片中应该更居中且填满卡片」）——
    /// `trailingPlaceholder` 这个参数连同它存在的理由一并删除。
    /// 收窄的另一半动机是「密度」而不是「宽度」本身：510 的卡里「环 + 两行数字」右侧
    /// 空着一大片（用户：「playstation 卡片的空白还是太多了」），2×2 正好把那片空白吃掉。
    /// 三张卡的基准/默认宽度上限（单列堆叠或紧凑时）。
    static let maxWidth: CGFloat = 412

    /// 弹性并排时单张卡片的最大允许宽度（避免在超大屏上过度拉伸造成留白稀疏）。
    static let maxElasticWidth: CGFloat = 520

    /// 计算给定容器宽度下的最佳卡片列宽（单列或双列自适应）。
    static func columnWidth(for containerWidth: CGFloat) -> CGFloat {
        if containerWidth >= twoUpMinWidth {
            let twoColWidth = (containerWidth - columnSpacing) / 2
            return min(maxElasticWidth, max(maxWidth, twoColWidth))
        }
        return min(containerWidth, maxWidth)
    }

    /// 卡片**并排**时的列间距。
    static let columnSpacing: CGFloat = 16

    /// 卡片四周的内边距（三张卡共用）。
    ///
    /// 2026-09-18 从各写各的 12 收到 10（用户：「感觉还能继续紧凑，减少高度，减少空白部分」）。
    /// 12 → 10 看着只省 4pt，但三张卡**是上下紧挨着**摆的，四边一起收才不会
    /// 出现「一张卡的内边距比另一张宽」这种一眼就能看出的不齐。
    static let contentPadding: CGFloat = 10

    /// 卡片内部**各块之间**的竖向间距（头部 / 环+格 / 游玩三项）。
    ///
    /// 同一个理由：三张卡的块间距必须相等，否则并排时块与块的水平线对不上。
    /// 12/10 各不相同 → 统一 **8**（PSN 原来 12、Xbox/Nintendo 原来 10）。
    static let blockSpacing: CGFloat = 8

    /// **环与它右边那 2×2 栅格**之间的水平间距（PSN 奖杯卡 / Xbox 成就卡共用）。
    static let ringGap: CGFloat = 14

    /// 环右边那 2×2 栅格的格间距，横竖同值。
    ///
    /// 两张卡的栅格是**同一套几何**（列宽 = 卡片内容宽 − 环 − `ringGap`），
    /// 间距各写一个数的话同一行两张卡的格子会差 1pt —— 上下叠放时看得出来。
    /// 与 `blockSpacing` 一起从 6 收到 **4**（2026-09-18 紧凑化）。
    static let gridSpacing: CGFloat = 4

    /// **并排的最小内容宽度**：详情页内容区达到这个值才把卡片两两并排，否则一列堆叠。
    ///
    /// **840 = 412 × 2 + 16**（两列卡片 + 列间距）—— 与 `maxWidth` 是同一个数的两种说法
    /// （见那边的说明）。2026-09-18 第二次收窄时**这个值没有动**：卡从 510 收到 412，
    /// 而 840 本来就在那儿，两条线今天才第一次闭合在同一个点上。
    ///
    /// 840 在 macOS 上对应窗口约 **1146pt**（1146 − 侧栏 250 − 详情页左右各 28）——
    /// 也就是「窗口拉到比较宽才发生」，正是用户要的「窗口尺寸合适的情况下」。
    /// 980pt 那个默认窗口（内容区 674）**不会**并排：一列堆叠，卡片 412 宽、左对齐。
    ///
    /// 判据**只看宽度、不判平台**：iPhone 永远到不了这个宽度，iPad 横屏到了就该并排 ——
    /// 加一道 `#if os(macOS)` 只会让「同一块屏宽下两台设备表现不同」这件怪事发生。
    static let twoUpMinWidth: CGFloat = 840
}

/// 环形的颜色与尺寸（PSN 与 Xbox 两张卡共用；模版截图取色，与 `BrandPalette` 同级归属）。
enum ExternalRingStyle {
    /// 进度弧的前景（模版里那道蓝色弧）。
    static let progress = Color(red: 0.298, green: 0.620, blue: 0.910)   // #4C9EE8
    /// 底槽。用自适应次要色而不是固定浅蓝 —— 深色模式下固定浅蓝会变成一根亮条。
    static let track = Color.secondary.opacity(0.18)
    /// 环粗 / 直径。2026-09-17 随卡片整体收紧：76 → 62（环粗 8 → 7）。
    static let lineWidth: CGFloat = 7
    static let diameter: CGFloat = 62
}

/// 三张外部来源卡共用的**百分比环**（PSN 奖杯完成度 / Xbox Gamerscore 完成度）。
///
/// 抽出来的理由与 `ExternalStatCell` 同一条：**环的构造只能有一处**。
/// 两个来源各画一遍的话，「从 12 点方向起画」「底槽用自适应次要色」「中心两行字的字号」
/// 这些细节迟早会在其中一张卡上变样 —— 而两张卡是上下紧挨着摆的，一眼就能看出不是一家人。
///
/// **只收百分比、不收比例**（`TrophyProgress.displayPercent` / `AchievementProgress.gamerscorePercent`）：
/// 环画到哪里与中心那行字是同一个数的两种画法，各传一份就有机会对不上
/// （「98%」配一根 97% 的弧）。比例在这里现算，两处永远一致。
struct ExternalRing: View {
    @Environment(\.appLanguageCode) private var language

    /// 整数百分比（`62`）。越低越不裁字，超出 0…100 会被夹回来（服务端自相矛盾时不画歪）。
    let percent: Int
    /// 环中心那行小字的 L10n key —— 说明这个百分比量的是什么
    /// （Xbox 传 `game.xbox.gamerscore`）。两个来源量的是不同的东西，key 由调用点决定、这里不猜。
    ///
    /// 有默认空串，因为**两种环心只给一个**：给了 `captionText` 就不必再编一个 key 出来
    /// （PSN 那一格填的是来源的两个计数，本来就没有可翻译的词 —— 见下）。
    var captionKey: String = ""
    /// 直接给中心那行**字面文本**，给了就完全不查 L10n（优先于 `captionKey`）。
    ///
    /// 只为 PSN 存在（2026-09-18 用户要求「把 12/42 挪进百分比环里」）：环心写 `12 / 42`
    /// 是**来源给出的两个整数**，不是一句话 —— 走 L10n 只会给三种语言各编一个
    /// 只含两个占位符的 key，而它在三种语言里长得一模一样。
    var captionText: String? = nil
    /// 读屏用的说法。`nil`（默认）= **环是纯装饰，整只隐藏**。
    ///
    /// 为什么默认隐藏：环里的百分比与旁边统计格里的数字是同一件事
    /// （Xbox 那只是「62%」＋ 格里的「1240 / 2000」），报两遍是噪音。
    /// ⚠️ **但 PSN 那只已经不是了** —— 「12 / 42」挪进环心之后，**卡片别处没有第二处**
    /// 说这两个数（四格只报分等级的数）。所以 PSN 传字面说法，把这条信息补回读屏流里。
    var accessibilityLabel: String? = nil

    private var fraction: Double { Double(min(100, max(0, percent))) / 100 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(ExternalRingStyle.track, lineWidth: ExternalRingStyle.lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(ExternalRingStyle.progress,
                        style: StrokeStyle(lineWidth: ExternalRingStyle.lineWidth, lineCap: .round))
                // 从 12 点方向起画。不加这一下，进度是从 3 点方向开始的。
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(verbatim: "\(percent)%")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(verbatim: captionText ?? L10n.tr(captionKey, lang: language))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    // 中心那行字比「62%」宽得多（Xbox 的 "Gamerscore" / "ゲーマースコア"，
                    // PSN 的 "12 / 42"），62pt 的环内沿只有 ~48pt 可用 ——
                    // 缩字比换行好（换行会把中心那两行挤歪）。
                    .minimumScaleFactor(0.6)
            }
            // 环是圆的，中心那行字是方的：不留这道内边距，长标签的两端会顶到弧线上。
            .padding(.horizontal, 4)
        }
        .frame(width: ExternalRingStyle.diameter, height: ExternalRingStyle.diameter)
        // 默认整只隐藏（纯装饰，同卡片里的统计格会报同一件事）；给了 `accessibilityLabel`
        // 就作为一个元素报出来 —— 那时环里的数是卡片上唯一的一份。
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: accessibilityLabel ?? ""))
        .accessibilityHidden(accessibilityLabel == nil)
    }
}
