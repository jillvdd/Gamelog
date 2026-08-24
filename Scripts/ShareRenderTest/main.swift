// GameLog 分享卡渲染管线冒烟测试：真实调用 ImageRenderer 出图，校验尺寸与编码路径。
// 覆盖：单卡竖版/横版、总览图（自适应列数）、无封面占位、无评分路径、分组卡（含拉高）、JPEG 导出。
//
// 编译运行（Xcode 工具链 + 宏插件路径，勿用 CLT swiftc）：
//   xcrun swiftc -o /tmp/gamelog_sharetest \
//     Scripts/ShareRenderTest/main.swift \
//     GameLog/Models/Game.swift GameLog/Models/Completion.swift GameLog/Models/GameGroup.swift \
//     GameLog/Models/PhysicalCopy.swift GameLog/Models/Presets.swift \
//     GameLog/Support/ScoreMath.swift GameLog/Support/AppLanguage.swift GameLog/Support/L10n.swift \
//     GameLog/Support/UserCustomization.swift GameLog/Support/PlatformImage.swift \
//     GameLog/Support/EnumPickerRow.swift GameLog/Support/PriceFormat.swift \
//     GameLog/Support/MarkdownReview.swift \
//     GameLog/Share/ShareCardView.swift GameLog/Share/ShareCardRenderer.swift \
//     -plugin-path <Xcode-beta 插件路径>
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

    // 一个有封面有评分有评价的游戏（封面用 SteamGridDB 真实比例 600×900 = 2:3）
    let cover = NSImage(size: NSSize(width: 600, height: 900))
    cover.lockFocus()
    NSColor.systemBlue.setFill()
    NSRect(x: 0, y: 0, width: 600, height: 900).fill()
    NSColor.white.withAlphaComponent(0.25).setFill()
    NSRect(x: 0, y: 600, width: 600, height: 300).fill()
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

    // 未通关游戏（想玩状态，带封面/平台/发售日/tagline）——单卡状态徽章变体路径
    let backlog = Game(name: "还没通关的作品", platform: "PC",
                       releaseDate: Calendar.current.date(from: DateComponents(year: 2024, month: 11, day: 15)),
                       coverData: coverData, reviewTitle: "等有空再玩")
    backlog.statusValue = .backlog
    context.insert(backlog)
    try? context.save()

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

    // 无评分路径（单卡竖版，未通关状态徽章路径）
    if let png = ShareCardRenderer.renderPNG(content: .single(plain, size: .phone), language: language) {
        check("无评分单卡渲染成功（未评分路径）", !png.isEmpty)
    } else {
        check("无评分单卡渲染成功（未评分路径）", false)
    }

    // 未通关（想玩）单卡：状态徽章变体，出图供视觉检查
    if let png = ShareCardRenderer.renderPNG(content: .single(backlog, size: .phone), language: language),
       let size = pngSize(png) {
        check("未通关单卡渲染成功（状态徽章路径）1080x1920（实际 \(size.width)x\(size.height)）",
              size.width == 1080 && size.height == 1920)
        try? png.write(to: URL(fileURLWithPath: "/tmp/gamelog_share_backlog.png"))
    } else {
        check("未通关单卡渲染成功（状态徽章路径）", false)
    }

    // 总览图列数分档（手机 2/3/4、电脑 4/5/6）
    check("总览手机 ≤4 款 2 列", ShareCardLayout.overviewColumns(gameCount: 4, size: .phone) == 2)
    check("总览手机 10 款 3 列", ShareCardLayout.overviewColumns(gameCount: 10, size: .phone) == 3)
    check("总览手机 20 款 4 列", ShareCardLayout.overviewColumns(gameCount: 20, size: .phone) == 4)
    check("总览电脑 8 款 4 列", ShareCardLayout.overviewColumns(gameCount: 8, size: .desktop) == 4)
    check("总览电脑 15 款 5 列", ShareCardLayout.overviewColumns(gameCount: 15, size: .desktop) == 5)
    check("总览电脑 30 款 6 列", ShareCardLayout.overviewColumns(gameCount: 30, size: .desktop) == 6)

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

    // 分组分享卡：一个已评分（Switch）游戏 + 一个未评分游戏（默认统计要素配置）
    let group = GameGroup(name: "JRPG")
    context.insert(group)
    group.games = [game, plain]
    try? context.save()

    // 分组卡画布高 = max(名义高, 内容高)：小内容保名义 9:16 / 16:9，大内容拉高。
    // 断言语义 = 渲染产物与布局函数一致 + 不低于名义尺寸。
    if let png = ShareCardRenderer.renderPNG(content: .group(group, title: "JRPG", size: .phone), language: language),
       let size = pngSize(png) {
        let expected = ShareCardLayout.groupSize(gameCount: 2, platformCount: 1, size: .phone)
        check("分组卡竖版宽 1080、高与布局一致 \(Int(expected.height))（实际 \(size.width)x\(size.height)）",
              size.width == 1080 && abs(Double(size.height) - expected.height) <= 1 && size.height >= 1920)
        try? png.write(to: URL(fileURLWithPath: "/tmp/gamelog_share_group_phone.png"))
    } else {
        check("分组卡竖版渲染成功", false)
    }

    if let png = ShareCardRenderer.renderPNG(content: .group(group, title: "JRPG", size: .desktop), language: language),
       let size = pngSize(png) {
        let expected = ShareCardLayout.groupSize(gameCount: 2, platformCount: 1, size: .desktop)
        check("分组卡横版宽 1920、高与布局一致 \(Int(expected.height))（实际 \(size.width)x\(size.height)）",
              size.width == 1920 && abs(Double(size.height) - expected.height) <= 1 && size.height >= 1080)
        try? png.write(to: URL(fileURLWithPath: "/tmp/gamelog_share_group_desktop.png"))

        // 调试:裁最底 80px 条带,供 Read 检查底边白线/水印位置(验收期临时件)。
        if let img = NSImage(data: png), let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff), let cg = rep.cgImage {
            let strip = cg.cropping(to: CGRect(x: 0, y: cg.height - 80, width: cg.width, height: 80))
            if let strip {
                let srep = NSBitmapImageRep(cgImage: strip)
                try? srep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: "/tmp/gamelog_share_bottom_strip.png"))
            }
        }
    } else {
        check("分组卡横版渲染成功", false)
    }

    // 分组卡拉高：10 款游戏 → 竖版画布应高于标准 1920（同总览，按内容拉高）
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

    // JPEG 导出路径（默认导出格式）：非 PNG 魔数但可解码为 NSImage
    if let jpeg = ShareCardRenderer.renderData(content: .single(game, size: .phone), language: language,
                                               format: .jpeg(quality: 0.9)),
       jpeg.prefix(3) != Data([0x89, 0x50, 0x4E]),
       NSImage(data: jpeg) != nil {
        check("JPEG 导出可解码且非 PNG 魔数", true)
    } else {
        check("JPEG 导出可解码且非 PNG 魔数", false)
    }

    // 统计要素配置：默认不含收藏价值、顺序稳定往返（总时长已从分享线移除，默认 4 项）
    let defaults = ShareGroupStatsConfig.load()
    check("统计要素默认 4 项（无收藏价值）",
          defaults.count == 4 && !defaults.contains(.collectionValue))
    ShareGroupStatsConfig.save([.topGame, .averageScore])
    check("统计要素保存后按存入顺序读回",
          ShareGroupStatsConfig.load().map(\.rawValue) == ["topGame", "averageScore"])
    UserDefaults.standard.removeObject(forKey: UserCustomization.shareGroupStatsKey)
    check("清除存储后回退默认配置", ShareGroupStatsConfig.load().count == 4)

    // 总览头部汇总池：默认（款数+均分）与顺序往返
    check("头部汇总默认 2 项（款数+均分）",
          ShareOverviewStatsConfig.load() == [.gameCount, .averageScore])
    ShareOverviewStatsConfig.save([.collectionValue, .completionCount])
    check("头部汇总保存后按存入顺序读回",
          ShareOverviewStatsConfig.load() == [.collectionValue, .completionCount])
    UserDefaults.standard.removeObject(forKey: UserCustomization.shareOverviewStatsKey)

    // 游戏格子字段池：默认（平台/评分/最近通关）与顺序往返
    check("格子字段默认 3 项（平台/评分/日期）",
          ShareTileFieldsConfig.load() == [.platform, .score, .date])
    ShareTileFieldsConfig.save([.status, .releaseYear])
    check("格子字段保存后按存入顺序读回",
          ShareTileFieldsConfig.load() == [.status, .releaseYear])
    UserDefaults.standard.removeObject(forKey: UserCustomization.shareTileFieldsKey)

    return failures == 0 ? 0 : 1
}

Task { @MainActor in
    let code = run()
    print(code == 0 ? "SHARE RENDER TEST PASSED" : "SHARE RENDER TEST FAILED")
    exit(code == 0 ? 0 : 1)
}
dispatchMain()
