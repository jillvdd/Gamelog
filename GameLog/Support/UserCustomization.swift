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
    /// 详情页「游戏记录」折叠区展开（默认 true=展开，跨会话记忆）。
    /// **全局一份而不是每个游戏一份** —— 与侧边栏三个分区同一套做法，理由见
    /// `GameDetailView.externalRecordsSection`。
    static let detailRecordsExpandedKey = "customization.detail.recordsExpanded"
    /// 库视图模式（`LibraryViewMode` 原始值字符串，**双平台共用**）。
    /// 取代了此前 macOS 的 `useGridView` Bool 与 iOS 的 `customization.iosLibraryViewMode` 两个键 ——
    /// 两个 Bool 表达不了三个状态（macOS 加方形网格后是 grid/squareGrid/list）。
    static let libraryViewModeKey = "customization.libraryViewMode"
    /// **旧键，仅供迁移读取**：iOS 库视图三态。新写入一律走 `libraryViewModeKey`。
    /// LibraryView 首次读取时若新键为空，则由它（或 macOS 的 `useGridView`）折算一次并写上。
    /// 迁移后不再删除：删了也读不到值，且留着可让用户回退旧版本时不丢偏好。
    static let iosLibraryViewModeKey = "customization.iosLibraryViewMode"
    /// **旧键，仅供迁移读取**：macOS 网格/列表 Bool（`true` = 网格）。
    /// 全文仅此一处定义 —— 调用点此前写作字面量 `"useGridView"`，是本项目**唯一**
    /// 没有命名空间前缀的键（新键一律 `customization.` / `share.` 开头）。
    static let legacyMacGridViewKey = "useGridView"
    /// 主页横幅标题 / 副标题 / 背景图文件引用（设置页「主页横幅」块读写；轮播第 1 页展示）。
    static let bannerTitleKey = "customization.bannerTitle"
    static let bannerSubtitleKey = "customization.bannerSubtitle"
    static let bannerBackgroundFileKey = "customization.bannerBackgroundFile"
    /// 随机游戏底图偏好（轮播第 2 页）：auto=默认横图优先（landscape→hero）、hero=仅背景图、
    /// landscape=仅横向封面（用户拍板 2026-09-05：mac 横向封面 2.8:1 卡片上下裁切影响观感，
    /// 给用户选择权）。设置页 Picker 读写；缺失/未知值回退 auto。
    /// iPad 横竖屏分开（2026-09-05 用户要求，仅 iPad）：横屏读 PadLandscapeKey，
    /// 竖屏读本键（iPhone/macOS 同源）；设置页仅 iPad 显示第二个 Picker。
    static let spotlightBackdropPreferenceKey = "customization.spotlightBackdrop"
    static let spotlightBackdropPadLandscapeKey = "customization.spotlightBackdropPadLandscape"
    static let spotlightBackdropAuto = "auto"
    static let spotlightBackdropHero = "hero"
    static let spotlightBackdropLandscape = "landscape"
    /// 网格极简模式（默认关闭；开启后网格卡仅显示封面 + 右上角胶囊 + 爱心角标，
    /// 封面下方名称/平台/日期等信息全部隐藏）。全平台生效。
    static let minimalGridKey = "customization.minimalGrid"

    /// 用户图（横幅背景/头像）变更通知：HomeCarousel 监听并重载 @State 缓存
    /// （轮播不再每次 body 求值都读磁盘，改图后靠此通知刷新）。
    static let userImagesChangedNotification = Notification.Name("customization.userImagesChanged")
    /// 整库替换（备份导入/自动备份恢复/AirDrop 导入）后广播：持有旧 Game/Group 强引用的
    /// 导航状态（iOS selectedGame、macOS path）立即重置，防悬空引用访问 detached 模型
    /// 触发 SwiftData fatal（与轮播 spotlight 崩溃同族，2026-09-05 审计）。
    static let libraryReplacedNotification = Notification.Name("library.replaced")

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

    // MARK: - 备份往返（自定义三项 + 主页横幅：用户名 / 头像 / 图标 / 横幅标题副标题背景）

    /// 读出各项供备份编码（BackupManager.encode 用；BackupWriter 走逐项读取同源）。
    static func encodedCustomization() -> (username: String?, avatarBase64: String?, iconBase64: String?,
                                            bannerTitle: String?, bannerSubtitle: String?, bannerBackgroundBase64: String?) {
        (
            UserDefaults.standard.string(forKey: usernameKey),
            avatarImageData()?.base64EncodedString(),
            iconImageData()?.base64EncodedString(),
            UserDefaults.standard.string(forKey: bannerTitleKey),
            UserDefaults.standard.string(forKey: bannerSubtitleKey),
            bannerBackgroundImageData()?.base64EncodedString()
        )
    }

    /// 从备份写回各项。**写序不变量**：先写可能抛错的文件（头像/图标/横幅背景）、最后写 UserDefaults（用户名等）——
    /// 用户名写盘不可回滚，若先写用户名、后写文件失败，会出现「提示导入失败但用户名已变更」；
    /// 文件写盘失败时用户名保持原值，与「失败时原库保持完好」口径一致。
    /// 旧版备份缺字段 → 保持现状不覆盖。返回是否全部成功（抛错即失败，调用方决定是否中断导入）。
    static func applyCustomization(username: String?, avatarBase64: String?, iconBase64: String?,
                                   bannerTitle: String? = nil, bannerSubtitle: String? = nil,
                                   bannerBackgroundBase64: String? = nil) throws {
        if let avatar = avatarBase64.flatMap({ Data(base64Encoded: $0) }) {
            try saveAvatarPNG(avatar)
        }
        if let icon = iconBase64.flatMap({ Data(base64Encoded: $0) }) {
            try saveIconPNG(icon)
        }
        if let bg = bannerBackgroundBase64.flatMap({ Data(base64Encoded: $0) }) {
            try saveBannerBackgroundPNG(bg)
        }
        if let title = bannerTitle {
            setBannerTitle(title)
        }
        if let subtitle = bannerSubtitle {
            setBannerSubtitle(subtitle)
        }
        if let name = username {
            setUsername(name)
        }
    }

    // MARK: - 主页横幅（轮播第 1 页）

    /// 横幅标题截断规则 = 用户名同款 20 字上限（规则一处，UI 绑定与持久化共用）。
    static func truncateBannerText(_ raw: String, limit: Int = usernameMaxLength) -> String {
        String(Array(raw).prefix(limit))
    }

    static func setBannerTitle(_ raw: String) {
        let t = truncateBannerText(raw)
        if t.isEmpty {
            UserDefaults.standard.removeObject(forKey: bannerTitleKey)
        } else {
            UserDefaults.standard.set(t, forKey: bannerTitleKey)
        }
    }

    static func setBannerSubtitle(_ raw: String) {
        let t = truncateBannerText(raw)
        if t.isEmpty {
            UserDefaults.standard.removeObject(forKey: bannerSubtitleKey)
        } else {
            UserDefaults.standard.set(t, forKey: bannerSubtitleKey)
        }
    }

    // MARK: - 文件存储

    private static let avatarFilename = "avatar.png"
    private static let iconFilename = "icon.png"
    private static let bannerBackgroundFilename = "bannerBackground.png"

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
        NotificationCenter.default.post(name: userImagesChangedNotification, object: nil)
    }

    static func saveIconPNG(_ data: Data) throws {
        try data.write(to: supportDir.appendingPathComponent(iconFilename), options: .atomic)
        UserDefaults.standard.set(iconFilename, forKey: iconFileKey)
        #if os(macOS)
        applyDockIcon()
        #endif
    }

    /// 主页横幅背景（不裁切、不压缩比例；显示时等比填充裁边）。
    static func saveBannerBackgroundPNG(_ data: Data) throws {
        try data.write(to: supportDir.appendingPathComponent(bannerBackgroundFilename), options: .atomic)
        UserDefaults.standard.set(bannerBackgroundFilename, forKey: bannerBackgroundFileKey)
        NotificationCenter.default.post(name: userImagesChangedNotification, object: nil)
    }

    static func bannerBackgroundImageData() -> Data? {
        guard UserDefaults.standard.string(forKey: bannerBackgroundFileKey) != nil else { return nil }
        return try? Data(contentsOf: supportDir.appendingPathComponent(bannerBackgroundFilename))
    }

    /// 主页横幅背景图（无背景 = nil，调用点回退品牌渐变默认）。
    static func bannerBackgroundImage() -> AppImage? {
        guard UserDefaults.standard.string(forKey: bannerBackgroundFileKey) != nil else { return nil }
        return loadAppImage(from: supportDir.appendingPathComponent(bannerBackgroundFilename))
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
        NotificationCenter.default.post(name: userImagesChangedNotification, object: nil)
    }

    static func removeIcon() {
        try? FileManager.default.removeItem(at: supportDir.appendingPathComponent(iconFilename))
        UserDefaults.standard.removeObject(forKey: iconFileKey)
        #if os(macOS)
        applyDockIcon()
        #endif
    }

    /// 移除主页横幅背景（回退品牌渐变默认）。
    static func removeBannerBackground() {
        try? FileManager.default.removeItem(at: supportDir.appendingPathComponent(bannerBackgroundFilename))
        UserDefaults.standard.removeObject(forKey: bannerBackgroundFileKey)
        NotificationCenter.default.post(name: userImagesChangedNotification, object: nil)
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
