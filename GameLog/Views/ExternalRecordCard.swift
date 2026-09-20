import SwiftUI

// 这个文件放的是**三张外部来源卡片共用的零件**：
//   PSN 记录 → `TrophyProgressView`（奖杯卡）
//   Nintendo 记录 → `PlayActivityView`（游玩记录卡）
//   Xbox 记录 → `XboxAchievementView`（成就卡）
// 三张卡在详情页里并列摆在同一块区域（见 `GameDetailView.externalActivitySection`），
// 长得也必须像一家人 —— 所以「头部」「一格统计」「游玩三项」各只有一份实现。

/// 外部来源卡片的头部：左「品牌名（+ 可选副标题）」、右「来源：xxx」。
///
/// 品牌名是**专有名词**（`AccountProvider.brandName`），三语原样显示、不进 L10n
/// （见 `AccountProvider` 上的说明）。副标题是奖杯卡专有的「哪个版本」（`PS3/PS4 · NPWR-08547`），
/// Nintendo 卡不传。
///
/// ⚠️ 外层是 `HStack(alignment: .firstTextBaseline)`：`VStack` 的基线取第一行（品牌名）的基线，
/// 所以右侧「来源：xxx」与品牌名同一条基线 —— 有没有副标题，右边那段的垂直位置都不动。
struct ExternalSourceHeader: View {
    @Environment(\.appLanguageCode) private var language

    let brandName: String
    /// 来源侧游戏原始标题。nil / 空 = 不渲染那一行。
    var titleName: String?
    /// 副标题（平台与编号，如 `PS3/PS4 · NPWR-08547`、`Xbox One` 或 `Nintendo Switch`）。nil / 空 = 不渲染那一行。
    var subtitle: String?
    /// 来源账号展示名。nil / 空 = 不渲染「来源：」。
    var sourceName: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: brandName)
                    .font(.subheadline.weight(.semibold))
                if let titleName, !titleName.isEmpty {
                    Text(verbatim: titleName)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(verbatim: subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let sourceName, !sourceName.isEmpty {
                Text(verbatim: L10n.tr("game.activity.source", [sourceName], lang: language))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }
}

/// 一格统计（标签 + 值），三张外部来源卡共用。
///
/// 抽出来的理由只有一条：**「缺值显示 `—`」这个口径只能有一处**。三张卡各有自己的格
///（奖杯三项 / 成就四项 / 游玩三项），各写一份的话，「来源不提供」迟早会在其中一张上
/// 变成空白或 `0`（`0` 与「没有数据」的区别是本项目一条贯穿始终的纪律）。
///
/// 一格之所以带 `minimumScaleFactor`：格宽在现在的卡片（`ExternalCardStyle.maxWidth` = 412）
/// 里约 128pt（三项一行）/ 156pt（2×2），中文标签 + 数字放得下，但放大字体 / 日语长标签
/// （`プラチナ`）就放不下 ——
/// 缩字比换行好（换行会把一行里的格子高低弄乱）。
struct ExternalStatCell: View {
    @Environment(\.appLanguageCode) private var language

    /// 标签的 L10n key。**不给默认值**：每一格的标签都必须是有意选的。
    let labelKey: String
    /// 值。nil = 来源不提供 → 显示 `—`（不是空、不是 0）。
    let value: String?

    var body: some View {
        VStack(spacing: 2) {
            Text(verbatim: L10n.tr(labelKey, lang: language))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(verbatim: value ?? "—")
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// 「首次游玩 / 最近游玩 / 游玩时长」一行（等宽三列、内容居中）。
///
/// 两个调用点（奖杯卡 `TrophyProgressView` 与游玩记录卡 `PlayActivityView`）现在
/// **都传三个值、不传别的** —— 三项均分整宽。这里曾经有个 `trailingPlaceholder`
/// 参数，给奖杯卡补一个空列，好让三项与它上面那行的四格逐列对齐；
/// 2026-09-18 奖杯卡的四格改成「环右边的 2×2」之后**那条对齐关系不存在了**，
/// 参数随之删除（留着一个只有 `false` 一个取值的开关，是在说一件假话）。
///
/// 某一项缺失显示 `—` 而不是把那一格去掉：这是**对齐的栅格**，挖掉一格会让剩下两格的位置
/// 随数据漂移。`—` 是本项目「来源不提供」的既有写法。
///
/// 列间距走 `ExternalCardStyle.gridSpacing`：这一行在奖杯卡里**紧贴着上面那 2×2**，
/// 两行各写一个间距数就会出现「上面四格的缝比下面三格的缝窄」—— 同一个文件里的两行同宽栅格，
/// 缝隙必须一样宽。
struct PlayActivityStatsRow: View {
    @Environment(\.appLanguageCode) private var language

    var firstPlayedAt: Date?
    var lastPlayedAt: Date?
    /// 小时数。**由调用点传 `ExternalGameRecord.displayHours`**（取整规则在模型上只有那一处）。
    var hours: Int?

    @ViewBuilder
    var body: some View {
        if PlayActivity.hasAny(firstPlayedAt: firstPlayedAt, lastPlayedAt: lastPlayedAt, hours: hours) {
            HStack(alignment: .top, spacing: ExternalCardStyle.gridSpacing) {
                ExternalStatCell(labelKey: "game.activity.firstPlayed",
                                 value: firstPlayedAt.map(PlayActivity.dayText))
                ExternalStatCell(labelKey: "game.activity.lastPlayed",
                                 value: lastPlayedAt.map(PlayActivity.dayText))
                ExternalStatCell(labelKey: "game.activity.playtime",
                                 value: hours.map { PlayActivity.hoursText($0, language: language) })
            }
        }
    }
}
