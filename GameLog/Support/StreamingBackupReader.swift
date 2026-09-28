import Foundation

// MARK: - 流式备份读取器
//
// 动机（2026-09-23）：`JSONDecoder` 必须把整个备份一次性变成对象树，GB 级备份在 iOS 上
// 峰值内存 = 文件 + 约两倍的解码结构，必被 jetsam 终结 → 用户看到「无效或已损坏」。
// 本文件把「解码」换成「扫描」：按字节状态机扫过文件（固定窗口内存），`games` 数组元素
// 只记字节区间；其余顶层小字段同样只记区间。**任何备份体积下内存占用恒定**，
// 第二阶段再按区间逐游戏读取 + 解码 + 落库（见 `BackupImporter.applyStreaming`）。
//
// 兼容性口径与 `BackupManager.decode` 完全一致：必填键缺失抛 `DecodingError.keyNotFound`，
// 结构非法/截断抛 `DecodingError.dataCorrupted`——调用方按 `DecodingError` 统一归类
// （`importFailMessageForUser`），两条形同虚设的失败信息就此合一。
// compact（BackupWriter）与 prettyPrinted + sortedKeys（BackupManager.encode）两种输出都覆盖。

/// 备份文件内一个 JSON 值的字节闭区间（含首尾）。
struct BackupByteRange: Sendable {
    let start: Int
    let end: Int
    var count: Int { end - start + 1 }
}

/// 流式扫描第一阶段结果。
struct BackupScanResult: Sendable {
    let fileSize: Int
    /// `games` 键是否出现（缺失 = 非法备份，与 bulk 解码同口径报 keyNotFound）。
    var hasGamesKey = false
    var gameRanges: [BackupByteRange] = []
    var versionRange: BackupByteRange?
    var exportedAtRange: BackupByteRange?
    var groupsRange: BackupByteRange?
    var usernameRange: BackupByteRange?
    var avatarRange: BackupByteRange?
    var iconRange: BackupByteRange?
    var bannerTitleRange: BackupByteRange?
    var bannerSubtitleRange: BackupByteRange?
    var bannerBackgroundRange: BackupByteRange?
}

/// 用户定制六字段（与 `UserCustomization.applyCustomization` 参数一一对应）。
struct BackupCustomization: Sendable {
    var username: String?
    var avatarBase64: String?
    var iconBase64: String?
    var bannerTitle: String?
    var bannerSubtitle: String?
    var bannerBackgroundBase64: String?
}

/// `games` 之外的小顶层字段解码结果。
struct BackupHeaderData: Sendable {
    var groups: [GroupDTO]
    var customization: BackupCustomization
}

extension GroupDTO: Sendable {}

enum StreamingBackupReader {

    fileprivate static func corrupted(_ message: String) -> DecodingError {
        DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "GameLog backup: \(message)"))
    }

    /// 与 `BackupManager.decode` 同款解码器配置（iso8601 日期）。
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: - 第一阶段：扫描

    /// 分块扫过整个文件，产出各字段字节区间。内存峰值 = 1MB 窗口（复用单缓冲）。
    /// `onBytes`：已扫绝对字节（约每 1MB 一次，含 games 数组内部），供进度映射。
    static func scan(url: URL, onBytes: ((Int) -> Void)? = nil) throws -> BackupScanResult {
        // 用裸 fd 而非 FileHandle：FileHandle 自带预读缓冲，若与底层 POSIX read 混用会让
        // 内核偏移与 FileHandle 记录错位（实测尾部误判「unterminated string」）。这里全程自持 fd。
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { throw ImportError.backupUnreadable }
        defer { close(fd) }
        var st = stat()
        let fileSize = (fstat(fd, &st) == 0) ? Int(st.st_size) : 0
        var cursor = ScanCursor(fd: fd, fileSize: fileSize)
        return try cursor.scanTopLevel(onBytes: onBytes)
    }

    // MARK: - 第二阶段：按区间解码

    /// 小顶层字段 → `BackupHeaderData`（区间回读，均为小体量；单字段上限 64MB 防爆）。
    static func header(of scan: BackupScanResult, url: URL) throws -> BackupHeaderData {
        let fh: FileHandle
        do { fh = try FileHandle(forReadingFrom: url) }
        catch { throw ImportError.backupUnreadable }
        defer { try? fh.close() }
        func raw(_ range: BackupByteRange?, required: Bool, key: String) throws -> Data? {
            guard let range else {
                if required {
                    throw DecodingError.keyNotFound(AnyKey(key),
                        .init(codingPath: [], debugDescription: "GameLog backup: missing \(key)"))
                }
                return nil
            }
            guard range.count <= 64_000_000 else { throw corrupted("field \(key) exceeds 64MB") }
            return try read(fh, range)
        }
        let decoder = decoder()
        _ = try raw(scan.versionRange, required: true, key: "version")
        _ = try raw(scan.exportedAtRange, required: true, key: "exportedAt")
        guard let groupsData = try raw(scan.groupsRange, required: true, key: "groups") else {
            throw corrupted("groups missing")
        }
        let groups = try decoder.decode([GroupDTO].self, from: groupsData)
        func str(_ range: BackupByteRange?, key: String) throws -> String? {
            guard let data = try raw(range, required: false, key: key) else { return nil }
            // 字段存在但值为 `null`（BackupWriter 对未设置项写 null）→ 解为 nil，
            // 不能按非可选 String 解（否则 valueNotFound）。
            return try decoder.decode(String?.self, from: data)
        }
        let customization = BackupCustomization(
            username: try str(scan.usernameRange, key: "username"),
            avatarBase64: try str(scan.avatarRange, key: "avatarBase64"),
            iconBase64: try str(scan.iconRange, key: "iconBase64"),
            bannerTitle: try str(scan.bannerTitleRange, key: "bannerTitle"),
            bannerSubtitle: try str(scan.bannerSubtitleRange, key: "bannerSubtitle"),
            bannerBackgroundBase64: try str(scan.bannerBackgroundRange, key: "bannerBackgroundBase64")
        )
        return BackupHeaderData(groups: groups, customization: customization)
    }

    /// 单个游戏区间 → `GameDTO`（复用同一 FileHandle，按序 seek 读）。
    static func game(from fh: FileHandle, decoder: JSONDecoder, range: BackupByteRange) throws -> GameDTO {
        try decoder.decode(GameDTO.self, from: read(fh, range))
    }

    static func read(_ fh: FileHandle, _ range: BackupByteRange) throws -> Data {
        try fh.seek(toFileOffset: UInt64(range.start))
        let data = fh.readData(ofLength: range.count)
        guard data.count == range.count else { throw corrupted("file shrank during read (moved/truncated?)") }
        return data
    }

    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ stringValue: String) { self.stringValue = stringValue }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}

