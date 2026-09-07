// GameLog 数据层回归冒烟测试（可重复运行，编译进产物但不编进 app）。
// 覆盖：多对多双向、级联删除、删分组不删游戏、评分集成、零记录、别名搜索、
//       备份全字段往返、重复导入幂等、导入替换语义、日期保真、持有记录往返。
//
// 编译运行（Xcode 工具链 + 宏插件路径，勿用 CLT swiftc；`-sdk` 必需，否则标准库加载失败）：
//   xcrun swiftc -sdk <Xcode-beta MacOSX.sdk> -o /tmp/gamelog_datasmoke \
//     Scripts/DataSmokeTest/main.swift \
//     GameLog/Models/Game.swift GameLog/Models/Completion.swift GameLog/Models/GameGroup.swift \
//     GameLog/Models/PhysicalCopy.swift GameLog/Models/Presets.swift GameLog/Models/Artwork.swift \
//     GameLog/Support/ScoreMath.swift GameLog/Support/ExportImport.swift GameLog/Support/Game+Backup.swift \
//     GameLog/Support/BackupWriter.swift GameLog/Support/ImageDecodeCache.swift \
//     GameLog/Support/LibraryStats.swift GameLog/Support/LibraryQuery.swift \
//     GameLog/Support/UserCustomization.swift GameLog/Support/PlatformImage.swift \
//     GameLog/Support/EnumPickerRow.swift GameLog/Support/L10n.swift GameLog/Support/AppLanguage.swift \
//     -plugin-path <Xcode-beta 插件路径>
//   /tmp/gamelog_datasmoke
import Foundation
import SwiftData

var failures = 0
func check(_ name: String, _ cond: Bool) {
    print("\(cond ? "PASS" : "FAIL") \(name)")
    if !cond { failures += 1 }
}

let schema = Schema([Game.self, Completion.self, GameGroup.self])
let config = ModelConfiguration(isStoredInMemoryOnly: true)
guard let container = try? ModelContainer(for: schema, configurations: [config]) else {
    print("FAIL: cannot create ModelContainer")
    exit(1)
}
let context = ModelContext(container)

// --- 1. 多对多双向 + 首条记录评分必填语义 ---
let game1 = Game(name: "塞尔达传说 旷野之息", aliases: ["BotW", "Zelda"],
                 releaseDate: Date(timeIntervalSince1970: 1_500_000_000),
                 developer: "Nintendo EPD", publisher: "Nintendo", genre: "开放世界 ARPG",
                 coverData: "fakecover".data(using: .utf8),
                 reviewTitle: "神作", reviewBody: "开放世界标杆")
let groupA = GameGroup(name: "塞尔达系列")
let groupB = GameGroup(name: "Switch 独占")
context.insert(game1); context.insert(groupA); context.insert(groupB)
game1.groups = [groupA, groupB]

let c1 = Completion(platform: "Switch", date: Date(timeIntervalSince1970: 1_600_000_000),
                    degree: "主线通关", playtime: 80, notes: "太棒了",
                    scoreGameplay: 10, scoreDesign: 9, scoreStory: 9, scoreArt: 8,
                    scoreMusic: 9, scorePerformance: 9)
c1.game = game1
context.insert(c1)
try? context.save()

check("game1.groups 双向（2 个）", game1.groups.count == 2)
check("groupA.games 含 game1", groupA.games.contains { $0.persistentModelID == game1.persistentModelID })
check("groupB.games 含 game1", groupB.games.contains { $0.persistentModelID == game1.persistentModelID })
check("c1.game 反向指向 game1", c1.game?.persistentModelID == game1.persistentModelID)
check("libraryScore 10+9+9+8+9+9 → 9.0", game1.libraryScore == 9.0)
check("recordAverage 9.0", c1.recordAverage == 9.0)

// --- 2. 追加一条跳过评分的记录：不计入库显示分 ---
let c2 = Completion(platform: "PC", date: Date(timeIntervalSince1970: 1_700_000_000),
                    degree: "全支线", playtime: 120, notes: "二周目")
c2.game = game1
context.insert(c2)
try? context.save()
check("跳过评分的记录 hasScores == false", c2.hasScores == false)
check("库显示分仍只看已评分记录（9.0）", game1.libraryScore == 9.0)
check("sortedCompletions 按 createdAt 升序（首条在前）", game1.sortedCompletions.first == c1)

// --- 3. 别名搜索 ---
check("别名 BotW 命中", game1.matches(search: "botw"))
check("名称模糊命中", game1.matches(search: "旷野"))
check("不命中", game1.matches(search: "不存在") == false)
check("空搜索恒真", game1.matches(search: "  ") == true)

// --- 4. 级联删除：删游戏 → 记录删、分组留 ---
let game1ID = game1.persistentModelID
context.delete(game1)
try? context.save()
let completionsAfterGameDelete = (try? context.fetch(FetchDescriptor<Completion>())) ?? []
let groupsAfterGameDelete = (try? context.fetch(FetchDescriptor<GameGroup>())) ?? []
check("删游戏后通关记录级联删除（0 条）", completionsAfterGameDelete.isEmpty)
check("删游戏后分组保留（2 个）", groupsAfterGameDelete.count == 2)
check("删游戏后分组内 games 空化", groupsAfterGameDelete.allSatisfy { $0.games.isEmpty })

