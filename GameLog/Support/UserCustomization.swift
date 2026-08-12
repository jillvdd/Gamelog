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
}
