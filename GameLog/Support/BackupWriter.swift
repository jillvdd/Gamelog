import Foundation
import SwiftData

/// 后台流式备份写入器：在 ModelActor 的后台上下文里 fetch 全库并**逐游戏分片编码**，
/// 边编边写文件（FileHandle），任何时刻内存里只有一个游戏的 JSON 片段。
///
/// 2026-08-29 性能改造：旧路径 BackupManager.encode 在主线程一次性产出 771MB Data
/// （DTO 树 + base64 膨胀 + JSON 缓冲，峰值 ~2GB），大库下编辑保存后 3 秒必卡死、
/// iOS 退后台兜底写盘直接被系统终止。本类型把这些全部移出主线程。
///
/// 输出格式与 BackupDTO 完全兼容（标准 JSON、日期 ISO8601），JSONDecoder /
/// decodeAndReplace 可直接读取；差异仅在无 prettyPrinted 空白（JSON 语义无影响，文件更小）。
/// 字段映射与 BackupManager.encode 共用 GameDTO(from:)（Support/Game+Backup.swift），
/// 由构造保证一致——DataSmokeTest 的「双路径输出一致」断言兜底。
@ModelActor
actor BackupWriter {

    /// 一次取多少款游戏（见 `writeStreamingBackup` 的 games 段：内存峰值 = 一批的外置图 Data）。
    static let backupBatchSize = 32

    /// 流式写整个备份到 url。返回写入字节数。
    /// - 顶层结构按 BackupDTO 字段顺序手拼：version / exportedAt / groups / games /
    ///   username / avatarBase64 / iconBase64 / bannerTitle / bannerSubtitle / bannerBackgroundBase64
    /// - groups 数组一次编码（体量小）；games **逐个**编码写盘（单游戏峰值 ~几十 MB）
    /// - 头像/图标/横幅背景 PNG 由调用方传入（后台读文件），base64 后写盘
    /// - `atomic` = 先写同目录临时件再换名。**macOS NSSavePanel 选定的路径只有目标文件
    ///    本身有沙盒授权，同目录新建临时件会被拒**，该场景必须传 false 直写目标。
    func writeStreamingBackup(to url: URL,
                              username: String?,
                              avatarPNG: Data?,
                              iconPNG: Data?,
                              bannerTitle: String? = nil,
                              bannerSubtitle: String? = nil,
                              bannerBackgroundPNG: Data? = nil,
                              atomic: Bool = true) async throws -> Int {
        // 上一轮若中途抛错，故障物化的封面还挂在本上下文对象图里；开头回滚一次清账
        // （只读用途的上下文，无未提交改动可丢）。
        modelContext.rollback()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        // 先写临时文件、成功后原子换名：中途被杀只留孤儿临时件，目标文件（旧备份）完好。
        let tmpURL = atomic
            ? url.deletingLastPathComponent().appendingPathComponent(".autobackup-tmp-\(UUID().uuidString).json")
            : url
        // 目录必须先存在。iOS 的 `Documents/Backups` 此前**没有任何代码创建过它**
        //（macOS 侧靠 `UserCustomization.supportDir` 的懒建目录侥幸覆盖），全新安装的 iPhone
        // 上第一次导入/第一次自动备份必失败：`createFile` 在缺目录时只返回 false 且被忽略，
        // 紧接着 `FileHandle(forWritingTo:)` 抛 NSCocoaErrorDomain Code=4「文件不存在」，
        // 真因被盖成「备份文件无效或已损坏」（2026-09-30 真机排查）。
        try FileManager.default.createDirectory(
            at: tmpURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // 返回值必须看：实测 `createFile` 会把已存在的目标**清空**（直写分支靠这一点截断旧备份），
        // 而在缺目录/不可写时返回 false —— 忽略它就是把真实原因换成一句误导性的「文件不存在」。
        guard FileManager.default.createFile(atPath: tmpURL.path, contents: nil) else {
            throw BackupWriterError.cannotCreate(path: tmpURL.path)
        }
        let fh = try FileHandle(forWritingTo: tmpURL)
        var closed = false
        func closeFH() {
            guard !closed else { return }
            closed = true
            try? fh.close()
        }
        defer { closeFH() }
        var total = 0

        func write(_ data: Data) throws {
            try fh.write(contentsOf: data)
            total += data.count
        }

        // 头
        try write(Data("{\"version\":1,\"exportedAt\":".utf8))
        try write(try encoder.encode(Date.now))
        try write(Data(",".utf8))

        // groups（小，一次编）
        let groups = try modelContext.fetch(FetchDescriptor<GameGroup>(sortBy: [SortDescriptor(\.name)]))
        let groupDTOs: [GroupDTO] = groups.map { g in
            GroupDTO(name: g.name, review: g.review)
        }
        try write(Data("\"groups\":".utf8))
        try write(try encoder.encode(groupDTOs))
        try write(Data(",\"games\":[".utf8))

        // games：按游标分批取、逐款编码写盘（2026-09-29 审计 P1）。
        //
        // 一次 `fetch` 整库在内存上是隐藏的双峰：
        // 1) **外置图 Data 挂账**。`coverData` 等字段是 externalStorage，逐款 fault 之后原始
        //    字节就钉在对象槽里，直到下一次 `rollback()` —— 而回滚原本在**整库编完之后**。
        //    峰值于是等于整库备份体积（本机 1.1 GB 级），iOS 上这就是导入/启动闪退的内存底座。
        //    现在每批只取 32 款，批末回滚 → 峰值 = 一批（约 130 MB 量级）。
        // 2) **自动释放池不排**。编码产物（每款数 MB 的 Data 片段）经 Foundation 走 autorelease，
        //    而 Swift 并发协作线程不像 RunLoop 那样逐轮排池，一个 actor job 跑到完都不排 →
        //    全程累积。逐款 `autoreleasepool` 把它们就地释放。
        //
        // 为什么用**游标分页**而不是 `fetchOffset`：offset 翻页在写入期间被并发编辑（用户在
        // 备份跑的这几秒里改了库）会整体错位 —— 少一款就是备份里**静默丢一款数据**。
        // 游标（createdAt, name 严格大于）只受「排序键本身变化」影响，插入/删除都不会让
        // 未写的游戏被跳过，因此也不需要「写一半发现对不上就中止」（中止会毁掉用户手选的直写目标）。
        var cursor: (date: Date, name: String)?
        var written = 0
        while true {
            var descriptor: FetchDescriptor<Game>
            if let cursor {
                let afterDate = cursor.date
                let afterName = cursor.name
                descriptor = FetchDescriptor<Game>(
                    predicate: #Predicate {
                        $0.createdAt > afterDate
                            || ($0.createdAt == afterDate && $0.name > afterName)
                    },
                    sortBy: [SortDescriptor(\.createdAt), SortDescriptor(\.name)]
                )
            } else {
                descriptor = FetchDescriptor<Game>(
                    sortBy: [SortDescriptor(\.createdAt), SortDescriptor(\.name)]
                )
            }
            descriptor.fetchLimit = Self.backupBatchSize
            let batch = try modelContext.fetch(descriptor)
            if batch.isEmpty { break }
            for game in batch {
                if written > 0 { try write(Data(",".utf8)) }
                written += 1
                cursor = (game.createdAt, game.name)
                // 字段映射唯一入口 = GameDTO(from:)（与 BackupManager.encode 同一构造器，永不漂移）。
                try autoreleasepool {
                    try write(try encoder.encode(GameDTO(from: game)))
                }
                // 每 24 款让路一次：编码要逐款 fault 外置封面（每款数百 KB 磁盘读），
                // 一口气跑几千款会把共享连接池/页缓存吃满 —— 主线程任何一次查询都被饿死
                // （2026-09-24 iOS 实机：启动备份与首帧全库 fetch 对撞 → 0x8BADF00D 看门狗）。
                // 4ms/24 款的节流对总时长影响 <2%，但让 SQLite 事务与磁盘 I/O 有插空窗口。
                if written % 24 == 0 { try? await Task.sleep(nanoseconds: 4_000_000) }
            }
            // 批末回滚：这一批 fault 出来的外置图 Data 就地交还内存（下一批各自重新 fault）。
            modelContext.rollback()
        }
        try write(Data("]".utf8))
        // 收尾再回滚一次：最后一批的对象同样不该留到下一次写盘。
        modelContext.rollback()

        // 自定义项（与 BackupManager.encode 同字段名；缺省 = null）
        try write(Data(",\"username\":".utf8))
        try write(try encoder.encode(username))
        try write(Data(",\"avatarBase64\":".utf8))
        try write(try encoder.encode(avatarPNG?.base64EncodedString()))
        try write(Data(",\"iconBase64\":".utf8))
        try write(try encoder.encode(iconPNG?.base64EncodedString()))
        try write(Data(",\"bannerTitle\":".utf8))
        try write(try encoder.encode(bannerTitle))
        try write(Data(",\"bannerSubtitle\":".utf8))
        try write(try encoder.encode(bannerSubtitle))
        try write(Data(",\"bannerBackgroundBase64\":".utf8))
        try write(try encoder.encode(bannerBackgroundPNG?.base64EncodedString()))
        try write(Data("}".utf8))

        closeFH()
        guard atomic else { return total }
        // 同目录 rename：同卷原子。旧目标文件保持完好直到这一刻。
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.moveItem(at: tmpURL, to: url)

        return total
    }

    /// 流式统计备份文件里的游戏数（数 `"reviewTitle"` 出现次数——每个 GameDTO 恰好一个；
    /// 用户文本里的引号在 JSON 中转义为 `\"`，不会误配）。不把文件整个读进内存
    /// （备份可达数百 MB）。供启动空库恢复询问用。
    static func countGames(at url: URL) -> Int {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return 0 }
        defer { try? fh.close() }
        let needle = Array("\"reviewTitle\"".utf8)
        var window: [UInt8] = []
        var count = 0
        let chunkSize = 1 << 20
        while let chunk = try? fh.read(upToCount: chunkSize), !chunk.isEmpty {
            window.append(contentsOf: Array(chunk))
            while let range = window.firstRange(of: needle) {
                count += 1
                window.removeSubrange(0..<range.upperBound)
            }
            // 保留窗口尾部防跨块漏配（needle 长度 - 1 即可，留整长更稳）。
            if window.count > needle.count * 2 {
                window.removeFirst(window.count - needle.count)
            }
        }
        return count
    }
}

/// 写备份文件本身建不出来（目录缺失/不可写）。与「磁盘写满」（在 `fh.write` 处抛真实 POSIX 错）
/// 分开，避免两种完全不同的故障共用一句「文件不存在」。
enum BackupWriterError: Error, CustomStringConvertible {
    case cannotCreate(path: String)

    var description: String {
        switch self {
        case .cannotCreate(let path): return "BackupWriter.cannotCreate(\(path))"
        }
    }
}
