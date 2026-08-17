import Foundation
import SwiftUI

/// 清除可自动重建的临时缓存。**不触碰任何用户数据**：
/// - SwiftData 库（.store 文件）
/// - 游戏的封面/收藏照片数据
/// - 自动备份文件（滚动备份 / 版本快照 / 恢复前快照）
/// - UserDefaults 设置
///
/// 清除三类缓存：
/// 1. 系统 HTTP 缓存（URLSession URLCache）——封面搜索的缩略图/网格图下载留下的磁盘缓存
/// 2. 内存解码缓存——封面 NSCache（GameCardView）、平台图标 aspect/template 缓存
/// 3. 临时目录残留文件——分享导出临时图、Quick Look 临时文件
enum CacheCleaner {

    /// 磁盘缓存占用（URLCache 磁盘部分 + 临时目录文件总字节数）。
    static func diskSize() -> Int64 {
        let urlCacheDisk = URLCache.shared.currentDiskUsage
        return Int64(urlCacheDisk) + directorySize(FileManager.default.temporaryDirectory)
    }

    /// 清空缓存，返回本次释放的磁盘字节数（best effort）。
    @discardableResult
    static func clear() -> Int64 {
        let before = diskSize()
        URLCache.shared.removeAllCachedResponses()
        GameCardView.clearCoverCache()
        PlatformIconLoader.clearCaches()
        removeContents(of: FileManager.default.temporaryDirectory)
        return Int64(max(0, before - diskSize()))
    }

    // MARK: - 私有工具

    private static func directorySize(_ dir: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(
                forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
            ), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    private static func removeContents(of dir: URL) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for item in items {
            try? fm.removeItem(at: item)
        }
    }
}