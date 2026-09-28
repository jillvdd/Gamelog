import SwiftUI
import SwiftData

#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#else
import UIKit
import UniformTypeIdentifiers
#endif

/// 关联设置：跟**外部服务**有关的三件事 —— SteamGridDB API Key、游戏账号、数据备份。
///
/// 这三样此前都住在「设置」里，但它们本质上不是「本机偏好」：一个是外部服务的凭证，
/// 一个是外部服务的绑定与网络同步，一个是整库的导入导出。2026-09-18 用户决定把它们整体
/// 搬到这里，入口分两端：
/// - **macOS**：App 菜单「设置…」正下方的第二个菜单项（⌘⇧,），开一个独立窗口；
/// - **iOS / iPadOS**：底部页签栏「统计」与「设置」之间的第三个位置。
///
/// 游戏账号这一节**不是一层跳转**：账号列表与同步动作直接铺在页面上，只有点某一个具体
/// 账号才 push 进二级页（用户明确要求）。为此这一页**必须**有 `NavigationStack`
/// （macOS 也是）—— 账号行是 `NavigationLink(value:)` + `navigationDestination` 的 push。
///
/// 版式与设置页同源（`Form` + `.formStyle(.grouped)`）：这两页在用户眼里是同胞，
/// 用同一套版式才能在两个窗口之间来回看时不觉得换了个 app。
struct LinkSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    @AppStorage("steamGridDBKey") private var steamGridDBKey = ""
    @AppStorage(UserCustomization.autoBackupKey) private var autoBackup = true
    /// iOS 的页标题按「隐藏上方毛玻璃」惯例可置空（同 `StatsView`）；macOS 不用它，
    /// 标题由 `Window` 场景给（见下）。
    @AppStorage(UserCustomization.hideToolbarGlassKey) private var hideToolbarGlass = false

    /// 导出只导出游戏与分组（备份 DTO 的入口参数），这两条查询**只**被备份路径用。
    @Query(sort: \Game.createdAt) private var games: [Game]
    @Query(sort: \GameGroup.name) private var groups: [GameGroup]
    @Query(sort: \LinkedAccount.linkedAt) private var accounts: [LinkedAccount]

    // MARK: - 账号状态

    @State private var showingAdd = false
    @State private var syncing: Set<UUID> = []
    @State private var banner: String?

    /// 还活着的账号。解绑会 `context.delete(account)` + `save()`，而 `@Query` 结果数组
    /// 会滞后一帧 —— 读死账号的 `displayName` / `localId` 就是 SwiftData fatal
    ///（判据见 `Game.isLive`）。本页所有列表与反查都从这一个入口取。
    private var liveAccounts: [LinkedAccount] { accounts.filter(\.isLive) }

    // MARK: - SteamGridDB key 状态

    /// key 是否明文显示。
    @State private var showKey = false
    /// key 验证状态（改动时自动校验，✓/✗）。
    @State private var keyStatus: SteamGridDBKeyStatus = .idle
    /// 最近一次已验证为有效的 key（避免重复请求）。
    @State private var validatedKey = ""
    @State private var keyValidationTask: Task<Void, Never>?

    // MARK: - 备份状态

    @State private var statusMessage: String?
    @State private var showingImportConfirm = false
    /// macOS 分享备份：待分享的临时文件 URL + 分享面板锚点触发开关。
    @State private var backupShareURL: URL?
    @State private var showingBackupShare = false
    /// 导出禁重入（2026-09-08）：BackupManager.encode 主线程同步编码，800MB 库
    /// 数秒卡死；连点会叠多个 1GB Data 编码。置位期间禁用导出按钮。
    @State private var isExporting = false
    /// 是否显示「从自动备份恢复」确认。
    @State private var showingAutoRestoreConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                steamGridDBSection
                accountsSection
                if !liveAccounts.isEmpty { accountsActionsSection }
                addAccountSection
                backupSection
            }
            .formStyle(.grouped)
            .navigationDestination(for: UUID.self) { id in
                // 按 localId 反查而不是把对象本身塞进导航值：解绑会把账号删掉，
                // 反查让「已经不存在」变成一个可表达的状态，而不是去碰一个已删除的对象。
                if let account = liveAccounts.first(where: { $0.localId == id }) {
                    ExternalAccountDetailView(account: account)
                } else {
                    Color.clear
                }
            }
            #if !os(macOS)
            .navigationTitle(hideToolbarGlass ? "" : L10n.tr("links.title", lang: language))
            #endif
        }
        .sheet(isPresented: $showingAdd) {
            AddExternalAccountView { account in
                showingAdd = false
                sync(account)
            }
        }
        #if os(macOS)
        // 用 min 而非固定：这一页要能装下详情子页（比它更长），也要能拉大看长账号列表。
        .frame(minWidth: 520, minHeight: 640)
        #endif
        // 这三个 modifier 是 key 校验的**唯一驱动**，必须跟着这一节走：
        // 留在设置页就会静默失效（那一页已经不认识这个 key 了）。
        .onAppear { validateKey() }
        .onChange(of: steamGridDBKey) { _, _ in validateKey() }
        .onDisappear { keyValidationTask?.cancel() }
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
    }

    // MARK: - 分区

    private var steamGridDBSection: some View {
        Section(L10n.tr("links.steamgriddb", lang: language)) {
            HStack(spacing: 8) {
                Group {
                    if showKey {
                        TextField(L10n.tr("links.steamGridDBKey", lang: language), text: $steamGridDBKey)
                    } else {
                        SecureField(L10n.tr("links.steamGridDBKey", lang: language), text: $steamGridDBKey)
                    }
                }
                .textFieldStyle(.roundedBorder)

                Button {
                    showKey.toggle()
                } label: {
                    Image(systemName: showKey ? "eye.slash" : "eye")
                }
                .appStandardButton()
                .help(L10n.tr(showKey ? "links.hideKey" : "links.showKey", lang: language))

                Button {
                    copyKey()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .appStandardButton()
                .help(L10n.tr("links.copyKey", lang: language))

                keyStatusIcon
                    .frame(width: 20, height: 20)
            }
            LText("links.steamGridDBHint")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// 游戏账号列表：本节就是「账号页」的全部内容，不是通往账号页的入口。
    private var accountsSection: some View {
        Section {
            if liveAccounts.isEmpty {
                LText("account.empty")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(liveAccounts) { account in
                    NavigationLink(value: account.localId) {
                        ExternalAccountRow(account: account,
                                           syncing: syncing.contains(account.localId)) {
                            sync(account)
                        }
                    }
                }
            }
        } header: {
            HStack(spacing: 6) {
                Text(verbatim: L10n.tr("links.accounts", lang: language))
                TagLabel(text: L10n.tr("account.experimental", lang: language), tint: .orange)
            }
        } footer: {
            // 两段都是**用户可见的安全声明**，不能因为「列表内联了」就丢掉其一：
            // experimentalHint 说明接口性质与第三方网关，accountsHint 说明凭证只进本机钥匙串。
            // 旧版里前者在账号页、后者在设置页那行入口的说明文字上，内联后合并到同一个 footer。
            VStack(alignment: .leading, spacing: 4) {
                LText("account.experimentalHint")
                LText("links.accountsHint")
            }
        }
    }

    private var accountsActionsSection: some View {
        Section {
            Button { syncAll() } label: {
                Label(L10n.tr("account.syncAll", lang: language),
                      systemImage: AccountUI.syncIcon)
            }
            .appStandardButton()
            .disabled(!syncing.isEmpty)
            if let banner {
                Text(verbatim: banner)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var addAccountSection: some View {
        Section {
            Button { showingAdd = true } label: {
                Label(L10n.tr("account.add", lang: language), systemImage: "plus")
            }
            .appStandardButton()
        }
    }

    private var backupSection: some View {
        Section(L10n.tr("links.backup", lang: language)) {
            Toggle(L10n.tr("links.autoBackup", lang: language), isOn: $autoBackup)
            LText("links.autoBackupHint")
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
                    .disabled(isExporting)
                Button {
                    shareBackup()
                } label: {
                    Label(L10n.tr("backup.share", lang: language), systemImage: "square.and.arrow.up")
                }
                .appStandardButton()
                .disabled(isExporting)
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
                .disabled(isExporting)
            Button(L10n.tr("backup.import", lang: language)) { importBackup() }
                .appStandardButton()
            #endif
            if let statusMessage {
                Text(verbatim: statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 同步

    private func sync(_ account: LinkedAccount) {
        guard !syncing.contains(account.localId) else { return }
        // 记下 localId 再进 Task：await 期间用户完全可能解绑这个账号（对象被删），
        // await 之后**不能再碰 `account`**（读 `displayName` 即 SwiftData fatal）。
        // 本行自身仍要读一次，先在这里取好。
        let localId = account.localId
        let displayName = account.displayName
        syncing.insert(localId)
        banner = nil
        Task { @MainActor in
            let result = await ExternalSyncDriver.sync(account, container: context.container,
                                                       language: AppLanguage(localeCode: language))
            syncing.remove(localId)
            // 账号已不在库里（解绑了）：这轮结果无处可归属，直接丢弃。
            guard accounts.contains(where: { $0.localId == localId }) else { return }
            banner = result.isSuccess
                ? L10n.tr("account.syncDone", [displayName, result.summary.processed], lang: language)
                : L10n.tr("account.syncFailed", [displayName], lang: language)
        }
    }

    private func syncAll() {
        let targets = accounts.filter(\.isLive)
        guard !targets.isEmpty else { return }
        syncing = Set(targets.map(\.localId))
        banner = nil
        Task { @MainActor in
            let results = await ExternalSyncDriver.syncAll(targets, container: context.container,
                                                           language: AppLanguage(localeCode: language))
            syncing.removeAll()
            let succeeded = results.values.filter(\.isSuccess).count
            banner = L10n.tr("account.syncAllDone", [succeeded, results.count], lang: language)
        }
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
                .help(L10n.tr("links.keyValid", lang: language))
        case .invalid:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .help(L10n.tr("links.keyInvalid", lang: language))
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
    /// 防抖 400ms + 代际守卫，只在停止输入后发一次请求；打开本页也会校验一次。
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

    // MARK: - 备份

    /// 备份导出文件名（macOS NSSavePanel 预填名 / 双平台分享临时文件共用；POSIX locale 保证格式稳定）。
    private func backupFileName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HH-mm"
        return "GameLog-backup-\(formatter.string(from: Date())).json"
    }

    /// 导出统一路径：ModelActor 后台逐游戏流式编码写盘（内存峰值 = 单游戏片段）。
    /// 旧 BackupManager.encode 在主线程序列化整库，GB 级库必卡死（2026-09-23 替换）。
    /// `atomic`=false 供 NSSavePanel 目标直写：powerbox 只授权选定文件本身，同目录临时件会被拒。
    private func streamExportBackup(to url: URL, atomic: Bool = true) async throws {
        let writer = BackupWriter(modelContainer: context.container)
        try await writer.writeStreamingBackup(
            to: url,
            username: UserDefaults.standard.string(forKey: UserCustomization.usernameKey),
            avatarPNG: UserCustomization.avatarImageData(),
            iconPNG: UserCustomization.iconImageData(),
            bannerTitle: UserDefaults.standard.string(forKey: UserCustomization.bannerTitleKey),
            bannerSubtitle: UserDefaults.standard.string(forKey: UserCustomization.bannerSubtitleKey),
            bannerBackgroundPNG: UserCustomization.bannerBackgroundImageData(),
            atomic: atomic
        )
    }

    /// 起后台导出任务：期间按钮禁用 + 「正在导出」状态，完成/失败回填文案。
    private func startStreamingExport(to url: URL, atomic: Bool = true,
                                      onDone: @escaping @MainActor () -> Void = {}) {
        isExporting = true
        statusMessage = L10n.tr("backup.exporting", lang: language)
        let language = language
        Task { @MainActor in
            defer { isExporting = false }
            do {
                try await streamExportBackup(to: url, atomic: atomic)
                onDone()
            } catch {
                NSLog("GameLog export failed: %@", String(describing: error))
                statusMessage = L10n.tr("backup.exportFailed", lang: language)
            }
        }
    }

    #if os(macOS)
    private func export() {
        // 禁重入：导出进行中按钮已禁用，此处双保险（2026-09-08）。
        guard !isExporting else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = backupFileName()
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        startStreamingExport(to: url, atomic: false) {
            statusMessage = L10n.tr("backup.exportDone", lang: language)
        }
    }

    /// macOS 分享备份：后台流式导出临时文件 → 完成后从按钮位置弹系统分享面板（含 AirDrop）。
    private func shareBackup() {
        guard !isExporting else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(backupFileName())
        startStreamingExport(to: url) {
            self.statusMessage = nil
            self.backupShareURL = url
            self.showingBackupShare = true
        }
    }
    #endif

    #if !os(macOS)
    /// iOS 备份导出：后台流式写临时文件 → 完成后直接用 UIKit 呈现系统分享单（含 AirDrop / 存储到文件）。
    /// 不走 SwiftUI sheet：挂 Form 行按钮上的 sheet 首次弹窗会呈现为空白、静默失败（先弹别的窗可「预热」）。
    private func prepareBackupShare() {
        guard !isExporting else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(backupFileName())
        let language = language
        startStreamingExport(to: url) {
            if !presentShareSheet(url: url) {
                statusMessage = L10n.tr("backup.exportFailed", lang: language)
            } else {
                statusMessage = nil
            }
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

    /// 解码并整库替换：读盘/解码/落库失败分型报错（统一走 AutoBackup.importBackup(fromFile:)，
    /// 与 AirDrop/打开方式入口同一实现，防口径漂移）。
    private func importBackupData(from url: URL, requestAccess: Bool) {
        let context = context
        let language = language
        Task { @MainActor in
            statusMessage = L10n.tr("backup.importing", lang: language)
            do {
                try await AutoBackup.shared.importBackup(fromFile: url, into: context,
                                                         requestAccess: requestAccess) { _ in }
                statusMessage = L10n.tr("backup.importDone", lang: language)
            } catch {
                NSLog("GameLog import failed: %@", String(describing: error))
                statusMessage = importFailMessageForUser(error, lang: language)
            }
        }
    }


    @ViewBuilder
    private var backupInfoRow: some View {
        if let date = AutoBackup.lastBackupDate {
            Text(verbatim: L10n.tr(
                "backup.lastBackup",
                ["\(date.formatted(date: .abbreviated, time: .shortened))（\(ByteFormat.fileSize(Int64(AutoBackup.lastBackupSize)))）"],
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
        // 统一入口是 async：包 Task，后台重建期间主线程不卡，完成后回填状态。
        // 进度遮罩由根容器按 importProgress 自动呈现。
        let context = context
        Task { @MainActor in
            do {
                try await AutoBackup.shared.restoreFromAutoBackup(context: context) { _ in }
                statusMessage = L10n.tr("backup.restoreDone", lang: language)
            } catch {
                statusMessage = L10n.tr("backup.restoreFailed", lang: language)
            }
        }
    }
}

/// SteamGridDB key 校验状态：无输入=idle，校验中=checking，通过=valid，失败=invalid。
private enum SteamGridDBKeyStatus {
    case idle, checking, valid, invalid
}
