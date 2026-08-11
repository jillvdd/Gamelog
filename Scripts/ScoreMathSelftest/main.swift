// ScoreMath 自检入口（不能放进 GameLog/ 同步文件夹，否则会作为应用模块编译）。
//
// 运行方式（任选其一）：
//   swiftc -o /tmp/scoremath_selftest ../../GameLog/Support/ScoreMath.swift main.swift && /tmp/scoremath_selftest
// 或在工程根目录：
//   swiftc -o /tmp/scoremath_selftest GameLog/Support/ScoreMath.swift Scripts/ScoreMathSelftest/main.swift && /tmp/scoremath_selftest
import Foundation

let passed = ScoreMath.runSelfTest()
print(passed ? "ScoreMath self-test passed." : "ScoreMath self-test FAILED.")
exit(passed ? 0 : 1)