// --- 5. 删分组不删游戏；零记录游戏 graceful ---
let game2 = Game(name: "零记录游戏", reviewTitle: "测试")
context.insert(game2)
game2.groups = [groupA]
let game3 = Game(name: "另一款", reviewTitle: "测试2")
context.insert(game3)
game3.groups = [groupA, groupB]
try? context.save()
let groupAID = groupA.persistentModelID
context.delete(groupA)
try? context.save()
check("删分组后游戏仍在（2 个）", (try? context.fetch(FetchDescriptor<Game>()))?.count == 2)
check("game2.groups 已不含 groupA", game2.groups.contains { $0.persistentModelID == groupAID } == false)
check("game3.groups 还剩 1 个", game3.groups.count == 1)
check("零记录游戏 libraryScore 为 nil", game2.libraryScore == nil)
check("零记录游戏 sortedCompletions 空", game2.sortedCompletions.isEmpty)
check("零记录游戏 latestCompletionDate 为 nil", game2.latestCompletionDate == nil)

// --- 6. 备份：全字段往返 ---
let exportGame = Game(name: "异度神剑3", aliases: ["XB3", "ゼノブレイド3"],
                      releaseDate: Date(timeIntervalSince1970: 1_650_000_000),
                      developer: "Monolith Soft", publisher: "Nintendo", genre: "JRPG",
                      coverData: "COVER_BASE64_MARKER".data(using: .utf8),
                      squareData: "SQUARE_BASE64_MARKER".data(using: .utf8),
                      logoSize: .large, logoVertical: .bottom, logoHorizontal: .center,
                      reviewTitle: "RPG 天花板", reviewBody: "系统深度惊人")
context.insert(exportGame)
let exportGroup = GameGroup(name: "JRPG")
exportGroup.review = "系列评价草稿"
context.insert(exportGroup)
exportGame.groups = [exportGroup]
let exportC = Completion(platform: "Switch", date: Date(timeIntervalSince1970: 1_660_000_000),
                         degree: "全收集/白金", playtime: 150.5, notes: "全图鉴",
                         scoreGameplay: 9.5, scoreDesign: 9, scoreStory: 9.5, scoreArt: 8.5,
                         scoreMusic: 9, scorePerformance: 9)
exportC.game = exportGame
context.insert(exportC)
try? context.save()
let originalDate = exportC.date
let originalRelease = exportGame.releaseDate!
let originalCreatedAt = exportGame.createdAt
let originalUpdatedAt = exportGame.updatedAt

// 先清掉当前上下文（模拟导入前已有数据），再走 decodeAndReplace
let stray = Game(name: "旧数据", reviewTitle: "应被替换")
context.insert(stray)
try? context.save()
let backupData = try BackupManager.encode(games: [exportGame], groups: [exportGroup])
check("备份 JSON 非空", !backupData.isEmpty)
try BackupManager.decodeAndReplace(backupData, into: context)
try context.save()

let importedGames = (try? context.fetch(FetchDescriptor<Game>())) ?? []
let importedGroups = (try? context.fetch(FetchDescriptor<GameGroup>())) ?? []
let importedCompletions = (try? context.fetch(FetchDescriptor<Completion>())) ?? []
check("导入替换：旧数据被清掉（仅 1 游戏）", importedGames.count == 1)
check("导入后分组 1 个", importedGroups.count == 1)
check("导入后记录 1 条", importedCompletions.count == 1)

let ig = importedGames[0]
check("名称往返", ig.name == "异度神剑3")
check("别名往返", ig.aliases == ["XB3", "ゼノブレイド3"])
check("发售日期保真", ig.releaseDate == originalRelease)
check("厂商/发行商/类型备份往返", ig.developer == "Monolith Soft" && ig.publisher == "Nintendo" && ig.genre == "JRPG")
check("Logo 三档备份往返", ig.logoSizeValue == .large && ig.logoVerticalValue == .bottom && ig.logoHorizontalValue == .center)
check("封面 base64 往返", ig.coverData == "COVER_BASE64_MARKER".data(using: .utf8))
check("1:1 封面 base64 往返", ig.squareData == "SQUARE_BASE64_MARKER".data(using: .utf8))
check("评价标题往返", ig.reviewTitle == "RPG 天花板")
check("评价正文往返", ig.reviewBody == "系统深度惊人")
check("分组映射往返", ig.groups.map(\.name) == ["JRPG"])
check("分组评价往返", ig.groups.first?.review == "系列评价草稿")

let ic = importedCompletions[0]
check("记录平台往返", ic.platform == "Switch")
check("记录日期保真", ic.date == originalDate)
check("记录通关程度往返", ic.degree == "全收集/白金")
check("记录时长往返（150.5）", ic.playtime == 150.5)
check("记录内容往返", ic.notes == "全图鉴")
check("六维评分往返", ic.scoreGameplay == 9.5 && ic.scoreDesign == 9 && ic.scoreStory == 9.5
    && ic.scoreArt == 8.5 && ic.scoreMusic == 9 && ic.scorePerformance == 9)
