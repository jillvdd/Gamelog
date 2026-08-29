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

    /// 流式写整个备份到 url。返回写入字节数。
    /// - 顶层结构按 BackupDTO 字段顺序手拼：version / exportedAt / groups / games / username / avatarBase64 / iconBase64
    /// - groups 数组一次编码（体量小）；games **逐个**编码写盘（单游戏峰值 ~几十 MB）
    /// - 头像/图标 PNG 由调用方传入（后台读文件），base64 后写盘
    func writeStreamingBackup(to url: URL,
                              username: String?,
                              avatarPNG: Data?,
                              iconPNG: Data?) throws -> Int {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        // 先写临时文件、成功后原子换名：中途被杀只留孤儿临时件，目标文件（旧备份）完好。
        let tmpURL = url.deletingLastPathComponent()
            .appendingPathComponent(".autobackup-tmp-\(UUID().uuidString).json")
        FileManager.default.createFile(atPath: tmpURL.path, contents: nil)
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

        // games：逐个编码、逗号分隔
        let games = try modelContext.fetch(FetchDescriptor<Game>(sortBy: [SortDescriptor(\.createdAt)]))
        for (index, game) in games.enumerated() {
            if index > 0 { try write(Data(",".utf8)) }
            // 字段映射唯一入口 = GameDTO(from:)（与 BackupManager.encode 同一构造器，永不漂移）。
            try write(try encoder.encode(GameDTO(from: game)))
        }
        try write(Data("]".utf8))

        // 自定义三项（与 BackupManager.encode 同字段名；缺省 = null）
        try write(Data(",\"username\":".utf8))
        try write(try encoder.encode(username))
        try write(Data(",\"avatarBase64\":".utf8))
        try write(try encoder.encode(avatarPNG?.base64EncodedString()))
        try write(Data(",\"iconBase64\":".utf8))
        try write(try encoder.encode(iconPNG?.base64EncodedString()))
        try write(Data("}".utf8))

        closeFH()
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
