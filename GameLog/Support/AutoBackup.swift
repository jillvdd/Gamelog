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
    /// 整库替换进行中（备份导入/自动备份恢复/AirDrop 导入）：抑制自动备份写盘，
    /// 防后台 save 触发 didSave 监听（object:nil）去编码半替换库（2026-09-08）。
    private var isImporting = false
    /// 「此刻有别的上下文正在批量写库」的计数 —— 自动备份据此让路（见 `performWrite` 的守卫）。
    ///
    /// ⚠️ 与 `isImporting` 是**两件事**，别合并：那个是「整库替换」的重入锁兼 UI 上锁依据，
    /// 这个是纯写盘闸门。外部账号同步不改整库、不上锁，但它**批量改写封面**，同样必须挡住备份。
    ///
    /// 为什么非挡不可（2026-09-18 两份崩溃报告，已离线复现）：`@Attribute(.externalStorage)`
    /// 的图**不在 store 里**，在 `_EXTERNAL_DATA/<uuid>` 文件里，store 行里只存一个引用。
    /// 另一个上下文改写封面时 CoreData 会删掉旧文件，而**正在跑的备份**手里攥着 fetch 时
    /// 缓存的旧引用 → 读的时候文件已经没了 → CoreData 抛
    /// `NSInternalInconsistencyException: External data reference can't find underlying file.`。
    /// **Swift 捕获不到 NSException**（`do/catch` 只接 Swift error），后台线程上没人接 → abort，
    /// 整个 app 死掉、备份从此不再推进。所以唯一的修法是**不让两边同时发生**。
    ///
    /// ⚠️ 必须计数而不是布尔：整库替换与外部账号同步是两条独立路径，任一条结束就清零的话，
    /// 另一条还在跑的时候备份就恢复写盘了。
    private var backupSuppression = 0
    /// 导入进度 0~1（非 nil = 锁定期，根容器据此上锁+显示进度；nil = 无锁）。
    /// @Published 供 AutoBackupContainer 观察；只在主线程读写（本类 @MainActor）。
    @Published var importProgress: Double? = nil
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

    // MARK: - 让路（别的上下文正在批量写库）

    /// 声明「从现在起别的上下文会批量写库」，期间自动备份不写盘。
    /// 必须与 `endBackupSuppression()` 配对（调用方用 `defer`），否则自动备份被永久关掉。
    ///
    /// 调用点：`ExternalSyncDriver.sync`（外部账号同步会批量回填封面）。
    /// 整库替换那条路径不用它 —— 它有自己的 `isImporting` 守卫。
    func beginBackupSuppression() { backupSuppression += 1 }

    /// 结束让路。归零时**补写一次**：被压掉的那几轮不能丢，否则同步完的库要等到
    /// 下一次改动才进备份（与整库替换路径「先解锁再补一次」同一条纪律）。
    func endBackupSuppression() {
        backupSuppression = max(0, backupSuppression - 1)
        guard backupSuppression == 0 else { return }
        scheduleWrite()
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
        // 整库替换期间抑制：didSave 监听（object:nil）会被后台导入 save 触发，
        // 此时写盘会编码半替换库；解锁后统一入口会补写一次（2026-09-08）。
        guard !isImporting else { completion?(false); return }
        // 别的上下文正在批量改封面（外部账号同步）→ 让路。理由见 `backupSuppression` 的注释：
        // 并发读外置存储的图会抛 Swift 接不住的 NSException，直接把 app 干掉。
        guard backupSuppression == 0 else { completion?(false); return }
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

    /// 统一导入入口：三条导入路径（设置页手动导入 / AirDrop / 自动备份恢复）唯一收敛点。
    ///
    /// 定序（新不变量，2026-09-08）：上锁 → 快照落盘 → 后台 decode+重建+save →
    /// 主线程定制回写 → 主线程清缓存 → 主线程广播整库替换 → 补一次自动备份 → 解锁。
    /// 任何一步 throw 即中断：后台草稿未 save，主库零触碰（比旧实现"内存已换、
    /// 持久化失败、无回滚"更安全）；当前数据已被恢复前快照保留，可手动找回。
    ///
    /// - Parameters:
    ///   - data: 已读入内存的备份 JSON（调用方在安全作用域内同步读完后传入，
    ///     后续链路只碰 Data 不碰 URL——`defer{stop}` 不可跨 await）。
    ///   - context: 主线程上下文（仅用于取 container 建后台上下文 + 读定制项；
    ///     绝不传进后台任务做 save）。
    ///   - onProgress: 0~1 进度（后台每 ~50 游戏一次 MainActor.run 上报）。
    func importBackup(_ data: Data, into context: ModelContext,
                      onProgress: @escaping @MainActor (Double) -> Void = { _ in }) async throws {
        // 重入保护：导入锁定期二次调用直接抛错（调用方回填 importFailed）。
        guard !isImporting else { throw ImportError.alreadyImporting }
        isImporting = true
        importProgress = 0
        // 保底清理：任何路径（成功/抛错/取消）都解锁，防旗标永久置位锁死自动备份。
        defer {
            isImporting = false
            importProgress = nil
        }

        // 1. 恢复前快照（throw 即中断，不再有"快照失败仍继续替换"）。
        await onProgress(0.02)
        try await writeSnapshot(context: context)

        // 2. 后台 decode + 重建 + save。
        // ⚠️ decode 必须在后台执行：1GB+ 备份 JSON 在 @MainActor 解码会撑爆主线程内存限额
        //    导致 JSONDecoder throw（2026-09-18 真机复现）。挪进 Task.detached 后，decode 完
        //    data 即可被 ARC 释放，不再与 DTO 对象树同时压在内存里。
        //    step 3 需要的定制字段（username 等）从 task 里作为 tuple 返回。
        await onProgress(0.05)
        let container = context.container
        typealias CustomizationFields = (username: String?, avatarBase64: String?, iconBase64: String?,
                                         bannerTitle: String?, bannerSubtitle: String?, bannerBackgroundBase64: String?)
        let customization: CustomizationFields = try await Task.detached(priority: .utility) {
            let dto = try BackupManager.decode(data)
            let importer = BackupImporter(modelContainer: container)
            try await importer.applyDTO(dto) { done, total in
                guard total > 0 else { return }
                let frac = 0.05 + 0.85 * Double(done) / Double(total)
                Task { @MainActor in onProgress(frac) }
            }
            return (dto.username, dto.avatarBase64, dto.iconBase64,
                    dto.bannerTitle, dto.bannerSubtitle, dto.bannerBackgroundBase64)
        }.value

        // 3. 主线程定制回写（DB 已落盘成功后才写文件/UserDefaults；写序不变量在内）。
        await onProgress(0.93)
        try UserCustomization.applyCustomization(
            username: customization.username,
            avatarBase64: customization.avatarBase64,
            iconBase64: customization.iconBase64,
            bannerTitle: customization.bannerTitle,
            bannerSubtitle: customization.bannerSubtitle,
            bannerBackgroundBase64: customization.bannerBackgroundBase64
        )

        // 4. 主线程清解码缓存（key 含 persistentModelID，旧 ID 旧图不再命中）。
        ImageDecodeCache.bump()

        // 5. 主线程广播整库替换（观察者在主线程重置导航，防后台 post 跑错线程）。
        await onProgress(0.97)
        NotificationCenter.default.post(name: UserCustomization.libraryReplacedNotification, object: nil)

        // 6. 先解锁再补一次自动备份：performWrite 被 isImporting 守卫拦住，
        // 必须解锁后才调；defer 的二次清零幂等无害。
        await onProgress(1.0)
        isImporting = false
        importProgress = nil
        scheduleWrite()
    }

    /// 从自动备份恢复：走统一入口 importBackup（快照→后台重建→定制回写→广播→补备份）。
    /// 快照失败/解码失败/ save 失败一律 throw，调用方回填 restoreFailed。
    func restoreFromAutoBackup(context: ModelContext,
                               onProgress: @escaping @MainActor (Double) -> Void = { _ in }) async throws {
        guard let data = try? Data(contentsOf: Self.backupFileURL) else {
            throw ImportError.backupUnreadable
        }
        try await importBackup(data, into: context, onProgress: onProgress)
    }

    /// 恢复/导入前快照：把当前数据写为带时间戳的文件（不参与滚动覆盖）。
    /// 每次「整体替换」操作（恢复、手动导入、AirDrop 导入）前调用，误恢复时能找回。
    /// 编码与写盘在 ModelActor 后台执行；`await` 返回 = 原子换名完成 = 快照已落盘，
    /// 调用方在 await 之后才能替换，顺序由编译器保证（2026-09-08 去 semaphore 化，
    /// 旧 DispatchSemaphore 同步等待阻塞主线程）。
    /// 空库无可快照视为成功；失败时 throw（调用方统一中断，不再有"快照失败仍继续替换"）。
    func writeSnapshot(context: ModelContext) async throws {
        let container = context.container
        var desc = FetchDescriptor<Game>()
        desc.fetchLimit = 1
        let hasGames = ((try? context.fetch(desc))?.isEmpty == false)
        var gdesc = FetchDescriptor<GameGroup>()
        gdesc.fetchLimit = 1
        let hasGroups = ((try? context.fetch(gdesc))?.isEmpty == false)
        guard hasGames || hasGroups else { return }

        let writer = writer ?? BackupWriter(modelContainer: container)
        let url = Self.backupDir.appendingPathComponent("GameLog-autobackup-snapshot-\(Self.snapshotTimestamp()).json")
        let username = UserDefaults.standard.string(forKey: UserCustomization.usernameKey)
        let avatarPNG = UserCustomization.avatarImageData()
        let iconPNG = UserCustomization.iconImageData()
        let bannerTitle = UserDefaults.standard.string(forKey: UserCustomization.bannerTitleKey)
        let bannerSubtitle = UserDefaults.standard.string(forKey: UserCustomization.bannerSubtitleKey)
        let bannerBG = UserCustomization.bannerBackgroundImageData()

        let bytes = try await writer.writeStreamingBackup(
            to: url, username: username, avatarPNG: avatarPNG, iconPNG: iconPNG,
            bannerTitle: bannerTitle, bannerSubtitle: bannerSubtitle, bannerBackgroundPNG: bannerBG
        )
        guard bytes >= 0 else { throw SnapshotError.writeFailed }
        Self.trimSnapshotFilesStatic(keep: 10)
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

/// 快照失败错误（writeSnapshot 改 async throws 后的失败载体）。
enum SnapshotError: Error {
    case writeFailed
}

/// 统一导入入口错误。
enum ImportError: Error {
    /// 导入锁定期间重入（导入未完成又点导入/恢复）。
    case alreadyImporting
    /// 自动备份文件读不出（不存在/权限/损坏到连 Data 都读不出）。
    case backupUnreadable
}

/// 整库替换锁定态环境键：根容器在导入锁定时置 true，下层 LibraryView 据此
/// 切静态占位分支（不持有任何 Game/Group，杜绝 detached 渲染崩溃 2026-09-08）。
private struct LibraryReplacingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var libraryReplacing: Bool {
        get { self[LibraryReplacingKey.self] }
        set { self[LibraryReplacingKey.self] = newValue }
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
        ZStack {
            content
                // 导入锁定时禁用底层一切交互（挡手；挡渲染靠 LibraryView 的分支占位）。
                .disabled(backup.importProgress != nil)
            // 整库替换锁定期全屏进度遮罩：吃掉所有触摸，防止用户在新旧库交替时操作。
            if let frac = backup.importProgress {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .allowsHitTesting(true)
                    .overlay {
                        VStack(spacing: 16) {
                            ProgressView(value: frac)
                                .frame(width: 220)
                            LText("backup.importing")
                                .foregroundStyle(.white)
                        }
                        .padding(28)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
            }
        }
            .environment(\.libraryReplacing, backup.importProgress != nil)
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
                        let context = context
                        Task { @MainActor in
                            try? await AutoBackup.shared.restoreFromAutoBackup(context: context) { _ in }
                        }
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
