import SwiftUI

// MARK: - 奖杯进度（值类型）
//
// 归属说明：奖杯是 **PlayStation 独有的来源事实**（Nintendo 没有奖杯体系），
// 只挂在 `ExternalGameRecord` 上，不进 `Game`。这一组数值要么全有、要么全无
// （来自同一个响应对象），所以用一个值类型承载，调用点不散着拼 9 个字段。

/// 一个标题的奖杯进度。
///
/// `percent` 用 `Int?` 有两层意思：
/// - 整个 `TrophyProgress` 为 `nil` = **这条记录没有奖杯数据**（Nintendo 全部、
///   PSN 里没匹配上奖杯套的那些）—— 与「0 个奖杯」是两件事，同 `playedSeconds` 的纪律。
/// - `percent` 单独为 `nil` = 来源这次没给百分比，用计数现算（见 `displayPercent`）。
struct TrophyProgress: Equatable, Hashable {
    var platinumEarned = 0
    var goldEarned = 0
    var silverEarned = 0
    var bronzeEarned = 0
    var platinumDefined = 0
    var goldDefined = 0
    var silverDefined = 0
    var bronzeDefined = 0
    /// 来源给的完成百分比（PSN 的 `progress`）。
    var percent: Int?

    func earned(_ grade: TrophyGrade) -> Int {
        switch grade {
        case .platinum: platinumEarned
        case .gold: goldEarned
        case .silver: silverEarned
        case .bronze: bronzeEarned
        }
    }

    func defined(_ grade: TrophyGrade) -> Int {
        switch grade {
        case .platinum: platinumDefined
        case .gold: goldDefined
        case .silver: silverDefined
        case .bronze: bronzeDefined
        }
    }

    /// 已获得总数。
    var earnedTotal: Int { platinumEarned + goldEarned + silverEarned + bronzeEarned }
    /// 奖杯套总数（包含白金，所以「白金 0/0」的游戏总数就是 金+银+铜）。
    var definedTotal: Int { platinumDefined + goldDefined + silverDefined + bronzeDefined }
    /// 还差几个。负数只可能来自服务端自相矛盾的数据，夹到 0。
    var remaining: Int { max(0, definedTotal - earnedTotal) }

    /// 展示用的百分比整数：**来源给了就用来源的**（PSN 的 `progress` 是索尼自己算的，
    /// 与「已得/总数」可能不一致 —— 差异本身是来源的事实，不该由我们悄悄改掉），
    /// 否则按计数现算。
    var displayPercent: Int {
        if let percent { return min(100, max(0, percent)) }
        guard definedTotal > 0 else { return 0 }
        return min(100, max(0, Int((Double(earnedTotal) / Double(definedTotal) * 100).rounded())))
    }

    // ⚠️ 这里曾有一个 `fraction`（`Double(displayPercent) / 100`），2026-09-18 删掉：
    //    环改走共用的 `ExternalRing`，而它**只收 `displayPercent`**、比例自己现算 ——
    //    「环画到哪」与「中心那行字」从此在构造上就不可能是两个数。没人读的字段不留。
}

// MARK: - 奖杯等级

/// 四个奖杯等级。
///
/// **配色与图标的唯一归属**（同 `StatusStyle` / `TagLabel` / `SurfaceStyle` 的口径）：
/// 新调用点从这里取色取图，别在视图里另写一套。
///
/// ⚠️ **图标目前是 SF Symbol 占位**。用户会提供 PlayStation 官方的白金/金/银/铜图标资源，
/// 到那时**只改 `TrophyIcon` 这一个视图的内部实现**（换成 `Image("trophy.gold")` 之类），
/// 其余调用点一行不动。颜色取自用户给的模版截图，届时若官方图标自带配色，也一并在这里对齐。
enum TrophyGrade: String, CaseIterable, Identifiable, LabelKeyed {
    case platinum
    case gold
    case silver
    case bronze

    var id: String { rawValue }
    var labelKey: String { "game.trophy.\(rawValue)" }

    /// 等级主题色（模版截图取色）。
    var tint: Color {
        switch self {
        case .platinum: Color(red: 0.624, green: 0.714, blue: 0.800)   // #9FB6CC
        case .gold: Color(red: 0.851, green: 0.643, blue: 0.255)       // #D9A441
        case .silver: Color(red: 0.576, green: 0.639, blue: 0.722)     // #93A3B8
        case .bronze: Color(red: 0.663, green: 0.463, blue: 0.294)     // #A9764B
        }
    }

    /// 占位图形。白金是奖杯（杯），其余三种是奖牌 —— 与模版截图的形状语言一致，
    /// 所以在官方图标到位之前，**形状已经能区分等级，颜色只是加强**。
    var symbolName: String {
        switch self {
        case .platinum: "trophy.fill"
        case .gold, .silver, .bronze: "medal.fill"
        }
    }
}

/// 等级图标。**换官方图标的唯一出口**（见 `TrophyGrade` 的说明）。
struct TrophyIcon: View {
    let grade: TrophyGrade
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: grade.symbolName)
            .font(.system(size: size))
            .foregroundStyle(grade.tint)
    }
}

// ⚠️ 这里曾有一个 `TrophyStyle`（环的颜色/尺寸 + 三档宽屏断点），2026-09-18 拆掉：
//  - 环的颜色与尺寸 → `ExternalRingStyle`（`Support/ExternalCardStyle.swift`）。
//    Xbox 成就卡也要一个环之后，把环画法留在叫「Trophy」的枚举里就是个假名字 ——
//    两张卡上下紧挨着摆，环必须逐像素同源，所以合并成一处、两个来源都引用它。
//  - 三档断点（`wideBreakpoint` / `wideGridMaxWidth` / `threeZoneBreakpoint`）→ 删。
//    断点存在的前提是奖杯卡铺满整宽；现在三张卡统一封顶 `ExternalCardStyle.maxWidth`
//    （用户 2026-09-18：「宽度相当」「特别是收窄 playstation 的卡片宽度」），
//    卡片内容区最多 486pt，永远到不了 600 的两栏线 —— 留着就是一整段跑不到的死代码。
//    那些断点当初要解决的问题（铺满 924pt 时一条又宽又空的横带）随着封顶本身消失了。
