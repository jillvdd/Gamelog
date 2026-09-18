import SwiftUI

/// 游戏详情页的奖杯区块（PlayStation 独有）。
///
/// 一块**中等宽度**的卡片（上限 `ExternalCardStyle.maxWidth` = 412，与 Xbox 成就卡、
/// Nintendo 游玩记录卡同宽），从上到下三行：
///
/// ```
/// ┌────────────────────────────────┐
/// │ PlayStation Network    来源：xxx│
/// │ PS3/PS4 · NPWR-08547           │
/// │  ╭──╮  ┌────────┐┌────────┐    │
/// │  │29│  │🏆 白金  ││🥇 金    │    │
/// │  │% │  │ 0 / 1  ││ 0 / 4  │    │
/// │  │──│  ├────────┤├────────┤    │
/// │  │12│  │🥈 银    ││🥉 铜    │    │
/// │  │/42│ │ 2 / 9  ││10 / 28 │    │
/// │  ╰──╯  └────────┘└────────┘    │
/// │  首次     最近      时长        │
/// │  7/5      5/4      189h        │
/// └────────────────────────────────┘
/// ```
///
/// 几处刻意的取舍：
/// - **宽度封顶 412**（2026-09-18 第二次收窄，510 → 412）。第一版是从铺满整宽收到 510
///   （用户：「三张卡宽度相当，特别是收窄 playstation 的卡片宽度」），第二版再收到 412 ——
///   「保持在我目前这个窗口尺寸里的宽度（双卡并列的最窄尺寸）就可以了」。
///   412 **就是并排列宽**（(840 − 16) ÷ 2，见 `ExternalCardStyle.maxWidth` 的算术），
///   所以卡片在并排阈值处正好铺满一行；比它宽的窗口仍是单列堆叠、卡片 412 左对齐。
///   封面封顶之后 `ViewThatFits` 那三档宽屏版式（两栏 / 三区）永远轮不到，早已删除。
/// - **四格是 2×2、摆在环右边**（2026-09-18）。此前是「环 + 两行大数字」一行、四格横排一行：
///   收窄到 412 之后那两行数字右侧空着一大片（用户：「playstation 卡片的空白还是太多了，
///   感觉可以把四种奖杯以上下左右的方式排列在百分比环的右边，并且高度整体对齐」）。
///   四格折成 2×2 塞进环右 → 空白被吃掉，卡片还少一行。
///   ⚠️ 由此**作废了本文件此前唯一的硬约束**（「四格与游玩三项必须同为四列」）——
///   那条是为两行横排对齐而立的。三项现在**铺满整宽**，与四格不再有列宽关系。
/// - **每一格是两行：图标与等级名并排在第一行、计数在第二行**（2026-09-18 第三版，
///   用户：「感觉还能继续紧凑，减少高度，减少空白部分」）。上一版是三行（图标 / 等级名 / 计数），
///   每格 67pt、整块 140pt，而旁边那只环只有 62pt —— 多出来的那几十点就是环上下那两片空白。
///   并排第一行之后每格 ~45pt、整块 ~94pt，与环同量级，整张卡 255 → ~200pt。
/// - **环心是 `12 / 42`，没有「已获得」也没有「还差 N 个」**（2026-09-18 用户原话：
///   「把 12/42 挪进百分比环里，距离全部奖杯还差 xx 个直接去掉，而且不用写已获得」）。
///   走 `ExternalRing.captionText`（字面文本）而不是 `captionKey` —— 两个整数不是一句话，
///   三语下写法相同，走 L10n 只会给三种语言各加一条只含两个占位符的死 key。
/// - **左上角是平台名而不是「🏆 奖杯」**（2026-09-17 用户要求）：卡片本身就是奖杯卡，
///   再写一遍「奖杯」是重复；去掉图标还给整块省下约一行高度。品牌名是专有名词，
///   走 `AccountProvider.brandName` 原样显示、不进 L10n（见那边的说明）。
/// - **「来源：」从底部挪到头部右端**：它本来自己占一行，与平台名同一行既贴题又省一行。
/// - **日期用 `.abbreviated`，与账号记录行的口径一致**：同一个事实在两个界面读起来必须一样
///   （账号行 `ExternalRecordRow.metaText` 也用这一档）。空间不够靠 `minimumScaleFactor` 收，
///   不换更短的日期格式。
/// - **某一项缺失时显示「—」而不是把这一格去掉**：四列是**对齐的栅格**，挖掉一格会让
///   剩下两格的位置随数据漂移（2×2 之后同理：删一格就变成 2+1，第二行会缺一角）。
///   `—` 是本项目「来源不提供」的既有写法（同 `StatsView`）。
/// - **三项全缺时整行不渲染**：PS3 / PS Vita 记录两个时间与时长都是 nil（索尼不提供），
///   一排三个「—」只是噪音。
/// - **四格等宽 + `minimumScaleFactor`**：2×2 里同一行的两格是给人横向比较的，
///   宽度不一致会让「哪个最少」这件事看起来有偏差。
/// - **不做横滑**：同上 —— 横滑把四格拆到两屏，就再也比不了了。
/// - **头部与「游玩三项」不是本文件实现的**：两者都与 Nintendo 的游玩记录卡
///   （`PlayActivityView`）共用同一份代码（`ExternalSourceHeader` / `PlayActivityStatsRow`）。
///   三张卡在详情页里并列摆在同一块区域，长得必须是「一家人」——
///   各写一份的话，同一个「来源：xxx」在两行里字号/颜色不一样只是时间问题。
/// - **环走共用的 `ExternalRing`**（`Support/ExternalCardStyle.swift`）：
///   Xbox 成就卡 2026-09-18 也有了环（Gamerscore 完成度），两张卡的环必须逐像素同源。
/// - **图标走 `TrophyIcon`**（`TrophyStyle.swift` 里那个唯一出口）。用户之后给了 PSN 官方
///   图标资源时，只改那一个视图，本文件一行不动 —— 所以这里**不出现任何 `Image(systemName:)`**。
/// - **`progress` 为空时也要显示百分比**：`TrophyProgress.displayPercent` 会按计数现算。
///   显示来源给的 `progress` 优先，因为那是索尼自己算的、与「已得/总数」不一致时也照实显示
///   （差异是来源的事实，见 `TrophyProgress.displayPercent`）。
struct TrophyProgressView: View {
    @Environment(\.appLanguageCode) private var language

