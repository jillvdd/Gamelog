import Foundation
import SwiftData

// MARK: - 备份 DTO

struct BackupDTO: Codable {
    var version: Int
    var exportedAt: Date
    var groups: [GroupDTO]
    var games: [GameDTO]
    /// 三项自定义（旧版备份无此字段 → nil，导入时保持现状）。
    var username: String?
    var avatarBase64: String?
    var iconBase64: String?
    /// 主页横幅（旧版备份缺字段 → nil，导入时保持现状）。
    var bannerTitle: String?
    var bannerSubtitle: String?
    var bannerBackgroundBase64: String?
}

struct GroupDTO: Codable {
    var name: String
    /// 分组评价。旧版备份缺字段 → nil，导入时保持现状。
    var review: String?
}

struct GameDTO: Codable {
    var name: String
    /// 多语言名（旧版备份缺字段 → nil）。
    var nameZh: String?
    var nameJa: String?
    var aliases: [String]
    /// 游戏主平台（旧版备份缺字段 → nil，导入默认空）。
    var platform: String?
    var releaseDate: Date?
    /// 厂商/发行商/游戏类型（旧版备份缺字段 → nil，导入保持现状）。
    var developer: String?
    var publisher: String?
    var genre: String?
    var coverBase64: String?
    /// 1:1 方形封面/横向封面/背景图/Logo（旧版备份缺字段 → nil，导入保持现状）。
    var squareBase64: String?
    var landscapeBase64: String?
    var heroBase64: String?
    var logoBase64: String?
    /// Logo 横幅展示三档（旧版备份缺字段 → nil，导入保持默认档）。
    var logoSizeRaw: String?
    var logoVerticalRaw: String?
    var logoHorizontalRaw: String?
    var reviewTitle: String
    var reviewBody: String
    var groupNames: [String]
    var completions: [CompletionDTO]
    /// 持有记录（收藏家模式；旧版备份缺字段 → nil，导入保持现状）。
    var copies: [CopyDTO]?
    /// 状态机状态（旧版备份缺字段 → nil，导入默认已通关）。
    var status: String?
    /// 我的最爱（旧版备份缺字段 → nil，导入保持未收藏）。
    var isFavorite: Bool?
    /// 创建/最近编辑时间（旧版备份缺字段 → nil，导入回落 .now）。
    /// 备份往返不保时间戳的话，导入后 @Query(sort: \Game.createdAt) 顺序漂移、
    /// 「最近编辑」排序失真（2026-09-05 审计）。
    var createdAt: Date?
    var updatedAt: Date?
}

/// 一条持有记录（版本 + 数量 + 最多 6 张照片 base64 + 藏品档案全字段）。
/// 旧版备份缺字段 → 全部 Optional，导入时用默认值兜底，不覆盖现状（§24 不变量）。
struct CopyDTO: Codable {
    var version: String
    var count: Int
    var images: [String]
    // 藏品档案（旧备份缺字段 → nil）。
    var mediaRaw: String?
    var regionalRaw: String?
    var conditionRaw: String?
    var acquisitionRaw: String?
    var platform: String?
    var priceZh: Double?
    var priceJa: Double?
    var priceEn: Double?
    var estValueZh: Double?
    var estValueJa: Double?
    var estValueEn: Double?
    var purchaseDate: Date?
    var notes: String?
}

struct CompletionDTO: Codable {
    var platform: String
    /// 通关日期。nil = 无（None）。旧版备份有日期，照常兼容。
    var date: Date?
    var degree: String
    var playtime: Double?
    var notes: String
    var scoreGameplay: Double?
    var scoreDesign: Double?
    var scoreStory: Double?
    var scoreArt: Double?
    var scoreMusic: Double?
    var scorePerformance: Double?
}

// MARK: - 导出 / 导入

/// 把整个库序列化成单个 JSON 文件（封面以 base64 内嵌），可整体导回。
enum BackupManager {

