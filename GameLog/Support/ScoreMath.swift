import Foundation

/// 评分相关纯逻辑。不依赖 SwiftData / SwiftUI，可独立编译验证。
enum ScoreMath {

    /// 四舍五入到最近的 0.5（8.3→8.5，8.2→8.0，8.0→8.0）。
    static func roundToHalf(_ value: Double) -> Double {
        (value * 2).rounded() / 2
    }

    /// 单条通关记录的平均分：六个维度的算术均值。
    /// 传入的六维评分不足六个或任一超出 1–10 范围则返回 nil（视为未评分）。
    static func recordAverage(_ scores: [Double]) -> Double? {
        guard scores.count == 6,
              scores.allSatisfy({ $0 >= 1 && $0 <= 10 }) else { return nil }
        return scores.reduce(0, +) / 6
    }

    /// 库显示分：所有已评分记录平均分的均值，再取整到最近的 0.5。
    /// 没有任何已评分记录时返回 nil（界面显示"未评分"）。
    static func libraryScore(recordAverages: [Double]) -> Double? {
        let valid = recordAverages.filter { $0 >= 1 && $0 <= 10 }
        guard !valid.isEmpty else { return nil }
        let mean = valid.reduce(0, +) / Double(valid.count)
        return roundToHalf(mean)
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
            assertEq("round 8.3", roundToHalf(8.3), 8.5),
            assertEq("round 8.2", roundToHalf(8.2), 8.0),
            assertEq("round 8.0", roundToHalf(8.0), 8.0),
            assertEq("round 8.25", roundToHalf(8.25), 8.5),
            assertEq("round 8.75", roundToHalf(8.75), 9.0),
            assertEq("record avg 8,9,8,7,9,7", recordAverage([8, 9, 8, 7, 9, 7]), 8.0),
            assertEq("record avg empty", recordAverage([]), nil),
            assertEq("record avg 2 items", recordAverage([8, 9]), nil),
            assertEq("record avg 4 items (旧四维) invalid", recordAverage([8, 9, 7, 8]), nil),
            assertEq("record avg out of range", recordAverage([8, 9, 11, 8, 9, 8]), nil),
            assertEq("library 8.0 & 9.0", libraryScore(recordAverages: [8.0, 9.0]), 8.5),
            assertEq("library 8.2 only", libraryScore(recordAverages: [8.2]), 8.0),
            assertEq("library empty", libraryScore(recordAverages: []), nil),
            assertEq("library invalid ignored", libraryScore(recordAverages: [8.0, 12.0]), 8.0),
            assertEq("library 7.6 & 8.4", libraryScore(recordAverages: [7.6, 8.4]), 8.0),
            assertEq("library 8.4 only", libraryScore(recordAverages: [8.4]), 8.5),
        ]
        return results.allSatisfy { $0 }
    }
}
