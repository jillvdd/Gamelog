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
    @AppStorage(UserCustomization.autoBackupKey) private var autoBackup = true

    /// 用户名绑定：写入时截断到上限。用 Binding 替代 `.onChange`——`.onChange` 挂 TextField 在 macOS 会吞尾随空格。
    private var usernameBinding: Binding<String> {
        Binding(
            get: { username },
            set: { username = String(Array($0).prefix(UserCustomization.usernameMaxLength)) }
        )
    }

    @Query(sort: \Game.createdAt) private var games: [Game]
    @Query(sort: \GameGroup.name) private var groups: [GameGroup]

    @State private var statusMessage: String?
    @State private var showingImportConfirm = false
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
    #if !os(macOS)
    @State private var showingAvatarPicker = false
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
                        Button(L10n.tr("settings.restoreIcon", lang: language)) { UserCustomization.removeIcon() }
                            .disabled(iconFile.isEmpty)
                    }
                }
                #endif

                Toggle(L10n.tr("settings.autoMatchCover", lang: language), isOn: $autoMatchCover)
                LText("settings.autoMatchCoverHint")
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
                    #if os(macOS)
                    .buttonStyle(.borderless)
                    #endif
                    .appStandardButton()
                    .help(L10n.tr(showKey ? "settings.hideKey" : "settings.showKey", lang: language))

                    Button {
                        copyKey()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    #if os(macOS)
                    .buttonStyle(.borderless)
                    #endif
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
                Button(L10n.tr("backup.export", lang: language)) { export() }
                Button(L10n.tr("backup.import", lang: language)) { showingImportConfirm = true }
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
        #if !os(macOS)
        .imageSourcePicker(isPresented: $showingAvatarPicker, onImages: { datas in
            if let data = datas.first, let image = AppImage(data: data) {
                cropSession = CropSession(kind: .avatar, image: image)
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
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
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

    // MARK: - 备份

    private func export() {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HH-mm"
        panel.nameFieldStringValue = "GameLog-backup-\(formatter.string(from: Date())).json"
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

    #if !os(macOS)
    /// iOS 备份导出：编码成 JSON → 写临时文件 → 直接用 UIKit 呈现系统分享单（含 AirDrop / 存储到文件）。
    /// 不走 SwiftUI sheet：挂 Form 行按钮上的 sheet 首次弹窗会呈现为空白、静默失败（先弹别的窗可「预热」）。
    private func prepareBackupShare() {
        guard let data = try? BackupManager.encode(games: games, groups: groups) else {
            statusMessage = L10n.tr("backup.exportFailed", lang: language)
            return
        }
        // 文件名带时间，与 macOS 导出（NSSavePanel 预填名）同一格式。
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GameLog-backup-\(formatter.string(from: Date())).json")
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
        AutoBackup.shared.writeNow()
        statusMessage = L10n.tr("backup.nowDone", lang: language)
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