// MARK: - 字节扫描状态机
//
// 固定 1MB 窗口，消费即丢（绝对偏移单调递增，只记区间不留字节）。UTF-8 安全：所有判定
// 只针对 ASCII 单字节（引号/反斜杠/括号/冒号/逗号/数字母），多字节序列的每个字节都 ≥0x80，
// 不会撞 ASCII 定界符。

private struct ScanCursor {
    private let fd: Int32
    private let fileSize: Int
    private let window: Int
    // 单次预分配、反复复用的窗口缓冲：POSIX read 直接读进 buf 基址，避免每窗口新造
    // `[UInt8]`（FileHandle.read→Array 的分配抖动会让 libmalloc 攒下 ~1GB 脏页，iOS 上足以
    // 触发 jetsam —— 实测 1GB 备份旧实现扫描峰值 1.06GB）。复用后扫描峰值恒定 ≈ 窗口大小。
    private var buf: [UInt8]
    private var pos = 0         // 窗口内游标：下一个待读字节在 buf[pos]
    private var filled = 0      // buf 内有效字节数
    private var idx = 0         // buf[pos] 的绝对文件偏移（单调递增，供区间记录）
    private var eof = false

    fileprivate init(fd: Int32, fileSize: Int) {
        self.fd = fd
        self.fileSize = fileSize
        self.window = 1 << 20
        self.buf = [UInt8](repeating: 0, count: 1 << 20)
    }

    /// 窗口耗尽时补一窗（cur 保证仅在 pos>=filled 时调用，无残余字节需搬运）。
    private mutating func refill() throws {
        pos = 0
        filled = 0
        guard !eof else { return }
        var got = 0
        let readFD = fd, win = window   // 拷入局部，避免闭包捕获 self 与 buf 独占借用冲突
        let status: Int = buf.withUnsafeMutableBytes { raw in
            let base = raw.baseAddress!
            while got < win {
                let r = read(readFD, base + got, win - got)
                if r > 0 { got += r; continue }
                if r == 0 { return got }            // 真 EOF：返回已读到的尾窗字节（不可清零丢弃）
                if errno == EINTR { continue }      // 信号打断，重试
                return -1                           // 硬错误：调用方转 backupUnreadable
            }
            return got
        }

        if status < 0 { throw ImportError.backupUnreadable }
        if status == 0 { eof = true; return }
        filled = status
    }

    /// 当前字节；nil = 文件结束。
    private mutating func cur() throws -> UInt8? {
        while pos >= filled {
            try refill()
            if eof { return nil }
        }
        return buf[pos]
    }

    private mutating func advance() { idx += 1; pos += 1 }

    private mutating func skipWS() throws {
        while let c = try cur() {
            if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D { advance() } else { break }
        }
    }

    private mutating func expect(_ byte: UInt8, what: String) throws {
        guard let c = try cur(), c == byte else { throw StreamingBackupReader.corrupted("expected \(what)") }
        advance()
    }

