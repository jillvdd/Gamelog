import Foundation
import SwiftData

/// 一次通关记录。挂在 Game 下，可追加多条。
/// 六维评分整体可选：首条记录必填，之后可跳过；跳过时六个分全部为 nil。
@Model
final class Completion {
    var platform: String
    /// 通关日期。nil = 无（不记得/长线运营无固定通关，界面显示 None）。
    var date: Date?
    var degree: String
    var playtime: Double?
    var notes: String
    var scoreGameplay: Double?
    var scoreDesign: Double?
    var scoreStory: Double?
    var scoreArt: Double?
    var scoreMusic: Double?
    var scorePerformance: Double?
    var createdAt: Date
    var game: Game?

    init(platform: String, date: Date?, degree: String, playtime: Double? = nil,
         notes: String = "", scoreGameplay: Double? = nil, scoreDesign: Double? = nil,
         scoreStory: Double? = nil, scoreArt: Double? = nil, scoreMusic: Double? = nil,
         scorePerformance: Double? = nil, createdAt: Date = .now) {
        self.platform = platform
        self.date = date
        self.degree = degree
        self.playtime = playtime
        self.notes = notes
        self.scoreGameplay = scoreGameplay
        self.scoreDesign = scoreDesign
        self.scoreStory = scoreStory
        self.scoreArt = scoreArt
        self.scoreMusic = scoreMusic
        self.scorePerformance = scorePerformance
        self.createdAt = createdAt
    }
}

// MARK: - 派生计算

extension Completion {

    /// 已有的六维评分（可能不足六个）。按 Dimension 顺序排列。
    var scoreValues: [Double] {
        [scoreGameplay, scoreDesign, scoreStory, scoreArt, scoreMusic, scorePerformance].compactMap { $0 }
    }

    /// 是否已评分：六维中至少一项有分即可（平均分按现有维度均值算）。
    var hasScores: Bool { !scoreValues.isEmpty }

    /// 单条平均分（现有维度原始均值），未评分则 nil。
    var recordAverage: Double? {
        hasScores ? ScoreMath.recordAverage(scoreValues) : nil
    }

    /// 界面展示用：均值取整到最近的 0.1。
    var displayAverage: Double? {
        recordAverage.map { ScoreMath.roundScore($0) }
    }

    /// 取指定维度的评分。
    func score(for dimension: Dimension) -> Double? {
        switch dimension {
        case .gameplay: scoreGameplay
        case .design: scoreDesign
        case .story: scoreStory
        case .art: scoreArt
        case .music: scoreMusic
        case .performance: scorePerformance
        }
    }
}
