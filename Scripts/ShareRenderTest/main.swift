// GameLog 分享卡渲染管线冒烟测试：真实调用 ImageRenderer 出图，校验尺寸与编码路径。
// 覆盖：单卡竖版/横版、总览图（自适应列数）、无封面占位、无评分路径、分组卡（含拉高）、JPEG 导出。
//
// 编译运行（Xcode 工具链 + 宏插件路径，勿用 CLT swiftc；`-sdk` 必需，否则标准库加载失败）：
//   xcrun swiftc -sdk <Xcode-beta MacOSX.sdk> -o /tmp/gamelog_sharetest \
//     Scripts/ShareRenderTest/main.swift \
//     GameLog/Models/Game.swift GameLog/Models/Completion.swift GameLog/Models/GameGroup.swift \
//     GameLog/Models/PhysicalCopy.swift GameLog/Models/Presets.swift \
//     GameLog/Models/LinkedAccount.swift GameLog/Models/ExternalGameRecord.swift \
//     GameLog/Support/ExternalImport/ExternalGameRecordDTO.swift \
//     GameLog/Support/ExternalImport/ExternalAPIError.swift \
//     GameLog/Support/ExternalImport/ExternalHTTPClient.swift \
//     GameLog/Support/ExternalImport/TitleScript.swift \
//     GameLog/Support/ExternalImport/PlayStation/PSNAPI.swift \
//     GameLog/Support/ExternalImport/Xbox/XboxAPI.swift \
//     GameLog/Support/ExternalImport/ExternalTimestamp.swift \
//     GameLog/Support/PlayActivity.swift \
//     GameLog/Support/Achievement.swift \
//     GameLog/Support/ScoreMath.swift GameLog/Support/AppLanguage.swift GameLog/Support/L10n.swift \
//     GameLog/Support/UserCustomization.swift GameLog/Support/PlatformImage.swift \
//     GameLog/Support/EnumPickerRow.swift GameLog/Support/PriceFormat.swift \
//     GameLog/Support/MarkdownReview.swift GameLog/Support/LiquidGlassToolbar.swift GameLog/Support/StatusStyle.swift \
//     GameLog/Support/BrandPalette.swift GameLog/Support/SurfaceStyle.swift \
//     GameLog/Support/TrophyStyle.swift \
//     GameLog/Models/Artwork.swift GameLog/Support/ImageDecodeCache.swift \
//     GameLog/Share/ShareCardView.swift GameLog/Share/ShareCardRenderer.swift \
//     -plugin-path <Xcode-beta 插件路径>
//   /tmp/gamelog_sharetest
//
// ⚠️ 命令随源码增长而失效过四次（`Game.swift` 引用 `ExternalGameRecord`、`ShareCardView` 引用
// `BrandPalette`、`ExternalGameRecord.psnPlatformDisplay` 引用 `PSNAPI`、
// `ExternalGameRecord.xboxPlatformDisplay` 引用 `XboxAPI`），所以**每次跑之前先
// 确认这行命令仍然编译得过**，别复用旧二进制 —— 旧二进制跑出来的 PASS 与当前源码无关。
// 最后一次失败（2026-09-17）的表现正是「编译报 3 个 error，而旧二进制照样打印 PASS」。
import Foundation
import AppKit
import SwiftData

