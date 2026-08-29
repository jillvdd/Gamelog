import Foundation

#if os(macOS)
import AppKit
#endif

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
    /// 平台标志开关（默认开启；关闭后各平台不显示 logo 图标）。
    static let platformIconsKey = "customization.platformIcons"
    /// 自动备份开关（默认开启=每次数据改动后自动写完整本地备份）。
    static let autoBackupKey = "customization.autoBackup"
    /// 持有页网格 / 列表视图切换（默认开启=网格），跨会话记忆，同 Library。
    static let useHoldingsGridViewKey = "customization.useHoldingsGridView"
    /// 分组分享卡统计要素（已启用项的有序 JSON 数组；缺失 = 默认配置）。
    static let shareGroupStatsKey = "share.groupStats"
    /// 总览图头部汇总要素池（同上格式）。
    static let shareOverviewStatsKey = "share.overviewStats"
    /// 游戏格子字段池（总览格与分组卡格共用，同上格式）。
    static let shareTileFieldsKey = "share.tileFields"
    /// 侧边栏「状态」区展开（默认 true=展开，跨会话记忆）。
    static let sidebarStatusExpandedKey = "customization.sidebar.statusExpanded"
    /// 侧边栏「平台」区展开（默认 true=展开，跨会话记忆）。
    static let sidebarPlatformsExpandedKey = "customization.sidebar.platformsExpanded"
    /// 侧边栏「分组」区展开（默认 true=展开，跨会话记忆）。
    static let sidebarGroupsExpandedKey = "customization.sidebar.groupsExpanded"
    /// iOS 库视图三态（grid/wideCard/list，原始值字符串）。仅 iOS 读写；macOS 仍用旧 useGridView Bool 键。
    /// 旧键迁移在 LibraryView 首次读取时做：无此键时按 useGridView 折算 grid/list。
    static let iosLibraryViewModeKey = "customization.iosLibraryViewMode"

    /// 用户名长度上限。
    static let usernameMaxLength = 20

    /// 用户名截断规则（字符数上限，非字节数——中日文一字一符）。
    /// UI 绑定（onChange 实时截断显示）直接用；持久化路径走 `setUsername`（截断+落库一体）。
    static func truncateUsername(_ raw: String) -> String {
        String(Array(raw).prefix(usernameMaxLength))
    }

    /// 用户名的**安全写入**唯一入口：截断 + 落 UserDefaults（空串 = 移除）。
    /// 备份导入等持久化路径用——规则一处，调用点不再手抄。
    static func setUsername(_ raw: String) {
        let truncated = truncateUsername(raw)
        if truncated.isEmpty {
            UserDefaults.standard.removeObject(forKey: usernameKey)
        } else {
            UserDefaults.standard.set(truncated, forKey: usernameKey)
        }
    }

    // MARK: - 备份往返（自定义三项：用户名 / 头像 / 图标）

    /// 读出三项供备份编码（BackupManager.encode 用；BackupWriter 走逐项读取同源）。
    static func encodedCustomization() -> (username: String?, avatarBase64: String?, iconBase64: String?) {
        (
            UserDefaults.standard.string(forKey: usernameKey),
            avatarImageData()?.base64EncodedString(),
            iconImageData()?.base64EncodedString()
        )
    }

    /// 从备份写回三项。**写序不变量**：先写可能抛错的文件（头像/图标）、最后写 UserDefaults（用户名）——
    /// 用户名写盘不可回滚，若先写用户名、后写文件失败，会出现「提示导入失败但用户名已变更」；
    /// 文件写盘失败时用户名保持原值，与「失败时原库保持完好」口径一致。
    /// 旧版备份缺字段 → 保持现状不覆盖。返回是否全部成功（抛错即失败，调用方决定是否中断导入）。
    static func applyCustomization(username: String?, avatarBase64: String?, iconBase64: String?) throws {
        if let avatar = avatarBase64.flatMap({ Data(base64Encoded: $0) }) {
            try saveAvatarPNG(avatar)
        }
        if let icon = iconBase64.flatMap({ Data(base64Encoded: $0) }) {
            try saveIconPNG(icon)
        }
        if let name = username {
            setUsername(name)
        }
    }

    // MARK: - 文件存储

    private static let avatarFilename = "avatar.png"
    private static let iconFilename = "icon.png"

    private static let supportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("GameLog", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Application Support/GameLog 目录（头像/图标/自动备份共用）。
    static var supportDirectory: URL { supportDir }

    // MARK: - 保存（裁切面板 / 备份导入产出 PNG data → 落盘 + 记引用）

    static func saveAvatarPNG(_ data: Data) throws {
        try data.write(to: supportDir.appendingPathComponent(avatarFilename), options: .atomic)
        UserDefaults.standard.set(avatarFilename, forKey: avatarFileKey)
    }

    static func saveIconPNG(_ data: Data) throws {
        try data.write(to: supportDir.appendingPathComponent(iconFilename), options: .atomic)
        UserDefaults.standard.set(iconFilename, forKey: iconFileKey)
        #if os(macOS)
        applyDockIcon()
        #endif
    }

    // MARK: - 读取

    static func avatarImage() -> AppImage? {
        guard UserDefaults.standard.string(forKey: avatarFileKey) != nil else { return nil }
        return loadAppImage(from: supportDir.appendingPathComponent(avatarFilename))
    }

    static func iconImage() -> AppImage? {
        guard UserDefaults.standard.string(forKey: iconFileKey) != nil else { return nil }
        return loadAppImage(from: supportDir.appendingPathComponent(iconFilename))
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
        #if os(macOS)
        applyDockIcon()
        #endif
    }

    #if os(macOS)
    // MARK: - Dock 图标（自定义图标只作用于 Dock；Finder/Launchpad 保持系统图标）

    static func applyDockIcon() {
        if let img = iconImage() {
            NSApplication.shared.applicationIconImage = img
        } else {
            // 未设置自定义图标：恢复 bundle 默认图标（置 nil 会把 Dock/About 图标清空）。
            NSApplication.shared.applicationIconImage = NSImage(named: NSImage.applicationIconName)
        }
    }
    #endif

    // MARK: - 工具

    // MARK: - 收藏照片处理（收藏家模式）

    /// 导入收藏照片：keepOriginal=true 存原文件数据；false 压缩（最长边 ≤ maxEdge、JPEG quality）。
    static func collectionImageData(from url: URL, keepOriginal: Bool) -> Data? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return collectionImageData(from: data, keepOriginal: keepOriginal)
    }

    /// 收藏照片 Data 版本（iOS PhotosPicker 直接给 Data；macOS 走 URL 版本）。
    static func collectionImageData(from data: Data, keepOriginal: Bool) -> Data? {
        if keepOriginal { return data }
        guard let image = AppImage(data: data) else { return nil }
        return image.compressedJPEGData()
    }
}
