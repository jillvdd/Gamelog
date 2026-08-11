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
}

struct GameDTO: Codable {
    var name: String
    var aliases: [String]
    var releaseDate: Date?
    var coverBase64: String?
    var reviewTitle: String
    var reviewBody: String
    var groupNames: [String]
    var completions: [CompletionDTO]
}

struct CompletionDTO: Codable {
    var platform: String
    var date: Date
    var degree: String
    var playtime: Double?
    var notes: String
    var scoreStory: Double?
    var scoreGraphics: Double?
    var scoreMusic: Double?
    var scoreGameplay: Double?
}

// MARK: - 导出 / 导入

/// 把整个库序列化成单个 JSON 文件（封面以 base64 内嵌），可整体导回。
enum BackupManager {

    /// 导出：所有游戏 + 分组 → JSON。
    static func encode(games: [Game], groups: [GameGroup]) throws -> Data {
        let dto = BackupDTO(
            version: 1,
            exportedAt: .now,
            groups: groups.map { GroupDTO(name: $0.name) },
            games: games.map { game in
                GameDTO(
                    name: game.name,
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
                            scoreStory: completion.scoreStory,
                            scoreGraphics: completion.scoreGraphics,
                            scoreMusic: completion.scoreMusic,
                            scoreGameplay: completion.scoreGameplay
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

        // 清空现有（删除游戏会级联删除通关记录）
        if let existingGames = try? context.fetch(FetchDescriptor<Game>()) {
            existingGames.forEach { context.delete($0) }
        }
        if let existingGroups = try? context.fetch(FetchDescriptor<GameGroup>()) {
            existingGroups.forEach { context.delete($0) }
        }

        var groupMap: [String: GameGroup] = [:]
        for groupDTO in dto.groups {
            let group = GameGroup(name: groupDTO.name)
            context.insert(group)
            groupMap[groupDTO.name] = group
        }

        for gameDTO in dto.games {
            let game = Game(
                name: gameDTO.name,
                aliases: gameDTO.aliases,
                releaseDate: gameDTO.releaseDate,
                coverData: gameDTO.coverBase64.flatMap { Data(base64Encoded: $0) },
                reviewTitle: gameDTO.reviewTitle,
                reviewBody: gameDTO.reviewBody
            )
            game.groups = gameDTO.groupNames.compactMap { groupMap[$0] }
            context.insert(game)

            for completionDTO in gameDTO.completions {
                let completion = Completion(
                    platform: completionDTO.platform,
                    date: completionDTO.date,
                    degree: completionDTO.degree,
                    playtime: completionDTO.playtime,
                    notes: completionDTO.notes,
                    scoreStory: completionDTO.scoreStory,
                    scoreGraphics: completionDTO.scoreGraphics,
                    scoreMusic: completionDTO.scoreMusic,
                    scoreGameplay: completionDTO.scoreGameplay
                )
                completion.game = game
                context.insert(completion)
            }
        }

        // 自定义三项：旧版备份缺字段 → 保持现状不覆盖
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
        if let avatar = dto.avatarBase64.flatMap({ Data(base64Encoded: $0) }) {
            try UserCustomization.saveAvatarPNG(avatar)
        }
        if let icon = dto.iconBase64.flatMap({ Data(base64Encoded: $0) }) {
            try UserCustomization.saveIconPNG(icon)
        }
    }
}
