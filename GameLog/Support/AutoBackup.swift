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

    // MARK: - 启动写闸门（防 scene-create 看门狗，2026-09-24）
    //
    // iOS 的 scene-create 看门狗只给 10 秒墙钟。真机大库（数千款 + 外置封面）首帧
    // 要在主队列 SQLQueue 上跑完整 @Query fetch；若在它旁边并发启动备份重活
    // （1.1GB pre 快照拷贝 + 全库逐款读图编码写盘），SQLite 连接池与磁盘带宽被吃满，
    // 主线程 fetch 直接超预算 → 0x8BADF00D 被 FrontBoard 杀掉（beta 3.5 实机复现，
    // 崩溃日志两份 SQLQueue 全库 fetch 并发）。所以启动期的一切整库级重活都排在
    // 「开屏淡出（首帧已提交）+ 2 秒宽限」之后统一放行，另有 15 秒兜底。
    //
    /// 闸门已开（首帧就绪 + 宽限，或兜底超时）。
    private var writeGateOpen = false
    /// 版本升级待拷贝的 pre- 快照旧版本号（闸门开启时消费；nil = 无）。
    private var pendingSnapshotVersion: String?
    /// 闸门开启时要执行的排队回调。
    private var gateCallbacks: [@MainActor () -> Void] = []
    private var firstFrameObserver: NSObjectProtocol?
    private var gateFallbackTask: Task<Void, Never>?

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

        armWriteGate()
    }

    // MARK: - 写闸门实现（见 `writeGateOpen` 的注释）

    /// 挂首帧广播监听 + 15 秒兜底；闸门开启时先冲启动备份（setup 必在
    /// performStartupCheck 之前调用，冲账读到的是其置好的状态）。
    private func armWriteGate() {
        guard !writeGateOpen else { return }
        // 先排入默认冲账回调：闸门开启时执行版本快照拷贝 + 滚动备份写盘。
        gateCallbacks.append { [weak self] in
            self?.flushLaunchBackupIfNeeded()
        }
        firstFrameObserver = NotificationCenter.default.addObserver(
            forName: .gameLogFirstFrameReady, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.writeGateOpen, self.firstFrameObserver != nil else { return }
                self.firstFrameObserver = nil
                // 再留 2 秒：淡出动画 + 卡片封面首轮物化，让主队列彻底缓过劲。
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    self?.openWriteGate()
                }
            }
        }
        gateFallbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled else { return }
            self?.openWriteGate()
        }
    }

    private func openWriteGate() {
        guard !writeGateOpen else { return }
        writeGateOpen = true
        gateFallbackTask?.cancel()
        gateFallbackTask = nil
        firstFrameObserver.map { NotificationCenter.default.removeObserver($0) }
        firstFrameObserver = nil
        let callbacks = gateCallbacks
        gateCallbacks.removeAll()
        for callback in callbacks { callback() }
    }

    /// 闸门开启后的启动备份冲账：先补版本升级 pre- 快照拷贝（大文件，后台做），
    /// 再修剪旧快照、写滚动备份。逻辑与原 performStartupCheck 内联版一致，
    /// 只是整体推迟到首帧之后。
    private func flushLaunchBackupIfNeeded() {
        guard Self.isEnabled else { return }
        let snapshotVersion = pendingSnapshotVersion
        pendingSnapshotVersion = nil
        guard needsWrite || Self.pendingFlag else { return }
        let url = Self.backupFileURL
        let dir = Self.backupDir
        Task.detached(priority: .utility) { [weak self] in
            if let snapshotVersion, FileManager.default.fileExists(atPath: url.path) {
                let dst = dir.appendingPathComponent("GameLog-autobackup-pre-\(snapshotVersion).json")
                try? FileManager.default.removeItem(at: dst)
                try? FileManager.default.copyItem(at: url, to: dst)
            }
            await MainActor.run { [weak self] in
                self?.trimPreVersionFilesOnVersionChange(changed: snapshotVersion != nil)
                self?.performWrite()
            }
        }
    }

    /// 把重活排到写闸门之后；闸门已开则立即执行。
    fileprivate func afterWriteGate(_ work: @escaping @MainActor () -> Void) {
        if writeGateOpen { work() } else { gateCallbacks.append(work) }
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
        // 启动写闸门未开：只记账，闸门开启时统一冲账（防 scene-create 看门狗，见 writeGateOpen）。
        guard writeGateOpen else { needsWrite = true; completion?(false); return }
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
        //    2026-09-24：这里只置账，不立刻动手 —— 整库级重活（1.1GB 拷贝 + 全库读图编码写盘）
        //    一律等写闸门（首帧提交 + 宽限）开启后由 `flushLaunchBackupIfNeeded` 冲账，
        //    保证「先快照旧内容、再覆盖滚动文件」的顺序不变（两者在同一条后台链上）。
        let lastVersion = UserDefaults.standard.string(forKey: Self.lastVersionKey)
        let versionChanged = lastVersion != currentVersion
        UserDefaults.standard.set(currentVersion, forKey: Self.lastVersionKey)
        if Self.isEnabled, versionChanged || Self.pendingFlag {
            if versionChanged { pendingSnapshotVersion = lastVersion }
            needsWrite = true
        }

        // 2. 空库检测：库为空 + 备份里有数据 → 弹窗询问是否恢复（取消保留空库，不强行恢复）。
        //    库空判定用 fetchLimit=1 的轻量探测；备份游戏数统计要流式扫完整个大文件
        //    （可达 GB 级），同样排到写闸门之后再跑（2026-09-24 防看门狗对撞）。
        var desc = FetchDescriptor<Game>()
        desc.fetchLimit = 1
        let hasGames = ((try? context.fetch(desc))?.isEmpty == false)
        var gdesc = FetchDescriptor<GameGroup>()
        gdesc.fetchLimit = 1
        let hasGroups = ((try? context.fetch(gdesc))?.isEmpty == false)
        if !hasGames && !hasGroups {
            let url = Self.backupFileURL
            afterWriteGate { [weak self] in
                guard let self else { return }
                Task.detached(priority: .utility) { [weak self] in
                    let count = BackupWriter.countGames(at: url)
                    await MainActor.run { [weak self] in
                        guard let self, self.emptyRestoreInfo == nil, count > 0 else { return }
                        self.emptyRestoreInfo = EmptyRestoreInfo(gameCount: count)
                    }
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
        onProgress(0.02)
        try await writeSnapshot(context: context)

        // 2. 后台 decode + 重建 + save。
        // ⚠️ decode 必须在后台执行：1GB+ 备份 JSON 在 @MainActor 解码会撑爆主线程内存限额
        //    导致 JSONDecoder throw（2026-09-18 真机复现）。挪进 Task.detached 后，decode 完
        //    data 即可被 ARC 释放，不再与 DTO 对象树同时压在内存里。
        //    step 3 需要的定制字段（username 等）从 task 里作为 tuple 返回。
        onProgress(0.05)
        let container = context.container
        typealias CustomizationFields = (username: String?, avatarBase64: String?, iconBase64: String?,
                                         bannerTitle: String?, bannerSubtitle: String?, bannerBackgroundBase64: String?)
        let customization: CustomizationFields = try await Task.detached(priority: .utility) {
            let dto = try BackupManager.decode(data)
            let importer = BackupImporter(modelContainer: container)
            try await importer.applyDTO(dto) { done, total in
                guard total > 0 else { return }
                let frac = 0.05 + 0.85 * Double(done) / Double(total)
                Task { @MainActor in self.importProgress = frac; onProgress(frac) }
            }
            return (dto.username, dto.avatarBase64, dto.iconBase64,
                    dto.bannerTitle, dto.bannerSubtitle, dto.bannerBackgroundBase64)
        }.value

        // 3. 主线程定制回写（DB 已落盘成功后才写文件/UserDefaults；写序不变量在内）。
        onProgress(0.93)
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
        onProgress(0.97)
        NotificationCenter.default.post(name: UserCustomization.libraryReplacedNotification, object: nil)

        // 6. 先解锁再补一次自动备份：performWrite 被 isImporting 守卫拦住，
        // 必须解锁后才调；defer 的二次清零幂等无害。
        onProgress(1.0)
        isImporting = false
        importProgress = nil
        scheduleWrite()
    }

    /// 从自动备份恢复：走流式统一入口 `importBackup(fromFile:)`（自动备份文件在本 App 沙盒内，
    /// 无需安全作用域）。文件不存在直接抛 `backupUnreadable`，其余（快照→流式重建→定制回写→
    /// 广播→补备份）与手动导入完全同路 —— GB 级自动备份也不再整文件 decode，不再撑爆内存。
    func restoreFromAutoBackup(context: ModelContext,
                               onProgress: @escaping @MainActor (Double) -> Void = { _ in }) async throws {
        guard FileManager.default.fileExists(atPath: Self.backupFileURL.path) else {
            throw ImportError.backupUnreadable
        }
        try await importBackup(fromFile: Self.backupFileURL, into: context,
                               requestAccess: false, onProgress: onProgress)
    }

    /// 从用户文件导入（设置页「导入备份」与 AirDrop/打开方式两入口共用）：**流式**整库替换。
    ///
    /// 定序：上锁 → 后台字节扫描 + header 校验（只读文件，不碰 DB、不写快照）→
    /// 恢复前快照（此后才是回滚锚点）→ 逐游戏增量落库 → 主线程定制回写 → 清缓存 →
    /// 广播整库替换 → 补一次自动备份 → 解锁。
    /// 全程峰值内存与备份体积无关，GB 级备份也能在 iOS 上导完（bulk `decode(Data(整文件))`
    /// 是 jetsam/OOM 根因，文件入口已全部改走此路径）。
    ///
    /// 失败分类：读盘/扫描/header/快照阶段 DB 尚未动，直接抛（`importFailMessageForUser`
    /// 按阶段出文案 + 附原始错误串）；`applyStreaming` 清库后抛 `replacementFailed`
    /// → 从快照尽力回滚后再抛原错。
    ///
    /// - Parameter requestAccess: 用户选择/AirDrop 打开的文件传 true（安全作用域）；
    ///   App 沙盒内的自动备份文件传 false。
    func importBackup(fromFile url: URL, into context: ModelContext, requestAccess: Bool,
                      onProgress: @escaping @MainActor (Double) -> Void = { _ in }) async throws {
        // 重入保护：导入锁定期二次调用直接抛错（调用方回填 importFailed）。
        guard !isImporting else { throw ImportError.alreadyImporting }
        isImporting = true
        importProgress = 0
        defer {
            isImporting = false
            importProgress = nil
        }

        // 进度上报合流：同刷 @Published importProgress（全屏遮罩读它）与调用方 onProgress。
        let report: @MainActor (Double) -> Void = { frac in
            self.importProgress = frac
            onProgress(frac)
        }

        // 1. 先扫盘校验（读盘 + header），**不碰 DB、也不写快照**。
        //    顺序理由（2026-09-30 iOS 真机排查）：快照要把当前整库重编码写盘（大库 = 1.1GB/次），
        //    旧顺序把它放在最前面，于是「文件读不到 / 不是备份 / 磁盘写不下」这类根本没动过 DB
        //    的失败也会各留一份 1.1GB 废快照 —— 在手机上重试几次就把空间吃光，而失败又被报成
        //    「备份文件无效或已损坏」，用户永远看不到真因。现在只有确认要清库了才写回滚锚点。
        let (scan, header): (BackupScanResult, BackupHeaderData) =
            try await scanAndHeader(url: url, requestAccess: requestAccess, report: report)

        // 2. 恢复前快照 = 流式替换失败的回滚锚点（空库返回 nil）。
        //    快照失败与「文件损坏」是两件事，分型出去才不会被兜底文案盖成无效或已损坏。
        report(0.5)
        let snapshotURL: URL?
        do {
            snapshotURL = try await writeSnapshot(context: context)
        } catch {
            throw ImportError.snapshotFailed(underlying: String(describing: error))
        }

        // 3. 逐游戏增量落库（DB 已落盘成功后才回写定制）。
        let customization: BackupCustomization
        do {
            customization = try await applyScan(scan, header: header, url: url,
                                                 requestAccess: requestAccess,
                                                 into: context, report: report)
        } catch {
            // 仅在确认「已开始清库后失败」（半替换）时回滚；DB 未动过的失败不回滚。
            // 空库时 snapshotURL = nil，无可回滚（本来也没有数据要保）。
            if case ImportError.replacementFailed = error, let snapshotURL {
                await rollbackToSnapshot(snapshotURL, into: context, report: report)
            }
            throw error
        }

        // 3. 主线程定制回写（DB 已落盘成功后才写文件/UserDefaults；写序不变量在内）。
        report(0.93)
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
        report(0.97)
        NotificationCenter.default.post(name: UserCustomization.libraryReplacedNotification, object: nil)

        // 6. 先解锁再补一次自动备份：performWrite 被 isImporting 守卫拦住，
        // 必须解锁后才调；defer 的二次清零幂等无害。
        report(1.0)
        isImporting = false
        importProgress = nil
        scheduleWrite()
    }

    /// 流式替换·阶段 1：后台扫描（1MB 窗口恒定内存）+ 读 header（groups + 定制）。
    /// 全程只读文件、不碰 DB —— 结构非法/读不到的备份在这里就抛，调用方因此**不必**先写快照。
    /// 安全作用域在同步读闭包内 start/stop（不跨 await）。进度 0.05→0.45（按字节）。
    private func scanAndHeader(url: URL, requestAccess: Bool,
                               report: @escaping @MainActor (Double) -> Void) async throws
        -> (BackupScanResult, BackupHeaderData) {
        try await Task.detached(priority: .utility) {
            let didStart = requestAccess ? url.startAccessingSecurityScopedResource() : false
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            let scan = try StreamingBackupReader.scan(url: url) { doneBytes in
                guard fileSize > 0 else { return }
                let frac = min(0.45, 0.05 + 0.40 * Double(doneBytes) / Double(fileSize))
                Task { @MainActor in report(frac) }
            }
            // games 键缺失 = 非备份文件（与 bulk decode 同口径报 DecodingError，走「解码失败」文案）。
            guard scan.hasGamesKey else {
                throw DecodingError.dataCorrupted(.init(codingPath: [],
                      debugDescription: "GameLog backup: missing games"))
            }
            let header = try StreamingBackupReader.header(of: scan, url: url)
            return (scan, header)
        }.value
    }

    /// 流式替换·阶段 2：按扫描区间逐游戏增量落库（`BackupImporter.applyStreaming`
    /// 自带安全作用域 + `replacementFailed` 包装）。进度 0.5→0.92（按游戏数）。
    /// 这一步会先清库，失败即半替换 → 调用方拿阶段 1 之后写的快照回滚。
    private func applyScan(_ scan: BackupScanResult, header: BackupHeaderData, url: URL,
                           requestAccess: Bool, into context: ModelContext,
                           report: @escaping @MainActor (Double) -> Void) async throws
        -> BackupCustomization {
        report(0.5)
        let importer = BackupImporter(modelContainer: context.container)
        try await importer.applyStreaming(url: url, requestAccess: requestAccess,
                                          scan: scan, groups: header.groups) { done, total in
            let frac = min(0.92, 0.5 + 0.42 * Double(done) / Double(max(1, total)))
            Task { @MainActor in report(frac) }
        }
        return header.customization
    }

    /// 扫描 + 落库连着跑（不回滚锚点场景用：`rollbackToSnapshot` 的输入是自家快照，
    /// 体积与当前库相当，再为它写一份快照纯属套娃）。
    private func streamingReplace(url: URL, requestAccess: Bool, into context: ModelContext,
                                  report: @escaping @MainActor (Double) -> Void) async throws -> BackupCustomization {
        let (scan, header) = try await scanAndHeader(url: url, requestAccess: requestAccess, report: report)
        return try await applyScan(scan, header: header, url: url,
                                   requestAccess: requestAccess, into: context, report: report)
    }

    /// 半替换后的尽力回滚：从快照再跑一次流式替换，把库整体恢复回替换前状态。
    /// 吞掉回滚自身异常（主错误已在抛出的路上，回滚失败只能记日志），结束一律清缓存 + 广播，
    /// 让界面反映回滚后的库 —— 无论回滚成功与否都不能停留在半替换态。
    private func rollbackToSnapshot(_ snapshotURL: URL, into context: ModelContext,
                                    report: @escaping @MainActor (Double) -> Void) async {
        do {
            let customization = try await streamingReplace(url: snapshotURL, requestAccess: false,
                                                           into: context, report: report)
            try? UserCustomization.applyCustomization(
                username: customization.username,
                avatarBase64: customization.avatarBase64,
                iconBase64: customization.iconBase64,
                bannerTitle: customization.bannerTitle,
                bannerSubtitle: customization.bannerSubtitle,
                bannerBackgroundBase64: customization.bannerBackgroundBase64
            )
        } catch {
            NSLog("GameLog import rollback failed: \(error)")
        }
        ImageDecodeCache.bump()
        NotificationCenter.default.post(name: UserCustomization.libraryReplacedNotification, object: nil)
    }

    /// 恢复/导入前快照：把当前数据写为带时间戳的文件（不参与滚动覆盖）。
    /// 每次「整体替换」操作（恢复、手动导入、AirDrop 导入）前调用，误恢复时能找回。
    /// 编码与写盘在 ModelActor 后台执行；`await` 返回 = 原子换名完成 = 快照已落盘，
    /// 调用方在 await 之后才能替换，顺序由编译器保证（2026-09-08 去 semaphore 化，
    /// 旧 DispatchSemaphore 同步等待阻塞主线程）。
    /// 空库无可快照视为成功（返回 nil）；失败时 throw（调用方统一中断，不再有"快照失败仍继续替换"）。
    /// 返回快照 URL 供流式导入的**失败回滚锚点**用（半替换状态可从它整库恢复）。
    @discardableResult
    func writeSnapshot(context: ModelContext) async throws -> URL? {
        let container = context.container
        var desc = FetchDescriptor<Game>()
        desc.fetchLimit = 1
        let hasGames = ((try? context.fetch(desc))?.isEmpty == false)
        var gdesc = FetchDescriptor<GameGroup>()
        gdesc.fetchLimit = 1
        let hasGroups = ((try? context.fetch(gdesc))?.isEmpty == false)
        guard hasGames || hasGroups else { return nil }

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
        Self.trimSnapshotFilesStatic(keep: Self.snapshotKeepCount)
        return url
    }

    /// 恢复前快照保留份数。
    ///
    /// 2026-09-29 用户决策「iOS 恢复前快照保留一份就行」：iOS 的快照与滚动备份同在
    /// `Documents/Backups`，每份都是**整库含图**（本机 1.1 GB 量级），保留 10 份等于
    /// 把 App 沙盒当成 11 倍的备份盘 —— 在 iOS 上这会直接触发「存储空间不足」类失败，
    /// 也正是导入崩溃的诱因之一。macOS 的备份目录在 Application Support、磁盘预算宽裕，
    /// 维持 10 份不变。
    #if os(macOS)
    nonisolated private static let snapshotKeepCount = 10
    #else
    nonisolated private static let snapshotKeepCount = 1
    #endif

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
    /// 读盘阶段失败（权限/磁盘/内存分配）。与解码/落库失败分开报，定位「无效或已损坏」误报。
    case readFailed(underlying: String)
    /// 导入前的「恢复前快照」写盘失败（多为存储空间不足 / 目录不可写）。
    /// 这一步在**读备份文件之前**，此时备份文件尚未被看过一眼，绝不能报成「文件损坏」。
    case snapshotFailed(underlying: String)
    /// 流式替换**已开始清库**后的失败（DB 可能半替换，须从快照回滚）。
    /// 扫描/头字段阶段的失败不裹这层 —— 那时 DB 尚未动过，回滚是纯浪费。
    case replacementFailed(underlying: String)
}

/// 导入错误 → 用户可读文案（设置页导入与 AirDrop/打开方式导入两入口共用，防口径漂移）。
///
/// 口径：**每个阶段说自己那句**。旧版把 `backupUnreadable` / 快照失败 / 落库失败 / 重入
/// 全部落进兜底的「备份文件无效或已损坏」，用户和我们都无从区分「文件坏了」和
/// 「这台机器读不到 / 写不下」（2026-09-30 iOS 真机 1.1GB 备份导入排查）。
/// 带 `underlying` 的阶段一律附原始错误串（beta 期自证用，`backup.importDiagnosis`）。
func importFailMessageForUser(_ error: Error, lang: String) -> String {
    func diagnose(_ stage: String, _ reason: String) -> String {
        // 原始 underlying 可能是整棵 CoreData 错误树（数 KB），弹窗放不下：截前 300 字符，
        // 完整串仍由调用方 NSLog 落到系统日志里。
        let tail = reason.count > 300 ? String(reason.prefix(300)) + "…" : reason
        return L10n.tr("backup.importDiagnosis", [stage, tail], lang: lang)
    }
    switch error {
    case ImportError.readFailed(let reason):
        return diagnose(L10n.tr("backup.importReadFailed", lang: lang), reason)
    case ImportError.backupUnreadable:
        return L10n.tr("backup.importReadFailed", lang: lang)
    case ImportError.snapshotFailed(let reason):
        return diagnose(L10n.tr("backup.importSnapshotFailed", lang: lang), reason)
    case ImportError.replacementFailed(let reason):
        return diagnose(L10n.tr("backup.importStoreFailed", lang: lang), reason)
    case ImportError.alreadyImporting:
        return L10n.tr("backup.importLocked", lang: lang)
    case let decodingError as DecodingError:
        return diagnose(L10n.tr("backup.importDecodeFailed", lang: lang), decodingFailReason(decodingError))
    default:
        return diagnose(L10n.tr("backup.importUnknown", lang: lang), String(describing: error))
    }
}

/// `DecodingError` 里真正有信息量的那一段（`localizedDescription` 会把整棵 codingPath 的
/// Swift 反射类型名糊上来，一行塞不进弹窗）。
private func decodingFailReason(_ error: DecodingError) -> String {
    func path(_ context: DecodingError.Context) -> String {
        context.codingPath.isEmpty ? "root" : context.codingPath.map(\.stringValue).joined(separator: ".")
    }
    switch error {
    case .keyNotFound(let key, let context):
        return "keyNotFound \(key.stringValue) @ \(path(context))"
    case .typeMismatch(let type, let context):
        return "typeMismatch \(type) @ \(path(context)): \(context.debugDescription)"
    case .valueNotFound(let type, let context):
        return "valueNotFound \(type) @ \(path(context))"
    case .dataCorrupted(let context):
        return "dataCorrupted @ \(path(context)): \(context.debugDescription)"
    @unknown default:
        return String(describing: error)
    }
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
                        VStack(spacing: 12) {
                            ProgressView(value: frac)
                                .frame(width: 220)
                            LText("backup.importing")
                                .foregroundStyle(.white)
                                .font(.headline)
                            Text("\(Int((frac * 100).rounded()))%")
                                .foregroundStyle(.white.opacity(0.85))
                                .font(.subheadline.monospacedDigit())
                            LText("backup.importingHint")
                                .foregroundStyle(.white.opacity(0.7))
                                .font(.footnote)
                                .multilineTextAlignment(.center)
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
