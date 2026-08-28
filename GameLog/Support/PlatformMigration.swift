import Foundation
import SwiftData

/// 存量数据迁移（启动时调用、幂等）：平台旧名改名 + Logo 垂直默认档改写。
enum PlatformMigration {
    /// 旧名 → 新名。
    static let renames: [String: String] = [
        "Switch": "Nintendo Switch",
        "Switch 2": "Nintendo Switch 2",
    ]

    /// 一次性迁移库内已存储的旧平台名 + Logo 垂直默认值。幂等，重复调用无害。
    ///
    /// Logo 垂直：beta 2.5 首次建模时默认档是 `center`，已随建模写进存量行；
    /// beta 2.6 起代码默认改 `bottom`，但改默认值救不了已固化的存量数据。
    /// 2026-08-28 用户定稿：默认靠下 → 把仍是 `center` 的存量行改写为 `bottom`。
    /// **只在 UserDefaults 标记未置位时跑一次**：之后用户在编辑页手动选「居中」
    /// 必须保持原样，不能被后续启动再次改写（一次性闸门，跑完即置位）。
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

        let logoRewriteKey = "migration.logoVerticalBottom20260828"
        if !UserDefaults.standard.bool(forKey: logoRewriteKey) {
            if let games = try? context.fetch(FetchDescriptor<Game>()) {
                for game in games {
                    if game.logoVertical == LogoBannerVertical.center.rawValue {
                        game.logoVertical = LogoBannerVertical.bottom.rawValue
                        changed = true
                    }
                }
            }
            UserDefaults.standard.set(true, forKey: logoRewriteKey)
        }

        if changed { try? context.save() }
    }
}
