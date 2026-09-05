import Foundation
import SwiftData
import SwiftUI
import Combine
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// 自动备份管理器：监听 SwiftData 保存事件，防抖 3 秒后把完整备份（与手动导出同格式）
/// 原子写入本地滚动文件。附带版本升级前快照、恢复/导入前快照、启动空库检测恢复。
///
/// 2026-08-29 性能改造：编码与写盘全部移到 BackupWriter（ModelActor 后台上下文），
/// 逐游戏分片流式写——主线程只剩事件转发。启动检查不再同步写盘（后台进行，
/// 完成后更新「最后备份」元数据）；iOS 退后台不再同步编码（等回到前台/下次启动补写）。
///
/// 文件布局（backupDir）：
///   GameLog-autobackup.json                   滚动备份（每次覆盖）
///   GameLog-autobackup-pre-<版本号>.json      版本升级前快照，保留最近 3 份
///   GameLog-autobackup-snapshot-<时间>.json   恢复/导入前快照（不参与滚动覆盖）
///
/// backupDir：macOS = `~/Library/Application Support/GameLog/`（私有）；
///            iOS = Documents/Backups/（「文件」App 可见——签名证书过期等无法打开 app 时
///            用户仍可取走文件手动恢复）。
@MainActor
final class AutoBackup: ObservableObject {
    static let shared = AutoBackup()

    // MARK: - 元数据（UserDefaults key）

    static let lastBackupDateKey = "backup.lastBackupDate"
    static let lastBackupSizeKey = "backup.lastBackupSize"
    private static let lastVersionKey = "backup.lastVersion"

    /// 防抖时长：改动停止后等待 3 秒才写盘，避免连续操作反复写大文件。
    private static let debounceNanos: UInt64 = 3_000_000_000

    /// 启动空库检测到的恢复信息（非空时根视图弹「是否从自动备份恢复」询问）。
    @Published var emptyRestoreInfo: EmptyRestoreInfo?

    private var container: ModelContainer?
    private var writer: BackupWriter?
    private var didSetup = false
    private var didStartupCheck = false
    private var needsWrite = false
    /// 后台写盘进行中（期间新触发的防抖在写完后补一轮）。
    private var isWriting = false
    private var debounceTask: Task<Void, Never>?
    private var didSaveObserver: NSObjectProtocol?
    private var lifecycleObserver: NSObjectProtocol?

