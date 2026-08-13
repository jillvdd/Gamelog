import Foundation
import SwiftData

/// 平台名迁移：Switch → Nintendo Switch、Switch 2 → Nintendo Switch 2（2026-08-13 改名）。
/// 存储值迁移（启动时调用、幂等）。
/// 展示层旧名兜底映射在 `Presets.localized` 里（旧备份导入后旧名仍显示新名）。
enum PlatformMigration {
    /// 旧名 → 新名。
    static let renames: [String: String] = [
        "Switch": "Nintendo Switch",
        "Switch 2": "Nintendo Switch 2",
    ]

    /// 一次性迁移库内已存储的旧平台名。幂等，重复调用无害。
    /// （平台筛选已改由侧边栏/分组局部状态驱动，不再有需要迁移的持久化筛选值。）
    static func migrate(in context: ModelContext) {
        var changed = false

        if let completions = try? context.fetch(FetchDescriptor<Completion>()) {
            for completion in completions {
                if let newName = renames[completion.platform], completion.platform != newName {
                    completion.platform = newName
                    changed = true
                }
            }
        }

        if changed { try? context.save() }
    }
}
