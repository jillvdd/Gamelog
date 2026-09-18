import Foundation

/// 字节数的展示格式（唯一归属）。
///
/// 「存储与缓存」那一节的缓存占用与「数据备份」那一节的备份体积是同一种数字，
/// 此前两处各有一份同名的私有 `formatSize`。既然两个界面已经分家（设置 / 关联设置），
/// 就把它收成一个出口 —— 同一个数字在两页上长得不一样才是更坏的结果。
///
/// `countStyle: .file` 是 Finder 口径（1000 进制、单位 B/KB/MB/GB），与系统磁盘用量一致。
enum ByteFormat {
    static func fileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
