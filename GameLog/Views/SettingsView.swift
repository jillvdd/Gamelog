import SwiftUI

#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#else
import PhotosUI
import UIKit
import UniformTypeIdentifiers
#endif

/// 设置：本机偏好 —— 语言（中日英）、个性化（用户名 / 头像 / 图标 / 主页横幅 / 显示开关）、
/// 存储与缓存。
///
/// ⚠️ 跟**外部服务**有关的三节（SteamGridDB API Key / 游戏账号 / 数据备份）2026-09-18 已搬去
/// `LinkSettingsView`（macOS 走 App 菜单「关联设置…」，iOS 走底部页签「关联」）。
/// 判断某一行属于哪一页看的是「它是不是本机偏好」，不是「它以前住哪」——
/// 所以别再往这里加需要网络、需要凭证、或会动整库的行。
struct SettingsView: View {
    @Environment(\.appLanguageCode) private var language
    @AppStorage("appLanguage") private var languageCode = AppLanguage.chinese.localeCode

    @AppStorage(UserCustomization.usernameKey) private var username = ""
    @AppStorage(UserCustomization.avatarFileKey) private var avatarFile = ""
    #if os(macOS)
    @AppStorage(UserCustomization.iconFileKey) private var iconFile = ""
    #endif
    @AppStorage(UserCustomization.autoMatchCoverKey) private var autoMatchCover = false
    #if os(macOS)
    @AppStorage(UserCustomization.hideToolbarGlassKey) private var hideToolbarGlass = false
    #endif
    @AppStorage(UserCustomization.collectorModeKey) private var collectorMode = false
    @AppStorage(UserCustomization.keepOriginalImagesKey) private var keepOriginalImages = false
    @AppStorage(UserCustomization.platformIconsKey) private var showPlatformIcons = true
    @AppStorage(UserCustomization.minimalGridKey) private var minimalGrid = false
    @AppStorage(UserCustomization.bannerBackgroundFileKey) private var bannerBackgroundFile = ""
    @AppStorage(UserCustomization.spotlightBackdropPreferenceKey) private var spotlightBackdropRaw = UserCustomization.spotlightBackdropAuto
    /// iPad 横屏专用底图偏好（仅 iPad 显示；竖屏/iPhone/macOS 走上面通用键）。
    #if os(iOS)
    @AppStorage(UserCustomization.spotlightBackdropPadLandscapeKey) private var spotlightBackdropPadLandscapeRaw = UserCustomization.spotlightBackdropAuto
    #endif

    /// 用户名绑定：写入时截断到上限。用 Binding 替代 `.onChange`——`.onChange` 挂 TextField 在 macOS 会吞尾随空格。
    private var usernameBinding: Binding<String> {
        Binding(
            get: { username },
            set: { username = UserCustomization.truncateUsername($0) }
        )
    }

    /// 主页横幅标题/副标题绑定：写入截断 + 空串移除（持久化唯一入口在 UserCustomization）。
    private var bannerTitleBinding: Binding<String> {
        Binding(
            get: { UserDefaults.standard.string(forKey: UserCustomization.bannerTitleKey) ?? "" },
            set: { UserCustomization.setBannerTitle($0) }
        )
    }

    private var bannerSubtitleBinding: Binding<String> {
        Binding(
            get: { UserDefaults.standard.string(forKey: UserCustomization.bannerSubtitleKey) ?? "" },
            set: { UserCustomization.setBannerSubtitle($0) }
        )
    }

    @State private var cropSession: CropSession?
    /// 是否显示「清除缓存」确认。
    @State private var showingCacheConfirm = false
    /// 当前缓存占用（字节），onAppear / 清除后刷新。
    @State private var cacheSizeBytes: Int64 = 0
    /// 缓存区操作反馈（清除成功）。
    @State private var cacheMessage: String?
    /// 照片图库选择器开关（macOS 用；photoLibraryPicker 在 iOS 为 no-op，状态无害）。
    @State private var showingAvatarLibrary = false
    @State private var showingIconLibrary = false
    /// 主页横幅背景图（macOS 文件面板 / 照片图库；iOS 相册/文件/拍照；两平台共用 SGDB 搜索）。
    @State private var showingBannerLibrary = false
    @State private var showingBannerSearch = false
    #if !os(macOS)
    @State private var showingAvatarPicker = false
    @State private var showingBannerPicker = false
    @State private var showingAbout = false
    #endif

