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
    private var didSetup = false
    private var didStartupCheck = false
    private var needsWrite = false
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
    /// macOS 额外挂 willTerminate、iOS 挂 didEnterBackground 做退出兜底。
    func setup(container: ModelContainer) {
        guard !didSetup else { return }
        didSetup = true
        self.container = container

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
            // queue 是主队列 = MainActor；同步兜底写（任务在此刻不可靠）。
            MainActor.assumeIsolated { self?.flushNow() }
        }
        #else
        lifecycleObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushNow() }
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

    /// 立即写入（设置页「立即备份」/ 启动检查用）。
    func writeNow() {
        needsWrite = true
        debounceTask?.cancel()
        debounceTask = nil
        performWrite()
    }

    /// 退出/后台兜底：有未落盘的改动才写（避免每次后台都重编码）。
    func flushNow() {
        debounceTask?.cancel()
        debounceTask = nil
        if needsWrite {
            performWrite()
        }
    }

    private func performWrite() {
        guard Self.isEnabled else { return }
        guard let container else { return }
        guard let games = try? container.mainContext.fetch(FetchDescriptor<Game>()),
              let groups = try? container.mainContext.fetch(FetchDescriptor<GameGroup>()) else { return }
        // 防空库覆盖：库为空时不写滚动备份——避免把上一份好的备份覆盖成空
        // （对应「store 被清空但 app 数据丢了」的场景，见 HANDOVER §25.5）。
        guard !games.isEmpty || !groups.isEmpty else { return }
        do {
            let data = try BackupManager.encode(games: games, groups: groups)
            let url = Self.backupFileURL
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            needsWrite = false
            UserDefaults.standard.set(Date(), forKey: Self.lastBackupDateKey)
            UserDefaults.standard.set(data.count, forKey: Self.lastBackupSizeKey)
        } catch {
            // 写盘失败（磁盘满等罕见）：needsWrite 保持，下次保存仍重试。
        }
    }

    // MARK: - 启动检查（启动备份 / 版本快照 / 空库检测）

    /// 启动时调用一次：版本变化时先复制「上次会话的滚动备份（升级前数据）」为 pre- 快照，
    /// 再刷新启动备份；库为空且备份非空时记下恢复询问。
    func performStartupCheck(context: ModelContext, currentVersion: String) {
        guard !didStartupCheck else { return }
        didStartupCheck = true

        let games = (try? context.fetch(FetchDescriptor<Game>())) ?? []
        let groups = (try? context.fetch(FetchDescriptor<GameGroup>())) ?? []

        // 1. 版本升级保护：先复制「上次会话留下的滚动备份」（升级前数据）为 pre-<旧版本> 快照，
        //    再刷新启动备份。顺序不能反——先覆盖再复制会把 pre 快照也变成迁移后的新内容。
        let lastVersion = UserDefaults.standard.string(forKey: Self.lastVersionKey)
        if let lastVersion, lastVersion != currentVersion {
            let src = Self.backupFileURL
            if FileManager.default.fileExists(atPath: src.path) {
                let dst = Self.backupDir.appendingPathComponent("GameLog-autobackup-pre-\(lastVersion).json")
                try? FileManager.default.removeItem(at: dst)
                try? FileManager.default.copyItem(at: src, to: dst)
            }
            trimPreVersionFiles(keep: 3)
        }
        UserDefaults.standard.set(currentVersion, forKey: Self.lastVersionKey)

        // 2. 启动备份（当前数据）——非空才写，避免空库/坏库覆盖上一份好的滚动备份。
        if !games.isEmpty || !groups.isEmpty {
            writeNow()
        }

        // 3. 空库检测：库为空 + 备份里有数据 → 弹窗询问是否恢复（取消保留空库，不强行恢复）。
        if games.isEmpty && groups.isEmpty {
            if let data = try? Data(contentsOf: Self.backupFileURL),
               let dto = try? JSONDecoder().decode(BackupDTO.self, from: data),
               !dto.games.isEmpty {
                emptyRestoreInfo = EmptyRestoreInfo(gameCount: dto.games.count)
            }
        }
    }

    func dismissEmptyRestore() {
        emptyRestoreInfo = nil
    }

    // MARK: - 恢复与快照

    /// 从自动备份恢复：先写当前状态快照（可后悔），再整体替换。返回是否成功。
    @discardableResult
    func restoreFromAutoBackup(context: ModelContext) -> Bool {
        guard let data = try? Data(contentsOf: Self.backupFileURL) else { return false }
        writeSnapshot(context: context)
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
    func writeSnapshot(context: ModelContext) {
        let games = (try? context.fetch(FetchDescriptor<Game>())) ?? []
        let groups = (try? context.fetch(FetchDescriptor<GameGroup>())) ?? []
        guard !games.isEmpty || !groups.isEmpty else { return }
        guard let data = try? BackupManager.encode(games: games, groups: groups) else { return }
        let url = Self.backupDir.appendingPathComponent("GameLog-autobackup-snapshot-\(Self.snapshotTimestamp()).json")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
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