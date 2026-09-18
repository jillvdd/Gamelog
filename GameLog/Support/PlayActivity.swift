import Foundation

/// 「首次游玩 / 最近游玩 / 游玩时长」这三项的**唯一归属**。
///
/// 三项不是 PlayStation 的专利：PSN 的奖杯卡把它排在四格之下，Nintendo 的游玩记录卡
/// 把它当**全部**内容（任天堂只有时长与两个日期，没有奖杯体系）。
/// 两张卡共用这一份口径 —— 「缺值显示什么」「日期什么格式」「时长怎么拼单位」
/// 各写一遍的话，同一个事实在两个来源的卡上迟早读出两个样子。
///
/// 值本身仍由调用点从 `ExternalGameRecord` 上取（`firstPlayedAt` / `lastPlayedAt` /
/// `displayHours`）：**取整规则在 `displayHours`，这里不再算一遍**。
enum PlayActivity {

    /// 三项是否至少有一项有值。全无时那一行 / 那张卡整块不渲染。
    ///
    /// 两个调用点：`ExternalGameRecord.showsPlayActivityCard`（这张卡该不该出现）
    /// 与 `PlayActivityStatsRow`（这一行该不该画）。
    static func hasAny(firstPlayedAt: Date?, lastPlayedAt: Date?, hours: Int?) -> Bool {
        firstPlayedAt != nil || lastPlayedAt != nil || hours != nil
    }

    /// 日期文本。与 `ExternalRecordRow.metaText` 同一档（`\.abbreviated`，随 app 语言本地化）。
    ///
    /// **不为了塞进窄格子换更短的格式**：同一个事实在账号记录行与这两张卡上必须读起来一样。
    /// 空间不够由 `PlayActivityStatsRow` 的 `minimumScaleFactor` 收字，不改口径。
    static func dayText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    /// 时长文本（`189 小时` / `189 h` / `189 時間`）。
    ///
    /// 单位走 `account.detail.hours` —— 那条 key 是「数字 + 小时单位」的**唯一归属**，
    /// 三个调用点（账号记录行 / 关联选择器 / 这两张卡）共用同一份三语文案。
    /// key 名里的 `account.detail.` 是历史包袱，**值本身与来源无关**，
    /// 所以不为了让名字好看再复制一份字符串出来（复制就会漂移）。
    static func hoursText(_ hours: Int, language: String) -> String {
        L10n.tr("account.detail.hours", [hours], lang: language)
    }
}

// ⚠️ 这里曾有一个 `PlayActivityStyle`（只有 `cardMaxWidth = 380` 一个成员），
//    2026-09-18 删掉：三张外部来源卡统一封顶 `ExternalCardStyle.maxWidth`（510）——
//    用户要的是「内容密度，空白程度，宽度相当」。380 那个值当初的道理
//    （「三项各约 118pt 才放得下 2023年7月5日」）在新的宽度下仍然成立：
//    510 − 左右各 12 内边距 − 3×6 间距 = 468，四列栅格（第四列留空）每格约 117pt。

