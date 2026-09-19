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

    // MARK: - 统计页瓦片与核心指标

    /// 想玩清单数量（status == backlog 的游戏数）。
    static func backlogCount(_ games: [Game]) -> Int {
        games.filter { $0.statusValue == .backlog }.count
    }

    /// 在玩游戏数（status == playing 的游戏数）。
    static func playingCount(_ games: [Game]) -> Int {
        games.filter { $0.statusValue == .playing }.count
    }

    /// 已通关/长线游玩的游戏数（有通关记录，或状态为 completed / longRunning）。
    static func clearedGameCount(_ games: [Game]) -> Int {
        games.filter { $0.isCompletedOrLongRunning || !$0.completions.isEmpty }.count
    }

    /// 通关率（0~100 百分比数值；库为空时返回 nil）。
    static func completionRate(_ games: [Game]) -> Double? {
        guard !games.isEmpty else { return nil }
        return (Double(clearedGameCount(games)) / Double(games.count)) * 100.0
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

    /// 已评分的游戏数量。
    static func scoredGameCount(_ games: [Game]) -> Int {
        games.filter { $0.libraryScore != nil }.count
    }

    // MARK: - 游玩时长与体量分布

    /// 单款游戏的总有效游玩时长（小时）：通关记录累加优先；无记录时降级到外部账号记录时长。
    static func gamePlaytime(_ game: Game) -> Double? {
        let loggedHours = game.completions.compactMap(\.playtime).reduce(0, +)
        if loggedHours > 0 { return loggedHours }
        let extHours = game.externalRecords.compactMap(\.playedHours).reduce(0, +)
        return extHours > 0 ? extHours : nil
    }

    /// 全库累计总游玩时长（小时，四舍五入到一位小数）。
    static func totalPlaytimeHours(_ games: [Game]) -> Double {
        let sum = games.compactMap(gamePlaytime).reduce(0, +)
        return (sum * 10).rounded() / 10
    }

    /// 平均单款通关时长（小时，仅针对有时长的游戏计算均值，一位小数；无时长数据返回 nil）。
    static func averagePlaytimeHours(_ games: [Game]) -> Double? {
        let hours = games.compactMap(gamePlaytime).filter { $0 > 0 }
        guard !hours.isEmpty else { return nil }
        let avg = hours.reduce(0, +) / Double(hours.count)
        return (avg * 10).rounded() / 10
    }

    /// 游玩体量区间（5 档）。
    struct PlaytimeBucket: Identifiable {
        let id: String
        let labelKey: String
        let rangeLabel: String
        let count: Int
    }

    /// 游玩体量梯队分布（<10h、10-30h、30-60h、60-100h、100h+）。
    static func playtimeBuckets(_ games: [Game]) -> [PlaytimeBucket] {
        let times = games.compactMap(gamePlaytime).filter { $0 > 0 }
        let b1 = times.filter { $0 < 10 }.count
        let b2 = times.filter { $0 >= 10 && $0 < 30 }.count
        let b3 = times.filter { $0 >= 30 && $0 < 60 }.count
        let b4 = times.filter { $0 >= 60 && $0 < 100 }.count
        let b5 = times.filter { $0 >= 100 }.count

        return [
            PlaytimeBucket(id: "micro", labelKey: "stats.tierMicro", rangeLabel: "< 10h", count: b1),
            PlaytimeBucket(id: "standard", labelKey: "stats.tierStandard", rangeLabel: "10-30h", count: b2),
            PlaytimeBucket(id: "medium", labelKey: "stats.tierMedium", rangeLabel: "30-60h", count: b3),
            PlaytimeBucket(id: "deep", labelKey: "stats.tierDeep", rangeLabel: "60-100h", count: b4),
            PlaytimeBucket(id: "epic", labelKey: "stats.tierEpic", rangeLabel: "100h+", count: b5)
        ]
    }

    // MARK: - 攻关深度与跨平台成就

    /// 通关程度分布（聚合 degree 字段，降序）。
    static func completionDegreeDistribution(_ games: [Game]) -> [(degree: String, count: Int)] {
        var counts: [String: Int] = [:]
        for game in games {
            for comp in game.completions {
                let deg = comp.degree.trimmingCharacters(in: .whitespacesAndNewlines)
                if !deg.isEmpty {
                    counts[deg, default: 0] += 1
                }
            }
        }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { (degree: $0.key, count: $0.value) }
    }

    /// 跨平台成就聚合：全平台白金奖杯数、Xbox Gamerscore 总点数。
    static func unifiedAchievements(_ games: [Game]) -> (platinumCount: Int, xboxGamerscore: Int) {
        var platinums = 0
        var gamerscore = 0
        for game in games {
            for record in game.externalRecords {
                if let plat = record.trophies?.platinumEarned {
                    platinums += plat
                }
                if let gs = record.gamerscoreEarned {
                    gamerscore += gs
                }
            }
        }
        return (platinums, gamerscore)
    }

    // MARK: - 常玩厂商与工作室

    /// 常玩开发商 Top N（按游戏数降序，同数按均分降序）。
    static func topDevelopers(_ games: [Game], limit: Int = 5) -> [(name: String, count: Int, avgScore: Double?)] {
        var devGames: [String: [Game]] = [:]
        for game in games {
            guard let dev = game.developer?.trimmingCharacters(in: .whitespacesAndNewlines), !dev.isEmpty else { continue }
            devGames[dev, default: []].append(game)
        }
        return devGames.map { (name, gList) in
            let scores = gList.compactMap(\.libraryScore)
            let avg: Double? = scores.isEmpty ? nil : ScoreMath.roundScore(scores.reduce(0, +) / Double(scores.count))
            return (name: name, count: gList.count, avgScore: avg)
        }
        .sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return ($0.avgScore ?? 0) > ($1.avgScore ?? 0)
        }
        .prefix(limit)
        .map { $0 }
    }

    // MARK: - 收藏家扩展分析

    /// 估值最高的前 N 款实体藏品。
    static func topValuedCopies(_ copies: [PhysicalCopy], language: String, limit: Int = 3) -> [(copy: PhysicalCopy, value: Double)] {
        copies.compactMap { copy -> (PhysicalCopy, Double)? in
            guard let val = copy.estValue(for: language), val > 0 else { return nil }
            return (copy, val)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(limit)
        .map { $0 }
    }

    /// 介质分布统计（实体标准/特别/限定/数字/周边等）。
    static func mediaDistribution(_ copies: [PhysicalCopy]) -> [(media: CopyMedia, count: Int)] {
        var counts: [CopyMedia: Int] = [:]
        for copy in copies {
            counts[copy.media, default: 0] += copy.count
        }
        return counts.sorted { $0.value > $1.value }
            .map { (media: $0.key, count: $0.value) }
    }
}