    private init() {}

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: UserCustomization.autoBackupKey) as? Bool ?? true
    }

    // MARK: - 文件位置

    /// 备份目录（macOS 私有 / iOS Documents 可见）。
    static var backupDir: URL {
        #if os(macOS)
        return UserCustomization.supportDirectory
        #else
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Backups", isDirectory: true)
        #endif
    }

    /// 滚动备份文件。
    static var backupFileURL: URL {
        backupDir.appendingPathComponent("GameLog-autobackup.json")
    }

    // MARK: - 元数据读取（设置页展示）

    static var lastBackupDate: Date? {
        UserDefaults.standard.object(forKey: lastBackupDateKey) as? Date
    }

    static var lastBackupSize: Int {
        UserDefaults.standard.integer(forKey: lastBackupSizeKey)
    }

    // MARK: - 生命周期接入

    /// 注册监听（幂等）：挂 ModelContext.didSave（每次保存触发防抖备份）。
    /// macOS 额外挂 willTerminate 做退出兜底（只标记，下次启动补写——终止时刻
    /// 后台编码已来不及）；iOS 改挂 willEnterForeground 补写（退后台同步编码
    /// 771MB 会被系统终止，正是「编辑后卡死需重启」的元凶之一）。
    func setup(container: ModelContainer) {
        guard !didSetup else { return }
        didSetup = true
        self.container = container
        writer = BackupWriter(modelContainer: container)

        didSaveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if Self.isEnabled { self.scheduleWrite() }
            }
        }

        #if os(macOS)
        lifecycleObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // 终止时刻只标记；下次启动检查会把这笔补上（needsWrite 持久化在 UserDefaults）。
            MainActor.assumeIsolated { self?.markPending() }
        }
        #else
        lifecycleObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.needsWrite || Self.pendingFlag { self.performWrite() }
            }
        }
        #endif
    }

    // MARK: - 触发

    /// 防抖编排：取消旧任务，3 秒无新改动后执行一次写入。
    func scheduleWrite() {
        guard Self.isEnabled else { return }
        needsWrite = true
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.debounceNanos)
            guard !Task.isCancelled else { return }
            self?.performWrite()
        }
    }

    /// 「立即备份」（设置页按钮，异步版本；完成后据实回填状态消息）。
    func writeNowAsync(completion: ((Bool) -> Void)? = nil) {
        needsWrite = true
        debounceTask?.cancel()
        debounceTask = nil
        performWrite { ok in
            completion?(ok)
        }
    }

    /// 退出兜底（macOS willTerminate）：只持久化「有待写」标记。
    /// 备份数据本身自上次成功写盘起未变（滚动文件仍是完整的旧状态），可安全回退。
    func markPending() {
        guard needsWrite else { return }
        Self.setPendingFlag(true)
    }

    // MARK: - 写入（后台）

    /// 空库保护判定：主上下文快速数游戏/分组（轻量，无 BLOB 物化风险——
    /// 仅取行存在性；图片字段在对象物化时才读）。
    private func libraryIsNonEmpty() -> Bool {
        guard let container else { return false }
        var desc = FetchDescriptor<Game>()
        desc.fetchLimit = 1
        let hasGames = ((try? container.mainContext.fetch(desc))?.isEmpty == false)
        var gdesc = FetchDescriptor<GameGroup>()
        gdesc.fetchLimit = 1
        let hasGroups = ((try? container.mainContext.fetch(gdesc))?.isEmpty == false)
        return hasGames || hasGroups
    }

    /// 后台流式写滚动备份。completion 回主线程；ok = 是否成功写盘。
    private func performWrite(completion: ((Bool) -> Void)? = nil) {
        guard Self.isEnabled else { completion?(false); return }
        guard let writer else { completion?(false); return }
        guard !isWriting else { completion?(false); return }
        guard libraryIsNonEmpty() else { needsWrite = false; completion?(false); return }

        isWriting = true
        needsWrite = false
        Self.setPendingFlag(false)
        let url = Self.backupFileURL
        let username = UserDefaults.standard.string(forKey: UserCustomization.usernameKey)
        let avatarPNG = UserCustomization.avatarImageData()
        let iconPNG = UserCustomization.iconImageData()
        let bannerTitle = UserDefaults.standard.string(forKey: UserCustomization.bannerTitleKey)
        let bannerSubtitle = UserDefaults.standard.string(forKey: UserCustomization.bannerSubtitleKey)
        let bannerBG = UserCustomization.bannerBackgroundImageData()

        Task.detached(priority: .utility) { [writer] in
            let result: Int?
            do {
                result = try await writer.writeStreamingBackup(
                    to: url, username: username, avatarPNG: avatarPNG, iconPNG: iconPNG,
                    bannerTitle: bannerTitle, bannerSubtitle: bannerSubtitle, bannerBackgroundPNG: bannerBG
                )
            } catch {
                // 写盘失败：保持旧文件不动（流式写在临时名 → 成功才换名，见下）。
                result = nil
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isWriting = false
                let ok = result.map { $0 >= 0 } ?? false
                if ok {
                    UserDefaults.standard.set(Date(), forKey: Self.lastBackupDateKey)
                    UserDefaults.standard.set(result!, forKey: Self.lastBackupSizeKey)
                } else {
                    // 失败重试标记：下次前台/启动补写。
                    Self.setPendingFlag(true)
                }
                // 写入期间有新改动（didSave 在 isWriting=true 时置位 needsWrite）→ 立刻补写一轮，
                // 否则这轮改动要等下一次 didSave 才会被备份（2026-09-05 审计：竞态漏备份窗口）。
                if ok && self.needsWrite {
                    self.performWrite()
                }
                completion?(ok)
            }
        }
    }

    // MARK: - 启动检查（启动备份 / 版本快照 / 空库检测）

    /// 启动时调用一次：版本变化时先把上次会话留下的滚动备份复制为 pre- 快照；
    /// 空库且有备份 → 弹恢复询问；有待写标记或版本变化 → 后台刷新滚动备份。
    /// **全部即时返回**（旧实现在这里同步编码 771MB，正是「启动要等一会儿」的主因）。
    func performStartupCheck(context: ModelContext, currentVersion: String) {
        guard !didStartupCheck else { return }
        didStartupCheck = true

        // 1. 版本升级保护：先把「上次会话留下的滚动备份」（升级前数据）复制为 pre-<旧版本> 快照。
        //    大文件拷贝挪后台（771MB 要数秒，不能在主线程）；启动备份在拷贝完成后执行，
        //    保证「先快照旧内容、再覆盖滚动文件」的顺序（顺序反了 pre 快照会变成新内容）。
        let lastVersion = UserDefaults.standard.string(forKey: Self.lastVersionKey)
        let versionChanged = lastVersion != currentVersion
        UserDefaults.standard.set(currentVersion, forKey: Self.lastVersionKey)
        if Self.isEnabled, versionChanged || Self.pendingFlag {
            let pendingVersion = lastVersion
            let url = Self.backupFileURL
            let dir = Self.backupDir
            needsWrite = true
            Task.detached(priority: .utility) { [weak self] in
                if versionChanged, let pendingVersion {
                    if FileManager.default.fileExists(atPath: url.path) {
                        let dst = dir.appendingPathComponent("GameLog-autobackup-pre-\(pendingVersion).json")
                        try? FileManager.default.removeItem(at: dst)
                        try? FileManager.default.copyItem(at: url, to: dst)
                    }
                }
                await MainActor.run { [weak self] in
                    self?.trimPreVersionFilesOnVersionChange(changed: versionChanged)
                    self?.performWrite()
                }
            }
        }

        // 2. 空库检测：库为空 + 备份里有数据 → 弹窗询问是否恢复（取消保留空库，不强行恢复）。
        //    库空判定用 fetchLimit=1 的轻量探测；备份游戏数统计（流式扫全文件）也挪后台。
        var desc = FetchDescriptor<Game>()
        desc.fetchLimit = 1
        let hasGames = ((try? context.fetch(desc))?.isEmpty == false)
        var gdesc = FetchDescriptor<GameGroup>()
        gdesc.fetchLimit = 1
        let hasGroups = ((try? context.fetch(gdesc))?.isEmpty == false)
        if !hasGames && !hasGroups {
            let url = Self.backupFileURL
            Task.detached(priority: .utility) { [weak self] in
                let count = BackupWriter.countGames(at: url)
                await MainActor.run { [weak self] in
                    guard let self, self.emptyRestoreInfo == nil, count > 0 else { return }
                    self.emptyRestoreInfo = EmptyRestoreInfo(gameCount: count)
                }
            }
        }
    }

    /// 版本变化时修剪 pre- 快照（仅此时调用，语义与旧实现一致）。
    private func trimPreVersionFilesOnVersionChange(changed: Bool) {
        guard changed else { return }
        trimPreVersionFiles(keep: 3)
    }

    func dismissEmptyRestore() {
        emptyRestoreInfo = nil
    }

    /// 跨会话「有待写」标记（退出兜底 / 写盘失败重试用）。
    private static var pendingFlag: Bool {
        UserDefaults.standard.bool(forKey: "backup.pendingWrite")
    }

    private static func setPendingFlag(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: "backup.pendingWrite")
    }

    // MARK: - 恢复与快照

    /// 从自动备份恢复：**先**后台写当前状态快照（可后悔），快照落盘**后**才整体替换。
    /// 返回是否恢复成功。
    @discardableResult
    func restoreFromAutoBackup(context: ModelContext) -> Bool {
        guard let data = try? Data(contentsOf: Self.backupFileURL) else { return false }
        guard writeSnapshot(context: context) else { return false }
        do {
            try BackupManager.decodeAndReplace(data, into: context)
            try context.save()
            return true
        } catch {
            // 恢复失败：当前数据已被快照保留，可手动找回。
            return false
        }
    }

    /// 恢复/导入前快照：把当前数据写为带时间戳的文件（不参与滚动覆盖）。
    /// 每次「整体替换」操作（恢复、手动导入、AirDrop 导入）前调用，误恢复时能找回。
    /// 编码与写盘在 ModelActor 后台执行、本调用**同步等待**完成（主线程不被
    /// 771MB 编码阻塞，只是等待；调用点语义与旧实现一致：返回时快照已落盘或失败）。
    /// 返回是否成功（空库无可快照视为成功）。
    @discardableResult
    func writeSnapshot(context: ModelContext) -> Bool {
        let container = context.container
        var desc = FetchDescriptor<Game>()
        desc.fetchLimit = 1
        let hasGames = ((try? context.fetch(desc))?.isEmpty == false)
        var gdesc = FetchDescriptor<GameGroup>()
        gdesc.fetchLimit = 1
        let hasGroups = ((try? context.fetch(gdesc))?.isEmpty == false)
        guard hasGames || hasGroups else { return true }

        let writer = writer ?? BackupWriter(modelContainer: container)
        let url = Self.backupDir.appendingPathComponent("GameLog-autobackup-snapshot-\(Self.snapshotTimestamp()).json")
        let username = UserDefaults.standard.string(forKey: UserCustomization.usernameKey)
        let avatarPNG = UserCustomization.avatarImageData()
        let iconPNG = UserCustomization.iconImageData()
        let bannerTitle = UserDefaults.standard.string(forKey: UserCustomization.bannerTitleKey)
        let bannerSubtitle = UserDefaults.standard.string(forKey: UserCustomization.bannerSubtitleKey)
        let bannerBG = UserCustomization.bannerBackgroundImageData()

        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var ok = false
        Task.detached(priority: .utility) { [writer] in
            var bytes = -1
            do {
                bytes = try await writer.writeStreamingBackup(
                    to: url, username: username, avatarPNG: avatarPNG, iconPNG: iconPNG,
                    bannerTitle: bannerTitle, bannerSubtitle: bannerSubtitle, bannerBackgroundPNG: bannerBG
                )
            } catch { }
            ok = bytes >= 0
            if ok { AutoBackup.trimSnapshotFilesStatic(keep: 10) }
            semaphore.signal()
        }
        semaphore.wait()
        return ok
    }

    /// trimSnapshotFiles 的静态包装（后台 Task 闭包内用）。
    /// 目录推导与 MainActor 版 backupDir 一致（纯文件系统路径，无隔离需求）。
    nonisolated private static func trimSnapshotFilesStatic(keep: Int) {
        #if os(macOS)
        let dir = UserCustomization.supportDirectory
        #else
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Backups", isDirectory: true)
        #endif
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let matches = files
            .filter { $0.lastPathComponent.hasPrefix("GameLog-autobackup-snapshot-") && $0.pathExtension == "json" }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return l < r
            }
        if matches.count > keep {
            matches.prefix(matches.count - keep).forEach { try? fm.removeItem(at: $0) }
        }
    }

    /// 只保留最近 keep 份恢复前快照（按修改时间，删除更旧的）。
    /// 此前快照无任何清理、无限累积（每份含封面可达数十 MB，HANDOVER §30.1 记录的磁盘隐患）。
    private func trimSnapshotFiles(keep: Int) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: Self.backupDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let matches = files
            .filter { $0.lastPathComponent.hasPrefix("GameLog-autobackup-snapshot-") && $0.pathExtension == "json" }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return l < r
            }
        if matches.count > keep {
            matches.prefix(matches.count - keep).forEach { try? fm.removeItem(at: $0) }
        }
    }

    /// 只保留最近 keep 份 pre-版本 快照（按修改时间，删除更旧的）。
    private func trimPreVersionFiles(keep: Int) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: Self.backupDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let matches = files
            .filter { $0.lastPathComponent.hasPrefix("GameLog-autobackup-pre-") && $0.pathExtension == "json" }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return l < r
            }
        if matches.count > keep {
            matches.prefix(matches.count - keep).forEach { try? fm.removeItem(at: $0) }
        }
    }

    private static func snapshotTimestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}

