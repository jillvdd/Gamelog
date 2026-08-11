import Foundation
import SwiftData

/// 一次通关记录。挂在 Game 下，可追加多条。
/// 四维评分整体可选：首条记录必填，之后可跳过；跳过时四个分全部为 nil。
@Model
final class Completion {
    var platform: String
    var date: Date
    var degree: String
    var playtime: Double?
    var notes: String
    var scoreStory: Double?
    var scoreGraphics: Double?
    var scoreMusic: Double?
    var scoreGameplay: Double?
    var createdAt: Date
    var game: Game?

    init(platform: String, date: Date, degree: String, playtime: Double? = nil,
         notes: String = "", scoreStory: Double? = nil, scoreGraphics: Double? = nil,
         scoreMusic: Double? = nil, scoreGameplay: Double? = nil, createdAt: Date = .now) {
        self.platform = platform
        self.date = date
        self.degree = degree
        self.playtime = playtime
        self.notes = notes
        self.scoreStory = scoreStory
        self.scoreGraphics = scoreGraphics
        self.scoreMusic = scoreMusic
        self.scoreGameplay = scoreGameplay
        self.createdAt = createdAt
    }
}

// MARK: - 派生计算

extension Completion {

    /// 已有的四维评分（可能不足四个）。
    var scoreValues: [Double] {
        [scoreStory, scoreGraphics, scoreMusic, scoreGameplay].compactMap { $0 }
    }

    /// 是否已评分（四维全部填齐才算）。
    var hasScores: Bool { scoreValues.count == 4 }

    /// 单条平均分（原始均值），未评分则 nil。
    var recordAverage: Double? {
        hasScores ? ScoreMath.recordAverage(scoreValues) : nil
    }

    /// 界面展示用：均值取整到最近的 0.5。
    var displayAverage: Double? {
        recordAverage.map { ScoreMath.roundToHalf($0) }
    }

    /// 取指定维度的评分。
    func score(for dimension: Dimension) -> Double? {
        switch dimension {
        case .story: scoreStory
        case .graphics: scoreGraphics
        case .music: scoreMusic
        case .gameplay: scoreGameplay
        }
    }
}
