import SwiftUI

/// 游戏详情页的 **Xbox 成就卡**（Xbox 独有）。
///
/// ```
/// ┌──────────────────────────────────┐
/// │ Xbox Live               来源：xxx │
/// │ Xbox One/Xbox Series X|S         │
/// │  ╭──╮   成就       游戏分数       │
/// │  │62│   25 / 52    1240/2000     │
/// │  │% │   ────────────────         │
/// │  │──│   游玩时长   最近游玩       │
/// │  │62│   189 小时   2026/9/15      │
/// │  ╰──╯                            │
/// └──────────────────────────────────┘
/// ```
///
/// 和奖杯卡（`TrophyProgressView`）、游玩记录卡（`PlayActivityView`）是同一块区域里并列的
/// 三种卡，视觉语言一致（同一个头部零件、同一个百分比环、同一套统计格、
/// 同一圈 `appPanelSurface()` 面板、同一个宽度上限）。差在**内容**：微软那边给的是
/// 「成就数 + Gamerscore + 时长 + 最近游玩」四项，没有索尼那种分级奖杯，所以没有四色格。
///
/// 几处刻意的取舍：
/// - **环量的是 Gamerscore**（2026-09-18 用户要求「xbox也要一个百分比环用来凸显已经
///   获得的 gamerscore」）。**不是**成就数的完成度 —— 每个成就 5–100 点、由发行方自定，
///   两者在真实数据上并不相等。`gamerscoreTotal = 0`（Xbox 上确实有这种条目）时
///   **整只环不画**，而不是画一只 `0%` 的空槽：那与「有成就套但一分没拿」长得一样，
///   而这两件事必须分得开（判据在 `AchievementProgress.gamerscorePercent`）。
/// - **环在左、四格 2×2 在右**，与奖杯卡**同一套骨架**（2026-09-18 收窄到 412 时定的）：
///   两卡并排 / 上下叠放时逐格同宽同高。奖杯卡那边是用户点名要的；这边是**跟着改的**——
///   一排四格在 412 里只剩 73pt/格，比奖杯卡 2×2 的 156pt 挤一倍，而「三张卡密度相当」
///   是本轮的总要求（详见 `statsRow` 的注释）。
/// - **宽度与其他两张卡相同**（`ExternalCardStyle.maxWidth` = 412）。这张卡本来是最宽的
///   一张（510），2026-09-18 与另外两张一起收到 412 —— 三张卡是上下紧挨着摆的，
///   宽度不一致读起来就不是「同一个游戏在三家的存档」。
/// - **头部有副标题（平台列表），没有编号**。`Xbox One/Xbox Series X|S` 是**来源事实**
///   （`devices`）；不写 `titleId` 是因为那是十进制的 `2131196662`，Xbox 自己的界面都不显示它。
///   为什么非要有这一行：同一个游戏在 Xbox 360 与 Xbox One 上是两个 titleId、两条记录、
///   **两张卡**，没有它就分不出谁是谁（PSN 侧同理，见 `xboxPlatformDisplay`）。
/// - **四格 = 成就 / 游戏分数 / 游玩时长 / 最近游玩**（用户点名要的第四格是游玩时长）。
///   没有「首次游玩」——**来源不给这个字段**（实测 330 条里一个字都没有），
///   与其画一格恒为 `—` 的，不如把宽度让给真有的四项。
/// - **不做 `ViewThatFits` 多档版式**：里面只有「环 + 2×2」一种排法，容器再宽也只是
///   格子变宽，窄了就靠 `minimumScaleFactor` 收字。
/// - **成就与 Gamerscore 的文本在 `AchievementProgress` 上**（`achievementsText` /
///   `gamerscoreText`），这里只负责摆位 —— 「总数 0 显示 `—`」这类口径与
///   `ExternalGameRecord.achievements` 同源，视图里不重写一遍。
/// - **入场判据在 `ExternalGameRecord.showsXboxAchievementCard`**（那里挡了一道
///   「来源不是 Xbox 就不出这张卡」，所以这里不重复判 provider）：四项全无时整张卡不出现。
struct XboxAchievementView: View {
    /// 成就进度。nil = 这条记录没有成就数据（四格显示 `—`），但游玩两项仍有可能有值。
    var achievements: AchievementProgress?
    /// 来源账号展示名。nil / 空 = 不渲染「来源：」。
    var sourceName: String?
    /// 来源侧原始标题。
    var titleName: String?
    /// 来源给的**可用平台列表**（`Xbox One/Xbox Series X|S`）——
    /// 由调用点传 `ExternalGameRecord.xboxPlatformDisplay`（拆列表 / 丢认不出的项
    /// 这些规则在模型上只有那一处，不在这里再写一遍）。
    var platformText: String?
    /// 最近游玩。**Xbox 没有「首次游玩」**（来源不提供），所以只有这一项。
    var lastPlayedAt: Date?
    /// 小时数。**由调用点传 `ExternalGameRecord.displayHours`**（取整规则在模型上只有那一处）。
    let hours: Int?
    /// 自定义卡片宽度（nil 时使用 ExternalCardStyle 弹性上限）
    var cardWidth: CGFloat? = nil

