import SwiftUI
import SwiftData

#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#else
import PhotosUI
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
    #if !os(macOS)
    @State private var showingAvatarPicker = false
    @State private var showingBackupImporter = false
    @State private var backupShareURL: URL?
    @State private var showingShareSheet = false
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
                        #else
                        Button(L10n.tr("settings.chooseImage", lang: language)) { showingAvatarPicker = true }
                        #endif
                        Button(L10n.tr("settings.removeAvatar", lang: language)) { UserCustomization.removeAvatar() }
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
            }

            Section(L10n.tr("settings.steamgriddb", lang: language)) {
                SecureField(L10n.tr("settings.steamGridDBKey", lang: language), text: $steamGridDBKey)
                    .textFieldStyle(.roundedBorder)
                LText("settings.steamGridDBHint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.tr("settings.backup", lang: language)) {
                #if os(macOS)
                Button(L10n.tr("backup.export", lang: language)) { export() }
                Button(L10n.tr("backup.import", lang: language)) { showingImportConfirm = true }
                #else
                Button(L10n.tr("backup.export", lang: language)) { prepareBackupShare() }
                Button(L10n.tr("backup.import", lang: language)) { showingBackupImporter = true }
                #endif
                if let statusMessage {
                    Text(verbatim: statusMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
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
        .fileImporter(isPresented: $showingBackupImporter, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result {
                do {
                    let data = try Data(contentsOf: url)
                    try BackupManager.decodeAndReplace(data, into: context)
                    try context.save()
                    statusMessage = L10n.tr("backup.importDone", lang: language)
                } catch {
                    statusMessage = L10n.tr("backup.importFailed", lang: language)
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = backupShareURL {
                ShareLink(item: url) {
                    Label(L10n.tr("backup.export", lang: language), systemImage: "square.and.arrow.up")
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
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
    /// iOS 备份导出：编码成 JSON → 写临时文件 → 打开系统分享单（含 AirDrop）。
    private func prepareBackupShare() {
        guard let data = try? BackupManager.encode(games: games, groups: groups) else {
            statusMessage = L10n.tr("backup.exportFailed", lang: language)
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("GameLog-backup.json")
        if (try? data.write(to: url)) != nil {
            backupShareURL = url
            showingShareSheet = true
        } else {
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
        do {
            let data = try Data(contentsOf: url)
            try BackupManager.decodeAndReplace(data, into: context)
            try context.save()
            statusMessage = L10n.tr("backup.importDone", lang: language)
        } catch {
            statusMessage = L10n.tr("backup.importFailed", lang: language)
        }
        #else
        // iOS：阶段 3 用 fileImporter 实现备份导入。
        #endif
    }
}

/// 一次「选图 → 裁切」会话，供 .sheet(item:) 驱动。
private struct CropSession: Identifiable {
    let id = UUID()
    let kind: CropKind
    let image: AppImage
}
