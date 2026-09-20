import Foundation
import SwiftData
import SQLite3

/// 存量数据迁移（启动时调用、幂等）：平台旧名改名 + Logo 垂直默认档改写。
enum PlatformMigration {
    /// 默认存储文件 URL（macOS / iOS Application Support 目录下）。
    static var defaultStoreURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("default.store")
    }

    /// 尝试自愈默认存储（若文件存在）。
    @discardableResult
    static func sanitizeDefaultStore() -> Int {
        sanitizeDatabase(at: defaultStoreURL)
    }

    /// 检查并修复 SQLite 底层存储中的非空列异常（如轻量迁移/旧数据/异常写入遗留的 NULL 值）。
    ///
    /// ⚠️ **必须在 SwiftData 物化任何实体前运行**：
    /// CoreData 对声明为非可选的属性（如 `logoHorizontal`、`reviewTitle` 等）做严格校验。
    /// 一旦 SQLite 磁盘行里某列为 NULL，CoreData 故障（faulting）该行时会直接抛出
    /// `Row (pk = ...) for entity 'Game' is missing mandatory text data`，
    /// SwiftData 随之触发 `Fatal error: This model instance was invalidated because its backing data could no longer be found`，
    /// 并导致 SIGTRAP 崩溃，Swift 层面无法通过 `do/catch` 捕获。
    /// 
    /// 本方法通过 SQLite C API 幂等自愈，单次耗时 < 5ms。
    @discardableResult
    static func sanitizeDatabase(at url: URL?) -> Int {
        guard let url, url.isFileURL else { return 0 }
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else { return 0 }

        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            return 0
        }
        defer { sqlite3_close(db) }

        var checkStmt: OpaquePointer?
        let checkSql = "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='ZGAME';"
        guard sqlite3_prepare_v2(db, checkSql, -1, &checkStmt, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(checkStmt) }
        guard sqlite3_step(checkStmt) == SQLITE_ROW, sqlite3_column_int(checkStmt, 0) > 0 else {
            return 0
        }

        let sql = """
        UPDATE ZGAME SET 
          ZLOGOHORIZONTAL = COALESCE(ZLOGOHORIZONTAL, 'leading'),
          ZLOGOVERTICAL = COALESCE(ZLOGOVERTICAL, 'bottom'),
          ZLOGOSIZE = COALESCE(ZLOGOSIZE, 'medium'),
          ZREVIEWTITLE = COALESCE(ZREVIEWTITLE, ''),
          ZREVIEWBODY = COALESCE(ZREVIEWBODY, ''),
          ZPLATFORM = COALESCE(ZPLATFORM, ''),
          ZSTATUS = COALESCE(ZSTATUS, 'completed'),
          ZNAME = COALESCE(ZNAME, '')
        WHERE 
          ZLOGOHORIZONTAL IS NULL OR 
          ZLOGOVERTICAL IS NULL OR 
          ZLOGOSIZE IS NULL OR 
          ZREVIEWTITLE IS NULL OR 
          ZREVIEWBODY IS NULL OR 
          ZPLATFORM IS NULL OR 
          ZSTATUS IS NULL OR 
          ZNAME IS NULL;
        """

        var updateStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &updateStmt, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(updateStmt) }

        if sqlite3_step(updateStmt) == SQLITE_DONE {
            let changes = Int(sqlite3_changes(db))
            if changes > 0 {
                NSLog("GameLog: PlatformMigration repaired \(changes) corrupted row(s) in ZGAME")
            }
        }

        let nintendoSql = """
        UPDATE ZEXTERNALGAMERECORD SET ZPLATFORM = 'Nintendo Switch 2'
        WHERE ZPROVIDERRAW = 'nintendo' AND ZPLATFORMRAW = 'BEE' AND ZPLATFORM = 'Nintendo Switch';
        """
        var nintendoStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, nintendoSql, -1, &nintendoStmt, nil) == SQLITE_OK {
            sqlite3_step(nintendoStmt)
            let nintendoChanges = Int(sqlite3_changes(db))
            if nintendoChanges > 0 {
                NSLog("GameLog: PlatformMigration migrated \(nintendoChanges) Nintendo Switch 2 (BEE) record(s)")
            }
            sqlite3_finalize(nintendoStmt)
        }

        return 0
    }

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
    /// save 失败向上抛（调用方记日志不阻断启动）；此前 `try?` 吞错 = 迁移丢失。
    static func migrate(in context: ModelContext) throws {
        sanitizeDatabase(at: context.container.configurations.first?.url)
        var changed = false

        // 平台改名覆盖**全部三处存储**：Completion.platform、Game.platform（主平台）、
        // PhysicalCopy.platform（持有记录）。此前只迁移 Completion，游戏与持有的旧名
        // 永远不同步——platformCounts 按原始字符串计数，同名两行（2026-09-05 审计）。
        // （Game.platformList 是计算属性，源头就是 completions+platform，改完源头即同步。）
        if let completions = try? context.fetch(FetchDescriptor<Completion>()) {
            for completion in completions {
                if let newName = renames[completion.platform], completion.platform != newName {
                    completion.platform = newName
                    changed = true
                }
            }
        }
        if let games = try? context.fetch(FetchDescriptor<Game>()) {
            for game in games {
                if let newName = renames[game.platform], game.platform != newName {
                    game.platform = newName
                    changed = true
                }
            }
        }
        if let copies = try? context.fetch(FetchDescriptor<PhysicalCopy>()) {
            for copy in copies {
                if let newName = renames[copy.platform], copy.platform != newName {
                    copy.platform = newName
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

        if let records = try? context.fetch(FetchDescriptor<ExternalGameRecord>()) {
            for record in records {
                if record.providerRaw == "nintendo", record.platformRaw == "BEE", record.platform != "Nintendo Switch 2" {
                    record.platform = "Nintendo Switch 2"
                    changed = true
                }
            }
        }

        // 迁移幂等（改动前后值相等时不重复标记），但 save 失败必须暴露：闸门/重跑语义
        // 依赖 save 真正落盘。静默 `try?` 会让用户以为已迁移（2026-09-05 审计）。
        // 失败时抛给调用方（启动迁移调用点 catch 记日志，不阻断启动）。
        if changed { try context.save() }
    }
}