check("记录↔游戏关联恢复", ic.game?.persistentModelID == ig.persistentModelID)
check("库显示分往返 9.1（9.5+9+9.5+8.5+9+9→54.5/6→9.083→round 0.1→9.1）", ig.libraryScore == 9.1)
// §47⑦：createdAt/updatedAt 备份往返保真（2026-09-05 修码时漏补断言，2026-09-08 补）。
// ISO8601 编码秒级精度：亚秒截断属编码器既定行为，断言秒级一致（排序/显示语义所需精度）。
check("时间戳往返：createdAt 保真（秒级）", abs(ig.createdAt.timeIntervalSince(originalCreatedAt)) < 1)
check("时间戳往返：updatedAt 保真（秒级）", (ig.updatedAt ?? .distantPast).timeIntervalSince(originalUpdatedAt ?? .distantPast).magnitude < 1)

// --- 7. 重复导入幂等 ---
try BackupManager.decodeAndReplace(backupData, into: context)
try context.save()
check("重复导入不累积游戏", (try? context.fetch(FetchDescriptor<Game>()))?.count == 1)
check("重复导入不累积分组", (try? context.fetch(FetchDescriptor<GameGroup>()))?.count == 1)
check("重复导入不累积记录", (try? context.fetch(FetchDescriptor<Completion>()))?.count == 1)

// --- 8. 空库备份往返 ---
let emptyData = try BackupManager.encode(games: [], groups: [])
try BackupManager.decodeAndReplace(emptyData, into: context)
try context.save()
check("空备份导入后库为空", (try? context.fetch(FetchDescriptor<Game>()))?.isEmpty == true)

// --- 9. 预设展示本地化：canonical 存储 + 展示翻译 ---
check("degree 主线通关 → zh 主线通关", Presets.display("主线通关", category: .degree, language: "zh-Hans") == "主线通关")
check("degree 主线通关 → en Main Story", Presets.display("主线通关", category: .degree, language: "en") == "Main Story")
check("degree 主线通关 → ja メインクリア", Presets.display("主线通关", category: .degree, language: "ja") == "メインクリア")
check("degree 全收集/白金 → en 含 Platinum", Presets.display("全收集/白金", category: .degree, language: "en") == "All Collectibles / Platinum")
check("platform 手机 → en Mobile", Presets.display("手机", category: .platform, language: "en") == "Mobile")
check("platform 掌机 → ja 携帯機", Presets.display("掌机", category: .platform, language: "ja") == "携帯機")
check("platform 其他 → ja その他（同 degree 其他也翻译）", Presets.display("其他", category: .degree, language: "ja") == "その他")
check("中性预设 PC → en 原样 PC", Presets.display("PC", category: .platform, language: "en") == "PC")
check("旧名 Switch → ja Nintendo Switch（兜底映射）", Presets.display("Switch", category: .platform, language: "ja") == "Nintendo Switch")
check("新预设 Nintendo Switch → en 原样", Presets.display("Nintendo Switch", category: .platform, language: "en") == "Nintendo Switch")
check("旧名 Switch 2 → zh Nintendo Switch 2（兜底映射）", Presets.display("Switch 2", category: .platform, language: "zh-Hans") == "Nintendo Switch 2")
check("新预设 Nintendo Switch 2 → ja 原样", Presets.display("Nintendo Switch 2", category: .platform, language: "ja") == "Nintendo Switch 2")
check("自定义值 Retro → 任意语言原样", Presets.display("Retro", category: .platform, language: "ja") == "Retro")
check("自定义值 特殊二周目 → en 原样", Presets.display("特殊二周目", category: .degree, language: "en") == "特殊二周目")

// --- 10. 平台限定评分（整体排名按平台切换用） ---
let multi = Game(name: "多平台游戏", reviewTitle: "")
context.insert(multi)
let multiSwitch = Completion(platform: "Nintendo Switch", date: .now, degree: "通关",
                             scoreGameplay: 9, scoreDesign: 9, scoreStory: 9, scoreArt: 9, scoreMusic: 9, scorePerformance: 9)
multiSwitch.game = multi
context.insert(multiSwitch)
let multiPS5 = Completion(platform: "PS5", date: .now, degree: "通关",
                          scoreGameplay: 5, scoreDesign: 5, scoreStory: 5, scoreArt: 5, scoreMusic: 5, scorePerformance: 5)
multiPS5.game = multi
context.insert(multiPS5)
try? context.save()
check("全平台库显示分 7.0（9 与 5 均值）", multi.libraryScore(platform: nil) == 7.0)
check("Switch 平台库显示分 9.0", multi.libraryScore(platform: "Nintendo Switch") == 9.0)
check("PS5 平台玩法均值 5.0", multi.dimensionAverage(for: .gameplay, platform: "PS5") == 5.0)
check("Switch 平台玩法均值 9.0", multi.dimensionAverage(for: .gameplay, platform: "Nintendo Switch") == 9.0)
check("无该平台记录 → nil", multi.libraryScore(platform: "Xbox One") == nil)

// --- 11. 无日期/无时长记录（None） + 备份往返 ---
let noDateGame = Game(name: "长线运营游戏", reviewTitle: "t")
context.insert(noDateGame)
let noDateC = Completion(platform: "PC", date: nil, degree: "长线", playtime: nil)
noDateC.game = noDateGame
context.insert(noDateC)
try? context.save()
check("无日期记录 date 为 nil", noDateC.date == nil)
check("无日期记录 latestCompletionDate 为 nil", noDateGame.latestCompletionDate == nil)
let noDateBackup = try BackupManager.encode(games: [noDateGame], groups: [])
try BackupManager.decodeAndReplace(noDateBackup, into: context)
try context.save()
let noDateImported = (try? context.fetch(FetchDescriptor<Completion>()))?.first { $0.platform == "PC" }
check("无日期记录备份往返保持 nil", noDateImported?.date == nil)
check("无时长记录备份往返保持 nil", noDateImported?.playtime == nil)

