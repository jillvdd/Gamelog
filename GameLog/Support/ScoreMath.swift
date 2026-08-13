import Foundation

/// 评分相关纯逻辑。不依赖 SwiftData / SwiftUI，可独立编译验证。
enum ScoreMath {

    /// 四舍五入到最近的 0.1（8.26→8.3，8.25→8.3，8.0→8.0）。评分展示的最小单位。
    static func roundScore(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    /// 单条通关记录的平均分：现有维度评分的算术均值（1–6 维都认可）。
    /// 没有任何评分或任一超出 1–10 范围则返回 nil（视为未评分）。
    static func recordAverage(_ scores: [Double]) -> Double? {
        guard !scores.isEmpty,
              scores.allSatisfy({ $0 >= 1 && $0 <= 10 }) else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }

    /// 库显示分：所有已评分记录平均分的均值，再取整到最近的 0.1。
    /// 没有任何已评分记录时返回 nil（界面显示"未评分"）。
    static func libraryScore(recordAverages: [Double]) -> Double? {
        let valid = recordAverages.filter { $0 >= 1 && $0 <= 10 }
        guard !valid.isEmpty else { return nil }
        let mean = valid.reduce(0, +) / Double(valid.count)
        return roundScore(mean)
    }

    // MARK: - 命令行自检

    /// 运行全部断言，逐条打印 PASS/FAIL，全部通过返回 true。
    /// 自检入口放在 Scripts/ 下（见 Scripts/ScoreMathSelftest/main.swift），
    /// 本文件保持无顶层语句，才能作为应用模块的一部分正常编译。
    static func runSelfTest() -> Bool {
        func assertEq(_ name: String, _ actual: Double?, _ expected: Double?) -> Bool {
            let ok: Bool
            if let actual, let expected {
                ok = abs(actual - expected) < 0.0001
            } else {
                ok = (actual == nil && expected == nil)
            }
            let actualText: String = actual.map { String($0) } ?? "nil"
            let expectedText: String = expected.map { String($0) } ?? "nil"
            print("\(ok ? "PASS" : "FAIL") \(name): got \(actualText), expected \(expectedText)")
            return ok
        }
        let results = [
            assertEq("round 8.3", roundScore(8.3), 8.3),
            assertEq("round 8.2", roundScore(8.2), 8.2),
            assertEq("round 8.0", roundScore(8.0), 8.0),
            assertEq("round 8.25", roundScore(8.25), 8.3),
            assertEq("round 8.75", roundScore(8.75), 8.8),
            assertEq("record avg 8,9,8,7,9,7", recordAverage([8, 9, 8, 7, 9, 7]), 8.0),
            assertEq("record avg empty", recordAverage([]), nil),
            assertEq("record avg 2 items", recordAverage([8, 9]), 8.5),
            assertEq("record avg 4 items (部分维度)", recordAverage([8, 9, 7, 8]), 8.0),
            assertEq("record avg out of range", recordAverage([8, 9, 11, 8, 9, 8]), nil),
            assertEq("library 8.0 & 9.0", libraryScore(recordAverages: [8.0, 9.0]), 8.5),
            assertEq("library 8.2 only", libraryScore(recordAverages: [8.2]), 8.2),
            assertEq("library empty", libraryScore(recordAverages: []), nil),
            assertEq("library invalid ignored", libraryScore(recordAverages: [8.0, 12.0]), 8.0),
            assertEq("library 7.6 & 8.4", libraryScore(recordAverages: [7.6, 8.4]), 8.0),
            assertEq("library 8.4 only", libraryScore(recordAverages: [8.4]), 8.4),
        ]
        return results.allSatisfy { $0 }
    }
}
