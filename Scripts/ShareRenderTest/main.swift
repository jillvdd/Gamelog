// GameLog 分享卡渲染管线冒烟测试：真实调用 ImageRenderer 生成 PNG，校验尺寸与内容。
// 覆盖：单卡竖版/横版、总览图（含换行）、无封面占位、无评分路径。
//
// 编译运行：
//   xcrun swiftc -o /tmp/gamelog_sharetest \
//     Scripts/ShareRenderTest/main.swift \
//     GameLog/Models/Game.swift GameLog/Models/Completion.swift GameLog/Models/GameGroup.swift \
//     GameLog/Models/PhysicalCopy.swift GameLog/Models/Presets.swift \
//     GameLog/Support/ScoreMath.swift GameLog/Support/AppLanguage.swift GameLog/Support/L10n.swift \
//     GameLog/Support/UserCustomization.swift \
//     GameLog/Share/ShareCardView.swift GameLog/Share/ShareCardRenderer.swift \
//     -plugin-path /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins
//   /tmp/gamelog_sharetest
import Foundation
import AppKit
import SwiftData

// Game.coverImage 扩展在 GameCardView.swift（含 NewGroupSheet，依赖 SwiftData 环境），
// 此处为纯渲染测试独立声明，避免拖入无关视图。
extension Game {
    var coverImage: NSImage? { coverData.flatMap(NSImage.init(data:)) }
}

var failures = 0
func check(_ name: String, _ cond: Bool) {
    print("\(cond ? "PASS" : "FAIL") \(name)")
    if !cond { failures += 1 }
}

/// 从 PNG 字节解析像素尺寸（宽 4 字节 + 高 4 字节，位于偏移 16）。
func pngSize(_ data: Data) -> (width: Int, height: Int)? {
    guard data.count >= 24, data[0] == 0x89, data[1] == 0x50 else { return nil }
    let w = Int(data[16]) << 24 | Int(data[17]) << 16 | Int(data[18]) << 8 | Int(data[19])
    let h = Int(data[20]) << 24 | Int(data[21]) << 16 | Int(data[22]) << 8 | Int(data[23])
    return (w, h)
}

