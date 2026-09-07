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
}
