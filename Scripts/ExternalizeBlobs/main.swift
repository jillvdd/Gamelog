// 一次性迁移脚本：把 store 里的内联图片 BLOB 真正搬到 .externalStorage。
// 背景：模型改 @Attribute(.externalStorage) 只影响**新写入**的行；轻量迁移后存量
// BLOB 仍内联在 SQLite 行里（探针实测：仅打开迁移 store 不减体积、重赋同一值
// Core Data 判定未变跳过）。nil→save→存回→save 两段式可强制外部化。
//
// 用法：gamelog_externalize  （操作真实 store，运行前必须：退 app + 快照 store）
// 编译（beta 工具链，文件清单 = DataSmokeTest + 全 Models）：
//   /Users/abc/Downloads/Xcode-beta.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc \
//     -sdk /Users/abc/Downloads/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk \
//     -plugin-path /Users/abc/Downloads/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins \
//     -o /tmp/gamelog_externalize \
//     Scripts/ExternalizeBlobs/main.swift \
//     GameLog/Models/Game.swift GameLog/Models/Completion.swift GameLog/Models/GameGroup.swift \
//     GameLog/Models/PhysicalCopy.swift GameLog/Models/Presets.swift \
//     GameLog/Support/ScoreMath.swift GameLog/Support/ExportImport.swift \
//     GameLog/Support/UserCustomization.swift GameLog/Support/PlatformImage.swift \
//     GameLog/Support/EnumPickerRow.swift GameLog/Support/L10n.swift GameLog/Support/AppLanguage.swift
import Foundation
import SwiftData

func say(_ s: String) { print(s); fflush(stdout) }

let storeURL = URL(fileURLWithPath: "/Users/abc/Library/Application Support/default.store")
let schema = Schema([Game.self, Completion.self, GameGroup.self])
let config = ModelConfiguration(url: storeURL)
guard let container = try? ModelContainer(for: schema, configurations: [config]) else {
    say("FATAL: cannot open store at \(storeURL.path)"); exit(1)
}
let context = ModelContext(container)
let games = (try? context.fetch(FetchDescriptor<Game>())) ?? []
say("store: \(storeURL.path) — \(games.count) games")

let t0 = Date()
var movedGames = 0
for g in games {
    let cover = g.coverData
    let square = g.squareData
    let landscape = g.landscapeData
    let hero = g.heroData
    let logo = g.logoData
    let copyImages = g.copies.map { $0.images }
    let isEmpty = cover == nil && square == nil && landscape == nil && hero == nil && logo == nil
        && copyImages.allSatisfy { $0.isEmpty }
    if isEmpty { continue }

    g.coverData = nil; g.squareData = nil; g.landscapeData = nil; g.heroData = nil; g.logoData = nil
    for c in g.copies { c.images = [] }
    do { try context.save() } catch { say("SAVE1 FAILED @\(g.name): \(error)"); exit(1) }

    g.coverData = cover
    g.squareData = square
    g.landscapeData = landscape
    g.heroData = hero
    g.logoData = logo
    for (i, c) in g.copies.enumerated() { c.images = copyImages[i] }
    do { try context.save() } catch { say("SAVE2 FAILED @\(g.name): \(error)"); exit(1) }
    movedGames += 1
    if movedGames % 20 == 0 { say("  … \(movedGames) games externalized") }
}
say("externalized \(movedGames) games in \(String(format: "%.1f", Date().timeIntervalSince(t0)))s")

// 完整性校验：重新 fetch，确认每张图仍是合法 PNG/JPEG/WebP 头。
let context2 = ModelContext(container)
let games2 = (try? context2.fetch(FetchDescriptor<Game>())) ?? []
var bad = 0
func looksLikeImage(_ d: Data) -> Bool {
    d.starts(with: [0xFF, 0xD8]) || d.starts(with: [0x89, 0x50, 0x4E, 0x47])
        || d.starts(with: Array("GIF8".utf8)) || d.starts(with: Array("RIFF".utf8))
}
for g in games2 {
    for (field, d) in [("cover", g.coverData), ("square", g.squareData), ("landscape", g.landscapeData),
                       ("hero", g.heroData), ("logo", g.logoData)] {
        if let d, !looksLikeImage(d) { say("CORRUPT \(field) @\(g.name)"); bad += 1 }
    }
    for c in g.copies {
        for (i, d) in c.images.enumerated() where !looksLikeImage(d) {
            say("CORRUPT photo[\(i)] @\(g.name)/\(c.version)"); bad += 1
        }
    }
}
if bad == 0 {
    say("VERIFY OK: all images valid")
} else {
    say("VERIFY FAILED: \(bad) corrupt — restore from snapshot!")
    exit(1)
}
