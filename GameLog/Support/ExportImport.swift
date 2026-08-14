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
    var releaseDate: Date?
    var coverBase64: String?
    var reviewTitle: String
    var reviewBody: String
    var groupNames: [String]
    var completions: [CompletionDTO]
    /// 持有记录（收藏家模式；旧版备份缺字段 → nil，导入保持现状）。
    var copies: [CopyDTO]?
}

/// 一条持有记录（版本 + 数量 + 最多 6 张照片 base64）。
struct CopyDTO: Codable {
    var version: String
    var count: Int
    var images: [String]
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
    static func encode(games: [Game], groups: [GameGroup]) throws -> Data {
        let dto = BackupDTO(
            version: 1,
            exportedAt: .now,
            groups: groups.map { GroupDTO(name: $0.name, review: $0.review) },
            games: games.map { game in
                GameDTO(
                    name: game.name,
                    nameZh: game.nameZh,
                    nameJa: game.nameJa,
                    aliases: game.aliases,
                    releaseDate: game.releaseDate,
                    coverBase64: game.coverData?.base64EncodedString(),
                    reviewTitle: game.reviewTitle,
                    reviewBody: game.reviewBody,
                    groupNames: game.groups.map(\.name),
                    completions: game.sortedCompletions.map { completion in
                        CompletionDTO(
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
                    },
                    copies: game.copies.map { copy in
                        CopyDTO(
                            version: copy.version,
                            count: copy.count,
                            images: copy.images.map { $0.base64EncodedString() }
                        )
                    }
                )
            },
            username: UserDefaults.standard.string(forKey: UserCustomization.usernameKey),
            avatarBase64: UserCustomization.avatarImageData()?.base64EncodedString(),
            iconBase64: UserCustomization.iconImageData()?.base64EncodedString()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(dto)
    }

    /// 导入：清空现有数据，按 JSON 重建。
    static func decodeAndReplace(_ data: Data, into context: ModelContext) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let dto = try decoder.decode(BackupDTO.self, from: data)

        // 自定义三项：先写可能抛错的文件（头像/图标），最后写 UserDefaults（用户名）。
        // 用户名写盘不可回滚，若先写用户名、后写文件失败，会出现「提示导入失败但用户名已变更」；
        // 文件写盘失败时（磁盘满等）用户名保持原值，与「失败时原库保持完好」口径一致。
        // 旧版备份缺字段 → 保持现状不覆盖。
        if let avatar = dto.avatarBase64.flatMap({ Data(base64Encoded: $0) }) {
            try UserCustomization.saveAvatarPNG(avatar)
        }
        if let icon = dto.iconBase64.flatMap({ Data(base64Encoded: $0) }) {
            try UserCustomization.saveIconPNG(icon)
        }
        if let name = dto.username {
            if name.isEmpty {
                UserDefaults.standard.removeObject(forKey: UserCustomization.usernameKey)
            } else {
                UserDefaults.standard.set(
                    String(Array(name).prefix(UserCustomization.usernameMaxLength)),
                    forKey: UserCustomization.usernameKey
                )
            }
        }

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
            let group = GameGroup(name: groupName)
            // 旧版备份缺 review → 保持现状（默认空串）
            if let review = groupDTO.review {
                group.review = review
            }
            context.insert(group)
            groupMap[groupName] = group
        }

        for gameDTO in dto.games {
            let game = Game(
                name: gameDTO.name,
                nameZh: gameDTO.nameZh,
                nameJa: gameDTO.nameJa,
                aliases: gameDTO.aliases,
                releaseDate: gameDTO.releaseDate,
                coverData: gameDTO.coverBase64.flatMap { Data(base64Encoded: $0) },
                reviewTitle: gameDTO.reviewTitle,
                reviewBody: gameDTO.reviewBody
            )
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

            // 持有记录（旧版备份缺字段 → 保持现状不创建）
            if let copies = gameDTO.copies {
                for copyDTO in copies {
                    let copy = PhysicalCopy(
                        version: copyDTO.version,
                        count: max(1, copyDTO.count),
                        images: copyDTO.images.prefix(6).compactMap { Data(base64Encoded: $0) }
                    )
                    copy.game = game
                    context.insert(copy)
                }
            }
        }
    }
}
