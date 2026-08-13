import Foundation
import SwiftData

/// 六维评分维度。顺序即全局显示顺序（滑块 / 条形图 / 分享卡一致）。
enum Dimension: String, CaseIterable, Identifiable {
    case gameplay
    case design
    case story
    case art
    case music
    case performance

    var id: String { rawValue }

    /// 本地化 key，见 Localizable.strings（dimension.story 等）。
    var labelKey: String { "dimension.\(rawValue)" }
}

/// 一个游戏（库条目）。创建时带首条通关记录，之后可追加。
/// 多语言名字：`name` 为英文名（必须、canonical），`nameZh`/`nameJa` 可选；
/// 展示时按当前语言用 `displayName(for:)` 回退（中文→nameZh??name，日文→nameJa??name，英文→name）。
@Model
final class Game {
    /// 英文名（必须，存储 canonical；展示按语言回退）。
    var name: String
    /// 中文名（可选）。
    var nameZh: String?
    /// 日文名（可选）。
    var nameJa: String?
    var aliases: [String]
    var releaseDate: Date?
    var coverData: Data?
    var reviewTitle: String
    var reviewBody: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Completion.game)
    var completions: [Completion]

    /// 多对多：一个游戏可进多个分组。删除游戏不应级联删分组（分组可能属于其他游戏）。
    @Relationship(deleteRule: .nullify, inverse: \GameGroup.games)
    var groups: [GameGroup]

    init(name: String, nameZh: String? = nil, nameJa: String? = nil,
         aliases: [String] = [], releaseDate: Date? = nil,
         coverData: Data? = nil, reviewTitle: String = "", reviewBody: String = "",
         createdAt: Date = .now) {
        self.name = name
        self.nameZh = nameZh
        self.nameJa = nameJa
        self.aliases = aliases
        self.releaseDate = releaseDate
        self.coverData = coverData
        self.reviewTitle = reviewTitle
        self.reviewBody = reviewBody
        self.createdAt = createdAt
        self.completions = []
        self.groups = []
    }
}

// MARK: - 派生计算

extension Game {

    /// 按当前语言的显示名：中文→中文名（未设回退英文），日文→日文名（未设回退英文），英文→英文名。
    func displayName(for language: String) -> String {
        switch language {
        case "zh-Hans": return nameZh ?? name
        case "ja": return nameJa ?? name
        default: return name
        }
    }

    /// 通关记录按时间正序。
    var sortedCompletions: [Completion] {
        completions.sorted { $0.createdAt < $1.createdAt }
    }

    /// 最近一次通关日期（用于排序）。全部记录都无日期则 nil（排序时排最后）。
    var latestCompletionDate: Date? {
        completions.compactMap(\.date).max()
    }

    /// 该游戏出现过的所有平台，去重；按平台预设的世代倒序排列，预设外的自定义值按字典序排在最后。
    var platformList: [String] {
        Presets.ordered(completions.map(\.platform))
    }

    /// 库显示分：已评分记录平均分的均值，取整到 0.5。无已评分记录则 nil。
    var libraryScore: Double? {
        libraryScore(platform: nil)
    }

    /// 库显示分（可限定某平台：只统计该平台下的通关记录）。
    func libraryScore(platform: String?) -> Double? {
        let averages = completions
            .filter { (platform == nil || $0.platform == platform) && $0.hasScores }
            .compactMap(\.recordAverage)
        return ScoreMath.libraryScore(recordAverages: averages)
    }

    /// 库内所有已评分记录平均分的原始均值（不取整）。无则 nil。排行榜按平均分排序用原始值，展示用取整值。
    func rawLibraryScore(platform: String?) -> Double? {
        let averages = completions
            .filter { (platform == nil || $0.platform == platform) && $0.hasScores }
            .compactMap(\.recordAverage)
        guard !averages.isEmpty else { return nil }
        return averages.reduce(0, +) / Double(averages.count)
    }

    /// 某维度在已评分记录上的均值（1–10），与 libraryScore 同一套已评分口径。无则 nil。
    func dimensionAverage(for dimension: Dimension) -> Double? {
        dimensionAverage(for: dimension, platform: nil)
    }

    /// 某维度均值（可限定某平台：只统计该平台下的通关记录）。
    func dimensionAverage(for dimension: Dimension, platform: String?) -> Double? {
        let values = completions
            .filter { (platform == nil || $0.platform == platform) && $0.hasScores }
            .compactMap { $0.score(for: dimension) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// 搜索文本：英文名 + 中文/日文名 + 全部别名，小写化。
    var searchableText: String {
        ([name] + [nameZh, nameJa].compactMap { $0 } + aliases)
            .map { $0.lowercased() }
            .joined(separator: " ")
    }

    /// 按名称或别名模糊匹配。
    func matches(search: String) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return true }
        return searchableText.contains(query)
    }
}