    let progress: TrophyProgress
    /// 来源账号展示名。nil / 空 = 不渲染「来源：」。
    var sourceName: String?
    /// 这条记录的**平台列表**（来源给的 `PS3,PS4` → 显示 `PS3/PS4`）。
    /// 由调用点传 `ExternalGameRecord.psnPlatformDisplay` —— 拆逗号 / 规范化 / 丢掉认不出的
    /// 那一项这些规则在模型上只有那一处，不在这里再写一遍。
    ///
    /// 为什么必须是**列表**：同一个奖杯套可以横跨两个平台（港版人中之龙 0 就是 PS3/PS4 共用
    /// 一套），压成单值就把「这个版本在哪些平台上」抹掉了 —— 那正是用户要看的信息。
    /// 传 nil 时退回 `progress` 来源那一条记录自己的平台折算值（见 `psnPlatformDisplay`）。
    var platformText: String?
    /// 来源编号的展示写法（`NPWR-08547`），同理由调用点传 `titleCodeDisplay`。
    var titleCode: String?
    /// 游玩三项（与奖杯**同一条来源记录**，不另取）。全 nil = 整行不渲染。
    var firstPlayedAt: Date?
    var lastPlayedAt: Date?
    /// 小时数。**由调用点传 `ExternalGameRecord.displayHours`** —— 取整规则（四舍五入、
    /// 不足 1 小时按 1 小时）在模型上只有那一处，不在这里再写一遍。
    var hours: Int?

