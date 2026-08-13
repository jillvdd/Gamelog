import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

/// 设置：语言（中日英）、个性化（用户名/头像/图标）、SteamGridDB key、数据备份。
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    @AppStorage("appLanguage") private var languageCode = AppLanguage.chinese.localeCode
    @AppStorage("steamGridDBKey") private var steamGridDBKey = ""

    @AppStorage(UserCustomization.usernameKey) private var username = ""
    @AppStorage(UserCustomization.avatarFileKey) private var avatarFile = ""
    @AppStorage(UserCustomization.iconFileKey) private var iconFile = ""
    @AppStorage(UserCustomization.autoMatchCoverKey) private var autoMatchCover = false
    @AppStorage(UserCustomization.hideToolbarGlassKey) private var hideToolbarGlass = false
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
                        Button(L10n.tr("settings.chooseImage", lang: language)) { pickImage(for: .avatar) }
                        Button(L10n.tr("settings.removeAvatar", lang: language)) { UserCustomization.removeAvatar() }
                            .disabled(avatarFile.isEmpty)
                    }
                }

                LabeledContent(L10n.tr("settings.icon", lang: language)) {
                    HStack {
                        iconPreview
                        Button(L10n.tr("settings.chooseImage", lang: language)) { pickImage(for: .icon) }
                        Button(L10n.tr("settings.restoreIcon", lang: language)) { UserCustomization.removeIcon() }
                            .disabled(iconFile.isEmpty)
                    }
                }

                Toggle(L10n.tr("settings.autoMatchCover", lang: language), isOn: $autoMatchCover)
                LText("settings.autoMatchCoverHint")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(L10n.tr("settings.hideToolbarGlass", lang: language), isOn: $hideToolbarGlass)
                LText("settings.hideToolbarGlassHint")
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
                Button(L10n.tr("backup.export", lang: language)) { export() }
                Button(L10n.tr("backup.import", lang: language)) { showingImportConfirm = true }
                if let statusMessage {
                    Text(verbatim: statusMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 720)
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
    }

    // MARK: - 个性化预览

    private var avatarPreview: some View {
        Group {
            if let img = UserCustomization.avatarImage() {
                Image(nsImage: img)
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

    private var iconPreview: some View {
        Group {
            if let img = UserCustomization.iconImage() {
                Image(nsImage: img)
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

    // MARK: - 选图 + 裁切

    private func pickImage(for kind: CropKind) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let image = NSImage(contentsOf: url) else { return }
        cropSession = CropSession(kind: kind, image: image)
    }

    private func saveCrop(kind: CropKind, image: NSImage) {
        guard let data = UserCustomization.pngData(from: image) else { return }
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
            statusMessage = L10n.tr("backup.importFailed", lang: language)
        }
    }

    private func importBackup() {
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
    }
}

/// 一次「选图 → 裁切」会话，供 .sheet(item:) 驱动。
private struct CropSession: Identifiable {
    let id = UUID()
    let kind: CropKind
    let image: NSImage
}