/// 空库恢复询问的内容（供 .platformConfirmDialog presenting 识别）。
struct EmptyRestoreInfo: Identifiable {
    let id = UUID()
    let gameCount: Int
}

/// 根视图包装：承载启动检查与「检测到库为空」恢复询问。
/// 挂在 WindowGroup 最外层，macOS/iOS 共用。
struct AutoBackupContainer<Content: View>: View {
    @StateObject private var backup = AutoBackup.shared
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var currentVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
    }

    /// 空库恢复弹窗的呈现绑定：出现时弹、消失时清 state。
    private var emptyRestoreBinding: Binding<Bool> {
        Binding(
            get: { backup.emptyRestoreInfo != nil },
            set: { if !$0 { backup.dismissEmptyRestore() } }
        )
    }

    var body: some View {
        content
            .platformConfirmDialog(
                L10n.tr("backup.emptyRestoreTitle", lang: language),
                isPresented: emptyRestoreBinding,
                message: L10n.tr(
                    "backup.emptyRestoreMessage",
                    [backup.emptyRestoreInfo?.gameCount ?? 0],
                    lang: language
                ),
                cancelTitle: L10n.tr("backup.keepEmpty", lang: language),
                actions: [
                    ConfirmAction(title: L10n.tr("backup.restoreNow", lang: language)) {
                        AutoBackup.shared.restoreFromAutoBackup(context: context)
                    }
                ]
            )
            .task {
                let context = context
                AutoBackup.shared.setup(container: context.container)
                AutoBackup.shared.performStartupCheck(context: context, currentVersion: currentVersion)
            }
    }
}