@MainActor
func run() -> Int {
    // 命令行工具里 NSApp 默认未初始化；真实 app 中始终有效。
    let app = NSApplication.shared
    _ = app

    let schema = Schema([Game.self, Completion.self, GameGroup.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    guard let container = try? ModelContainer(for: schema, configurations: [config]) else {
        print("FAIL: cannot create ModelContainer"); return 1
    }
    let context = ModelContext(container)

    // 一个有封面有评分有评价的游戏
    let cover = NSImage(size: NSSize(width: 4, height: 4))
    cover.lockFocus()
    NSColor.systemBlue.setFill()
    NSRect(x: 0, y: 0, width: 4, height: 4).fill()
    cover.unlockFocus()
    guard let coverData = cover.tiffRepresentation else { print("FAIL: no tiff"); return 1 }

    let game = Game(name: "异度神剑3", aliases: [], releaseDate: nil,
                    coverData: coverData, reviewTitle: "RPG 天花板", reviewBody: "")
    context.insert(game)
    let c = Completion(platform: "Switch", date: .now, degree: "全收集/白金", playtime: 150,
                       notes: "", scoreGameplay: 9.5, scoreDesign: 9, scoreStory: 9.5,
                       scoreArt: 8.5, scoreMusic: 9, scorePerformance: 9)
    c.game = game
    context.insert(c)

    // 无封面无评分的游戏（覆盖占位与"未评分"路径）
    let plain = Game(name: "未收录封面", reviewTitle: "测试")
    context.insert(plain)

    // 一个用于总览图换行的第三个游戏
    let third = Game(name: "第三款游戏", reviewTitle: "测试3")
    context.insert(third)
    try? context.save()

    let language = "zh-Hans"

    // 单卡竖版
    if let png = ShareCardRenderer.renderPNG(content: .single(game, size: .phone), language: language),
       let size = pngSize(png) {
        check("单卡竖版尺寸 1080x1920（实际 \(size.width)x\(size.height)）", size.width == 1080 && size.height == 1920)
        try? png.write(to: URL(fileURLWithPath: "/tmp/gamelog_share_phone.png"))
    } else {
        check("单卡竖版渲染成功", false)
    }

    // 单卡横版
    if let png = ShareCardRenderer.renderPNG(content: .single(game, size: .desktop), language: language),
       let size = pngSize(png) {
        check("单卡横版尺寸 1920x1080（实际 \(size.width)x\(size.height)）", size.width == 1920 && size.height == 1080)
        try? png.write(to: URL(fileURLWithPath: "/tmp/gamelog_share_desktop.png"))
    } else {
        check("单卡横版渲染成功", false)
    }

    // 无评分路径（单卡竖版）
    if let png = ShareCardRenderer.renderPNG(content: .single(plain, size: .phone), language: language) {
        check("无评分单卡渲染成功（未评分路径）", !png.isEmpty)
    } else {
        check("无评分单卡渲染成功（未评分路径）", false)
    }

    // 总览图：3 款手机 → 2 列 2 行
    if let png = ShareCardRenderer.renderPNG(content: .overview([game, plain, third], title: "我的通关记录", size: .phone), language: language) {
        let expectedHeight = ShareCardLayout.overviewSize(gameCount: 3, size: .phone).height
        if let size = pngSize(png) {
            check("总览 3 款手机宽度 1080", size.width == 1080)
            // 高度容差 ±1px：cellHeight 含 4/3 亚像素，ImageRenderer 按整数像素取整
            check("总览 3 款手机高度按布局 \(Int(expectedHeight))（实际 \(size.height)）",
                  abs(Double(size.height) - expectedHeight) <= 1)
        } else {
            check("总览 3 款手机尺寸可解析", false)
        }
        try? png.write(to: URL(fileURLWithPath: "/tmp/gamelog_share_overview3.png"))
    } else {
        check("总览 3 款手机渲染成功", false)
    }

    // 总览图：5 款桌面 → 4 列 2 行
    let gameB = Game(name: "游戏B", reviewTitle: "B")
    let gameC = Game(name: "游戏C", reviewTitle: "C")
    let gameD = Game(name: "游戏D", reviewTitle: "D")
    context.insert(gameB); context.insert(gameC); context.insert(gameD)
    if let png = ShareCardRenderer.renderPNG(
        content: .overview([game, plain, third, gameB, gameC], title: "合集", size: .desktop), language: language) {
        let expectedHeight = ShareCardLayout.overviewSize(gameCount: 5, size: .desktop).height
        if let size = pngSize(png) {
            check("总览 5 款桌面宽度 1920", size.width == 1920)
            check("总览 5 款桌面高度按布局 \(Int(expectedHeight))（实际 \(size.height)）",
                  abs(Double(size.height) - expectedHeight) <= 1)
        } else {
            check("总览 5 款桌面尺寸可解析", false)
        }
        try? png.write(to: URL(fileURLWithPath: "/tmp/gamelog_share_overview5.png"))
    } else {
        check("总览 5 款桌面渲染成功", false)
    }

    // 分组分享卡：一个已评分（Switch）游戏 + 一个未评分游戏
    let group = GameGroup(name: "JRPG")
    context.insert(group)
    group.games = [game, plain]
    try? context.save()

    if let png = ShareCardRenderer.renderPNG(content: .group(group, title: "JRPG", size: .phone), language: language),
       let size = pngSize(png) {
        check("分组卡竖版尺寸 1080x1920（实际 \(size.width)x\(size.height)）", size.width == 1080 && size.height == 1920)
        try? png.write(to: URL(fileURLWithPath: "/tmp/gamelog_share_group_phone.png"))
    } else {
        check("分组卡竖版渲染成功", false)
    }

    if let png = ShareCardRenderer.renderPNG(content: .group(group, title: "JRPG", size: .desktop), language: language),
       let size = pngSize(png) {
        check("分组卡横版尺寸 1920x1080（实际 \(size.width)x\(size.height)）", size.width == 1920 && size.height == 1080)
        try? png.write(to: URL(fileURLWithPath: "/tmp/gamelog_share_group_desktop.png"))
    } else {
        check("分组卡横版渲染成功", false)
    }

    // 分组卡拉长：10 款游戏 → 竖版画布应高于标准 1920（同总览，按内容拉高）
    let bigGroup = GameGroup(name: "大合集")
    context.insert(bigGroup)
    let extraGames = (0..<10).map { i -> Game in
        let g = Game(name: "游戏\(i)", reviewTitle: "t")
        context.insert(g)
        return g
    }
    bigGroup.games = extraGames
    try? context.save()
    if let png = ShareCardRenderer.renderPNG(content: .group(bigGroup, title: "大合集", size: .phone), language: language),
       let size = pngSize(png) {
        let expected = ShareCardLayout.groupSize(gameCount: 10, platformCount: 0, size: .phone)
        check("分组卡 10 款拉高至 \(Int(expected.height))（实际 \(size.height)）",
              abs(Double(size.height) - expected.height) <= 1)
        try? png.write(to: URL(fileURLWithPath: "/tmp/gamelog_share_group_10.png"))
    } else {
        check("分组卡 10 款渲染成功", false)
    }

    return failures == 0 ? 0 : 1
}

Task { @MainActor in
    let code = run()
    print(code == 0 ? "SHARE RENDER TEST PASSED" : "SHARE RENDER TEST FAILED")
    exit(code == 0 ? 0 : 1)
}
dispatchMain()