// --- 12. 多语言名字 ---
let ml = Game(name: "The Legend of Zelda", nameZh: "塞尔达传说", nameJa: "ゼルダの伝説", reviewTitle: "")
context.insert(ml)
let mlPlain = Game(name: "Xenoblade", reviewTitle: "")
context.insert(mlPlain)
try? context.save()
check("中文模式显示中文名", ml.displayName(for: "zh-Hans") == "塞尔达传说")
check("日文模式显示日文名", ml.displayName(for: "ja") == "ゼルダの伝説")
check("英文模式显示英文名", ml.displayName(for: "en") == "The Legend of Zelda")
check("中文未设回退英文", mlPlain.displayName(for: "zh-Hans") == "Xenoblade")
check("搜中文名命中", ml.matches(search: "塞尔达"))
check("搜日文名命中", ml.matches(search: "ゼルダ"))

// --- 13. 持有记录（收藏家模式）备份往返 ---
let holdGame = Game(name: "Holding Test", reviewTitle: "")
let holdCopy = PhysicalCopy(version: "日版初版", count: 2, images: [Data([1, 2, 3]), Data([4, 5, 6])])
holdCopy.game = holdGame
context.insert(holdGame)
context.insert(holdCopy)
try? context.save()
check("持有：版本名", holdGame.copies.first?.version == "日版初版")
check("持有：数量", holdGame.copies.first?.count == 2)
check("持有：图片数", holdGame.copies.first?.images.count == 2)
check("持有：级联关系", holdCopy.game?.persistentModelID == holdGame.persistentModelID)

let holdBackup = try BackupManager.encode(games: [holdGame], groups: [])
try BackupManager.decodeAndReplace(holdBackup, into: context)
try context.save()
let holdImported = (try? context.fetch(FetchDescriptor<Game>()))?.first { $0.name == "Holding Test" }
check("持有：备份往返版本名", holdImported?.copies.first?.version == "日版初版")
check("持有：备份往返数量", holdImported?.copies.first?.count == 2)
check("持有：备份往返图片", holdImported?.copies.first?.images == [Data([1, 2, 3]), Data([4, 5, 6])])

// 持有：导入时照片数上限 6（防手工构造备份 JSON 塞 >6 张破坏「最多 6 张」不变量）
let bigGame = Game(name: "Big Photo Test", reviewTitle: "")
let bigCopy = PhysicalCopy(version: "限定版", count: 1, images: (0..<7).map { Data([UInt8($0)]) })
bigCopy.game = bigGame
context.insert(bigGame)
context.insert(bigCopy)
try? context.save()
let bigBackup = try BackupManager.encode(games: [bigGame], groups: [])
try BackupManager.decodeAndReplace(bigBackup, into: context)
try context.save()
let bigImported = (try? context.fetch(FetchDescriptor<Game>()))?.first { $0.name == "Big Photo Test" }
check("持有：导入照片上限 6 张", bigImported?.copies.first?.images.count == 6)

// --- 14. 状态机（想玩/在玩/搁置/弃坑/已通关） ---
check("状态机：默认状态已通关", Game(name: "x", reviewTitle: "").statusValue == .completed)
let backlogGame = Game(name: "想玩游戏", reviewTitle: "", status: .backlog)
context.insert(backlogGame)
try? context.save()
check("状态机：想玩状态存储", backlogGame.statusValue == .backlog)
check("状态机：想玩游戏无通关记录", backlogGame.sortedCompletions.isEmpty)
check("状态机：想玩游戏库显示分为 nil", backlogGame.libraryScore == nil)

// 状态备份往返
let statusBackup = try BackupManager.encode(games: [backlogGame], groups: [])
try BackupManager.decodeAndReplace(statusBackup, into: context)
try context.save()
let statusImported = (try? context.fetch(FetchDescriptor<Game>()))?.first { $0.name == "想玩游戏" }
check("状态机：想玩状态备份往返", statusImported?.statusValue == .backlog)

// 未通关游戏也有游戏级平台
let backlogWithPlatform = Game(name: "想玩带平台", platform: "Nintendo Switch", reviewTitle: "", status: .backlog)
context.insert(backlogWithPlatform)
try? context.save()
check("平台：想玩游戏 platformList 含游戏级平台", backlogWithPlatform.platformList == ["Nintendo Switch"])

// 已通关：游戏平台 + 记录平台合并去重（PS5 在预设顺序中排在 Nintendo Switch 前）
let multiP = Game(name: "多平台", platform: "PS5", reviewTitle: "")
context.insert(multiP)
let mpC = Completion(platform: "Nintendo Switch", date: nil, degree: "通关")
mpC.game = multiP
context.insert(mpC)
try? context.save()
check("平台：已通关合并游戏+记录平台", multiP.platformList == ["PS5", "Nintendo Switch"])