    var body: some View {
        Form {
            Section(L10n.tr("settings.language", lang: language)) {
                Picker(L10n.tr("settings.language", lang: language), selection: $languageCode) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(verbatim: lang.displayName).tag(lang.localeCode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(L10n.tr("settings.customization", lang: language)) {
                LabeledContent(L10n.tr("settings.username", lang: language)) {
                    BorderedTextField(
                        text: usernameBinding,
                        placeholder: L10n.tr("settings.username", lang: language)
                    )
                }
                    .textFieldStyle(.roundedBorder)

                LabeledContent(L10n.tr("settings.avatar", lang: language)) {
                    HStack {
                        avatarPreview
                        #if os(macOS)
                        Button(L10n.tr("settings.chooseImage", lang: language)) { pickImage(for: .avatar) }
                            .appStandardButton()
                        Button(L10n.tr("image.photoLibrary", lang: language)) { showingAvatarLibrary = true }
                            .appStandardButton()
                        #else
                        Button(L10n.tr("settings.chooseImage", lang: language)) { showingAvatarPicker = true }
                            .appStandardButton()
                        #endif
                        Button(L10n.tr("settings.removeAvatar", lang: language)) { UserCustomization.removeAvatar() }
                            .appStandardButton()
                            .disabled(avatarFile.isEmpty)
                    }
                }

                #if os(macOS)
                LabeledContent(L10n.tr("settings.icon", lang: language)) {
                    HStack {
                        iconPreview
                        Button(L10n.tr("settings.chooseImage", lang: language)) { pickImage(for: .icon) }
                            .appStandardButton()
                        Button(L10n.tr("image.photoLibrary", lang: language)) { showingIconLibrary = true }
                            .appStandardButton()
                        Button(L10n.tr("settings.restoreIcon", lang: language)) { UserCustomization.removeIcon() }
                            .appStandardButton()
                            .disabled(iconFile.isEmpty)
                    }
                }
                #endif

                // 主页横幅（轮播第 1 页）：标题 / 副标题 / 背景图。
                LabeledContent(L10n.tr("settings.bannerTitle", lang: language)) {
                    BorderedTextField(
                        text: bannerTitleBinding,
                        placeholder: L10n.tr("app.menu", lang: language)
                    )
                }
                .textFieldStyle(.roundedBorder)

                LabeledContent(L10n.tr("settings.bannerSubtitle", lang: language)) {
                    BorderedTextField(
                        text: bannerSubtitleBinding,
                        placeholder: L10n.tr("settings.bannerSubtitle", lang: language)
                    )
                }
                .textFieldStyle(.roundedBorder)

                LabeledContent(L10n.tr("settings.bannerBackground", lang: language)) {
                    HStack {
                        bannerBackgroundPreview
                        #if os(macOS)
                        Button(L10n.tr("settings.chooseImage", lang: language)) { pickBannerBackground() }
                            .appStandardButton()
                        Button(L10n.tr("image.photoLibrary", lang: language)) { showingBannerLibrary = true }
                            .appStandardButton()
                        #else
                        Button(L10n.tr("settings.chooseImage", lang: language)) { showingBannerPicker = true }
                            .appStandardButton()
                        #endif
                        Button(L10n.tr("cover.titleHero", lang: language)) { showingBannerSearch = true }
                            .appStandardButton()
                            .help(L10n.tr("cover.titleHero", lang: language))
                        Button(L10n.tr("settings.removeBanner", lang: language)) { UserCustomization.removeBannerBackground() }
                            .appStandardButton()
                            .disabled(bannerBackgroundFile.isEmpty)
                    }
                }
                LText("settings.bannerHint")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(L10n.tr("settings.autoMatchCover", lang: language), isOn: $autoMatchCover)
                LText("settings.autoMatchCoverHint")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // 随机游戏底图偏好（轮播第 2 页）：默认横图优先；可选仅背景图/仅横向封面
                // （mac 横向封面全幅打底上下裁切影响观感，用户拍板给选择权 2026-09-05）。
                // iOS 上此键只管 iPad 竖屏 + iPhone（竖屏语义）；iPad 横屏用下面专用 Picker。
                Picker(L10n.tr("settings.spotlightBackdrop", lang: language), selection: $spotlightBackdropRaw) {
                    Text(verbatim: L10n.tr("settings.spotlightBackdropAuto", lang: language)).tag(UserCustomization.spotlightBackdropAuto)
                    Text(verbatim: L10n.tr("game.hero", lang: language)).tag(UserCustomization.spotlightBackdropHero)
                    Text(verbatim: L10n.tr("game.landscape", lang: language)).tag(UserCustomization.spotlightBackdropLandscape)
                }

                #if os(iOS)
                // iPad 横屏专用底图（仅 iPad 显示；iPhone 上第二个 Picker 无意义）。
                if iPadLayout.isPad {
                    Picker(L10n.tr("settings.spotlightBackdropPadLandscape", lang: language), selection: $spotlightBackdropPadLandscapeRaw) {
                        Text(verbatim: L10n.tr("settings.spotlightBackdropAuto", lang: language)).tag(UserCustomization.spotlightBackdropAuto)
                        Text(verbatim: L10n.tr("game.hero", lang: language)).tag(UserCustomization.spotlightBackdropHero)
                        Text(verbatim: L10n.tr("game.landscape", lang: language)).tag(UserCustomization.spotlightBackdropLandscape)
                    }
                }
                #endif

                #if os(macOS)
                Toggle(L10n.tr("settings.hideToolbarGlass", lang: language), isOn: $hideToolbarGlass)
                LText("settings.hideToolbarGlassHint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #endif

                Toggle(L10n.tr("settings.collectorMode", lang: language), isOn: $collectorMode)
                LText("settings.collectorModeHint")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if collectorMode {
                    Toggle(L10n.tr("settings.keepOriginalImages", lang: language), isOn: $keepOriginalImages)
                    LText("settings.keepOriginalImagesHint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle(L10n.tr("settings.platformIcons", lang: language), isOn: $showPlatformIcons)
                LText("settings.platformIconsHint")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // 网格极简模式（全平台；默认关）：网格卡仅封面 + 右上角胶囊 + 爱心角标。
                Toggle(L10n.tr("settings.minimalGrid", lang: language), isOn: $minimalGrid)
                LText("settings.minimalGridHint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.tr("settings.storage", lang: language)) {
                Text(verbatim: L10n.tr("settings.cacheSize", [ByteFormat.fileSize(cacheSizeBytes)], lang: language))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(L10n.tr("settings.cacheClear", lang: language)) { showingCacheConfirm = true }
                    .appStandardButton()
                if let cacheMessage {
                    Text(verbatim: cacheMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            #if !os(macOS)
            // iOS 无 app 菜单，「关于」入口放设置页底部（macOS 走 App 名菜单 → 关于）。
            Section {
                Button(L10n.tr("about.menu", lang: language)) { showingAbout = true }
                    .appStandardButton()
            }
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
            #endif
        }
        .formStyle(.grouped)
        .onAppear { refreshCacheSize() }
        #if os(macOS)
        .frame(width: 520, height: 720)
        #endif
        .platformConfirmDialog(
            L10n.tr("common.confirm", lang: language),
            isPresented: $showingCacheConfirm,
            message: L10n.tr("settings.cacheClearConfirm", lang: language),
            cancelTitle: L10n.tr("common.cancel", lang: language),
            actions: [
                ConfirmAction(title: L10n.tr("settings.cacheClear", lang: language)) { clearCache() }
            ]
        )
        .sheet(item: $cropSession) { session in
            ImageCropSheet(
                kind: session.kind,
                sourceImage: session.image,
                onCancel: { cropSession = nil },
                onConfirm: { result in
                    saveCrop(kind: session.kind, image: result)
                    cropSession = nil
                }
            )
        }
        .sheet(isPresented: $showingBannerSearch) {
            #if os(macOS)
            BannerSearchSheet()
            #else
            NavigationStack { BannerSearchSheet() }
            #endif
        }
        #if !os(macOS)
        .imageSourcePicker(isPresented: $showingAvatarPicker, onImages: { datas in
            if let data = datas.first, let image = AppImage(data: data) {
                cropSession = CropSession(kind: .avatar, image: image)
            }
        })
        .imageSourcePicker(isPresented: $showingBannerPicker, onImages: { datas in
            if let data = datas.first {
                try? UserCustomization.saveBannerBackgroundPNG(data)
            }
        })
        #endif
        #if os(macOS)
        // macOS 照片图库选图：与 iOS 相册分支同口径——Data → AppImage → 进既有裁切链。
        .photoLibraryPicker(isPresented: $showingAvatarLibrary, onImages: { datas in
            if let data = datas.first, let image = AppImage(data: data) {
                cropSession = CropSession(kind: .avatar, image: image)
            }
        })
        .photoLibraryPicker(isPresented: $showingIconLibrary, onImages: { datas in
            if let data = datas.first, let image = AppImage(data: data) {
                cropSession = CropSession(kind: .icon, image: image)
            }
        })
        .photoLibraryPicker(isPresented: $showingBannerLibrary, onImages: { datas in
            if let data = datas.first {
                try? UserCustomization.saveBannerBackgroundPNG(data)
            }
        })
        #endif
    }

    // MARK: - 个性化预览

    private var avatarPreview: some View {
        Group {
            if let img = UserCustomization.avatarImage() {
                Image(appImage: img)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }
        }
    }

    #if os(macOS)
    private var iconPreview: some View {
        Group {
            if let img = UserCustomization.iconImage() {
                Image(appImage: img)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }
        }
    }
    #endif

    /// 主页横幅背景预览（无背景回退品牌深色渐变），设置页内小尺寸缩略。
    private var bannerBackgroundPreview: some View {
        Group {
            if let img = UserCustomization.bannerBackgroundImage() {
                Image(appImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(
                        colors: [BrandPalette.gradientTop, BrandPalette.background],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.6))
                    }
            }
        }
        .frame(width: 76, height: 42)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary, lineWidth: 0.5))
    }

    // MARK: - 选图 + 裁切

    private func pickImage(for kind: CropKind) {
        #if os(macOS)
        // 类型统一走 ImageImport.allowedTypes（历史四类型收紧遗留，放宽无副作用：裁切链转 PNG 落盘）。
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ImageImport.allowedTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let image = loadAppImage(from: url) else { return }
        cropSession = CropSession(kind: kind, image: image)
        #else
        // iOS：阶段 3 用 PhotosPicker 实现选图 + 裁切。
        #endif
    }

    private func saveCrop(kind: CropKind, image: AppImage) {
        guard let data = image.pngData() else { return }
        do {
            switch kind {
            case .avatar: try UserCustomization.saveAvatarPNG(data)
            case .icon: try UserCustomization.saveIconPNG(data)
            }
        } catch {
            // 保存失败（磁盘满等罕见情况）静默；下次打开设置仍显示原值
        }
    }

    /// 主页横幅背景（macOS 文件面板）：不裁切不压缩、原样存盘（显示时等比填充裁边）。
    /// iOS 走 `.imageSourcePicker`（相册/文件/拍照），不经此路径。
    private func pickBannerBackground() {
        guard let data = ImageImport.pickOneFromPanel(), AppImage(data: data) != nil else { return }
        try? UserCustomization.saveBannerBackgroundPNG(data)
    }

    // MARK: - 缓存

    private func clearCache() {
        let freed = CacheCleaner.clear()
        cacheSizeBytes = CacheCleaner.diskSize()
        cacheMessage = L10n.tr("settings.cacheCleared", [ByteFormat.fileSize(freed)], lang: language)
    }

    private func refreshCacheSize() {
        cacheSizeBytes = CacheCleaner.diskSize()
    }
}

/// 一次「选图 → 裁切」会话，供 .sheet(item:) 驱动。
private struct CropSession: Identifiable {
    let id = UUID()
    let kind: CropKind
    let image: AppImage
}
