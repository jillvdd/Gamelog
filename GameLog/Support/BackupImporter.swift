import Foundation
import SwiftData

/// 后台备份导入执行器：在独立 ModelContext 里解码 + 删库重建 + save，全程不出主线程。
///
/// 用法（调用方在 @MainActor）：先 `BackupManager.decode` 得 DTO（IBAction 内同步读完 Data），
/// 再 `Task.detached` 里 `BackupImporter(modelContainer:)` 执行 `applyDTO`，成功后回主线程
/// 按定序做定制回写 → bump → 发通知 → 解锁（见 AutoBackup.importBackup）。
///
/// 线程红线：绝不把主线程的 ModelContext 传进来；绝不在后台碰 container.mainContext；
/// notification 不在这里 post（后台发通知会让观察者在后台线程跑 UI 重置）。
@ModelActor
actor BackupImporter {

    /// 在后台上下文里按 DTO 重建全库并 save。
    /// - Parameters:
    ///   - dto: 已解码的备份（调用方在主线程 `BackupManager.decode` 得到）。
    ///   - onProgress: 已处理游戏数/总数（约每 50 个游戏一次 + 末尾一次），后台线程回调，
    ///     调用方负责 hop 回主线程（如 `MainActor.run`）再更新 UI。
    func applyDTO(_ dto: BackupDTO, onProgress: @escaping (Int, Int) -> Void) throws {
        try BackupManager.apply(dto, into: modelContext, onProgress: onProgress)
        try modelContext.save()
    }

    /// 流式整库替换：按扫描区间逐游戏读盘 → 解码 → 增量落库（每 25 款 save 一次）。
    /// 峰值内存 = 单款游戏 JSON + 当前批次对象，与备份总体积无关 —— GB 级备份在
    /// iOS 上也能导完（bulk 路径 `decode(Data(整文件))` 是内存爆炸根因，已弃用于文件入口）。
    /// 安全作用域在本同步调用内 start/stop（不跨 await，满足线程与生命周期约束）。
    /// 替换开始（clear 已执行）后的任何失败统一包装为 `ImportError.replacementFailed`，
    /// 调用方据此决定「库可能半替换 → 从快照回滚」；扫描/头字段失败不裹（DB 未动）。
    func applyStreaming(url: URL, requestAccess: Bool, scan: BackupScanResult,
                        groups: [GroupDTO],
                        onProgress: @escaping @Sendable (Int, Int) -> Void) throws {
        let didStart = requestAccess ? url.startAccessingSecurityScopedResource() : false
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        let total = max(1, scan.gameRanges.count)
        do {
            let session = try BackupManager.beginReplace(groups: groups, into: modelContext, batching: true)
            // 在 beginReplace（已清库）之后打开：读盘失败经外层 catch 归为 replacementFailed → 触发回滚。
            let fh = try FileHandle(forReadingFrom: url)
            defer { try? fh.close() }
            let decoder = StreamingBackupReader.decoder()
            for (index, range) in scan.gameRanges.enumerated() {
                // 逐款套池：`readData(ofLength:)` 与 JSONDecoder 的中间对象都走 autoreleased，
                // 而整个循环是 actor 上的**一个** job —— 不逐轮排空就要等函数返回才释放。
                // （2026-09-30 模拟器实测：1.1GB 备份导入峰值 1638MB，加不加这一层数字不动，
                // 大头在别处；留着是因为它压的是瞬时分配，成本为零。）
                try autoreleasepool {
                    let dto = try StreamingBackupReader.game(from: fh, decoder: decoder, range: range)
                    try session.applyGame(dto)
                }
                onProgress(index + 1, total)
            }
            try session.finish(save: true)
        } catch let error as ImportError {
            throw error
        } catch {
            throw ImportError.replacementFailed(underlying: String(describing: error))
        }
    }
}
