import Foundation
import SwiftData

/// 四维评分维度。
enum Dimension: String, CaseIterable, Identifiable {
    case story
    case graphics
    case music
    case gameplay

    var id: String { rawValue }

    /// 本地化 key，见 Localizable.strings（dimension.story 等）。
    var labelKey: String { "dimension.\(rawValue)" }
}

/// 一个游戏（库条目）。创建时带首条通关记录，之后可追加。
@Model
final class Game {
    var name: String
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

    init(name: String, aliases: [String] = [], releaseDate: Date? = nil,
         coverData: Data? = nil, reviewTitle: String = "", reviewBody: String = "",
         createdAt: Date = .now) {
        self.name = name
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

    /// 通关记录按时间正序。
    var sortedCompletions: [Completion] {
        completions.sorted { $0.createdAt < $1.createdAt }
    }

    /// 最近一次通关日期（用于排序）。没有记录时 nil。
    var latestCompletionDate: Date? {
        completions.map(\.date).max()
    }

    /// 该游戏出现过的所有平台，去重；按平台预设的世代倒序排列，预设外的自定义值按字典序排在最后。
    var platformList: [String] {
        let order = Dictionary(
            uniqueKeysWithValues: Presets.platforms.enumerated().map { ($0.element, $0.offset) }
        )
        let unique = Set(completions.map(\.platform).filter { !$0.isEmpty })
        return unique.sorted { a, b in
            switch (order[a], order[b]) {
            case (nil, nil): return a < b
            case (nil, _): return false
            case (_, nil): return true
            case (let ia?, let ib?): return ia < ib
            }
        }
    }

    /// 库显示分：已评分记录平均分的均值，取整到 0.5。无已评分记录则 nil。
    var libraryScore: Double? {
        let averages = completions
            .filter(\.hasScores)
            .compactMap(\.recordAverage)
        return ScoreMath.libraryScore(recordAverages: averages)
    }

    /// 某维度在已评分记录上的均值（1–10），与 libraryScore 同一套已评分口径。无则 nil。
    func dimensionAverage(for dimension: Dimension) -> Double? {
        let values = completions
            .filter(\.hasScores)
            .compactMap { $0.score(for: dimension) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// 搜索文本：名称 + 全部别名，小写化。
    var searchableText: String {
        ([name] + aliases).map { $0.lowercased() }.joined(separator: " ")
    }

    /// 按名称或别名模糊匹配。
    func matches(search: String) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return true }
        return searchableText.contains(query)
    }
}