// `Game.coverImage` 等五个图片访问器自 2026-09-16 起归属 `Models/Artwork.swift`
//（解码走 `Support/ImageDecodeCache`），两者都编进本测试即可 —— 不再需要本地重复声明。
// 此前这里有一份手写的 `coverImage` 扩展，与 Artwork.swift 的同名属性冲突（重复声明）。

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

    // 单卡方版 (1:1)
    if let png = ShareCardRenderer.renderData(content: .single(game, size: .square), language: language),
       let size = pngSize(png) {
        check("单卡方版尺寸 1200x1200（实际 \(size.width)x\(size.height)）", size.width == 1200 && size.height == 1200)
    } else {
        check("单卡方版渲染成功", false)
    }

    // 单卡社交版 (4:5)
    if let png = ShareCardRenderer.renderData(content: .single(game, size: .portrait), language: language),
       let size = pngSize(png) {
        check("单卡社交版尺寸 1080x1350（实际 \(size.width)x\(size.height)）", size.width == 1080 && size.height == 1350)
    } else {
        check("单卡社交版渲染成功", false)
    }

    // 浅色主题渲染测试
    if let png = ShareCardRenderer.renderData(content: .single(game, size: .phone), language: language, theme: .editorialLight) {
        check("雪岭纯白主题渲染成功", !png.isEmpty)
    } else {
        check("雪岭纯白主题渲染成功", false)
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

    // MARK: - 梯1.2 偏好持久化：RawRepresentable 枚举走 @AppStorage(String) 往返

    UserDefaults.standard.set(ShareSize.desktop.rawValue, forKey: UserCustomization.shareLastSizeKey)
    check("上次画幅持久化往返",
          UserDefaults.standard.string(forKey: UserCustomization.shareLastSizeKey) == ShareSize.desktop.rawValue
              && ShareSize(rawValue: ShareSize.desktop.rawValue) == .desktop)
    UserDefaults.standard.removeObject(forKey: UserCustomization.shareLastSizeKey)

    // MARK: - 梯1.4 effectiveScale：超限自动缩倍率

    check("effectiveScale 4000px 画布不缩", ShareCardRenderer.effectiveScale(canvas: CGSize(width: 4000, height: 4000), scale: 1) == 1)
    check("effectiveScale 20000px 画布缩到 0.6",
          abs(ShareCardRenderer.effectiveScale(canvas: CGSize(width: 20000, height: 20000), scale: 1) - 0.6) < 0.001)
    check("effectiveScale 预览倍率不被抬高",
          ShareCardRenderer.effectiveScale(canvas: CGSize(width: 1080, height: 1920), scale: 0.5) == 0.5)

    // MARK: - 梯2.5 水印显示方式：存储往返

    check("水印默认 full", ShareWatermarkStyle.current == .full)
    ShareWatermarkStyle.save(.textOnly)
    check("水印保存后读回 textOnly", ShareWatermarkStyle.current == .textOnly)
    check("textOnly 显示文字不显头像",
          ShareWatermarkStyle.textOnly.showsText && !ShareWatermarkStyle.textOnly.showsAvatar)
    check("hidden 两者都不显示", !ShareWatermarkStyle.hidden.showsText && !ShareWatermarkStyle.hidden.showsAvatar)
    UserDefaults.standard.removeObject(forKey: UserCustomization.shareWatermarkStyleKey)
    check("清除后回退 full", ShareWatermarkStyle.current == .full)

    // MARK: - 梯2.8 封面取色主题

    let tintTheme = ShareTheme.coverTint(from: [game])
    let brandTheme = ShareTheme.brand
    check("取色主题为暗底", tintTheme.isDark)
    // 无封面回退：coverTint(from: []) 不应崩溃且仍为暗底（等价 brand 路径）。
    check("无封面取色回退不崩", ShareTheme.coverTint(from: []).isDark)
    // 渲染一张取色卡并导出：蓝色封面应派生出明显非品牌暖底的背景（肉眼/像素双验）。
    if let png = ShareCardRenderer.renderData(content: .single(game, size: .phone), language: language, theme: tintTheme),
       NSImage(data: png) != nil {
        check("封面取色主题渲染成功", true)
        try? png.write(to: URL(fileURLWithPath: "/tmp/gamelog_share_covertint.png"))
    } else {
        check("封面取色主题渲染成功", false)
    }
    check("取色主题与品牌底不同", tintTheme.background != brandTheme.background || tintTheme.accent != brandTheme.accent)

    // MARK: - 梯2.6 浅色主题轨道色：分组卡（含分数条）雪岭纯白导出

    if let png = ShareCardRenderer.renderData(content: .group(group, title: "JRPG", size: .phone),
                                              language: language, theme: .editorialLight),
       NSImage(data: png) != nil {
        check("浅色分组卡渲染成功", true)
        try? png.write(to: URL(fileURLWithPath: "/tmp/gamelog_share_group_light.png"))
    } else {
        check("浅色分组卡渲染成功", false)
    }

    // MARK: - 梯3.9 九宫格分块纯函数 + 多图渲染

    let gridPool = Array(repeating: game, count: 20)
    let chunks = ShareCardRenderer.grid9Chunks(games: gridPool)
    check("九宫格 20 款切 9 块", chunks.count == 9)
    check("九宫格 20 款总量守恒", chunks.reduce(0) { $0 + $1.count } == 20)
    check("九宫格 20 款块间差 ≤1",
          (chunks.map(\.count).max() ?? 0) - (chunks.map(\.count).min() ?? 0) <= 1)
    check("九宫格 5 款切 5 块", ShareCardRenderer.grid9Chunks(games: Array(repeating: game, count: 5)).count == 5)
    check("九宫格 0 款空块", ShareCardRenderer.grid9Chunks(games: []).isEmpty)
    let gridDatas = ShareCardRenderer.renderGrid9Data(games: [game, plain, third, gameB, gameC],
                                                      title: "合集", language: language, theme: .brand,
                                                      format: .png)
    check("九宫格 5 款出 5 图", gridDatas.count == 5)
    if let first = gridDatas.first, let s = pngSize(first) {
        check("九宫格单图 1200x1200（实际 \(s.width)x\(s.height)）", s.width == 1200 && s.height == 1200)
        try? first.write(to: URL(fileURLWithPath: "/tmp/gamelog_share_grid9_1.png"))
    } else {
        check("九宫格单图尺寸可解析", false)
    }

    // MARK: - 梯3.10 统计摘要卡：四画幅渲染高宽与 statsSize 一致

    let stats = ShareStatsContent(
        title: "我的游戏档案",
        totalGames: 128, clearedGames: 42, totalPlaytime: 3210.5, averageScore: 8.4,
        statusRows: GameStatus.allCases.prefix(7).map { ShareStatsContent.StatusRow(status: $0, count: 20) },
        topGames: [ShareStatsContent.TopGame(name: "异度神剑3", score: 9.3),
                   ShareStatsContent.TopGame(name: "游戏B", score: 8.1)],
        platinumCount: 17, xboxGamerscore: 28450,
        spentTotal: 12345.6, estimateTotal: 23456.7)
    for sz in ShareSize.allCases {
        if let png = ShareCardRenderer.renderPNG(content: .stats(stats, size: sz), language: language),
           let s = pngSize(png) {
            let expected = ShareCardLayout.statsSize(content: stats, size: sz)
            check("统计卡 \(sz.rawValue) 尺寸 \(Int(expected.width))x\(Int(expected.height))（实际 \(s.width)x\(s.height)）",
                  abs(Double(s.width) - expected.width) <= 1 && abs(Double(s.height) - expected.height) <= 1)
            try? png.write(to: URL(fileURLWithPath: "/tmp/gamelog_share_stats_\(sz.rawValue).png"))
        } else {
            check("统计卡 \(sz.rawValue) 渲染成功", false)
        }
    }
    // 空数据（全新库）也要能出图不崩
    let emptyStats = ShareStatsContent(title: "t", totalGames: 0, clearedGames: 0, totalPlaytime: 0,
                                       averageScore: nil, statusRows: [], topGames: [],
                                       platinumCount: 0, xboxGamerscore: 0, spentTotal: nil, estimateTotal: nil)
    if let png = ShareCardRenderer.renderPNG(content: .stats(emptyStats, size: .phone), language: language) {
        check("统计卡空库渲染成功", !png.isEmpty)
        try? png.write(to: URL(fileURLWithPath: "/tmp/gamelog_share_stats_empty.png"))
    } else {
        check("统计卡空库渲染成功", false)
    }

    // MARK: - §82-1 水印文字自定义（样式设置可编辑）

    UserDefaults.standard.set("jillの遊び帳", forKey: UserCustomization.shareWatermarkTextKey)
    if let png = ShareCardRenderer.renderPNG(content: .stats(stats, size: .square), language: language) {
        check("水印文字自定义卡渲染成功", !png.isEmpty)
        try? png.write(to: URL(fileURLWithPath: "/tmp/gamelog_share_watermarktext.png"))
    } else {
        check("水印文字自定义卡渲染成功", false)
    }
    // 总览卡右上角水印是 OverviewCard 独立实现，同样必须吃到覆盖文字
    if let png = ShareCardRenderer.renderPNG(content: .overview([game, plain], title: "水印总览", size: .phone), language: language) {
        check("总览卡水印自定义渲染成功", !png.isEmpty)
        try? png.write(to: URL(fileURLWithPath: "/tmp/gamelog_share_watermarktext_overview.png"))
    } else {
        check("总览卡水印自定义渲染成功", false)
    }
    // 清空回退默认拼接（用户名 + 游戏簿）
    UserDefaults.standard.set("", forKey: UserCustomization.shareWatermarkTextKey)
    if let png = ShareCardRenderer.renderPNG(content: .stats(stats, size: .square), language: language) {
        check("水印文字清空回退默认渲染成功", !png.isEmpty)
        try? png.write(to: URL(fileURLWithPath: "/tmp/gamelog_share_watermarkdefault.png"))
    } else {
        check("水印文字清空回退默认渲染成功", false)
    }

    // MARK: - §82-3 宽封面不露底色框：letterboxes 判据 + 模糊铺底出图

    // 16:9 横图（1.778 > 2:3 框 × 1.15 容差 = 0.767）→ 该走「完整展示 + 模糊铺底」档
    let wide = NSImage(size: NSSize(width: 960, height: 540))
    wide.lockFocus()
    NSColor.systemRed.setFill()
    NSRect(x: 0, y: 0, width: 960, height: 540).fill()
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: 380, y: 170, width: 200, height: 200)).fill()
    wide.unlockFocus()
    guard let wideData = wide.tiffRepresentation else { print("FAIL: wide no tiff"); return 1 }
    let wideGame = Game(name: "横版封面测试", coverData: wideData)
    context.insert(wideGame)
    try? context.save()

    check("横图进 2:3 框判定为留白档", wideGame.coverImage?.letterboxes(inBoxAspect: 2.0 / 3.0) == true)
    check("竖图进 2:3 框判定为裁切档", game.coverImage?.letterboxes(inBoxAspect: 2.0 / 3.0) == false)

    // §83「去掉框」：单卡海报框必须与封面同比例（2:3 源 → 海报清晰区宽高比 ≈ 2:3，
    // 框内不得出现比封面更大的留缝框）。导出供像素级复核。
    if let png = ShareCardRenderer.renderPNG(content: .single(wideGame, size: .phone), language: language) {
        check("横封面单卡渲染成功（去框导出）", !png.isEmpty)
        try? png.write(to: URL(fileURLWithPath: "/tmp/gamelog_share_widecover_single.png"))
    } else {
        check("横封面单卡渲染成功（去框导出）", false)
    }

    if let png = ShareCardRenderer.renderPNG(
        content: .overview([game, wideGame, third], title: "宽图框测试", size: .phone), language: language) {
        check("含横封面总览卡渲染成功", !png.isEmpty)
        try? png.write(to: URL(fileURLWithPath: "/tmp/gamelog_share_widecover.png"))
    } else {
        check("含横封面总览卡渲染成功", false)
    }
    let wideGrid = ShareCardRenderer.renderGrid9Data(games: [game, wideGame], title: "宽图九宫",
                                                     language: language, theme: .brand, format: .png)
    check("宽图九宫格出 2 图", wideGrid.count == 2)
    if let first = wideGrid.first, let s = pngSize(first) {
        check("宽图九宫格仍精确 1200x1200（实际 \(s.width)x\(s.height)）", s.width == 1200 && s.height == 1200)
        try? first.write(to: URL(fileURLWithPath: "/tmp/gamelog_share_widecover_grid9.png"))
    } else {
        check("宽图九宫格渲染成功", false)
    }

    return failures == 0 ? 0 : 1
}

Task { @MainActor in
    let code = run()
    print(code == 0 ? "SHARE RENDER TEST PASSED" : "SHARE RENDER TEST FAILED")
    exit(code == 0 ? 0 : 1)
}
dispatchMain()
