import Foundation

// MARK: - Game↔DTO 单一映射（2026-08-29 深化）

/// Game / Completion / PhysicalCopy 与备份 DTO 之间的**唯一**字段映射。
/// 此前同一映射存在三份手抄：BackupManager.encode、BackupWriter.writeStreamingBackup、
/// decodeAndReplace——加新字段要改 5 处，漏一处自动备份静默丢字段。
/// 深化后两条导出路径与导入都经这里的构造器；DataSmokeTest 的
/// 「手动导出与自动备份输出一致」断言守住两条路径永不漂移。
extension GameDTO {
    /// 从模型构建 DTO（导出路径唯一入口）。
    init(from game: Game) {
        self.init(
            name: game.name,
            nameZh: game.nameZh,
            nameJa: game.nameJa,
            aliases: game.aliases,
            platform: game.platform,
            releaseDate: game.releaseDate,
            developer: game.developer,
            publisher: game.publisher,
            genre: game.genre,
            coverBase64: game.artwork(.poster)?.base64EncodedString(),
            squareBase64: game.artwork(.square)?.base64EncodedString(),
            landscapeBase64: game.artwork(.landscape)?.base64EncodedString(),
            heroBase64: game.artwork(.hero)?.base64EncodedString(),
            logoBase64: game.artwork(.logo)?.base64EncodedString(),
            logoSizeRaw: game.logoSize,
            logoVerticalRaw: game.logoVertical,
            logoHorizontalRaw: game.logoHorizontal,
            reviewTitle: game.reviewTitle,
            reviewBody: game.reviewBody,
            groupNames: game.groups.map(\.name),
            completions: game.sortedCompletions.map { CompletionDTO(from: $0) },
            copies: game.copies.map { CopyDTO(from: $0) },
            status: game.status,
            isFavorite: game.isFavorite,
            createdAt: game.createdAt,
            updatedAt: game.updatedAt
        )
    }
}

extension CompletionDTO {
    /// 从模型构建 DTO（导出路径唯一入口）。
    init(from completion: Completion) {
        self.init(
            platform: completion.platform,
            date: completion.date,
            degree: completion.degree,
            playtime: completion.playtime,
            notes: completion.notes,
            scoreGameplay: completion.scoreGameplay,
            scoreDesign: completion.scoreDesign,
            scoreStory: completion.scoreStory,
            scoreArt: completion.scoreArt,
            scoreMusic: completion.scoreMusic,
            scorePerformance: completion.scorePerformance
        )
    }
}

extension CopyDTO {
    /// 从模型构建 DTO（导出路径唯一入口）。
    /// 归一化约定（与历史 encode 一致）：空平台/空备注写 nil，备份文件里不落空串。
    init(from copy: PhysicalCopy) {
        self.init(
            version: copy.version,
            count: copy.count,
            images: copy.images.map { $0.base64EncodedString() },
            mediaRaw: copy.mediaRaw,
            regionalRaw: copy.regionalRaw,
            conditionRaw: copy.conditionRaw,
            acquisitionRaw: copy.acquisitionRaw,
            platform: copy.platform.isEmpty ? nil : copy.platform,
            priceZh: copy.priceZh,
            priceJa: copy.priceJa,
            priceEn: copy.priceEn,
            estValueZh: copy.estValueZh,
            estValueJa: copy.estValueJa,
            estValueEn: copy.estValueEn,
            purchaseDate: copy.purchaseDate,
            notes: copy.notes.isEmpty ? nil : copy.notes
        )
    }
}