    /// 当前字节为起始 `"`；推进到闭合引号之后（处理 `\` 转义）。
    private mutating func scanStringBody() throws {
        try expect(0x22, what: "\"")
        var escaped = false
        while let c = try cur() {
            advance()
            if escaped { escaped = false; continue }
            if c == 0x5C { escaped = true; continue }
            if c == 0x22 { return }
        }
        throw StreamingBackupReader.corrupted("unterminated string")
    }

    /// 扫过一个任意 JSON 值（当前字节 = 值首字节），返回值结束的绝对偏移（不含，`<` 终止处）。
    /// 容器按深度配平（字符串内的括号跳过）；标量到 `,` `}` `]` 或 ws 为止。
    private mutating func scanValue() throws -> Int {
        guard let c0 = try cur() else { throw StreamingBackupReader.corrupted("value expected at EOF") }
        switch c0 {
        case 0x22:
            try scanStringBody()
            return idx
        case 0x7B, 0x5B:
            var depth = 0
            while let c = try cur() {
                switch c {
                case 0x22:
                    // scanStringBody 自行消费起始引号 —— 此处绝不可提前 advance，否则它会
                    // 把正文首字符当引号 `expect` 而抛「expected "」（容器内任何字符串都会踩）。
                    try scanStringBody()
                case 0x7B, 0x5B:
                    advance(); depth += 1
                case 0x7D, 0x5D:
                    advance(); depth -= 1
                    if depth == 0 { return idx }
                default:
                    advance()
                }
            }
            throw StreamingBackupReader.corrupted("unbalanced container")
        default:
            // 标量（number/true/false/null）：吃到定界符前一字节。
            let scalarStart = idx
            while let c = try cur() {
                if c == 0x2C || c == 0x7D || c == 0x5D || c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D { break }
                advance()
            }
            guard idx > scalarStart else { throw StreamingBackupReader.corrupted("empty scalar") }
            return idx
        }
    }

    /// 读取键名（当前在起始 `"`）。仅用于顶层键（本项目字段名都是 ASCII），转义按字面处理。
    private mutating func readKey() throws -> String {
        try expect(0x22, what: "key")
        var bytes: [UInt8] = []
        var escaped = false
        while let c = try cur() {
            advance()
            if escaped { bytes.append(c); escaped = false; continue }
            if c == 0x5C { escaped = true; continue }
            if c == 0x22 { break }
            bytes.append(c)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: 顶层扫描主循环

    fileprivate mutating func scanTopLevel(onBytes: ((Int) -> Void)?) throws -> BackupScanResult {
        var result = BackupScanResult(fileSize: fileSize)
        try skipWS()
        try expect(0x7B, what: "{ (backup root must be an object)")
        var lastReported = 0
        while true {
            try skipWS()
            guard let c = try cur() else { break }
            if c == 0x7D { advance(); break }   // 顶层对象收尾
            if c == 0x2C { advance(); continue } // 容忍冗余逗号（bulk 解码会拒绝不了的内容这里也不炸）
            let key = try readKey()
            try skipWS()
            try expect(0x3A, what: ":")
            try skipWS()

            if key == "games", try cur() == 0x5B {
                result.hasGamesKey = true
                advance() // '['
                while true {
                    try skipWS()
                    guard let e = try cur() else { throw StreamingBackupReader.corrupted("games array unterminated") }
                    if e == 0x5D { advance(); break }
                    if e == 0x2C { advance(); continue }
                    guard e == 0x7B else { throw StreamingBackupReader.corrupted("games element must be an object") }
                    let start = idx
                    let end = try scanValue()
                    result.gameRanges.append(BackupByteRange(start: start, end: end - 1))
                    // games 数组是文件体积主体：逐元素按 ~1MB 粒度上报，否则整段扫描期间进度条
                    // 完全静止（顶层键循环每键才检查一次，会一路沉默到最后）。
                    if let onBytes, idx - lastReported >= (1 << 20) {
                        lastReported = idx
                        onBytes(idx)
                    }
                }
            } else {
                let start = idx
                let end = try scanValue()
                let range = BackupByteRange(start: start, end: end - 1)
                switch key {
                case "version": result.versionRange = range
                case "exportedAt": result.exportedAtRange = range
                case "groups": result.groupsRange = range
                case "username": result.usernameRange = range
                case "avatarBase64": result.avatarRange = range
                case "iconBase64": result.iconRange = range
                case "bannerTitle": result.bannerTitleRange = range
                case "bannerSubtitle": result.bannerSubtitleRange = range
                case "bannerBackgroundBase64": result.bannerBackgroundRange = range
                default: break   // 未知键 = 前瞻兼容字段，与 JSONDecoder 忽略未知键的行为一致
                }
            }

            if let onBytes, idx - lastReported >= (1 << 20) {
                lastReported = idx
                onBytes(idx)
            }
        }
        onBytes?(fileSize)
        return result
    }
}
