import Foundation

// =============================================================================
//  Xbox 成就（成就数 + Gamerscore + 那张成就卡）
//
//  ⚠️ 成就是 **Xbox 独有的来源事实**，与 PSN 的奖杯（`TrophyProgress` / `TrophyStyle`）
//      是**两套互不折算**的体系 —— 见 `AchievementProgress` 的说明。
// =============================================================================

/// 一个标题的 Xbox 成就进度。
///
/// **与 `TrophyProgress` 是两套东西，绝不互相折算**：奖杯是索尼的分级体系
///（白金/金/银/铜，一个套有固定总数），成就是微软的点数体系（每个成就 5–100 点，
/// 成就数与点数都由发行方自己定）。同一个游戏在两个平台上的「完成度」本来就不同，
/// 折算只会在界面上产生一个两边都不对的数。
///
/// 值本身**只是来源给的四个计数**（`/v2/titles` 的 `achievement` 对象），
/// 唯一的派生值是环要用的那个百分比（`gamerscorePercent`）—— 成就卡上有一个
/// Gamerscore 完成度的环（2026-09-18 用户要求「xbox也要一个百分比环用来凸显
/// 已经获得的 gamerscore」）。除此之外不派生任何东西：「还差几个成就」这类
/// 目前没有人读的字段不留（同 `XboxAccountIdentity.hasRealGamertag` 那条纪律）。
struct AchievementProgress: Equatable, Hashable {
    /// 已获得的成就数。`0` 是合法状态（有成就套但一个都没拿到），不是「没有数据」。
    var earned: Int
    /// 成就总数。
    var total: Int
    /// 已获得的 Gamerscore（微软的点数）。
    var gamerscoreEarned: Int
    /// Gamerscore 总数。
    var gamerscoreTotal: Int

    /// 四个可空原始值 → 进度。**四个都缺 → nil**（= 这条没有成就数据）。
    ///
    /// 为什么不返回一个全 0 的值：全 0 是「有成就套但一个都没拿到」的合法状态，
    /// 两者在界面上必须长得不一样（`—` vs `0 / 52`）—— 同 `TrophyProgress` 与
    /// `playedSeconds` 的纪律。
    ///
    /// 为什么在**值类型**上收口（而不是让 `ExternalGameRecord.achievements` 与
    /// `XboxGameService` 各拼一遍）：四个可空字段的组装规则只能有一处，否则
    /// 「四个都缺算不算有数据」会在两条路径上给出两个答案。
    ///
    /// 负数（服务端自相矛盾）按 0 收 —— 同 `PSNAPI.trophyProgress` 对负数的处理。
    /// **不整条丢掉**：一个负分不该把同一响应里其余三个正确的数一起判死。
    init?(earned: Int?, total: Int?, gamerscoreEarned: Int?, gamerscoreTotal: Int?) {
        guard [earned, total, gamerscoreEarned, gamerscoreTotal].contains(where: { $0 != nil })
        else { return nil }
        self.earned = max(0, earned ?? 0)
        self.total = max(0, total ?? 0)
        self.gamerscoreEarned = max(0, gamerscoreEarned ?? 0)
        self.gamerscoreTotal = max(0, gamerscoreTotal ?? 0)
    }

    /// 「成就」那一格的值：`25 / 52`。
    ///
    /// 总数 0 → nil（格子显示 `—`）。Xbox 上确实有条目带 `totalAchievements = 0`
    /// （没有成就的游戏/应用），那时写 `0 / 0` 看起来像坏了。
    ///
    /// **不按语言加千位分隔符**：同一个 Xbox 库里 Gamerscore 总数现实上限在四位数，
    /// 而三格的邻居（`25 / 52`、`189 小时`、`2026年9月15日`）都不分组 ——
    /// 给其中一格加一个随**系统** locale 漂移的分隔符，只会让这一格成为异类。
    var achievementsText: String? { total > 0 ? "\(earned) / \(total)" : nil }

    /// 「游戏分数」那一格的值：`1240 / 2000`。总数 0 → nil（同上）。
    var gamerscoreText: String? {
        gamerscoreTotal > 0 ? "\(gamerscoreEarned) / \(gamerscoreTotal)" : nil
    }

    /// **Gamerscore 完成度的整数百分比**（环要用的那个 0…100）。
    ///
    /// 为什么量 Gamerscore 而不是成就数：用户点名的就是 gamerscore
    /// （「凸显已经获得的 gamerscore」）。两者在真实数据上并不相等 ——
    /// 每个成就 5–100 点、由发行方自定，拿满一半成就完全可能只拿到三成分。
    ///
    /// **总分为 0 → nil**（不是 `0%`）。`totalGamerscore = 0` 在 Xbox 上确实存在
    /// （没有成就的游戏 / 应用），而「有成就套但一分没拿」是另一种合法状态 —— 两者在环上
    /// 必须长得不一样：前者**整只环不画**，后者画一只空槽。同 `gamerscoreText` 返回 nil 的口径。
    ///
    /// 已得 > 总数（服务端自相矛盾）夹到 100%，不画出一只超过一圈的环。
    /// 环的**比例**由 `ExternalRing` 从这个整数现算 —— 中心那行字与弧长因此永远一致。
    var gamerscorePercent: Int? {
        guard gamerscoreTotal > 0 else { return nil }
        let ratio = Double(min(gamerscoreEarned, gamerscoreTotal)) / Double(gamerscoreTotal)
        return min(100, max(0, Int((ratio * 100).rounded())))
    }

    /// 这两格**至少有一格会印出真数字**（而不是 `—`）。
    ///
    /// 存在的理由：「四格全是 `—`」与「四格全空」在界面上一样糟 —— 而 Xbox 上确实有条目
    /// 带 `totalAchievements = 0` 与 `totalGamerscore = 0`（没有成就的游戏 / 应用），
    /// 那种条目**有** `achievement` 对象、却不该因此判成「有内容」。所以成就卡的入场判据
    ///（`ExternalGameRecord.showsXboxAchievementCard`）判的是这个，不是 `!= nil`。
    var hasDisplayableValue: Bool { achievementsText != nil || gamerscoreText != nil }
}

// ⚠️ 这里曾有一个 `AchievementStyle`（只有 `cardMaxWidth = 510` 一个成员），
//    2026-09-18 删掉：三张外部来源卡统一封顶 `ExternalCardStyle.maxWidth`（`Support/ExternalCardStyle.swift`）。
//    510 本来就是从这张卡定的（用户点名要的「中等宽度」），现在成了三张卡共用的值。

