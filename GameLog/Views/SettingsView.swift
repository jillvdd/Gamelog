import SwiftUI
import SwiftData

#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#else
import PhotosUI
import UIKit
import UniformTypeIdentifiers
#endif

/// 设置：语言（中日英）、个性化（用户名/头像/图标）、SteamGridDB key、数据备份。
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    @AppStorage("appLanguage") private var languageCode = AppLanguage.chinese.localeCode
    @AppStorage("steamGridDBKey") private var steamGridDBKey = ""

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
    @AppStorage(UserCustomization.autoBackupKey) private var autoBackup = true
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

    @Query(sort: \Game.createdAt) private var games: [Game]
    @Query(sort: \GameGroup.name) private var groups: [GameGroup]

    @State private var statusMessage: String?
    @State private var showingImportConfirm = false
    /// macOS 分享备份：待分享的临时文件 URL + 分享面板锚点触发开关。
    @State private var backupShareURL: URL?
    @State private var showingBackupShare = false
    @State private var cropSession: CropSession?
    /// SteamGridDB key 是否明文显示。
    @State private var showKey = false
    /// SteamGridDB key 验证状态（改动时自动校验，✓/✗）。
    @State private var keyStatus: SteamGridDBKeyStatus = .idle
    /// 最近一次已验证为有效的 key（避免重复请求）。
    @State private var validatedKey = ""
    @State private var keyValidationTask: Task<Void, Never>?
    /// 是否显示「从自动备份恢复」确认。
    @State private var showingAutoRestoreConfirm = false
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

            Section(L10n.tr("settings.steamgriddb", lang: language)) {
                HStack(spacing: 8) {
                    Group {
                        if showKey {
                            TextField(L10n.tr("settings.steamGridDBKey", lang: language), text: $steamGridDBKey)
                        } else {
                            SecureField(L10n.tr("settings.steamGridDBKey", lang: language), text: $steamGridDBKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)

                    Button {
                        showKey.toggle()
                    } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                    }
                    .appStandardButton()
                    .help(L10n.tr(showKey ? "settings.hideKey" : "settings.showKey", lang: language))

                    Button {
                        copyKey()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .appStandardButton()
                    .help(L10n.tr("settings.copyKey", lang: language))

                    keyStatusIcon
                        .frame(width: 20, height: 20)
                }
                LText("settings.steamGridDBHint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.tr("settings.backup", lang: language)) {
                Toggle(L10n.tr("settings.autoBackup", lang: language), isOn: $autoBackup)
                LText("settings.autoBackupHint")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                backupInfoRow

                Button(L10n.tr("backup.backupNow", lang: language)) { backupNow() }
                    .appStandardButton()
                Button(L10n.tr("backup.autobackupRestore", lang: language)) { showingAutoRestoreConfirm = true }
                    .appStandardButton()

                #if os(macOS)
                HStack {
                    Button(L10n.tr("backup.export", lang: language)) { export() }
                        .appStandardButton()
                    Button {
                        shareBackup()
                    } label: {
                        Label(L10n.tr("backup.share", lang: language), systemImage: "square.and.arrow.up")
                    }
                    .appStandardButton()
                    // 系统分享面板（含 AirDrop）从本按钮位置弹出；anchor 隐藏在按钮背后。
                    .background {
                        if let url = backupShareURL {
                            MacSharingAnchor(isPresented: $showingBackupShare) { [url] }
                        }
                    }
                }
                Button(L10n.tr("backup.import", lang: language)) { showingImportConfirm = true }
                    .appStandardButton()
                #else
                // iOS：导出分享单由 prepareBackupShare 直接以 UIKit 呈现（不走 SwiftUI sheet，
                // 规避 sheet 首次弹出为空白、需先弹其他窗「预热」的问题）。
                Button(L10n.tr("backup.export", lang: language)) { prepareBackupShare() }
                    .appStandardButton()
                Button(L10n.tr("backup.import", lang: language)) { importBackup() }
                    .appStandardButton()
                #endif
                if let statusMessage {
                    Text(verbatim: statusMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section(L10n.tr("settings.storage", lang: language)) {
                Text(verbatim: L10n.tr("settings.cacheSize", [formatSize(Int(cacheSizeBytes))], lang: language))
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
        .onAppear { validateKey(); refreshCacheSize() }
        .onChange(of: steamGridDBKey) { _, _ in validateKey() }
        .onDisappear { keyValidationTask?.cancel() }
        #if os(macOS)
        .frame(width: 520, height: 720)
        #endif
        .confirmationDialog(
            L10n.tr("common.confirm", lang: language),
            isPresented: $showingImportConfirm,
            titleVisibility: .visible
        ) {
            Button(L10n.tr("common.confirm", lang: language)) { importBackup() }
            Button(L10n.tr("common.cancel", lang: language), role: .cancel) {}
        } message: {
            LText("backup.importConfirm")
        }
        .platformConfirmDialog(
            L10n.tr("common.confirm", lang: language),
            isPresented: $showingAutoRestoreConfirm,
            message: L10n.tr("backup.autobackupRestoreConfirm", lang: language),
            cancelTitle: L10n.tr("common.cancel", lang: language),
            actions: [
                ConfirmAction(title: L10n.tr("common.confirm", lang: language)) { restoreFromAutoBackup() }
            ]
        )
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
                        colors: [Color(red: 0.13, green: 0.115, blue: 0.09),
                                 Color(red: 0.075, green: 0.067, blue: 0.055)],
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

    // MARK: - SteamGridDB key 验证

    /// key 验证状态图标：空=无、转圈=验证中、✓=有效、✗=无效。
    @ViewBuilder
    private var keyStatusIcon: some View {
        switch keyStatus {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .valid:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help(L10n.tr("settings.keyValid", lang: language))
        case .invalid:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .help(L10n.tr("settings.keyInvalid", lang: language))
        }
    }

    /// 复制 key（复制净化后的值，不带网页粘贴进来的多余文字）。
    private func copyKey() {
        let key = SteamGridDBClient.sanitizedKey(steamGridDBKey)
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(key, forType: .string)
        #else
        UIPasteboard.general.string = key
        #endif
    }

    /// 校验 key 可用性：取净化后的 key，调 SteamGridDB 搜索接口，200=✓、失败=✗。
    /// 防抖 400ms + 代际守卫，只在停止输入后发一次请求；打开设置页也会校验一次。
    private func validateKey() {
        keyValidationTask?.cancel()
        let key = SteamGridDBClient.sanitizedKey(steamGridDBKey)
        guard !key.isEmpty else {
            keyStatus = .idle
            validatedKey = ""
            return
        }
        if keyStatus == .valid, validatedKey == key { return }
        validatedKey = key
        keyStatus = .checking
        let task = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            do {
                _ = try await SteamGridDBClient(apiKey: key).search(term: "zelda")
                guard !Task.isCancelled else { return }
                keyStatus = .valid
            } catch {
                guard !Task.isCancelled else { return }
                keyStatus = .invalid
            }
        }
        keyValidationTask = task
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

    // MARK: - 备份

    /// 备份导出文件名（macOS NSSavePanel 预填名 / 双平台分享临时文件共用；POSIX locale 保证格式稳定）。
    private func backupFileName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HH-mm"
        return "GameLog-backup-\(formatter.string(from: Date())).json"
    }

    private func export() {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = backupFileName()
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try BackupManager.encode(games: games, groups: groups)
            try data.write(to: url)
            statusMessage = L10n.tr("backup.exportDone", lang: language)
        } catch {
            statusMessage = L10n.tr("backup.exportFailed", lang: language)
        }
        #else
        // iOS：阶段 3 用 ShareLink（系统分享单，含 AirDrop）导出备份。
        #endif
    }

    #if os(macOS)
    /// macOS 分享备份：编码整库 → 写临时文件 → 从「分享备份」按钮位置弹出系统分享面板（含 AirDrop）。
    /// 同步编码与 export() / iOS prepareBackupShare 口径一致。
    private func shareBackup() {
        guard let data = try? BackupManager.encode(games: games, groups: groups) else {
            statusMessage = L10n.tr("backup.exportFailed", lang: language)
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(backupFileName())
        guard (try? data.write(to: url)) != nil else {
            statusMessage = L10n.tr("backup.exportFailed", lang: language)
            return
        }
        backupShareURL = url
        showingBackupShare = true
    }
    #endif

    #if !os(macOS)
    /// iOS 备份导出：编码成 JSON → 写临时文件 → 直接用 UIKit 呈现系统分享单（含 AirDrop / 存储到文件）。
    /// 不走 SwiftUI sheet：挂 Form 行按钮上的 sheet 首次弹窗会呈现为空白、静默失败（先弹别的窗可「预热」）。
    private func prepareBackupShare() {
        guard let data = try? BackupManager.encode(games: games, groups: groups) else {
            statusMessage = L10n.tr("backup.exportFailed", lang: language)
            return
        }
        // 文件名带时间，与 macOS 导出（NSSavePanel 预填名）同一格式。
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(backupFileName())
        guard (try? data.write(to: url)) != nil else {
            statusMessage = L10n.tr("backup.exportFailed", lang: language)
            return
        }
        if !presentShareSheet(url: url) {
            statusMessage = L10n.tr("backup.exportFailed", lang: language)
        }
    }
    #endif

    private func importBackup() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importBackupData(from: url, requestAccess: false)
        #else
        // iOS：裸 UIDocumentPickerViewController（DocumentPicker），不走 SwiftUI fileImporter。
        DocumentPicker.present(types: [.json]) { url in
            self.importBackupData(from: url, requestAccess: true)
        }
        #endif
    }

    /// 解码并整库替换。iOS 的「文件」App URL 在安全沙盒作用域外，需先取得安全作用域授权才能读取，
    /// 否则 Data(contentsOf:) 抛权限错误被静默吞掉（与 onOpenURL 路径一致）。
    private func importBackupData(from url: URL, requestAccess: Bool) {
        let didStart = requestAccess ? url.startAccessingSecurityScopedResource() : false
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            AutoBackup.shared.writeSnapshot(context: context)
            try BackupManager.decodeAndReplace(data, into: context)
            try context.save()
            statusMessage = L10n.tr("backup.importDone", lang: language)
        } catch {
            statusMessage = L10n.tr("backup.importFailed", lang: language)
        }
    }

    // MARK: - 自动备份 + 缓存

    @ViewBuilder
    private var backupInfoRow: some View {
        if let date = AutoBackup.lastBackupDate {
            Text(verbatim: L10n.tr(
                "backup.lastBackup",
                ["\(date.formatted(date: .abbreviated, time: .shortened))（\(formatSize(AutoBackup.lastBackupSize))）"],
                lang: language
            ))
            .font(.callout)
            .foregroundStyle(.secondary)
        } else {
            LText("backup.noBackupYet")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func backupNow() {
        // 据实提示：写盘失败（磁盘满等）时不再误报「已保存备份」。
        // 编码在后台进行，完成后回填状态消息（主线程不阻塞，按钮期间不转圈——大库下也秒回）。
        AutoBackup.shared.writeNowAsync { ok in
            statusMessage = ok
                ? L10n.tr("backup.nowDone", lang: language)
                : L10n.tr("backup.nowFailed", lang: language)
        }
    }

    private func restoreFromAutoBackup() {
        let ok = AutoBackup.shared.restoreFromAutoBackup(context: context)
        statusMessage = ok
            ? L10n.tr("backup.restoreDone", lang: language)
            : L10n.tr("backup.restoreFailed", lang: language)
    }

    private func clearCache() {
        let freed = CacheCleaner.clear()
        cacheSizeBytes = CacheCleaner.diskSize()
        cacheMessage = L10n.tr("settings.cacheCleared", [formatSize(Int(freed))], lang: language)
    }

    private func refreshCacheSize() {
        cacheSizeBytes = CacheCleaner.diskSize()
    }

    private func formatSize(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// 一次「选图 → 裁切」会话，供 .sheet(item:) 驱动。
private struct CropSession: Identifiable {
    let id = UUID()
    let kind: CropKind
    let image: AppImage
}

/// SteamGridDB key 校验状态：无输入=idle，校验中=checking，通过=valid，失败=invalid。
private enum SteamGridDBKeyStatus {
    case idle, checking, valid, invalid
}
