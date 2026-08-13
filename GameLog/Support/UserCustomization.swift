import AppKit
import Foundation

/// 用户个性化项（用户名 / app 图标 / 头像 / 自动匹配封面开关）的持久化与读取。
///
/// - 用户名：标准 UserDefaults（设置页用 `@AppStorage("customization.username")` 读写同一源）。
/// - 头像 / app 图标：PNG 文件存 `~/Library/Application Support/GameLog/`，
///   UserDefaults 存文件名引用（非空即表示已设置）。
///
/// 备份时由 `BackupManager` 读成 base64 内嵌进导出 JSON；导入时写回文件与引用。
enum UserCustomization {

    // MARK: - UserDefaults keys

    static let usernameKey = "customization.username"
    static let avatarFileKey = "customization.avatarFile"
    static let iconFileKey = "customization.iconFile"
    /// 自动匹配封面开关（默认关闭，设置页读写同一源）。
    static let autoMatchCoverKey = "customization.autoMatchCover"
    /// 隐藏工具栏毛玻璃开关（默认关闭=保留玻璃+标题；开启=方案 B：无标题、完全无毛玻璃）。
    static let hideToolbarGlassKey = "customization.hideToolbarGlass"
    /// 收藏家模式开关（默认关闭；开启后详情页出现「详情/持有」分段切换）。
    static let collectorModeKey = "customization.collectorMode"
    /// 保存原图开关（默认关闭=收藏照片导入时压缩；开启=存原图，只影响之后新增的图）。
    static let keepOriginalImagesKey = "customization.keepOriginalImages"

    /// 用户名长度上限（设置页输入与导入时统一截断）。
    static let usernameMaxLength = 20

    // MARK: - 文件存储

    private static let avatarFilename = "avatar.png"
    private static let iconFilename = "icon.png"

    private static let supportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("GameLog", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: - 保存（裁切面板 / 备份导入产出 PNG data → 落盘 + 记引用）

    static func saveAvatarPNG(_ data: Data) throws {
        try data.write(to: supportDir.appendingPathComponent(avatarFilename), options: .atomic)
        UserDefaults.standard.set(avatarFilename, forKey: avatarFileKey)
    }

    static func saveIconPNG(_ data: Data) throws {
        try data.write(to: supportDir.appendingPathComponent(iconFilename), options: .atomic)
        UserDefaults.standard.set(iconFilename, forKey: iconFileKey)
        applyDockIcon()
    }

    // MARK: - 读取

    static func avatarImage() -> NSImage? {
        guard UserDefaults.standard.string(forKey: avatarFileKey) != nil else { return nil }
        return NSImage(contentsOf: supportDir.appendingPathComponent(avatarFilename))
    }

    static func iconImage() -> NSImage? {
        guard UserDefaults.standard.string(forKey: iconFileKey) != nil else { return nil }
        return NSImage(contentsOf: supportDir.appendingPathComponent(iconFilename))
    }

    static func avatarImageData() -> Data? {
        guard UserDefaults.standard.string(forKey: avatarFileKey) != nil else { return nil }
        return try? Data(contentsOf: supportDir.appendingPathComponent(avatarFilename))
    }

    static func iconImageData() -> Data? {
        guard UserDefaults.standard.string(forKey: iconFileKey) != nil else { return nil }
        return try? Data(contentsOf: supportDir.appendingPathComponent(iconFilename))
    }

    // MARK: - 移除 / 恢复

    static func removeAvatar() {
        try? FileManager.default.removeItem(at: supportDir.appendingPathComponent(avatarFilename))
        UserDefaults.standard.removeObject(forKey: avatarFileKey)
    }

    static func removeIcon() {
        try? FileManager.default.removeItem(at: supportDir.appendingPathComponent(iconFilename))
        UserDefaults.standard.removeObject(forKey: iconFileKey)
        applyDockIcon()
    }

    // MARK: - Dock 图标（自定义图标只作用于 Dock；Finder/Launchpad 保持系统图标）

    static func applyDockIcon() {
        if let img = iconImage() {
            NSApplication.shared.applicationIconImage = img
        } else {
            // 未设置自定义图标：恢复 bundle 默认图标（置 nil 会把 Dock/About 图标清空）。
            NSApplication.shared.applicationIconImage = NSImage(named: NSImage.applicationIconName)
        }
    }

    // MARK: - 工具

    /// NSImage → PNG data（裁切面板与备份导出共用）。
    static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { return nil }
        return data
    }

    // MARK: - 收藏照片处理（收藏家模式）

    /// 导入收藏照片：keepOriginal=true 存原文件数据；false 压缩（最长边 ≤ maxEdge、JPEG quality）。
    static func collectionImageData(from url: URL, keepOriginal: Bool) -> Data? {
        if keepOriginal { return try? Data(contentsOf: url) }
        guard let image = NSImage(contentsOf: url) else { return nil }
        return compressedJPEGData(from: image)
    }

    /// 压缩为 JPEG：最长边 ≤ maxEdge、quality。尺寸未超限时只转 JPEG 不放大。
    static func compressedJPEGData(from image: NSImage, maxEdge: CGFloat = 1600, quality: CGFloat = 0.8) -> Data? {
        let size = image.size
        let maxDim = max(size.width, size.height)
        let scale = maxDim > maxEdge ? maxEdge / maxDim : 1.0
        let target = NSSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(target.width), pixelsHigh: Int(target.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = target
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: target))
        NSGraphicsContext.current?.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}
