import Foundation
import SwiftData
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// 图片导入 seam（2026-08-29 深化）：统一「本地选一张图」的平台管线——
/// macOS = NSOpenPanel（模态），iOS = imageSourcePicker（相册/文件/拍照底部菜单）。
///
/// 深化前：ImageSourcePicker/MacPhotoLibraryPicker 只管「弹出选择器」，调用点各自
/// 手接 panel 配置（allowedContentTypes 已实际漂移：编辑页 [.image] vs 设置页四类型）、
/// 处理、缓存失效。深化后：类型配置、平台分派在此一处，调用点给 sink 不给管线。
enum ImageImport {

    /// 统一导入类型：全部系统可解码图像。设置页头像/图标历史上是 [.png,.jpeg,.tiff,.heic]，
    /// 放宽到 [.image] 无副作用（裁切链把任何可解码格式转成 PNG 落盘），少一个
    /// 「为什么这里不能选 webp」的困惑。
    static var allowedTypes: [UTType] { [.image] }

    /// 当前平台是否用同步 panel 选图（macOS）；false = iOS 走 imageSourcePicker 异步回调。
    static var supportsPanel: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    /// macOS 同步 panel 选一张图（iOS 无此路径，调用点用 imageSourcePicker + activeKind 驱动）。
    /// 返回 nil = 用户取消或读取失败。
    static func pickOneFromPanel() -> Data? {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = allowedTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return try? Data(contentsOf: url)
        #else
        return nil
        #endif
    }

    // MARK: - 持有照片导入（pick → process → append → bump → save 共享管线）

    /// macOS 多选 panel 导入持有照片：读 URL → 按 keepOriginal 处理 → 截到剩余名额 → 追加并持久化。
    @discardableResult
    static func importCollectionPhotos(into copy: PhysicalCopy, keepOriginal: Bool,
                                       context: ModelContext) -> Bool {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = allowedTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return false }
        return appendCollectionPhotos(from: panel.urls, into: copy, keepOriginal: keepOriginal, context: context)
        #else
        return false
        #endif
    }

    /// 文件 URL 入口：读取并处理（keepOriginal）、截上限、追加并持久化。
    @discardableResult
    static func appendCollectionPhotos(from urls: [URL], into copy: PhysicalCopy,
                                       keepOriginal: Bool, context: ModelContext) -> Bool {
        let remaining = 6 - copy.images.count
        guard remaining > 0 else { return false }
        let datas = urls.prefix(remaining).compactMap {
            UserCustomization.collectionImageData(from: $0, keepOriginal: keepOriginal)
        }
        return appendProcessed(datas, keepOriginal: keepOriginal, into: copy, context: context)
    }

    /// 相册/拍照回调入口（Data 已在内存）：处理（keepOriginal）、截上限、追加并持久化。
    @discardableResult
    static func appendCollectionPhotos(datas: [Data], into copy: PhysicalCopy,
                                       keepOriginal: Bool, context: ModelContext) -> Bool {
        let processed = datas.compactMap { UserCustomization.collectionImageData(from: $0, keepOriginal: keepOriginal) }
        return appendProcessed(processed, keepOriginal: keepOriginal, into: copy, context: context)
    }

    /// 追加管线尾段：截上限 → 写模型 → 清解码缓存 → save。
    private static func appendProcessed(_ datas: [Data], keepOriginal: Bool, into copy: PhysicalCopy,
                                        context: ModelContext) -> Bool {
        var images = copy.images
        for data in datas {
            guard images.count < 6 else { break }
            // 逐字节相同的照片不重复入库：持有页 `ForEach(copy.images, id: \.self)` 见到重复
            // ID 会直接崩（不变式在 `PhysicalCopy.deduplicated`，两条写入路径都要守）。
            if images.contains(data) { continue }
            images.append(data)
        }
        guard images.count != copy.images.count else { return false }
        copy.images = images
        ImageDecodeCache.bump()
        try? context.save()
        return true
    }
}