// 想玩 + 平台备份往返
let plBackup = try BackupManager.encode(games: [backlogWithPlatform], groups: [])
try BackupManager.decodeAndReplace(plBackup, into: context)
try context.save()
let plImported = (try? context.fetch(FetchDescriptor<Game>()))?.first { $0.name == "想玩带平台" }
check("平台：想玩平台备份往返", plImported?.platform == "Nintendo Switch")

// 长线游玩：对应已通关（挂记录、isCompletedOrLongRunning 为真）
let longGame = Game(name: "长线游戏", reviewTitle: "", status: .longRunning)
context.insert(longGame)
let longC = Completion(platform: "PC", date: nil, degree: "长线")
longC.game = longGame
context.insert(longC)
try? context.save()
check("状态机：长线游玩状态存储", longGame.statusValue == .longRunning)
check("状态机：长线游玩视为已通关类", longGame.isCompletedOrLongRunning)
check("状态机：想玩不是已通关类", Game(name: "t", reviewTitle: "", status: .backlog).isCompletedOrLongRunning == false)

// 旧备份缺 status 字段 → 导入默认已通关
let legacyJSON = """
{"version":1,"exportedAt":"2026-01-01T00:00:00Z","groups":[],"games":[{"name":"旧版游戏","aliases":[],"reviewTitle":"","reviewBody":"","groupNames":[],"completions":[]}]}
"""
let legacyData = legacyJSON.data(using: .utf8)!
try BackupManager.decodeAndReplace(legacyData, into: context)
try context.save()
let legacyImported = (try? context.fetch(FetchDescriptor<Game>()))?.first { $0.name == "旧版游戏" }
check("状态机：旧备份缺 status → 默认已通关", legacyImported?.statusValue == .completed)
// §47⑦：旧备份缺 createdAt/updatedAt → 回落非 nil（.now / createdAt），不崩不丢序。
check("时间戳：旧备份缺 createdAt → 回落 .now（非 nil）", legacyImported?.createdAt != nil)
check("时间戳：旧备份缺 updatedAt → 回落 createdAt（非 nil）", legacyImported?.updatedAt != nil)

// MARK: - 持有档案枚举 migrate（beta 2.2）

check("介质 migrate: physical → physicalStandard", CopyMedia.migrate("physical") == .physicalStandard)
check("介质 migrate: digital → digitalStandard", CopyMedia.migrate("digital") == .digitalStandard)
check("介质 migrate: code → physicalCode", CopyMedia.migrate("code") == .physicalCode)
check("介质 migrate: 新值原样", CopyMedia.migrate("digitalPremium") == .digitalPremium)
check("介质 migrate: 未知兜底 standard", CopyMedia.migrate("???") == .physicalStandard)
check("介质 isPhysical: 实体三类+digitalCode 真", CopyMedia.physicalStandard.isPhysical && CopyMedia.physicalSpecial.isPhysical && CopyMedia.physicalLimited.isPhysical && CopyMedia.physicalCode.isPhysical)
check("介质 isPhysical: 数字三类 假", !CopyMedia.digitalStandard.isPhysical && !CopyMedia.digitalPremium.isPhysical && !CopyMedia.digitalUpgrade.isPhysical)

check("来源 migrate: firstHand → officialChannelOverseas", CopyAcquisition.migrate("firstHand") == .officialChannelOverseas)
check("来源 migrate: secondHand → personalSecondHand", CopyAcquisition.migrate("secondHand") == .personalSecondHand)
check("来源 migrate: 新值原样", CopyAcquisition.migrate("digitalStore") == .digitalStore)
check("来源 migrate: 未知兜底 other", CopyAcquisition.migrate("???") == .other)

// 版本区分 / 品相 migrate 兜底
check("版本区分 migrate: 未知兜底 jp", CopyRegional.migrate("???") == .jp)
check("品相 migrate: 未知兜底 used", CopyCondition.migrate("???") == .used)

// hasCondition 随 media.isPhysical 联动
let physC = PhysicalCopy(version: "v", media: .physicalStandard)
let digiC = PhysicalCopy(version: "v", media: .digitalStandard)
check("hasCondition: 实体真 / 数字假", physC.hasCondition && !digiC.hasCondition)

// 三语价格严格隔离（不跨语言回退）
let pricedC = PhysicalCopy(version: "v", priceZh: 399, priceJa: nil, priceEn: 60)
check("价格: zh=399", pricedC.price(for: "zh-Hans") == 399)
check("价格: en=60", pricedC.price(for: "en") == 60)
check("价格: ja=nil（不回退 zh/en）", pricedC.price(for: "ja") == nil)

// 旧备份持有（physical/code/firstHand）导入后落对枚举（经 migrate，非 flatMap(rawValue)）
let legacyCopyJSON = """
{"version":1,"exportedAt":"2026-01-01T00:00:00Z","groups":[],
 "games":[{"name":"旧持有游戏","aliases":[],"reviewTitle":"","reviewBody":"","groupNames":[],
   "completions":[],
   "copies":[{"version":"首发版","count":2,"images":[],"mediaRaw":"physical","acquisitionRaw":"firstHand"}]}]}
"""
try BackupManager.decodeAndReplace(legacyCopyJSON.data(using: .utf8)!, into: context)
try context.save()
if let legacyCopyGame = (try? context.fetch(FetchDescriptor<Game>()))?.first(where: { $0.name == "旧持有游戏" }),
   let legacyCopy = legacyCopyGame.copies.first {
    check("旧持有导入: mediaRaw=physical → physicalStandard", legacyCopy.media == .physicalStandard)
    check("旧持有导入: acquisitionRaw=firstHand → officialChannelOverseas", legacyCopy.acquisition == .officialChannelOverseas)
    check("旧持有导入: hasCondition 实体为真", legacyCopy.hasCondition)
} else {
    check("旧持有导入: 解析到游戏与持有", false)
}