    /// 一种版式：头部 / 环 + 总数 / 四格 / 游玩三项，从上到下。
    ///
    /// 这里曾用 `ViewThatFits` 在「三区 / 两栏 / 竖排」三档里挑（`minWidth` 当断点）。
    /// 2026-09-18 随宽度封顶一起删掉：卡片内容区最多 486pt，两栏那档要 600、
    /// 三区那档要 920，**两档都永远轮不到**。断点式版式的价值在于「宽了就换一种排法」，
    /// 而封顶之后这里不再有「宽了」这回事。
    ///
    /// 保留竖排而不是别的：四格 + 三项两行本来就是同一套四列栅格（见类型注释的硬约束），
    /// 环与总数摆在它们上方，486pt 下每一项都有富余。
    var body: some View {
        VStack(alignment: .leading, spacing: ExternalCardStyle.blockSpacing) {
            header
            summary
            playStats
        }
        .padding(ExternalCardStyle.contentPadding)
        .frame(maxWidth: ExternalCardStyle.maxWidth, alignment: .leading)
        .appPanelSurface()
    }

    // MARK: - 头部（品牌名 + 版本副标题 + 来源）
    //
    // 实际画的是 `ExternalSourceHeader`（与 Nintendo 的游玩记录卡共用同一份实现 ——
    // 两张卡在同一块区域里并列，头部必须长得一模一样）。
    // 这里只负责把「副标题」拼出来。

    private var header: some View {
        ExternalSourceHeader(brandName: AccountProvider.playstation.brandName,
                             subtitle: subtitle,
                             sourceName: sourceName)
    }