    /// 导出：所有游戏 + 分组 → JSON。
    /// 字段映射唯一入口 = GameDTO(from:)（Support/Game+Backup.swift）。
    static func encode(games: [Game], groups: [GameGroup]) throws -> Data {
        let customization = UserCustomization.encodedCustomization()
        let dto = BackupDTO(
            version: 1,
            exportedAt: .now,
            groups: groups.map { GroupDTO(name: $0.name, review: $0.review) },
            games: games.map { GameDTO(from: $0) },
            username: customization.username,
            avatarBase64: customization.avatarBase64,
            iconBase64: customization.iconBase64,
            bannerTitle: customization.bannerTitle,
            bannerSubtitle: customization.bannerSubtitle,
            bannerBackgroundBase64: customization.bannerBackgroundBase64
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(dto)
    }

    /// 导入：清空现有数据，按 JSON 重建。
    /// 兼容入口：行为与旧实现一致（decode → 定制回写 → apply → 清缓存 → 广播），
    /// 供 DataSmokeTest 与过渡期调用方使用；新异步导入链走 decode + apply（见下）。
    static func decodeAndReplace(_ data: Data, into context: ModelContext) throws {
        let dto = try decode(data)

        // 自定义项：写序不变量（文件先、用户名最后）在 UserCustomization.applyCustomization 内。
        try UserCustomization.applyCustomization(
            username: dto.username,
            avatarBase64: dto.avatarBase64,
            iconBase64: dto.iconBase64,
            bannerTitle: dto.bannerTitle,
            bannerSubtitle: dto.bannerSubtitle,
            bannerBackgroundBase64: dto.bannerBackgroundBase64
        )

        try apply(dto, into: context)

        // 全库重建：解码缓存按 persistentModelID 做 key，全部失效（旧 ID 的旧图不再命中）。
        ImageDecodeCache.bump()
        // 广播整库替换：导航栈里的旧 Game/Group 引用已全部 detached，持有方（iOS selectedGame、
        // macOS path、轮播 spotlight 等）收到后重置，防悬空访问 SwiftData fatal。
        NotificationCenter.default.post(name: UserCustomization.libraryReplacedNotification, object: nil)
    }

    /// 纯解码：JSON → BackupDTO（无副作用，可在后台线程调用）。
    static func decode(_ data: Data) throws -> BackupDTO {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupDTO.self, from: data)
    }