// 持有档案平台字段：写入 / 导出导入往返
let platGame = Game(name: "持有机平台", reviewTitle: "")
context.insert(platGame)
let platCopy = PhysicalCopy(version: "v", platform: "PS5")
platCopy.game = platGame
context.insert(platCopy)
try? context.save()
check("持有: 平台写入", platCopy.platform == "PS5")
let platJSON = try BackupManager.encode(games: [platGame], groups: [])
try BackupManager.decodeAndReplace(platJSON, into: context)
try context.save()
if let platImported = (try? context.fetch(FetchDescriptor<Game>()))?.first(where: { $0.name == "持有机平台" }),
   let platCopy2 = platImported.copies.first {
    check("持有: 平台备份往返", platCopy2.platform == "PS5")
} else {
    check("持有: 平台备份往返", false)
}

// MARK: - ArtworkKind 深模块（表驱动 + Game.artwork/setArtwork 接口）

do {
    let g = Game(name: "ArtworkKindProbe")
    // 每类图经 kind 接口写入 = 直连字段（同一存储）。
    for kind in ArtworkKind.allCases {
        let payload = Data("img-\(kind.rawValue)".utf8)
        g.setArtwork(kind, payload)
        check("ArtworkKind: setArtwork(\(kind.rawValue)) → artwork() 读回", g.artwork(kind) == payload)
    }
    // nil = 清空。
    g.setArtwork(.logo, nil)
    check("ArtworkKind: setArtwork(nil) 清空", g.artwork(.logo) == nil)
    // kind 表自检：key 约定与门控例外。
    check("ArtworkKind: labelKey 约定", ArtworkKind.square.labelKey == "game.square")
    check("ArtworkKind: searchTitleKey poster 沿用 cover.title",
          ArtworkKind.poster.searchTitleKey == "cover.title" && ArtworkKind.logo.searchTitleKey == "cover.titleLogo")
    check("ArtworkKind: noResultKey 约定",
          ArtworkKind.poster.noResultKey == "cover.noGrids" && ArtworkKind.square.noResultKey == "cover.noSquare")
    check("ArtworkKind: 封面唯一非门控", ArtworkKind.allCases.filter { !$0.isToggleGated } == [.poster])
    check("ArtworkKind: 分页集合正确", Set(ArtworkKind.allCases.filter(\.supportsPaging)) == [.poster, .square, .landscape])
    // 备份往返：五类图字段不因深化丢失。
    let probeJSON = try BackupManager.encode(games: [g], groups: [])
    try BackupManager.decodeAndReplace(probeJSON, into: context)
    try context.save()
    if let roundTrip = (try? context.fetch(FetchDescriptor<Game>()))?.first(where: { $0.name == "ArtworkKindProbe" }) {
        check("ArtworkKind: 五类图备份往返",
              roundTrip.artwork(.poster) == Data("img-poster".utf8)
                  && roundTrip.artwork(.square) == Data("img-square".utf8)
                  && roundTrip.artwork(.landscape) == Data("img-landscape".utf8)
                  && roundTrip.artwork(.hero) == Data("img-hero".utf8)
                  && roundTrip.artwork(.logo) == nil)
    } else {
        check("ArtworkKind: 五类图备份往返", false)
    }
}

// MARK: - 备份双路径一致性（手动导出 vs 自动备份流式输出）

do {
    let g1 = Game(name: "DualPathProbe", aliases: ["DPP"],
                  releaseDate: Date(timeIntervalSince1970: 1_600_000_000),
                  coverData: Data("dualpath-cover".utf8),
                  reviewTitle: "双路径", reviewBody: "一致性")
    g1.isFavorite = true
    let g1c = Completion(platform: "PS5", date: Date(timeIntervalSince1970: 1_700_000_000),
                         degree: "主线通关", playtime: 40, notes: "n",
                         scoreGameplay: 8, scoreDesign: 8, scoreStory: 7,
                         scoreArt: 8, scoreMusic: 7, scorePerformance: 9)
    g1c.game = g1
    context.insert(g1)
    context.insert(g1c)
    try? context.save()

    // 手动导出（BackupManager.encode）与自动备份（BackupWriter 流式写盘）经同一 GameDTO(from:)，
    // decode 后语义字段必须一致（逐字节比对不可行：prettyPrinted 差异是既定兼容口径）。
    let manualJSON = try BackupManager.encode(games: [g1], groups: [])
    let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("datasmoke-stream.json")
    let writer = BackupWriter(modelContainer: context.container)
    let bytes = try await writer.writeStreamingBackup(to: tmpURL, username: nil, avatarPNG: nil, iconPNG: nil)
    check("备份双路径: 流式写出非空", bytes > 0)

    let isoDecoder = JSONDecoder()
    isoDecoder.dateDecodingStrategy = .iso8601
    let manualDTO = try isoDecoder.decode(BackupDTO.self, from: manualJSON)
    let streamDTO = try isoDecoder.decode(BackupDTO.self, from: Data(contentsOf: tmpURL))
    // 流式备份写的是整个库（此前断言段残留的游戏在内），按名字取 probe。
    guard let m = manualDTO.games.first(where: { $0.name == "DualPathProbe" }),
          let s = streamDTO.games.first(where: { $0.name == "DualPathProbe" }) else {
        print("FAIL 备份双路径: probe 游戏未在输出中找到")
        failures += 1
        exit(1)
    }
    check("备份双路径: 名称/别名/日期一致", m.name == s.name && m.aliases == s.aliases && m.releaseDate == s.releaseDate)
    check("备份双路径: 封面 base64 一致", m.coverBase64 == s.coverBase64)
    check("备份双路径: isFavorite 一致", m.isFavorite == true && s.isFavorite == true)
    check("备份双路径: 记录字段一致", m.completions[0].platform == s.completions[0].platform
          && m.completions[0].scoreGameplay == s.completions[0].scoreGameplay
          && m.completions[0].date == s.completions[0].date)
    check("备份双路径: createdAt/updatedAt 一致", m.createdAt == s.createdAt && m.updatedAt == s.updatedAt)
    try? FileManager.default.removeItem(at: tmpURL)
}

