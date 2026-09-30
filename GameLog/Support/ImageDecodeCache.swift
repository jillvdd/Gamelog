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
/// 2026-09-29 内存改造：此前 NSCache **既没有 cost 也没有上限**，等于无界字典 ——
/// NSCache 只在系统已经缺内存时才被动淘汰，而「被动淘汰来不及」正是 iOS 闪退的形态
/// （ jetsam 直接杀进程，不给进程清理的机会）。278 款 × 2~3 类图 × 每张解码后
/// 2~5 MB 位图 = 理论上限数 GB。现在按解码位图字节计价并设硬上限，另在内存告警时整库清空。
///
/// 数据变更一致性：写入图片的路径（编辑页保存、持有照片增删、备份导入重建）
/// 必须调用 `bump()` 清缓存，否则同 ID 旧图残留。CacheCleaner 也经此清空。
enum ImageDecodeCache {
    private static let cache = NSCache<NSString, AppImage>()

    /// 计价上限（字节）与条数上限。按平台分档：
    /// - iOS：单进程内存预算远小于 macOS，且导入/启动期峰值本已很高，只留 96 MB
    ///   （约 40 张封面级位图）—— 够铺满首屏网格 + 少量预取，超出部分交 NSCache 淘汰。
    /// - macOS：整库窗口/多窗口同时可见的需求真实存在，给 256 MB。
    #if os(macOS)
    private static let costLimit = 256 * 1024 * 1024
    private static let countLimit = 1200
    #else
    private static let costLimit = 96 * 1024 * 1024
    private static let countLimit = 400
    #endif

    /// 一次性安装：上限 + 内存告警观察者。`static let` 的惰性初始化保证只跑一次，
    /// 且不需要在 App 启动流程里插一行（谁先用缓存谁安装）。
    private static let install: Void = {
        cache.totalCostLimit = costLimit
        cache.countLimit = countLimit
        #if os(macOS)
        // macOS 没有 `didReceiveMemoryWarning`，用系统内存压力源等价兜底。
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical], queue: .main
        )
        source.setEventHandler { ImageDecodeCache.bump() }
        source.resume()
        memoryPressureSource = source
        #else
        // 通知名用字面量而非 `UIApplication.didReceiveMemoryWarningNotification`：
        // 该常量挂在 @MainActor 的 UIApplication 上，而本安装路径是 nonisolated。
        NotificationCenter.default.addObserver(
            forName: Notification.Name("UIApplicationDidReceiveMemoryWarningNotification"),
            object: nil,
            queue: .main
        ) { _ in
            ImageDecodeCache.bump()
        }
        #endif
    }()

    #if os(macOS)
    /// 压力源必须长期持有（释放即停止派发），且 `install` 只能写 `static var`。
    nonisolated(unsafe) private static var memoryPressureSource: DispatchSourceMemoryPressure?
    #endif

    static func image(for game: Game, field: String, data: Data?) -> AppImage? {
        guard let data else { return nil }
        _ = install
        let key = "\(game.persistentModelID.hashValue).\(field)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let image = AppImage(data: data) else { return nil }
        cache.setObject(image, forKey: key, cost: cost(of: image))
        return image
    }

    /// 解码后位图字节数（近似 宽×高×4，按**像素**而非点算）。
    ///
    /// 不用 `data.count`：那是压缩后的 JPEG/PNG 大小，通常是位图的 1/10，
    /// 用它计价会让上限形同虚设（96 MB 限额实际驻留近 1 GB）。
    private static func cost(of image: AppImage) -> Int {
        var pixelsWide = 0, pixelsHigh = 0
        #if os(macOS)
        if let rep = image.representations.first {
            pixelsWide = rep.pixelsWide
            pixelsHigh = rep.pixelsHigh
        }
        #else
        if let cg = image.cgImage {
            pixelsWide = cg.width
            pixelsHigh = cg.height
        }
        #endif
        if pixelsWide <= 0 || pixelsHigh <= 0 {
            pixelsWide = Int(image.size.width)
            pixelsHigh = Int(image.size.height)
        }
        return max(1, pixelsWide * pixelsHigh * 4)
    }

    /// 图片数据变更后调用（编辑页保存 / 持有照片增删 / 备份导入后），全量清空。
    /// 清空代价 = 下次各图重新物化 + 解码一次，可接受。
    static func bump() {
        cache.removeAllObjects()
    }
}
