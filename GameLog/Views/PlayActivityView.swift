import SwiftUI

/// 游戏详情页的**游玩记录卡**（Nintendo 独有）。
///
/// ```
/// ┌──────────────────────────────────────────────┐
/// │ Nintendo Account                    来源：xxx │
/// │  首次游玩     最近游玩     游玩时长           │
/// │  2023/7/5     2024/5/4     189 小时           │
/// └──────────────────────────────────────────────┘
/// ```
///
/// 和奖杯卡（`TrophyProgressView`）、成就卡（`XboxAchievementView`）是同一块区域里并列的
/// 三种卡，视觉语言一致（同一个头部零件、同一套「游玩三项」口径、同一圈 `appPanelSurface()`
/// 面板、同一个宽度上限），差在**内容**：任天堂没有奖杯体系，只有时长与两个日期，
/// 所以没有环也没有四格。
///
/// 几处刻意的取舍：
/// - **宽度与另外两张卡相同**（`ExternalCardStyle.maxWidth`）。这张卡曾经是最窄的一张（380），
///   2026-09-18 统一 —— 三张卡上下紧挨着摆，宽度不一致读起来不像一家人。
///   用户的原话是「内容密度，空白程度，宽度相当」。
/// - **三项铺满整宽、内容居中**（2026-09-18 修正）。此前这里传 `trailingPlaceholder: true`
///   给三项**补了一个空列**，只为让它们与奖杯卡的四格逐列对齐 —— 奖杯卡改成
///   「环 + 2×2」之后那条对齐关系不存在了，而补空列的直接后果就是
///   **三项只占了卡片的 3/4 宽、右侧空着一块**（用户：「任天堂卡片的三项数据在卡片中
///   应该更居中且填满卡片」）。现在不传那个参数（它已随四列栅格一起删除），
///   三项均分整宽 —— 每格从 117pt 变成 129pt，与另外两张卡同一档。
/// - **头部没有副标题**。奖杯卡那行写的是「哪个版本」（`PS3/PS4 · NPWR-08547`），
///   任天堂这边没有对应的两段式信息：`titleId` 是 16 位十六进制（`0100000000010000`），
///   用户认不出来，写上去只是噪音。
/// - **不做 `ViewThatFits` 多档版式**。奖杯卡以前要三档，是因为它铺满整宽、宽窄差得远；
///   现在三张卡都封了顶，容器宽度只有「不够 412」和「412」两种，加档位只是多维护一份
///   永远用不上的布局。窄了就靠 `minimumScaleFactor` 收字。
/// - **三项全缺时整张卡不出现**：入场判据在 `ExternalGameRecord.showsPlayActivityCard`
///   （那里挡了一道「来源不是 Nintendo 就不出这张卡」），所以这里不重复判一遍 provider。
///   三项的「缺值显示 `—`」「日期格式」全在 `PlayActivityStatsRow` / `PlayActivity` 里，
///   本文件一行都不重复。
struct PlayActivityView: View {

    /// 来源账号展示名。nil / 空 = 不渲染「来源：」。
    var sourceName: String?
    var firstPlayedAt: Date?
    var lastPlayedAt: Date?
    /// 小时数。**由调用点传 `ExternalGameRecord.displayHours`** —— 取整规则在模型上只有那一处。
    var hours: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: ExternalCardStyle.blockSpacing) {
            ExternalSourceHeader(brandName: AccountProvider.nintendo.brandName,
                                 sourceName: sourceName)
            PlayActivityStatsRow(firstPlayedAt: firstPlayedAt,
                                 lastPlayedAt: lastPlayedAt,
                                 hours: hours)
        }
        .padding(ExternalCardStyle.contentPadding)
        // ⚠️ 宽度上限必须**在 `appPanelSurface()` 之前**：顺序反过来的话面板会先铺满整宽，
        // 再在满宽的面板上画一条窄内容 —— 看起来就是「这块面板左边挤了三个数字」。
        .frame(maxWidth: ExternalCardStyle.maxWidth, alignment: .leading)
        .appPanelSurface()
    }
}