// MARK: - LibraryStats（平台聚合 / 收藏汇总 / 瓦片）

do {
    var statGames: [Game] = []
    let played1 = Game(name: "StatsPlayed1", platform: "PS5", reviewTitle: "t")
    let c1 = Completion(platform: "PS5", date: Date(timeIntervalSince1970: 1_700_000_000),
                        degree: "主线通关", playtime: 10, notes: "",
                        scoreGameplay: 8, scoreDesign: 8, scoreStory: 8,
                        scoreArt: 8, scoreMusic: 8, scorePerformance: 8)
    c1.game = played1
    context.insert(played1); context.insert(c1)

    let backlogGame = Game(name: "StatsBacklog", platform: "Switch", reviewTitle: "t", status: .backlog)
    context.insert(backlogGame)
    let multiPlatform = Game(name: "StatsMulti", platform: "PC", reviewTitle: "t", status: .playing)
    context.insert(multiPlatform)

    statGames = [played1, backlogGame, multiPlatform]
    try? context.save()

    // 平台聚合：未通关游戏的游戏级平台也计入；游戏 × 平台各计 1。
    let counts = LibraryStats.platformCounts(statGames)
    check("LibraryStats: platformCounts 游戏级平台计入",
          counts["PS5"] == 1 && counts["Switch"] == 1 && counts["PC"] == 1)
    check("LibraryStats: platformsInUse 排序含全部平台",
          Set(LibraryStats.platformsInUse(statGames)) == ["PS5", "Switch", "PC"])

    // 平级裁决固化：同数量平台按名称升序。
    let tie = LibraryStats.platformDistribution(statGames)
    let names = tie.map(\.platform)
    let countsSeq = tie.map(\.count)
    var stableOK = true
    for i in 0..<(names.count - 1) where countsSeq[i] == countsSeq[i + 1] {
        if names[i] > names[i + 1] { stableOK = false }
    }
    check("LibraryStats: 平级裁决（数量相同 → 名称升序）", stableOK)

    // 收藏汇总：未填跳过（nil ≠ 0）、全未填 = nil。
    let copy1 = PhysicalCopy(version: "V1", count: 2)
    copy1.priceZh = 199.5
    copy1.game = played1
    context.insert(copy1)
    let copy2 = PhysicalCopy(version: "V2", count: 3)
    copy2.estValueJa = 1200
    copy2.game = played1
    context.insert(copy2)
    try? context.save()

    let totalsZh = LibraryStats.collectorTotals([copy1, copy2], language: "zh-Hans")
    check("LibraryStats: 版本数/总量", totalsZh.editionCount == 2 && totalsZh.totalQuantity == 5)
    check("LibraryStats: 花费 zh 只算已填（199.5）", totalsZh.totalSpent == 199.5)
    check("LibraryStats: 估值 zh 全未填 = nil（非 0）", totalsZh.totalEstimate == nil)
    let totalsJa = LibraryStats.collectorTotals([copy1, copy2], language: "ja")
    check("LibraryStats: 估值 ja 只算已填（1200）", totalsJa.totalEstimate == 1200)
    check("LibraryStats: 花费 ja 全未填 = nil", totalsJa.totalSpent == nil)

    // 瓦片。
    check("LibraryStats: backlogCount", LibraryStats.backlogCount(statGames) == 1)
    check("LibraryStats: averageScore 8×6 维 → 8.0", LibraryStats.averageScore(statGames) == 8.0)
    check("LibraryStats: averageScore 空库 nil", LibraryStats.averageScore([]) == nil)
}

// MARK: - LibraryQuery（过滤 + 稳定排序 + 平级裁决）