    /// 按 DTO 重建全库：清空现有 + 逐游戏重建（不含定制回写/清缓存/广播——
    /// 新定序要求这三者在 DB 落盘成功后由调用方在主线程执行，见 AutoBackup.importBackup）。
    /// - Parameters:
    ///   - onProgress: 已处理游戏数/总数回调（约每 50 个游戏一次 + 末尾一次），nil = 不上报。
    static func apply(_ dto: BackupDTO, into context: ModelContext,
                      onProgress: ((Int, Int) -> Void)? = nil) throws {

        // 再清空现有（删除游戏会级联删除通关记录与持有记录；以下重建均不抛错，不会中途失败）
        if let existingGames = try? context.fetch(FetchDescriptor<Game>()) {
            existingGames.forEach { context.delete($0) }
        }
        if let existingGroups = try? context.fetch(FetchDescriptor<GameGroup>()) {
            existingGroups.forEach { context.delete($0) }
        }

        var groupMap: [String: GameGroup] = [:]
        for groupDTO in dto.groups {
            // 分组名 trim：与新建/改名弹窗的存储口径一致，避免备份里带空格的分组名造成视觉重名
            // 或与游戏 groupNames 引用错位（如导出 "ABC "、游戏引用 "ABC"）。
            let groupName = groupDTO.name.trimmingCharacters(in: .whitespaces)
            guard !groupName.isEmpty else { continue }
            // 重名只建第一个（手工编辑过的备份可能出现重复名，否则会产生重复的孤儿分组）。
            guard groupMap[groupName] == nil else { continue }
            let group = GameGroup(name: groupName)
            // 旧版备份缺 review → 保持现状（默认空串）
            if let review = groupDTO.review {
                group.review = review
            }
            context.insert(group)
            groupMap[groupName] = group
        }

        for (index, gameDTO) in dto.games.enumerated() {
            // 进度上报（后台导入链用；每 50 个游戏一次 + 末尾一次，主线程节流见调用方）。
            if let onProgress = onProgress, (index % 50 == 0 || index + 1 == dto.games.count) {
                onProgress(index + 1, dto.games.count)
            }
            // base64 解码/枚举解析拆出局部变量：Game init 参数 20+，全内联会超出编译器
            // 类型检查预算（2026-09-05 实测 unable to type-check in reasonable time）。
            let coverData = gameDTO.coverBase64.flatMap { Data(base64Encoded: $0) }
            let squareData = gameDTO.squareBase64.flatMap { Data(base64Encoded: $0) }
            let landscapeData = gameDTO.landscapeBase64.flatMap { Data(base64Encoded: $0) }
            let heroData = gameDTO.heroBase64.flatMap { Data(base64Encoded: $0) }
            let logoData = gameDTO.logoBase64.flatMap { Data(base64Encoded: $0) }
            let logoSize = gameDTO.logoSizeRaw.flatMap(LogoBannerSize.init(rawValue:)) ?? LogoBannerSize.medium
            let logoVertical = gameDTO.logoVerticalRaw.flatMap(LogoBannerVertical.init(rawValue:)) ?? LogoBannerVertical.bottom
            let logoHorizontal = gameDTO.logoHorizontalRaw.flatMap(LogoBannerHorizontal.init(rawValue:)) ?? LogoBannerHorizontal.leading
            let importedStatus = gameDTO.status.flatMap(GameStatus.init(rawValue:)) ?? GameStatus.completed
            let importedCreatedAt = gameDTO.createdAt ?? Date.now
            let game = Game(
                name: gameDTO.name,
                nameZh: gameDTO.nameZh,
                nameJa: gameDTO.nameJa,
                aliases: gameDTO.aliases,
                platform: gameDTO.platform ?? "",
                releaseDate: gameDTO.releaseDate,
                developer: gameDTO.developer,
                publisher: gameDTO.publisher,
                genre: gameDTO.genre,
                coverData: coverData,
                squareData: squareData,
                landscapeData: landscapeData,
                heroData: heroData,
                logoData: logoData,
                logoSize: logoSize,
                logoVertical: logoVertical,
                logoHorizontal: logoHorizontal,
                reviewTitle: gameDTO.reviewTitle,
                reviewBody: gameDTO.reviewBody,
                // 旧版备份缺 createdAt → .now（模型默认）；缺 status → 默认已通关。
                createdAt: importedCreatedAt,
                status: importedStatus,
                isFavorite: gameDTO.isFavorite ?? false
            )
            // updatedAt 单独恢复：init 把 updatedAt 钉成 createdAt，而导入的 updatedAt 可能更早/更晚。
            game.updatedAt = gameDTO.updatedAt ?? game.createdAt
            game.groups = gameDTO.groupNames.compactMap { groupMap[$0.trimmingCharacters(in: .whitespaces)] }
            context.insert(game)

            for completionDTO in gameDTO.completions {
                let completion = Completion(
                    platform: completionDTO.platform,
                    date: completionDTO.date,
                    degree: completionDTO.degree,
                    playtime: completionDTO.playtime,
                    notes: completionDTO.notes,
                    scoreGameplay: completionDTO.scoreGameplay,
                    scoreDesign: completionDTO.scoreDesign,
                    scoreStory: completionDTO.scoreStory,
                    scoreArt: completionDTO.scoreArt,
                    scoreMusic: completionDTO.scoreMusic,
                    scorePerformance: completionDTO.scorePerformance
                )
                completion.game = game
                context.insert(completion)
            }

            // 持有记录（旧版备份缺字段 → 默认值兜底；枚举走 migrate 而非 flatMap(rawValue)）
            if let copies = gameDTO.copies {
                for copyDTO in copies {
                    let copy = PhysicalCopy(
                        version: copyDTO.version,
                        count: max(1, copyDTO.count),
                        images: copyDTO.images.prefix(6).compactMap { Data(base64Encoded: $0) }
                    )
                    copy.media = CopyMedia.migrate(copyDTO.mediaRaw ?? "")
                    copy.regional = CopyRegional.migrate(copyDTO.regionalRaw ?? "")
                    copy.condition = CopyCondition.migrate(copyDTO.conditionRaw ?? "")
                    copy.acquisition = CopyAcquisition.migrate(copyDTO.acquisitionRaw ?? "")
                    copy.platform = copyDTO.platform ?? ""
                    copy.priceZh = copyDTO.priceZh
                    copy.priceJa = copyDTO.priceJa
                    copy.priceEn = copyDTO.priceEn
                    copy.estValueZh = copyDTO.estValueZh
                    copy.estValueJa = copyDTO.estValueJa
                    copy.estValueEn = copyDTO.estValueEn
                    copy.purchaseDate = copyDTO.purchaseDate
                    copy.notes = copyDTO.notes ?? ""
                    copy.game = game
                    context.insert(copy)
                }
            }
        }
    }
}