    /// 头部副标题：`PS3/PS4 · NPWR-08547`。
    ///
    /// 用户 2026-09-17 的原话是「在左上角 PlayStation Network 下写明游戏的平台和号码」；
    /// Nintendo 那张卡没有这一行（那边的 `titleId` 是 16 位十六进制，认不出来）。
    ///
    /// 两段之间用 ` · ` 连（与 `account.detail.syncSummary` 那类回执同一写法）。
    /// 只有一段时就只显示那一段；**两段都没有才返回 nil，让整行不渲染** ——
    /// 渲染一个空 `Text` 会白占一行高度，卡片看起来像缺了东西。
    ///
    /// ⚠️ 空串按「没有」处理：`titleCodeDisplay` 在形状认不出时**原样返回**（空串也可能
    /// 原样返回），不在这里滤掉就会画出一道孤零零的分隔符。
    private var subtitle: String? {
        let parts = [platformText, titleCode]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    // MARK: - 环 + 四格（左右并排）

    /// 左：百分比环（环心写着「12 / 42」）；右：四色奖杯的 **2×2**。
    ///
    /// 2026-09-18 重排，用户原话：「playstation 卡片的空白还是太多了，感觉可以把四种奖杯
    /// 以**上下左右**的方式排列在百分比环的右边，并且**高度整体对齐**，三项数据放在下面」。
    /// 上一版是「环 + 两行大数字」独占一行、四格另占一行铺满整宽 ——
    /// 收窄到 412 之后，那两行大数字右侧就是一大片空白，而四格又横着摊了 412pt。
    /// 现在把四格折成 2×2 塞进环右边，两个问题一起解决：空白被吃掉、卡片**少一行**。
    ///
    /// ⚠️ 这一改**废掉了本文件此前唯一的硬约束**（「四格与游玩三项必须同为四列」）——
    /// 那条约束是为「四格横排 + 三项横排」两行对齐而立的，2×2 之后不存在了。
    /// 三项从此**铺满整宽**，与四格不再有列宽关系。
    private var summary: some View {
        HStack(alignment: .center, spacing: ExternalCardStyle.ringGap) {
            ring
            gradeGrid
        }
    }

    // MARK: - 环形百分比

    /// 环走共用的 `ExternalRing`（与 Xbox 成就卡**同一份实现**，理由见那边的类型注释）。
    /// 本文件只管把两个数递进去 —— 颜色、粗细、「从 12 点起画」都不在这里。
    ///
    /// 环心第二行是**已得 / 总数**（用户 2026-09-18：「把 12/42 挪进百分比环里，
    /// 距离全部奖杯还差 xx 个直接去掉，而且不用写已获得」）。
    /// 这里传的是 `captionText` 而不是 `captionKey` —— 它不是一句话，是两个计数，
    /// 三语下长得一模一样，走 L10n 只会多出三条死 key（`game.trophies.earned` /
    /// `game.trophies.remaining` / `game.trophies.complete` 正是这么被删掉的）。
    ///
    /// 百分比仍用 `displayPercent`（来源给了就照来源、没给按计数现算），
    /// 与环心那两个数**同源**：数字来自 `earnedTotal / definedTotal`，弧长来自同一个 `progress`。
    private var ring: some View {
        ExternalRing(percent: progress.displayPercent,
                     captionText: "\(progress.earnedTotal) / \(progress.definedTotal)",
                     // 「12 / 42」挪进环心之后，这两个数**在卡片上只剩这一处**（四格只报分等级的数），
                     // 所以环不能再当纯装饰隐藏 —— 传一句读屏说法把它补回去。
                     accessibilityLabel: L10n.tr("game.trophies.a11y",
                                                 [progress.definedTotal, progress.earnedTotal],
                                                 lang: language))
    }

    // MARK: - 四格（2×2）
    //
    // 两行 `HStack` 而不是 `LazyVGrid`：格子要 `maxWidth: .infinity` 均分，
    // 而 `LazyVGrid(.adaptive)` 里不能放 `.fixedSize()`（项目内存里的既有陷阱，
    // 曾经让持有页崩过）—— 两个等宽 `HStack` 是同一件事的最简写法，
    // 行高一致也由「两行结构逐字相同」天然保证，不需要额外对齐手段。

    private var gradeGrid: some View {
        VStack(spacing: ExternalCardStyle.gridSpacing) {
            HStack(spacing: ExternalCardStyle.gridSpacing) {
                gradeCell(.platinum)
                gradeCell(.gold)
            }
            HStack(spacing: ExternalCardStyle.gridSpacing) {
                gradeCell(.silver)
                gradeCell(.bronze)
            }
        }
    }

    /// 一格：第一行「图标 + 等级名」，第二行「已得 / 总数」。
    ///
    /// ⚠️ 2026-09-18 从**三行**（图标 / 等级名 / 计数）折成**两行**（图标与等级名并排）——
    /// 用户原话「感觉还能继续紧凑，减少高度，减少空白部分」。三层堆叠时每格 67pt 高、
    /// 整块 2×2 有 140pt，而旁边的环只有 62pt，环上下那两片空白正是「空白太多」的来源。
    /// 并排之后每格 ~45pt、整块 ~94pt，与 62pt 的环才是同一个量级。
    ///
    /// 并排的代价是**图标不再逐列对齐**（「白金」比「金」宽，居中后两个图标位置不同）——
    /// 这是把 4 个图标从「一列一列对齐」换成「格子中心对齐」的结果，值这 20pt 高度。
    /// 计数用 `monospacedDigit`：同一行两格的数字位数不同也不抖。
    private func gradeCell(_ grade: TrophyGrade) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                TrophyIcon(grade: grade, size: 16)
                Text(verbatim: L10n.tr(grade.labelKey, lang: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(verbatim: "\(progress.earned(grade)) / \(progress.defined(grade))")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                // 2×2 之后每格宽约 156pt（412 − 左右内边距 20 − 间距 4，再减环那 62 + 14），
                // 但仍留着缩字：放大字体 / 日语「プラチナ」在原字号下也放不下，
                // 缩字比换行好（换行会把两行格子弄乱）。
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .appCardSurface()
        .accessibilityElement(children: .combine)
    }

    // MARK: - 游玩三项
    //
    // 实现在 `PlayActivityStatsRow`（与 Nintendo 的游玩记录卡**共用同一份**）：
    // 「哪三项」「缺值显示 `—`」「日期格式」「时长单位」都在那边，本文件不重复一遍。
    // **不传 `trailingPlaceholder`**（那个参数已随四列栅格一起删除）：三项从此**铺满整宽**，
    // 没有第四列要对齐了 —— 「与上面四格列宽对齐」这条旧理由随四格改 2×2 一起失效。

    /// 首次游玩 / 最近游玩 / 游玩时长。三项全 nil 时整行不渲染（判在 `PlayActivityStatsRow` 内部）。
    private var playStats: some View {
        PlayActivityStatsRow(firstPlayedAt: firstPlayedAt,
                             lastPlayedAt: lastPlayedAt,
                             hours: hours)
    }
}