do {
    let name = "MQuery"
    let q1 = Game(name: "Zelda", reviewTitle: "t")   // 同名并列组
    let q2 = Game(name: "zelda", reviewTitle: "t")   // 大小写不同、并列
    let q3 = Game(name: "Mario", reviewTitle: "t")
    context.insert(q1); context.insert(q2); context.insert(q3)
    try? context.save()
    let pool = [q3, q2, q1]

    // 过滤：平台/搜索。
    let filtered = LibraryQuery.filter(games: pool, group: nil, platform: nil, status: nil, search: "zelda")
    check("LibraryQuery: 搜索过滤（大小写不敏感命中 2）", filtered.count == 2)

    // 按名排序：大小写不敏感 + 并列以 createdAt 裁决（同刻创建→稳定序不跳动）。
    let byName = LibraryQuery.sorted(pool, by: .name, language: "zh-Hans")
    check("LibraryQuery: 按名排序（Mario 在前）", byName.first?.name == "Mario")

    // 平级裁决：未评分按 scoreDescending 沉底、并列同名以 createdAt 破——两两断言确定性。
    let byScore = LibraryQuery.sorted(pool, by: .scoreDescending, language: "zh-Hans")
    check("LibraryQuery: 未评分沉底且顺序确定（连跑两次一致）",
          byScore.map(\.persistentModelID) == LibraryQuery.sorted(pool, by: .scoreDescending, language: "zh-Hans").map(\.persistentModelID))

    // 菜单顺序与 labelKey 表。
    check("LibraryQuery: menuOrder 最近编辑置顶", LibrarySort.menuOrder.first == .recentEdit)
    check("LibraryQuery: labelKey 表", LibrarySort.name.labelKey == "library.sortByName"
          && LibrarySort.valueDescending.labelKey == "library.sortByValueDesc")
}

// MARK: - 我的最爱（isFavorite 建模 + 备份往返）+ 主页横幅字段

do {
    let favGame = Game(name: "FavoriteProbe", reviewTitle: "t", isFavorite: true)
    context.insert(favGame)
    let plainGame = Game(name: "PlainProbe", reviewTitle: "t")
    context.insert(plainGame)
    try? context.save()
    check("favorites: init isFavorite=true 存储", favGame.isFavorite)
    check("favorites: 默认未收藏", !plainGame.isFavorite)

    let favBackup = try BackupManager.encode(games: [favGame, plainGame], groups: [])
    try BackupManager.decodeAndReplace(favBackup, into: context)
    try context.save()
    if let fi = (try? context.fetch(FetchDescriptor<Game>()))?.first(where: { $0.name == "FavoriteProbe" }),
       let pi = (try? context.fetch(FetchDescriptor<Game>()))?.first(where: { $0.name == "PlainProbe" }) {
        check("favorites: 备份往返 true 保真", fi.isFavorite)
        check("favorites: 备份往返 false 保真", !pi.isFavorite)
    } else {
        check("favorites: 备份往返解析到游戏", false)
    }

    // 旧备份缺 isFavorite → 导入未收藏。
    let legacyFavJSON = """
    {"version":1,"exportedAt":"2026-01-01T00:00:00Z","groups":[],"games":[{"name":"旧最爱游戏","aliases":[],"reviewTitle":"","reviewBody":"","groupNames":[],"completions":[]}]}
    """
    try BackupManager.decodeAndReplace(legacyFavJSON.data(using: .utf8)!, into: context)
    try context.save()
    let legacyFav = (try? context.fetch(FetchDescriptor<Game>()))?.first(where: { $0.name == "旧最爱游戏" })
    check("favorites: 旧备份缺 isFavorite → 未收藏", legacyFav?.isFavorite == false)

    // 主页横幅：截断规则 + 备份编码/解码往返（真实 UserDefaults，用完清掉）。
    check("banner: truncateBannerText 20 字上限",
          UserCustomization.truncateBannerText("一二三四五六七八九十一二三四五六七八九十一二") == "一二三四五六七八九十一二三四五六七八九十")
    UserCustomization.setBannerTitle("登录标题")
    UserCustomization.setBannerSubtitle("登录副标题")
    let bannerGame = Game(name: "BannerProbe", reviewTitle: "")
    context.insert(bannerGame)
    try? context.save()
    let bannerData = try BackupManager.encode(games: [bannerGame], groups: [])
    UserCustomization.setBannerTitle("待覆盖")
    UserCustomization.setBannerSubtitle("待覆盖")
    try BackupManager.decodeAndReplace(bannerData, into: context)
    try context.save()
    check("banner: 备份往返标题", UserDefaults.standard.string(forKey: UserCustomization.bannerTitleKey) == "登录标题")
    check("banner: 备份往返副标题", UserDefaults.standard.string(forKey: UserCustomization.bannerSubtitleKey) == "登录副标题")
    // 旧版备份缺横幅字段 → 保持现状不覆盖。
    let legacyBannerJSON = """
    {"version":1,"exportedAt":"2026-01-01T00:00:00Z","groups":[],"games":[]}
    """
    try BackupManager.decodeAndReplace(legacyBannerJSON.data(using: .utf8)!, into: context)
    try context.save()
    check("banner: 无字段备份不覆盖标题", UserDefaults.standard.string(forKey: UserCustomization.bannerTitleKey) == "登录标题")
    // 清理测试污染。
    UserCustomization.setBannerTitle("")
    UserCustomization.setBannerSubtitle("")
    check("banner: 空串移除 key", UserDefaults.standard.string(forKey: UserCustomization.bannerTitleKey) == nil)
}

print(failures == 0 ? "DATA SMOKE TEST PASSED" : "DATA SMOKE TEST FAILED: \(failures) failures")
exit(failures == 0 ? 0 : 1)
