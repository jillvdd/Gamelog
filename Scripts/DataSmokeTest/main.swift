// GameLog 数据层回归冒烟测试（可重复运行，编译进产物但不编进 app）。
// 覆盖：多对多双向、级联删除、删分组不删游戏、评分集成、零记录、别名搜索、
//       备份全字段往返、重复导入幂等、导入替换语义、日期保真。
//
// 编译运行（Xcode 工具链 + 宏插件路径，勿用 CLT swiftc）：
//   xcrun swiftc -o /tmp/gamelog_datasmoke \
//     Scripts/DataSmokeTest/main.swift \
//     GameLog/Models/Game.swift GameLog/Models/Completion.swift GameLog/Models/GameGroup.swift \
//     GameLog/Models/Presets.swift GameLog/Support/ScoreMath.swift GameLog/Support/ExportImport.swift \
//     GameLog/Support/UserCustomization.swift \
//     -plugin-path /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins
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
                      coverData: "COVER_BASE64_MARKER".data(using: .utf8),
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
check("封面 base64 往返", ig.coverData == "COVER_BASE64_MARKER".data(using: .utf8))
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

print(failures == 0 ? "DATA SMOKE TEST PASSED" : "DATA SMOKE TEST FAILED: \(failures) failures")
exit(failures == 0 ? 0 : 1)
