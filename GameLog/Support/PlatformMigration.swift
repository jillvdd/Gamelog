import Foundation
import SwiftData

/// 平台名迁移：Switch → Nintendo Switch、Switch 2 → Nintendo Switch 2（2026-08-13 改名）。
/// 存储值迁移（启动时调用、幂等）+ 平台筛选持久化值同步。
/// 展示层旧名兜底映射在 `Presets.localized` 里（旧备份导入后旧名仍显示新名）。
enum PlatformMigration {
    /// 旧名 → 新名。
    static let renames: [String: String] = [
        "Switch": "Nintendo Switch",
        "Switch 2": "Nintendo Switch 2",
    ]

    /// 一次性迁移库内已存储的旧平台名与平台筛选持久化值。幂等，重复调用无害。
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

        // 平台筛选的持久化值（AppStorage key）同步迁移，避免迁移后筛选落空。
        let filterKey = "libraryPlatformFilter"
        if let filter = UserDefaults.standard.string(forKey: filterKey),
           let newName = renames[filter] {
            UserDefaults.standard.set(newName, forKey: filterKey)
            changed = true
        }

        if changed { try? context.save() }
    }
}
