import Foundation

/// 库级派生统计的**唯一**归属（2026-08-29 深化）。
/// 此前两族聚合在各视图体内重推：收藏汇总 ×2（HoldingsView / StatsView，注释自认「各自实现」）、
/// 平台计数 ×3（RootView / StatsView / GroupFooter）、在用平台 ×3（RootView / iOSRootView /
/// GroupGamePickerView）、统计页瓦片内联（StatsView）——语义改动只能 grep 找点，且全部
/// 不可测试。深化后一处算、多处用、DataSmokeTest 全覆盖。
///
/// 语义约定（全部为现状保真，勿在此「顺手」改口径）：
/// - 平台计数 = 游戏 × 平台（`platformList`，每游戏每平台计 1；未通关游戏也有游戏级平台）。
/// - platformCounts 平级裁决 = 数量降序 + 平台名升序（§27 修过的「同数量横跳」bug 定案，固化不参数化）。
/// - 收藏汇总「未填跳过」：某语言价格/估值未填不计入（是 nil 不是 0）；全未填 = nil（显示「—」）。
enum LibraryStats {

    // MARK: - 平台聚合

    /// 库里出现过的平台（预设世代倒序 + 自定义字母排最后的全局排序）。
    static func platformsInUse(_ games: [Game]) -> [String] {
        Presets.ordered(games.flatMap(\.platformList))
    }

    /// 平台 → 去重游戏数（游戏 × 平台计数）。
    static func platformCounts(_ games: [Game]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for game in games {
            for platform in game.platformList {
                counts[platform, default: 0] += 1
            }
        }
        return counts
    }

    /// 平台分布行（已按「数量降序 + 名称升序」稳定裁决排序，直接渲染）。
    static func platformDistribution(_ games: [Game]) -> [(platform: String, count: Int)] {
        platformCounts(games)
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { (platform: $0.key, count: $0.value) }
    }

    // MARK: - 收藏汇总（一组持有档案 → 四格）

    struct CollectorTotals {
        /// 持有档案条数（同名版本是独立档案，各计一条）。
        let editionCount: Int
        /// 总数量（Σ count）。
        let totalQuantity: Int
        /// 总花费（按语言；全未填 = nil）。
        let totalSpent: Double?
        /// 总估值（按语言；全未填 = nil）。
        let totalEstimate: Double?
    }

    /// 一组持有档案的收藏汇总（HoldingsView 传 game.copies、StatsView 传全库 flatMap）。
    static func collectorTotals(_ copies: [PhysicalCopy], language: String) -> CollectorTotals {
        let spent = copies.compactMap { $0.price(for: language) }
        let estimate = copies.compactMap { $0.estValue(for: language) }
        return CollectorTotals(
            editionCount: copies.count,
            totalQuantity: copies.reduce(0) { $0 + $1.count },
            totalSpent: spent.isEmpty ? nil : spent.reduce(0, +),
            totalEstimate: estimate.isEmpty ? nil : estimate.reduce(0, +)
        )
    }

    // MARK: - 统计页瓦片

    /// 想玩清单数量（status == backlog 的游戏数）。
    static func backlogCount(_ games: [Game]) -> Int {
        games.filter { $0.statusValue == .backlog }.count
    }

    /// 库平均分：库内每条已评分通关记录的六维平均分之均值，取整到 0.1
    /// （单条记录按六维评分求均值，一条通关记录计一次；无已评分记录 = nil）。
    static func averageScore(_ games: [Game]) -> Double? {
        let averages = games
            .flatMap(\.completions)
            .compactMap(\.recordAverage)
        guard !averages.isEmpty else { return nil }
        return ScoreMath.roundScore(averages.reduce(0, +) / Double(averages.count))
    }
}
