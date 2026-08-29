import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// 五类图 + 持有照片的解码缓存（NSCache，key = persistentModelID + 字段名）。
///
/// 2026-08-29 性能改造：旧实现 key 用 `data.hashValue`——每次 body 重算都对整段图片
/// Data（数百 KB～数 MB）做 O(n) 全量哈希，网格滚动/状态切换时大量浪费。
/// 改为 (persistentModelID, field) 稳定 key：命中时不触碰 data（externalStorage 下
/// 访问 data = 读外部文件），只在未命中时物化 + 解码一次。
///
/// 数据变更一致性：写入图片的路径（编辑页保存、持有照片增删、备份导入重建）
/// 必须调用 `bump()` 清缓存，否则同 ID 旧图残留。CacheCleaner 也经此清空。
enum ImageDecodeCache {
    private static let cache = NSCache<NSString, AppImage>()

    static func image(for game: Game, field: String, data: Data?) -> AppImage? {
        guard let data else { return nil }
        let key = "\(game.persistentModelID.hashValue).\(field)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let image = AppImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// 图片数据变更后调用（编辑页保存 / 持有照片增删 / 备份导入后），全量清空。
    /// 清空代价 = 下次各图重新物化 + 解码一次，可接受。
    static func bump() {
        cache.removeAllObjects()
    }
}