    @Environment(\.appLanguageCode) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: ExternalCardStyle.blockSpacing) {
            ExternalSourceHeader(brandName: AccountProvider.xbox.brandName,
                                 titleName: titleName,
                                 subtitle: platformText,
                                 sourceName: sourceName)
            statsRow
        }
        .padding(ExternalCardStyle.contentPadding)
        // ⚠️ 宽度上限必须**在 `appPanelSurface()` 之前**：顺序反过来的话面板会先铺满整宽，
        // 再在满宽的面板上画一条窄内容 —— 看起来就是「这块面板左边挤了四个数字」。
        .frame(maxWidth: cardWidth ?? ExternalCardStyle.maxElasticWidth, alignment: .leading)
        .appPanelSurface()
    }

    /// 环 + 四格 2×2（成就 / 游戏分数 ‖ 游玩时长 / 最近游玩）。
    ///
    /// `alignment: .center`：环有 62pt 高，2×2 那两行加起来约 64pt（两个 30pt 的统计格 +
    /// `gridSpacing` 4）——
    /// 顶对齐的话环会整只吊在上面，看起来像两个不相干的东西。
    ///
    /// **四格从一排改成 2×2 是 2026-09-18 随卡片收窄一起做的**（510 → 412）：
    /// 一排四格在 412 里每格只有 73pt，而同一张页面上奖杯卡的格子（环右边的 2×2）
    /// 有 156pt —— 用户要的「三张卡内容密度相当」就又破了，而且是**反着破**的
    /// （这回是这张挤）。改成 2×2 之后两张带环的卡**逐格同宽同高**，
    /// 上下叠放时看起来本来就是一套东西。
    /// 分行按语义分：第一行是「成就体系」（成就数 / 分数），第二行是「游玩」（时长 / 最近）。
    ///
    /// 某一格没值时 `ExternalStatCell` 显示 `—` 而**不是把那一格去掉**：格子是给人横向
    /// 比较的，挖掉一格会让同行的另一格位置随数据漂移（时长缺失是常态 —— Xbox 360 的游戏
    /// 一律没有时长）。
    private var statsRow: some View {
        HStack(alignment: .center, spacing: ExternalCardStyle.ringGap) {
            // 没有环的情形有两种，都走同一个 `if`：整条记录没有成就数据（`achievements == nil`），
            // 或有数据但 `gamerscoreTotal = 0`（那种条目只该有四格，不该有一只 0% 的环）。
            if let percent = achievements?.gamerscorePercent {
                ExternalRing(percent: percent, captionKey: "game.xbox.gamerscore")
            }
            VStack(spacing: ExternalCardStyle.gridSpacing) {
                HStack(alignment: .top, spacing: ExternalCardStyle.gridSpacing) {
                    ExternalStatCell(labelKey: "game.xbox.achievements",
                                     value: achievements?.achievementsText)
                    ExternalStatCell(labelKey: "game.xbox.gamerscore",
                                     value: achievements?.gamerscoreText)
                }
                HStack(alignment: .top, spacing: ExternalCardStyle.gridSpacing) {
                    ExternalStatCell(labelKey: "game.activity.playtime",
                                     value: hours.map { PlayActivity.hoursText($0, language: language) })
                    ExternalStatCell(labelKey: "game.activity.lastPlayed",
                                     value: lastPlayedAt.map(PlayActivity.dayText))
                }
            }
        }
    }
}
