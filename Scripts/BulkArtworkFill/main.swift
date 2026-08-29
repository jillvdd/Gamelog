// 一次性批量补图脚本：为库内所有游戏的缺失图像字段（五类：2:3 封面/方形/横向/背景图/Logo）
// 按 SteamGridDB 自动匹配。语义与编辑页 autoMatch 同口径：只补缺、绝不覆盖已有图；每类取端点第一张。
// 搜索词链：英文名 → 别名 → 中文名 → 日文名（首个命中即用，结果按词缓存含无命中）。
//
// 用法：gamelog_bulkfill <SGDB API Key>
// 编译（beta 工具链，铁律⑦；文件清单 = DataSmokeTest + SteamGridDBClient）：
//   /Users/abc/Downloads/Xcode-beta.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc \
//     -sdk /Users/abc/Downloads/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk \
//     -plugin-path /Users/abc/Downloads/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins \
//     -o /tmp/gamelog_bulkfill \
//     Scripts/BulkArtworkFill/main.swift \
//     GameLog/Models/Game.swift GameLog/Models/Completion.swift GameLog/Models/GameGroup.swift \
//     GameLog/Models/PhysicalCopy.swift GameLog/Models/Presets.swift \
//     GameLog/Support/ScoreMath.swift GameLog/Support/ExportImport.swift \
//     GameLog/Support/UserCustomization.swift GameLog/Support/PlatformImage.swift \
//     GameLog/Support/EnumPickerRow.swift GameLog/Support/L10n.swift GameLog/Support/AppLanguage.swift \
//     GameLog/Support/SteamGridDBClient.swift \
//     GameLog/Models/Artwork.swift \
//     GameLog/Support/ImageDecodeCache.swift
// 注意：写真实 store 前先退 app 并快照 store（GameLog-backups/<日期>-pre-bulk-artwork）。
import Foundation
import SwiftData

func say(_ s: String) { print(s); fflush(stdout) }

let args = CommandLine.arguments
guard args.count >= 2 else { say("usage: gamelog_bulkfill <SGDB API Key>"); exit(2) }
let apiKey = SteamGridDBClient.sanitizedKey(args[1])
guard !apiKey.isEmpty else { say("empty API key"); exit(2) }

let storeURL = URL(fileURLWithPath: "/Users/abc/Library/Application Support/default.store")
let schema = Schema([Game.self, Completion.self, GameGroup.self])
let config = ModelConfiguration(url: storeURL)
guard let container = try? ModelContainer(for: schema, configurations: [config]) else {
    say("FATAL: cannot open store at \(storeURL.path)"); exit(1)
}
let context = ModelContext(container)
let games = (try? context.fetch(FetchDescriptor<Game>())) ?? []
say("store: \(storeURL.path) — \(games.count) games")

let client = SteamGridDBClient(apiKey: apiKey)
/// term.lowercased() → SGDB 游戏 id；-1 = 该词确认无命中（网络错误不缓存，下个词继续试）。
var searchCache: [String: Int] = [:]

func looksLikeImage(_ data: Data) -> Bool {
    if data.starts(with: [0xFF, 0xD8]) { return true }              // JPEG
    if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return true }  // PNG
    if data.starts(with: Array("GIF8".utf8)) { return true }        // GIF
    if data.starts(with: Array("RIFF".utf8)) { return true }        // WebP
    return false
}

@MainActor
func searchGameID(for game: Game) async -> (id: Int, term: String)? {
    var terms = [game.name.trimmingCharacters(in: .whitespaces)]
    terms += game.aliases.map { $0.trimmingCharacters(in: .whitespaces) }
    if let zh = game.nameZh?.trimmingCharacters(in: .whitespaces), !zh.isEmpty { terms.append(zh) }
    if let ja = game.nameJa?.trimmingCharacters(in: .whitespaces), !ja.isEmpty { terms.append(ja) }
    for term in terms where term.count >= 2 {
        let key = term.lowercased()
        if let cached = searchCache[key] {
            if cached != -1 { return (cached, term) }
            continue
        }
        do {
            let hits = try await client.search(term: term)
            let id = hits.first?.id ?? -1
            searchCache[key] = id
            if id != -1 { return (id, term) }
        } catch {
            say("  search error for \(term): \(error)")
        }
    }
    return nil
}

/// 单类图：端点第一张 → 下载（校验图片 magic bytes，防错误页当图入库）→ 经 Game.setArtwork 写入。
/// kind→端点的分派复用 app 的 SteamGridDBClient.artworkResults（不再手抄映射）。返回 nil = 成功。
@MainActor
func fill(kind: ArtworkKind, game: Game, sgdbID: Int) async -> String? {
    let grid: SteamGridDBGrid?
    do {
        grid = try await client.artworkResults(for: sgdbID, kind: kind).first
    } catch { return "endpoint error: \(error)" }
    guard let g = grid else { return "no candidate" }
    let data: Data
    do { data = try await client.fetchImage(urlString: g.url) } catch { return "download error: \(error)" }
    guard data.count > 100, looksLikeImage(data) else { return "not an image (\(data.count)B)" }
    game.setArtwork(kind, data)
    return nil
}

@MainActor
func missingKinds(of game: Game) -> [ArtworkKind] {
    ArtworkKind.allCases.filter { game.artwork($0) == nil }
}

var gamesTouched = 0, kindsFilled = 0, noHit = 0, failedKinds = 0

for (idx, game) in games.enumerated() {
    let missing = missingKinds(of: game)
    guard !missing.isEmpty else { continue }
    say("[\(idx + 1)/\(games.count)] \(game.name) — 补 \(missing.map(\.rawValue).joined(separator: ","))")
    guard let hit = await searchGameID(for: game) else {
        noHit += 1
        say("  ✗ SGDB 无命中（主名/别名/中文名/日文名都试过）")
        continue
    }
    say("  → SGDB #\(hit.id)（搜索词「\(hit.term)」）")
    var ok: [ArtworkKind] = [], fail: [ArtworkKind] = []
    for kind in missing {
        if let reason = await fill(kind: kind, game: game, sgdbID: hit.id) {
            fail.append(kind)
        } else {
            ok.append(kind)
        }
    }
    if !ok.isEmpty {
        do { try context.save() } catch { say("  save error: \(error)") }
        gamesTouched += 1
        kindsFilled += ok.count
        say("  ✓ 已填 \(ok.map(\.rawValue).joined(separator: ","))")
    }
    if !fail.isEmpty {
        failedKinds += fail.count
        say("  △ 未填 \(fail.map(\.rawValue).joined(separator: ", "))")
    }
}

say("")
say("===== 汇总 =====")
say("游戏总数 \(games.count)；补图成功 \(gamesTouched) 个游戏共 \(kindsFilled) 张；SGDB 无命中 \(noHit) 个；失败类目 \(failedKinds) 张")
exit(0)
