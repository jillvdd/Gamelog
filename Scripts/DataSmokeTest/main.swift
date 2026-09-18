// GameLog 数据层回归冒烟测试（可重复运行，编译进产物但不编进 app）。
// 覆盖：多对多双向、级联删除、删分组不删游戏、评分集成、零记录、别名搜索、
//       备份全字段往返、重复导入幂等、导入替换语义、日期保真、持有记录往返、
//       外部账号导入基础层（错误分类 / 表单编码 / 平台归一化 / HTTP 分层与重试）
//       与 Nintendo 层（登录 URL / 回调解析 / 语言归码 / Play Activity 合并解析 / 重试梯子，
//       全部用 URLProtocol 桩离线跑，不打真实网络）、PlayStation 层（duration / 时间戳 /
//       平台映射 / 200 带 error / 授权链 / 翻页护栏 / 身份解析）、奖杯层（奖杯平台映射 /
//       宽松解码 / 四条合并规则 / PSN 语言阶梯 / 奖杯端点翻页与 200 带 error /
//       按 npTitleId 精确对号：分批 · 去重 · 整批被拒逐条重试 · bestProgress）、Xbox 层
//      （响应外壳的数字/字符串两种 code / 平台映射：`devices` 折叠 + `mediaItemType` 事实两级 /
//       时长批量请求体 / 宽松的 LenientInt /
//       http→https 图片升级 / 身份解析与兜底名 / 少一档端点就报 playtimeUnavailable /
//       成就四项的组装规则 / 平台列表展开 / 成就卡入场判据 / 搜索来源事实清单 /
//       Gamerscore 完成度百分比（成就卡那只环）），
//       以及导入协调层（匹配引擎 / 幂等 upsert / 自动墓碑 / 手动绑定与合并 / 封面下载）。
//
// 编译运行（Xcode 工具链 + 宏插件路径，勿用 CLT swiftc；`-sdk` 必需，否则标准库加载失败）：
//   xcrun swiftc -sdk <Xcode-beta MacOSX.sdk> -o /tmp/gamelog_datasmoke \
//     Scripts/DataSmokeTest/main.swift \
//     GameLog/Models/Game.swift GameLog/Models/Completion.swift GameLog/Models/GameGroup.swift \
//     GameLog/Models/PhysicalCopy.swift GameLog/Models/Presets.swift GameLog/Models/Artwork.swift \
//     GameLog/Models/LinkedAccount.swift GameLog/Models/ExternalGameRecord.swift \
//     GameLog/Support/ExternalImport/ExternalAPIError.swift \
//     GameLog/Support/ExternalImport/ExternalHTTPClient.swift \
//     GameLog/Support/ExternalImport/ExternalGameRecordDTO.swift \
//     GameLog/Support/ExternalImport/TitleScript.swift \
//     GameLog/Support/ExternalImport/Nintendo/NintendoAPI.swift \
//     GameLog/Support/ExternalImport/Nintendo/NintendoAuthService.swift \
//     GameLog/Support/ExternalImport/Nintendo/NintendoPlayHistoryClient.swift \
//     GameLog/Support/ExternalImport/Nintendo/NintendoTitleId.swift \
//     GameLog/Support/ExternalImport/Nintendo/NintendoAccountService.swift \
//     GameLog/Support/ExternalImport/PlayStation/PSNAPI.swift \
//     GameLog/Support/ExternalImport/PlayStation/PSNAuthService.swift \
//     GameLog/Support/ExternalImport/PlayStation/PSNGameService.swift \
//     GameLog/Support/ExternalImport/PlayStation/PSNAccountService.swift \
//     GameLog/Support/ExternalImport/PlayStation/PSNTrophyService.swift \
//     GameLog/Support/ExternalImport/Xbox/XboxAPI.swift \
//     GameLog/Support/ExternalImport/Xbox/XboxAuthService.swift \
//     GameLog/Support/ExternalImport/Xbox/XboxAccountService.swift \
//     GameLog/Support/ExternalImport/Xbox/XboxGameService.swift \
//     GameLog/Support/ExternalImport/ExternalTimestamp.swift \
//     GameLog/Support/PlayActivity.swift \
//     GameLog/Support/Achievement.swift \
//     GameLog/Support/TrophyStyle.swift \
//     GameLog/Support/ExternalImport/GameLinker.swift \
//     GameLog/Support/ExternalImport/ArtworkFetcher.swift \
//     GameLog/Support/ExternalImport/ImportCoordinator.swift \
//     GameLog/Support/ExternalImport/GameMerger.swift \
//     GameLog/Support/ExternalImport/ExternalAccountBinder.swift \
//     GameLog/Support/ExternalImport/AccountCredentialStore.swift \
//     GameLog/Support/KeychainStore.swift \
//     GameLog/Support/ScoreMath.swift GameLog/Support/ExportImport.swift GameLog/Support/Game+Backup.swift \
//     GameLog/Support/BackupWriter.swift GameLog/Support/ImageDecodeCache.swift \
//     GameLog/Support/LibraryStats.swift GameLog/Support/LibraryQuery.swift \
//     GameLog/Support/UserCustomization.swift GameLog/Support/PlatformImage.swift \
//     GameLog/Support/EnumPickerRow.swift GameLog/Support/L10n.swift GameLog/Support/AppLanguage.swift \
//     -plugin-path <Xcode-beta 插件路径>
//   /tmp/gamelog_datasmoke
import AppKit
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
// 主名允许为空（2026-09-16：「必须有英文名」改成「必须有**一个**语言的名称」）。
// 同步下来的中日文标题只落语言槽，主名就是空的 —— 显示层必须能兜住，否则卡片一片空白。
let zhOnly = Game(name: "", nameZh: "異度神劍 終極版", reviewTitle: "")
context.insert(zhOnly)
check("主名为空 → 中文界面仍显示中文名", zhOnly.displayName(for: "zh-Hans") == "異度神劍 終極版")
check("主名为空 → **英文界面**也退到中文名，不显示空白", zhOnly.displayName(for: "en") == "異度神劍 終極版")
check("主名为空 → primaryName 解析出唯一那个名字", zhOnly.primaryName == "異度神劍 終極版")
check("allNames 不含空串（同名匹配不该拿到一个空名字）", zhOnly.allNames == ["異度神劍 終極版"])
check("主名为空也能被搜到", zhOnly.matches(search: "終極版"))
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

// MARK: - LibraryViewMode（双平台库视图模式：平台子集 + 未知值收敛）

do {
    // 每个原始值都能往返（枚举与 `@AppStorage` 存的是同一个字符串）。
    for mode in LibraryViewMode.allCases {
        check("LibraryViewMode: \(mode.rawValue) 往返", LibraryViewMode(rawValue: mode.rawValue) == mode)
    }

    // 本平台可用集合：macOS 有方形网格无宽卡，iOS 反之。**这一条是加 macOS 第三视图的
    // 全部安全保证** —— 两个 switch 都写了「本平台不支持的档位」的臂，只有 `resolved` 把它们挡住。
    #if os(macOS)
    check("LibraryViewMode: macOS 可选集合 = 网格/方形网格/列表",
          LibraryViewMode.available == [.grid, .squareGrid, .list])
    check("LibraryViewMode: macOS 上 wideCard 被收敛成网格",
          LibraryViewMode.resolved("wideCard") == .grid)
    check("LibraryViewMode: macOS 上 squareGrid 原样放行",
          LibraryViewMode.resolved("squareGrid") == .squareGrid)
    #else
    check("LibraryViewMode: iOS 可选集合 = 网格/宽卡/列表",
          LibraryViewMode.available == [.grid, .wideCard, .list])
    check("LibraryViewMode: iOS 上 squareGrid 被收敛成网格",
          LibraryViewMode.resolved("squareGrid") == .grid)
    check("LibraryViewMode: iOS 上 wideCard 原样放行",
          LibraryViewMode.resolved("wideCard") == .wideCard)
    #endif

    // 空串（新键还没写过 / 迁移还没跑）与垃圾值一律回退网格，不能崩也不能空白。
    check("LibraryViewMode: 空串回退网格", LibraryViewMode.resolved("") == .grid)
    check("LibraryViewMode: 未知值回退网格", LibraryViewMode.resolved("holodeck") == .grid)

    // labelKey 每个都要有（L10n 三语齐平由 L10n 检查兜底；这里防的是「新加的 case 忘了接线」）。
    check("LibraryViewMode: 每个 case 都有 labelKey",
          LibraryViewMode.allCases.allSatisfy { !$0.labelKey.isEmpty })
    check("LibraryViewMode: 方形网格的 labelKey 是 library.squareGridView",
          LibraryViewMode.squareGrid.labelKey == "library.squareGridView")
    check("LibraryViewMode: 每个 case 都有 systemImage",
          LibraryViewMode.allCases.allSatisfy { !$0.systemImage.isEmpty })
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

// --- 15. 外部账号导入基础层（错误分类 / 表单编码 / 平台归一化 / HTTP 分层与重试）---

/// URLProtocol 桩：让 HTTP 层的行为（状态码分类、重试次数、错误体判定）**离线**可验证。
/// 注入后 URLSession 的协议栈被整体替换 —— 任何漏出去的请求都会失败，
/// 于是「这些断言没打真实网络」是被机制保证的，不是靠自觉。
final class ExternalImportStub: URLProtocol {
    struct Stub {
        var status: Int
        var headers: [String: String] = [:]
        var body: Data = Data()
    }

    private static let stateLock = NSLock()
    private static var storedHandler: ((URLRequest) -> Stub)?
    private static var storedRequests: [URLRequest] = []

    /// 装桩并清零计数。
    static func install(_ handler: @escaping (URLRequest) -> Stub) {
        stateLock.lock(); defer { stateLock.unlock() }
        storedHandler = handler
        storedRequests = []
    }

    static func clear() {
        stateLock.lock(); defer { stateLock.unlock() }
        storedHandler = nil
        storedRequests = []
    }

    /// 已发出的请求（用来断言重试次数）。
    static var requests: [URLRequest] {
        stateLock.lock(); defer { stateLock.unlock() }
        return storedRequests
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.stateLock.lock()
        Self.storedRequests.append(request)
        let handler = Self.storedHandler
        Self.stateLock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let stub = handler(request)
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: stub.status,
                                             httpVersion: "HTTP/1.1",
                                             headerFields: stub.headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !stub.body.isEmpty { client?.urlProtocol(self, didLoad: stub.body) }
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// 形状故意与真实响应不符，用来验证解码错误**只带字段路径、不带字段值**。
private struct StrictShapeProbe: Decodable {
    let playHistories: [Int]
}

do {
    // ① 表单编码：这几个细节直接决定 OAuth 换不换得到 token。
    let encoded = String(decoding: ExternalHTTPClient.formEncode(["b": "x y", "a": "p+q",
                                                                 "c": "ab-c_d", "d": "a:b"]),
                         as: UTF8.self)
    check("formEncode: 键排序稳定", encoded.hasPrefix("a="))
    check("formEncode: 空格 → %20（不是 +）", encoded.contains("b=x%20y"))
    check("formEncode: + → %2B（否则服务端会解成空格）", encoded.contains("a=p%2Bq"))
    check("formEncode: base64url 的 - 与 _ 不编码", encoded.contains("c=ab-c_d"))
    check("formEncode: : → %3A（grant_type 值里就有冒号）", encoded.contains("d=a%3Ab"))

    // ② 平台归一化：两家 provider 共用；认不出来必须返回 nil 交给调用方兜底，不许猜。
    check("平台: 'Nintendo Switch' 原样",
          ExternalPlatformNormalizer.canonical(fromRaw: "Nintendo Switch") == "Nintendo Switch")
    check("平台: 大小写与分隔符无关",
          ExternalPlatformNormalizer.canonical(fromRaw: "nintendo-SWITCH") == "Nintendo Switch")
    check("平台: 'Switch 2' 不会被吞成 'Nintendo Switch'（包含匹配的顺序陷阱）",
          ExternalPlatformNormalizer.canonical(fromRaw: "Switch 2") == "Nintendo Switch 2")
    check("平台: 旧名 'Switch' → Nintendo Switch（兼容历史数据）",
          ExternalPlatformNormalizer.canonical(fromRaw: "Switch") == "Nintendo Switch")
    check("平台: 'ps5' → PS5", ExternalPlatformNormalizer.canonical(fromRaw: "ps5") == "PS5")
    check("平台: 'PlayStation 4' → PS4",
          ExternalPlatformNormalizer.canonical(fromRaw: "PlayStation 4") == "PS4")
    check("平台: 空 / 空白 / nil → nil",
          ExternalPlatformNormalizer.canonical(fromRaw: "   ") == nil
            && ExternalPlatformNormalizer.canonical(fromRaw: "") == nil
            && ExternalPlatformNormalizer.canonical(fromRaw: nil) == nil)
    check("平台: 认不出来 → nil（不硬塞「其他」，那是正经预设值）",
          ExternalPlatformNormalizer.canonical(fromRaw: "Dreamcast") == nil)
    check("平台: 兜底值生效",
          ExternalPlatformNormalizer.resolve(raw: "Dreamcast", fallback: "Nintendo Switch") == "Nintendo Switch")
    check("平台: 全部预设值都原样回到自己（归一化表无键冲突）",
          Presets.platforms.allSatisfy { ExternalPlatformNormalizer.canonical(fromRaw: $0) == $0 })

    // ③ 体验版判定：拉丁词必须整词匹配（子串匹配会把 Demon's Souls 判成体验版）。
    check("版本: 'Demon's Souls' 不是体验版", ExternalVersionType.classifyVersion(title: "Demon's Souls") == .full)
    check("版本: 'Demo' 是体验版", ExternalVersionType.classifyVersion(title: "Demo") == .demo)
    check("版本: 'Demo Version' 是体验版", ExternalVersionType.classifyVersion(title: "Demo Version") == .demo)
    check("版本: 'Trial Version' 是体验版", ExternalVersionType.classifyVersion(title: "Trial Version") == .demo)
    check("版本: 'Trials of Mana' 不是体验版", ExternalVersionType.classifyVersion(title: "Trials of Mana") == .full)
    check("版本: '体験版' 是体验版", ExternalVersionType.classifyVersion(title: "ゼルダの伝説 体験版") == .demo)
    check("版本: 'demo版'（拉丁词紧贴汉字）是体验版", ExternalVersionType.classifyVersion(title: "demo版") == .demo)
    check("版本: 空标题留 unknown（不猜）", ExternalVersionType.classifyVersion(title: "") == .unknown)

    // ④ DTO：负数当「没有这个数」，不让脏值落库。
    let negativeDTO = ExternalGameRecordDTO(titleId: "T", titleName: "X", platform: "PS5",
                                            playedSeconds: -5, playCount: -1)
    check("DTO: 负数时长/次数 → nil",
          negativeDTO.playedSeconds == nil && negativeDTO.playCount == nil)
    check("DTO: 0 时长保留（合法值，PSN 会给 0）",
          ExternalGameRecordDTO(titleId: "T", titleName: "X", platform: "PS5",
                                playedSeconds: 0).playedSeconds == 0)
    check("DTO: 版本类型默认由标题判定",
          ExternalGameRecordDTO(titleId: "T", titleName: "体験版", platform: "PS5").versionType == .demo)
    check("DTO: 显式版本类型优先于启发式",
          ExternalGameRecordDTO(titleId: "T", titleName: "体験版", platform: "PS5",
                                versionType: .full).versionType == .full)

    // ⑤ 错误 → 落库分类 / 是否可重试。
    check("错误: 断网 → network 且可重试",
          ExternalAPIError.network("offline").syncErrorKind == .network
            && ExternalAPIError.network("offline").isRetryable)
    check("错误: 凭证失效 → authExpired 且**不可**重试",
          ExternalAPIError.authExpired.syncErrorKind == .authExpired
            && !ExternalAPIError.authExpired.isRetryable)
    check("错误: 解析失败归入 apiChanged（与结构变化同因）",
          ExternalAPIError.decoding("x").syncErrorKind == .apiChanged)
    check("错误: 认不出的状态码归入 unknown（不硬塞已知桶）",
          ExternalAPIError.http(418).syncErrorKind == .unknown)
    check("错误: 展示 key 走分类 labelKey",
          ExternalAPIError.authExpired.messageKey == AccountSyncErrorKind.authExpired.labelKey)

    // ⑥ 安全不变量：错误里绝不出现响应体原文 / 凭证。
    let secret = "NPSSO-SECRET-VALUE-9f3a"
    let oauthBody = Data("{\"error\":\"invalid_grant\",\"error_description\":\"token=\(secret)\"}".utf8)
    let oauthError = ExternalAPIError.fromOAuthBody(oauthBody)
    check("OAuth 体: invalid_grant → authExpired", oauthError == .authExpired)
    let oauthDump = String(describing: oauthError)
        + (oauthError?.errorDescription ?? "") + (oauthError?.diagnosticDetail ?? "")
    check("OAuth 体: error_description 自由文本不进错误", !oauthDump.contains(secret))
    check("OAuth 体: 未知 error 码不猜分类（返回 nil 交回状态码判定）",
          ExternalAPIError.fromOAuthBody(Data("{\"error\":\"brand_new_code\"}".utf8)) == nil)
    check("OAuth 体: 非 JSON 不误判",
          ExternalAPIError.fromOAuthBody(Data("<html>502</html>".utf8)) == nil)

    let leakedValue = "LEAKED-FIELD-VALUE-77"
    var decodingError: ExternalAPIError?
    do {
        _ = try JSONDecoder().decode(StrictShapeProbe.self,
                                     from: Data("{\"playHistories\":\"\(leakedValue)\"}".utf8))
    } catch let error as DecodingError {
        decodingError = .decoding(ExternalAPIError.describe(error))
    } catch {
        // 非 DecodingError 说明测试数据写错了，交给下面的断言报出来。
    }
    check("解码错误: 带字段路径（便于定位接口变化）",
          decodingError?.diagnosticDetail?.contains("playHistories") == true)
    check("解码错误: 不泄漏字段值（不得用 context.debugDescription）",
          !(decodingError?.diagnosticDetail ?? "").contains(leakedValue))

    // ⑦ HTTP 层的分类与重试（离线桩；节流设为 0 免得测试白等）。
    let stubClient = ExternalHTTPClient(minimumRequestInterval: 0, timeout: 5,
                                        protocolClasses: [ExternalImportStub.self])
    let probeURL = URL(string: "https://external.invalid/probe")!

    func probe(_ body: @escaping () async throws -> Void) async -> ExternalAPIError? {
        do { try await body(); return nil } catch let error as ExternalAPIError { return error } catch { return nil }
    }

    ExternalImportStub.install { _ in .init(status: 401) }
    var caught = await probe { _ = try await stubClient.get(probeURL) }
    check("HTTP: 401 → authExpired", caught == .authExpired)
    check("HTTP: 401 不重试（凭证失效重发无意义）", ExternalImportStub.requests.count == 1)

    ExternalImportStub.install { _ in .init(status: 500) }
    caught = await probe { _ = try await stubClient.get(probeURL) }
    check("HTTP: 500 → server", caught == .server(500))
    check("HTTP: 5xx 至多重试一次（共发 2 次）", ExternalImportStub.requests.count == 2)

    ExternalImportStub.install { _ in .init(status: 500) }
    caught = await probe { _ = try await stubClient.postForm(probeURL, fields: ["a": "b"]) }
    check("HTTP: 500 → server（POST）", caught == .server(500))
    check("HTTP: POST 不自动重试（OAuth code 一次性，重发会把成功变成 invalid_grant）",
          ExternalImportStub.requests.count == 1)

    ExternalImportStub.install { _ in .init(status: 429, headers: ["Retry-After": "42"]) }
    caught = await probe { _ = try await stubClient.get(probeURL) }
    check("HTTP: 429 → rateLimited 且带上 Retry-After", caught == .rateLimited(retryAfter: 42))

    ExternalImportStub.install { _ in
        .init(status: 400, headers: ["Content-Type": "application/json"],
              body: Data("{\"error\":\"invalid_grant\"}".utf8))
    }
    caught = await probe { _ = try await stubClient.get(probeURL) }
    check("HTTP: 400 + invalid_grant → authExpired（任天堂把会话失效报成 400 而非 401）",
          caught == .authExpired)

    // 302 + acceptStatuses：不抛错且 Location 可读 —— 这是 PSN authorize 取 code 的通道。
    // ⚠️ 「是否真的没跟随重定向」**这里证明不了**：URLProtocol 桩不走 URLSession 的重定向协商。
    //    `NoRedirectDelegate` 要等真机跑一次 PSN authorize 才能验证，别把这条断言当成它的证据。
    ExternalImportStub.install { _ in
        .init(status: 302, headers: ["Location": "com.scee.psxandroid.scecompcall://auth?code=ABC"])
    }
    let redirectResponse = try? await stubClient.getRaw(probeURL, allowsRedirects: false,
                                                       acceptStatuses: [302])
    check("HTTP: 302 被 acceptStatuses 接受，且 Location 可读",
          redirectResponse?.location?.contains("code=ABC") == true)
    check("HTTP: 只发了一次（没有跟着 302 再请求）", ExternalImportStub.requests.count == 1)

    ExternalImportStub.clear()
}

// --- 16. Nintendo 层（登录 URL / 回调解析 / 语言与平台归一 / Play Activity 合并解析）---

/// 从桩记录的请求里读出 body。
///
/// ⚠️ URLSession 交给 `URLProtocol` 的请求体**通常在 `httpBodyStream` 而不是 `httpBody`**，
/// 只读 `httpBody` 会永远是 nil，于是「code 没进 URL」这类断言会假通过。两种都认。
func stubBody(of request: URLRequest) -> String? {
    if let body = request.httpBody { return String(decoding: body, as: UTF8.self) }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: buffer.count)
        if read <= 0 { break }
        data.append(contentsOf: buffer[0..<read])
    }
    return data.isEmpty ? nil : String(decoding: data, as: UTF8.self)
}

do {
    // ① 登录 URL。这几个参数名是**协议正确性**的命门 —— 写错会被直接拒，且报错形状
    //    与「接口变了」一样，排查成本极高，所以逐条钉死。
    let login = try NintendoAuthService.makeLoginRequest()
    let loginURL = login.url.absoluteString

    check("Nintendo: authorize 端点是 accounts.nintendo.com/connect/1.0.0/authorize",
          loginURL.hasPrefix(NintendoAPI.authorizeEndpoint + "?"))
    check("Nintendo: 用 session_token_code_challenge（不是通用的 code_challenge）",
          loginURL.contains("session_token_code_challenge="))
    check("Nintendo: 没有误写成通用的 code_challenge 参数",
          !loginURL.contains("&code_challenge=") && !loginURL.contains("?code_challenge="))
    check("Nintendo: challenge 方法为 S256",
          loginURL.contains("session_token_code_challenge_method=S256"))
    check("Nintendo: response_type=session_token_code",
          loginURL.contains("response_type=session_token_code"))
    check("Nintendo: client_id 与回调 scheme 同源（npf + clientId）",
          loginURL.contains("client_id=" + NintendoAPI.clientId)
          && NintendoAPI.callbackURLScheme == "npf" + NintendoAPI.clientId)
    check("Nintendo: redirect_uri 按 form 规则编码（:// 不放行）",
          loginURL.contains("redirect_uri=npf5c38e31cd085304b%3A%2F%2Fauth"))
    check("Nintendo: scope 里的 [] 被编码成 %5B%5D（原样发会被网关拒）",
          loginURL.contains("%5B%5D") && !loginURL.contains("user.links[].id"))
    check("Nintendo: PKCE verifier **不在** URL 里（它是换 token 才用的秘密）",
          !loginURL.contains(login.codeVerifier))
    check("Nintendo: verifier 长度符合 RFC 7636（43–128）",
          login.codeVerifier.count >= 43 && login.codeVerifier.count <= 128)
    check("Nintendo: state 能校验通过（回显一致）",
          NintendoAuthService.callbackMatches(NintendoCallback(code: "C", state: login.state),
                                              request: login))

    let login2 = try NintendoAuthService.makeLoginRequest()
    check("Nintendo: 每次登录的 state 与 verifier 都不同（防串线）",
          login.state != login2.state && login.codeVerifier != login2.codeVerifier)

    // ② 回调解析：code 在 **fragment** 里，不在 query。用户还会手工粘贴带 UI 文字的链接。
    let fragmentForm = "npf5c38e31cd085304b://auth#session_token_code=abc-123&state=xyz"
    check("Nintendo: 从 fragment 取到 code 与 state",
          NintendoAPI.parseCallback(fragmentForm)?.code == "abc-123"
          && NintendoAPI.parseCallback(fragmentForm)?.state == "xyz")
    check("Nintendo: query 形式的回调也能取到",
          NintendoAPI.parseCallback("npf5c38e31cd085304b://auth?session_token_code=abc-123")?.code == "abc-123")
    check("Nintendo: 带浏览器 UI 噪音/换行的粘贴文本仍能解析（fallback UX 必须真的能用）",
          NintendoAPI.parseCallback("""
          已在浏览器中打开
          npf5c38e31cd085304b://auth#session_token_code=abc-123&state=xyz
          """)?.code == "abc-123")
    check("Nintendo: 缺 code 的回调返回 nil（调用方据此提示「粘贴的链接不对」）",
          NintendoAPI.parseCallback("npf5c38e31cd085304b://auth#state=xyz") == nil)
    check("Nintendo: 空白串返回 nil", NintendoAPI.parseCallback("   ") == nil)
    check("Nintendo: state 缺失算「无法校验」而不是「串线」（截断的粘贴链接不该吓到用户）",
          NintendoAuthService.callbackMatches(NintendoCallback(code: "C", state: nil), request: login))
    check("Nintendo: state 不匹配才算串线",
          !NintendoAuthService.callbackMatches(NintendoCallback(code: "C", state: "other"),
                                              request: login))

    // ③ Gentry-Locale：中文/日文/英文三个 App 语言都要给出取值；拿不准一律退到实证过的 en-GB。
    check("Nintendo: zh-Hans → zh-CN",
          NintendoAuthService.gentryLocale(appLocaleCode: "zh-Hans") == "zh-CN")
    check("Nintendo: ja → ja-JP", NintendoAuthService.gentryLocale(appLocaleCode: "ja") == "ja-JP")
    check("Nintendo: en → en-US（美版，用户 2026-09-16 点名的偏好）",
          NintendoAuthService.gentryLocale(appLocaleCode: "en") == "en-US")
    check("Nintendo: App 的三种语言都有取值", AppLanguage.allCases.allSatisfy {
        !NintendoAuthService.gentryLocale(appLocaleCode: $0.localeCode).isEmpty
    })
    check("Nintendo: 兜底链 en-US → en-GB，链尾那个才是唯一被实证过的（猜错不该让功能不可用）",
          NintendoAuthService.fallbackLocales == ["en-US", "en-GB"]
          && NintendoAuthService.verifiedFallbackLocale == "en-GB"
          && NintendoAuthService.gentryLocale(appLocaleCode: "fr") == "en-US")

    // ④ Play Activity 解析：必须按 titleId 合并，且「字段缺失」与「就是 0」要分得开。
    let historyJSON = """
    {
      "playHistories": [
        {"titleId":"0100AAA","titleName":"斯普拉遁 3","platform":"Nintendo Switch",
         "imageUrl":"https://img.example/1.jpg",
         "firstPlayedAt":"2023-01-02T03:04:05Z","lastPlayedAt":"2024-05-06T07:08:09Z",
         "totalPlayedDays":12,"totalPlayedMinutes":120.5},
        {"titleId":"0100AAA","titleName":"斯普拉遁 3","deviceType":"Switch 2",
         "firstPlayedAt":"2024-01-01T00:00:00Z","lastPlayedAt":"2025-01-01T00:00:00Z",
         "totalPlayedMinutes":60},
        {"titleId":"0100BBB","titleName":"某游戏 体验版","deviceType":"Switch",
         "firstPlayedAt":"2024-02-02","lastPlayedAt":"2024-02-03"},
        {"titleId":"0005000010101D00","titleName":"MARIO KART 8","deviceType":"Wii U",
         "lastPlayedAt":"2022-01-01T00:00:00Z","totalPlayedMinutes":300},
        {"titleId":"9999ZZZ","titleName":"未知编号段的游戏","deviceType":"Wii U",
         "lastPlayedAt":"2021-01-01T00:00:00Z","totalPlayedMinutes":5},
        {"titleName":"没有 id 的孤儿条目","totalPlayedMinutes":5},
        {"titleId":"0100CCC","titleName":"   ","totalPlayedMinutes":5}
      ],
      "hiddenTitleList": [{"shape":"unknown"}],
      "lastUpdatedAt": "2025-01-01T00:00:00Z"
    }
    """
    // 未声明 `hiddenTitleList` 是刻意的：形状未知时猜一个具体类型会让**整个响应**解码失败。
    let history = try ExternalHTTPClient.decode(NintendoAPI.PlayHistoryResponse.self,
                                               from: Data(historyJSON.utf8))
    let records = NintendoPlayHistoryClient.records(from: history)

    check("Nintendo: 未声明的 hiddenTitleList 不会让整次解码失败", records.count == 4)
    let splatoon = records.first { $0.titleId == "0100AAA" }
    check("Nintendo: 同一 titleId 的两台机器合成一条", splatoon != nil)
    check("Nintendo: 时长累加（120.5 + 60 分钟 → 10830 秒）", splatoon?.playedSeconds == 10830)
    check("Nintendo: firstPlayedAt 取最早、lastPlayedAt 取最晚",
          splatoon?.firstPlayedAt == Date(timeIntervalSince1970: 1672628645)
          && splatoon?.lastPlayedAt == Date(timeIntervalSince1970: 1735689600))
    check("Nintendo: 平台按 titleId 前缀定（0100 → Nintendo Switch），不看在哪台机器上玩的",
          splatoon?.platform == "Nintendo Switch")
    check("Nintendo: 0005 前缀 → Wii U（同一套前缀规则，与 deviceType 无关）",
          records.first { $0.titleId == "0005000010101D00" }?.platform == "Wii U")
    check("Nintendo: 保留原始平台串以备核对", splatoon?.platformRaw == "Nintendo Switch")
    check("Nintendo: 图片取第一个非空", splatoon?.imageURLString == "https://img.example/1.jpg")
    check("Nintendo: 任天堂没有 concept / 游玩次数，落 nil 而不是编一个",
          splatoon?.conceptId == nil && splatoon?.playCount == nil)
    check("Nintendo: 缺 id 或名字为空白的条目被丢弃（半条记录进库只会变成孤儿）",
          records.contains { $0.titleId == "0100CCC" } == false)
    check("Nintendo: 最近玩过的排前面",
          records.first?.titleId == "0100AAA" && records.last?.titleId == "9999ZZZ")

    let demoRecord = records.first { $0.titleId == "0100BBB" }
    check("Nintendo: 标题带「体验版」→ demo（默认不自动建库）",
          demoRecord?.versionType == .demo)
    check("Nintendo: **没给时长**落 nil，不伪装成「玩过 0 秒」", demoRecord?.playedSeconds == nil)
    check("Nintendo: 前缀认不出来（9999…）才退回来源给的机型（Wii U）",
          records.first { $0.titleId == "9999ZZZ" }?.platform == "Wii U")

    // ⑤ 时间戳容错：解析不出是**正常情况**，不能让它变成一次同步失败。
    check("Nintendo: RFC3339 带毫秒可解",
          NintendoAPI.parseTimestamp("2024-01-02T03:04:05.678Z") != nil)
    check("Nintendo: 不带时区按 UTC 解（与一手源 Go 的语义一致，不随设备时区漂）",
          NintendoAPI.parseTimestamp("2024-01-02T03:04:05")
              .map { Int($0.timeIntervalSince1970) } == 1704164645)
    check("Nintendo: 纯日期可解",
          NintendoAPI.parseTimestamp("2024-01-02").map { Int($0.timeIntervalSince1970) } == 1704153600)
    check("Nintendo: 解析不出返回 nil（nil 与空串都不炸）",
          NintendoAPI.parseTimestamp("昨天") == nil && NintendoAPI.parseTimestamp(nil) == nil)

    // ⑥ id_token：**不验签**，只用于本机身份标识与展示。
    let fakeJWT = "x." + Data(#"{"sub":"abcdef123456","nickname":"玩家"}"#.utf8)
        .base64URLEncodedString() + ".sig"
    check("Nintendo: 从 id_token 的 payload 读出 sub",
          NintendoAPI.idTokenClaims(fakeJWT)?["sub"] as? String == "abcdef123456")
    check("Nintendo: 不是 JWT 的串返回 nil（不会崩）",
          NintendoAPI.idTokenClaims("not-a-jwt") == nil)
    check("Nintendo: 无昵称时的兜底展示名带账号 ID 后四位（多账号并存要能分清）",
          NintendoAccountService.fallbackDisplayName(externalAccountId: "abcdef123456").hasSuffix("3456"))

    // ⑦ 用桩把「换取链路」和「4 组合重试梯子」也离线跑一遍 —— 一条真网络都不打。
    let nintendoHTTP = ExternalHTTPClient(
        defaultHeaders: ["User-Agent": NintendoAPI.userAgent, "Accept": "application/json"],
        protocolClasses: [ExternalImportStub.self])
    let tokenOK = ExternalImportStub.Stub(
        status: 200, body: Data(#"{"access_token":"AT","id_token":"IDT","expires_in":900}"#.utf8))

    func nintendoError(_ body: @escaping () async throws -> Void) async -> ExternalAPIError? {
        do { try await body(); return nil } catch let error as ExternalAPIError { return error } catch { return nil }
    }
    func isAPIChanged(_ error: ExternalAPIError?) -> Bool {
        if case .apiChanged = error { return true }
        return false
    }

    // (a) session_token 端点：POST form，code 与 verifier 在 body 里、**不进 URL**。
    ExternalImportStub.install { _ in .init(status: 200, body: Data(#"{"session_token":"ST"}"#.utf8)) }
    let exchangeAuth = NintendoAuthService(http: nintendoHTTP, sessionTokenProvider: { "ST" })
    let exchanged = try? await exchangeAuth.exchangeSessionTokenCode("CODE-1", codeVerifier: "VER-1")
    let sessionRequest = ExternalImportStub.requests.first
    check("Nintendo: code 换到 session_token", exchanged == "ST")
    check("Nintendo: session_token 端点走 POST form",
          sessionRequest?.httpMethod == "POST"
          && sessionRequest?.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
    check("Nintendo: code 与 verifier 在请求体里",
          (sessionRequest.flatMap(stubBody) ?? "").contains("session_token_code=CODE-1")
          && (sessionRequest.flatMap(stubBody) ?? "").contains("session_token_code_verifier=VER-1"))
    check("Nintendo: code 与 verifier **不在 URL 里**（URL 会进系统网络日志）",
          !(sessionRequest?.url?.absoluteString ?? "").contains("CODE-1")
          && !(sessionRequest?.url?.absoluteString ?? "").contains("VER-1"))
    check("Nintendo: 每个请求都带 User-Agent（网关无 UA 一律拒绝）",
          sessionRequest?.value(forHTTPHeaderField: "User-Agent") == NintendoAPI.userAgent)

    // (b) 响应里没有 session_token → apiChanged，而不是把一个半残账号绑进去。
    ExternalImportStub.install { _ in .init(status: 200, body: Data("{}".utf8)) }
    let emptyExchangeAuth = NintendoAuthService(http: nintendoHTTP, sessionTokenProvider: { "ST" })
    check("Nintendo: 换不到 session_token → apiChanged",
          isAPIChanged(await nintendoError {
              _ = try await emptyExchangeAuth.exchangeSessionTokenCode("C", codeVerifier: "V")
          }))

    // (c) access token 派生：JSON body（与 session_token 端点的 form 形状不同），且要缓存。
    ExternalImportStub.install { _ in tokenOK }
    let tokenAuth = NintendoAuthService(http: nintendoHTTP, sessionTokenProvider: { "ST" })
    let credentials = try? await tokenAuth.validCredentials()
    let requestsAfterFirstDerive = ExternalImportStub.requests.count
    let cached = try? await tokenAuth.validCredentials()
    let tokenRequest = ExternalImportStub.requests.first
    check("Nintendo: 派生出 access / id token",
          credentials?.accessToken == "AT" && credentials?.idToken == "IDT")
    check("Nintendo: 15 分钟内复用缓存（不缓存的话每次同步都多发一个请求）",
          ExternalImportStub.requests.count == requestsAfterFirstDerive && cached?.accessToken == "AT")
    check("Nintendo: token 端点请求体是 JSON（两个端点形状不同，别想当然统一）",
          (tokenRequest?.value(forHTTPHeaderField: "Content-Type") ?? "").hasPrefix("application/json"))
    check("Nintendo: grant_type 用 jwt-bearer-session-token",
          (tokenRequest.flatMap(stubBody) ?? "").contains("jwt-bearer-session-token"))
    check("Nintendo: session_token **不在 URL 里**",
          !(tokenRequest?.url?.absoluteString ?? "").contains("ST"))

    let noSessionAuth = NintendoAuthService(http: nintendoHTTP, sessionTokenProvider: { nil })
    check("Nintendo: 没有 session token → authExpired（提示重新登录）",
          await nintendoError { _ = try await noSessionAuth.validCredentials() } == .authExpired)

    // (d) Play Activity 的重试梯子 —— 每个组合都对应一个**具体**的已知失败模式。
    //     桩按 URL 分流：/api/token 正常，play_histories 第一次 400。
    func nintendoStub(playHistories: @escaping () -> ExternalImportStub.Stub)
        -> (URLRequest) -> ExternalImportStub.Stub {
        { request in
            (request.url?.path ?? "").contains("play_histories")
                ? playHistories()
                : .init(status: 200, body: Data(#"{"access_token":"AT","id_token":"IDT","expires_in":900}"#.utf8))
        }
    }
    func playHistoryRequests() -> [URLRequest] {
        ExternalImportStub.requests.filter { ($0.url?.path ?? "").contains("play_histories") }
    }

    // 400 是「Gentry-Locale 猜错」或「网关只认 id_token」的样子 → 换 en-GB 重试一次即可。
    ExternalImportStub.install(nintendoStub {
        playHistoryRequests().count <= 1
            ? .init(status: 400)
            : .init(status: 200, body: Data(historyJSON.utf8))
    })
    let ladderAuth = NintendoAuthService(http: nintendoHTTP, sessionTokenProvider: { "ST" })
    let client = NintendoPlayHistoryClient(auth: ladderAuth, locale: "ja-JP", http: nintendoHTTP)
    let fetched = try? await client.fetchRecords()
    check("Nintendo: 本账号语言被拒后换英文成功（猜错语言的代价不该是整个功能不可用）",
          fetched?.records.count == 4)
    check("Nintendo: 语言回退必须能被界面看见（请求 ja-JP、实际用 en-US）",
          fetched?.requestedLocale == "ja-JP" && fetched?.usedLocale == "en-US"
          && fetched?.didFallBackLocale == true)
    check("Nintendo: 首次用绑定账号时写定的语言",
          playHistoryRequests().first?.value(forHTTPHeaderField: NintendoAPI.localeHeader) == "ja-JP")
    check("Nintendo: 语言候选按链序试（本次要的 → en-US → en-GB）",
          playHistoryRequests().map { $0.value(forHTTPHeaderField: NintendoAPI.localeHeader) }
          == ["ja-JP", "en-US"])
    check("Nintendo: 只试了 2 个组合就成功（不做无谓的组合爆炸）",
          playHistoryRequests().count == 2)
    check("Nintendo: play history 请求带 Authorization: Bearer",
          playHistoryRequests().allSatisfy {
              ($0.value(forHTTPHeaderField: "Authorization") ?? "").hasPrefix("Bearer ")
          })

    // en-US 也被拒（它是推定值）→ 落到链尾那个被实证过的 en-GB。兜底链的用处就在这里。
    ExternalImportStub.install(nintendoStub {
        playHistoryRequests().count <= 2
            ? .init(status: 400)
            : .init(status: 200, body: Data(historyJSON.utf8))
    })
    let chainAuth = NintendoAuthService(http: nintendoHTTP, sessionTokenProvider: { "ST" })
    let chained = try? await NintendoPlayHistoryClient(auth: chainAuth, locale: "ja-JP",
                                                       http: nintendoHTTP).fetchRecords()
    check("Nintendo: en-US 也被拒时落到链尾的 en-GB（英文偏好不该拿可用性去换）",
          chained?.usedLocale == "en-GB" && chained?.didFallBackLocale == true
          && playHistoryRequests().map { $0.value(forHTTPHeaderField: NintendoAPI.localeHeader) }
             == ["ja-JP", "en-US", "en-GB"])

    // 全 400：候选链（ja-JP/en-US/en-GB）× 2 种 bearer 的组合都要试到，最后抛可分类的错误。
    ExternalImportStub.install(nintendoStub { .init(status: 400) })
    let ladderAuth2 = NintendoAuthService(http: nintendoHTTP, sessionTokenProvider: { "ST" })
    let client2 = NintendoPlayHistoryClient(auth: ladderAuth2, locale: "ja-JP", http: nintendoHTTP)
    let ladderError = await nintendoError { _ = try await client2.fetchRecords() }
    check("Nintendo: 全 400 时把 3 个取值 × 2 种 bearer 都试过",
          playHistoryRequests().count == 6)
    check("Nintendo: 整条语言链试完才换 id_token（一手源实测网关有时只认它）",
          playHistoryRequests()[3].value(forHTTPHeaderField: "Authorization") == "Bearer IDT"
          && playHistoryRequests().prefix(3).allSatisfy {
              $0.value(forHTTPHeaderField: "Authorization") == "Bearer AT"
          })
    check("Nintendo: 全失败时保留可分类的错误（.http(400)），不吞成 unknown",
          ladderError == .http(400))

    // 5xx：换 bearer 或语言都不会变好，不该把组合全试一遍 —— 只走 HTTP 层那一次重试。
    ExternalImportStub.install(nintendoStub { .init(status: 500) })
    let ladderAuth3 = NintendoAuthService(http: nintendoHTTP, sessionTokenProvider: { "ST" })
    let client3 = NintendoPlayHistoryClient(auth: ladderAuth3, locale: "ja-JP", http: nintendoHTTP)
    check("Nintendo: 5xx 不换组合，只走 HTTP 层的一次重试（共 2 次）",
          await nintendoError { _ = try await client3.fetchRecords() } == .server(500)
          && playHistoryRequests().count == 2)

    // (e) 标题覆盖率：接口**逐条**回落，请求成功 ≠ 拿回目标语言。
    //
    //     真账号实测（2026-09-16，151 条，Gentry-Locale: zh-TW，请求没被拒）：只有 62 条
    //     真是繁體中文，76 条回落英文、13 条回落日文，而响应里没有任何字段说明回落发生了。
    //     第二遍的全部意义就是「换成同语言的另一个区域写法，逐条把名字补回来」——
    //     只补名字，数据仍以主值那份为权威。
    // imageUrl 与名字成对：任天堂的图标**按语言发**（实测：日文名的游戏给的就是日文版商品图），
    // 所以换名字必须连图一起换 —— 否则就复现了「标题繁體中文、封面英文」那个反馈。
    func localeHistoryJSON(_ titles: [(id: String, name: String, minutes: Int, image: String)]) -> String {
        let items = titles.map {
            #"{"titleId":"\#($0.id)","titleName":"\#($0.name)","totalPlayedMinutes":\#($0.minutes),"imageUrl":"\#($0.image)"}"#
        }
        return #"{"playHistories":[\#(items.joined(separator: ","))]}"#
    }
    let twBody = localeHistoryJSON([
        ("0100AAA", "異度神劍 終極版", 10, "https://img.example/tw-a.png"),   // zh-TW 这条真给了中文
        ("0100BBB", "Mario Kart 8 Deluxe", 20, "https://img.example/en-b.png"),  // 回落成英文
        ("0100CCC", "スプラトゥーン3", 30, "https://img.example/ja-c.png"),   // 回落成日文
    ])
    let hkBody = localeHistoryJSON([
        ("0100AAA", "異度神劍 終極版", 999, "https://img.example/hk-a.png"),  // 候选里连时长都不一样
        ("0100BBB", "瑪利歐賽車 8 豪華版", 999, "https://img.example/hk-b.png"),
        ("0100CCC", "斯普拉遁 3", 999, "https://img.example/hk-c.png"),
        ("0100ZZZ", "候选多出来的条目", 5, "https://img.example/hk-z.png"),   // 主值没有它 → 不许新增
    ])
    ExternalImportStub.install(nintendoStub {
        playHistoryRequests().last?.value(forHTTPHeaderField: NintendoAPI.localeHeader) == "zh-HK"
            ? .init(status: 200, body: Data(hkBody.utf8))
            : .init(status: 200, body: Data(twBody.utf8))
    })
    let zhAuth = NintendoAuthService(http: nintendoHTTP, sessionTokenProvider: { "ST" })
    let zhFetched = try? await NintendoPlayHistoryClient(auth: zhAuth, locale: "zh-TW",
                                                         http: nintendoHTTP).fetchRecords()
    func zhRecord(_ titleId: String) -> ExternalGameRecordDTO? {
        zhFetched?.records.first { $0.titleId == titleId }
    }
    check("Nintendo: 主取舍没吃满目标语言时，会用同语言的另一个区域写法逐条把标题补回来",
          zhRecord("0100BBB")?.titleName == "瑪利歐賽車 8 豪華版"
          && zhRecord("0100CCC")?.titleName == "斯普拉遁 3")
    check("Nintendo: 已经拿到的中文名不会被候选的回落结果冲掉",
          zhRecord("0100AAA")?.titleName == "異度神劍 終極版")
    check("Nintendo: 名字换了，配图必须跟着换（否则就是「标题中文、封面英文」）",
          zhRecord("0100BBB")?.imageURLString == "https://img.example/hk-b.png"
          && zhRecord("0100CCC")?.imageURLString == "https://img.example/hk-c.png"
          && zhRecord("0100AAA")?.imageURLString == "https://img.example/tw-a.png")
    check("Nintendo: 候选只补标题名与配图 —— 时长仍是主取舍那份，多出来的 titleId 不新增",
          zhRecord("0100AAA")?.playedSeconds == 600
          && zhRecord("0100BBB")?.playedSeconds == 1_200
          && zhFetched?.records.count == 3)
    check("Nintendo: 两遍用同一个 bearer（候选不重走整条 (bearer, locale) 梯子）",
          playHistoryRequests().count == 2
          && playHistoryRequests().allSatisfy {
              $0.value(forHTTPHeaderField: "Authorization") == "Bearer AT"
          })
    check("Nintendo: usedLocale 仍是主取舍（数据是那一份，只有个别标题名来自候选）",
          zhFetched?.usedLocale == "zh-TW" && zhFetched?.didFallBackLocale == false)

    // 已经吃满 → 一次多余请求都不发（全中文时不该多花一遍流量）。
    ExternalImportStub.install(nintendoStub {
        .init(status: 200, body: Data(localeHistoryJSON([("0100AAA", "斯普拉遁 3", 10, "https://img.example/zh.png")]).utf8))
    })
    _ = try? await NintendoPlayHistoryClient(auth: zhAuth, locale: "zh-TW",
                                            http: nintendoHTTP).fetchRecords()
    check("Nintendo: 主取舍已经把目标语言吃满时根本不发候选请求",
          playHistoryRequests().count == 1)

    // 整个取值被服务端拒掉（400 → 梯子退到 en-GB）：孪生写法只会被同样拒掉，不发。
    ExternalImportStub.install(nintendoStub {
        playHistoryRequests().last?.value(forHTTPHeaderField: NintendoAPI.localeHeader) == "en-GB"
            ? .init(status: 200,
                    body: Data(localeHistoryJSON([("0100BBB", "Mario Kart 8 Deluxe", 20, "https://img.example/en.png")]).utf8))
            : .init(status: 400)
    })
    let zhFallback = try? await NintendoPlayHistoryClient(auth: zhAuth, locale: "zh-TW",
                                                          http: nintendoHTTP).fetchRecords()
    check("Nintendo: 语言取值被整体拒掉时沿链退到 en-GB，且不试孪生写法（它只会被同样拒掉）",
          zhFallback?.usedLocale == "en-GB" && zhFallback?.didFallBackLocale == true
          && playHistoryRequests().map { $0.value(forHTTPHeaderField: NintendoAPI.localeHeader) }
             == ["zh-TW", "en-US", "en-GB"]
          && !playHistoryRequests().contains {
              $0.value(forHTTPHeaderField: NintendoAPI.localeHeader) == "zh-HK"
          })

    ExternalImportStub.clear()
}

// --- 17. PlayStation 层（时长/时间戳解析 / code 提取 / 平台映射 / 换取链路 / 翻页）---

/// 线程安全的字符串收集盒（桩的闭包在别的线程上跑，普通 `var` 捕获会有数据竞争）。
final class StringBox: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    func append(_ value: String) { lock.lock(); values.append(value); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return values }
}

do {
    // ① ISO-8601 duration。**小时可超 24，这是不能用 DateComponentsFormatter 的原因。**
    check("PSN: PT228H56M33S → 824193 秒", PSNAPI.parseDurationSeconds("PT228H56M33S") == 824_193)
    check("PSN: 超过 24 小时不被折成天（PT25H → 90000 秒，不是 1 天 1 小时）",
          PSNAPI.parseDurationSeconds("PT25H") == 90_000)
    check("PSN: PT0S → 0（0 是合法值，不能与「没有数据」混为一谈）",
          PSNAPI.parseDurationSeconds("PT0S") == 0)
    check("PSN: PT1H / PT30M / P1DT2H 都认",
          PSNAPI.parseDurationSeconds("PT1H") == 3_600
          && PSNAPI.parseDurationSeconds("PT30M") == 1_800
          && PSNAPI.parseDurationSeconds("P1DT2H") == 93_600)
    check("PSN: 小数秒（点号与逗号两种写法）",
          PSNAPI.parseDurationSeconds("PT1.5S") == 2
          && PSNAPI.parseDurationSeconds("PT1,5S") == 2)
    check("PSN: 缺 P 前缀 → nil", PSNAPI.parseDurationSeconds("228H56M33S") == nil)
    check("PSN: 年/月不做等效换算，认不出来就别猜",
          PSNAPI.parseDurationSeconds("P1Y") == nil && PSNAPI.parseDurationSeconds("P1M") == nil)
    check("PSN: 空串 / nil / 只有 T → nil",
          PSNAPI.parseDurationSeconds("") == nil
          && PSNAPI.parseDurationSeconds(nil) == nil
          && PSNAPI.parseDurationSeconds("PT") == nil)

    // ② 时间戳：实测有 `.12Z` 这种**两位**小数秒，而 ISO8601DateFormatter 只吃固定位数。
    let twoDigit = PSNAPI.parseTimestamp("2024-08-03T19:28:27.12Z")
    let noFraction = PSNAPI.parseTimestamp("2024-08-03T19:28:27Z")
    check("PSN: 两位小数秒能解出来（且与整秒几乎同时刻）",
          twoDigit != nil && noFraction != nil
          && abs(twoDigit!.timeIntervalSince(noFraction!)) < 1)
    check("PSN: 三位小数秒能解出来",
          PSNAPI.parseTimestamp("2024-08-03T19:28:27.123Z") != nil)
    check("PSN: 普通 RFC3339 能解出来",
          PSNAPI.parseTimestamp("2015-07-10T19:40:19Z") != nil)
    check("PSN: 解析不出返回 nil（时间缺失是正常情况，不该让整次同步失败）",
          PSNAPI.parseTimestamp("昨天") == nil && PSNAPI.parseTimestamp(nil) == nil
          && PSNAPI.parseTimestamp("") == nil)

    // ③ 从 302 的 Location 里取 code。
    check("PSN: 从 redirect 的 query 里取到 code",
          PSNAPI.code(fromRedirect: "com.scee.psxandroid.scecompcall://redirect/?code=v3.ABC&cid=x")
              == "v3.ABC")
    check("PSN: code 在 fragment 里也认",
          PSNAPI.code(fromRedirect: "com.scee.psxandroid.scecompcall://redirect#code=v3.ABC")
              == "v3.ABC")
    check("PSN: 百分号编码的 code 会被解码",
          PSNAPI.code(fromRedirect: "https://example.invalid/redirect?code=v3.A%2BB") == "v3.A+B")
    check("PSN: 没有 code 返回 nil（调用方据此提示「NPSSO 无效或已过期」）",
          PSNAPI.code(fromRedirect: "com.scee.psxandroid.scecompcall://redirect/?cid=x") == nil
          && PSNAPI.code(fromRedirect: "") == nil)

    // ④ category → 平台。显式表而不是丢给归一化器，因为 pspc_game / psp_game 那种紧凑写法
    //    归一化器的关键词表认不出来。
    check("PSN: ps5_native_game → PS5", PSNAPI.platform(forCategory: "ps5_native_game") == "PS5")
    check("PSN: ps4_game → PS4", PSNAPI.platform(forCategory: "ps4_game") == "PS4")
    check("PSN: ps3_game → PS3", PSNAPI.platform(forCategory: "ps3_game") == "PS3")
    check("PSN: psvita_game → PS Vita", PSNAPI.platform(forCategory: "psvita_game") == "PS Vita")
    check("PSN: psp_game → PSP", PSNAPI.platform(forCategory: "psp_game") == "PSP")
    check("PSN: pspc_game → PC", PSNAPI.platform(forCategory: "pspc_game") == "PC")
    check("PSN: unknown / nil 认不出来就返回 nil（由调用方落 provider 兜底）",
          PSNAPI.platform(forCategory: "unknown") == nil
          && PSNAPI.platform(forCategory: nil) == nil)
    check("PSN: 映射出的每个平台都是合法预设值（否则入库会出现界面筛不到的野值）",
          ["PS5", "PS4", "PS3", "PS Vita", "PSP", "PC"].allSatisfy(Presets.platforms.contains))

    // ⑤ 「HTTP 200 里带 error」—— PSN 侧独有也最隐蔽的失败形状。
    let errorBody = Data(#"{"error":{"code":2101,"message":"server free text 不要泄漏"}}"#.utf8)
    let apiError = PSNAPI.apiError(in: errorBody)
    var apiErrorIsChanged = false
    if case .apiChanged = apiError { apiErrorIsChanged = true }
    check("PSN: 200 里的 error 对象被识别出来（不识别就会变成「同步成功、0 条记录」）",
          apiErrorIsChanged)
    check("PSN: 服务端的 message 绝不进错误描述",
          !(apiError?.errorDescription ?? "").contains("server free text")
          && !String(describing: apiError!).contains("server free text"))
    check("PSN: OAuth 形状的 error 交给共享层白名单判定 → authExpired",
          PSNAPI.apiError(in: Data(#"{"error":"invalid_grant","error_description":"x"}"#.utf8))
              == .authExpired)
    check("PSN: 正常响应体不误报",
          PSNAPI.apiError(in: Data(#"{"titles":[],"totalItemCount":0}"#.utf8)) == nil
          && PSNAPI.apiError(in: Data("not json".utf8)) == nil)

    // ⑥ 换取链路（全部走桩，一条真网络都不打）。
    let psnHTTP = ExternalHTTPClient(defaultHeaders: ["Accept": "application/json"],
                                     protocolClasses: [ExternalImportStub.self])

    func psnRequests(_ suffix: String) -> [URLRequest] {
        ExternalImportStub.requests.filter { ($0.url?.path ?? "").hasSuffix(suffix) }
    }
    func psnError(_ body: @escaping () async throws -> Void) async -> ExternalAPIError? {
        do { try await body(); return nil } catch let error as ExternalAPIError { return error } catch { return nil }
    }
    func psnErrorIsInvalidCredential(_ body: @escaping () async throws -> Void) async -> Bool {
        if case .invalidCredential = await psnError(body) { return true }
        return false
    }
    func psnErrorIsAPIChanged(_ body: @escaping () async throws -> Void) async -> Bool {
        if case .apiChanged = await psnError(body) { return true }
        return false
    }
    let tokenOK = ExternalImportStub.Stub(status: 200, body: Data("""
    {"access_token":"AT","refresh_token":"RT","id_token":"IDT",
     "expires_in":3600,"refresh_token_expires_in":5184000}
    """.utf8))
    let redirectWithCode = ExternalImportStub.Stub(
        status: 302,
        headers: ["Location": "com.scee.psxandroid.scecompcall://redirect/?code=v3.CODE&cid=abc"])

    // (a) NPSSO → code：**NPSSO 只在 Cookie 头里，绝不进 URL**。
    let sink = StringBox()
    func makePSNAuth(npsso: String?, refresh: String?) -> PSNAuthService {
        PSNAuthService(http: psnHTTP,
                       npssoProvider: { npsso },
                       refreshTokenProvider: { refresh },
                       refreshTokenSink: { sink.append($0) })
    }

    ExternalImportStub.install { _ in redirectWithCode }
    let psnAuth = makePSNAuth(npsso: "NPSSO-1", refresh: nil)
    let fetchedCode = try? await psnAuth.exchangeNPSSOForAccessCode("NPSSO-1")
    let authorizeRequest = psnRequests("/authorize").first
    let authorizeURL = authorizeRequest?.url?.absoluteString ?? ""
    check("PSN: NPSSO 换到一次性 code", fetchedCode == "v3.CODE")
    check("PSN: NPSSO 只在 Cookie 头里",
          authorizeRequest?.value(forHTTPHeaderField: "Cookie") == "npsso=NPSSO-1")
    check("PSN: NPSSO **不在 URL 里**（URL 会进系统网络日志）",
          !authorizeURL.contains("NPSSO-1"))
    check("PSN: authorize 参数齐全（access_type=offline / response_type=code / redirect_uri 编码正确）",
          authorizeURL.contains("access_type=offline")
          && authorizeURL.contains("response_type=code")
          && authorizeURL.contains("client_id=09515159-7237-4370-9b40-3806e67c0891")
          && authorizeURL.contains("redirect_uri=com.scee.psxandroid.scecompcall%3A%2F%2Fredirect"))

    // (b) 200 而不是 3xx / 3xx 但没有 code → 都是「NPSSO 不对」。
    ExternalImportStub.install { _ in .init(status: 200, body: Data("<html>".utf8)) }
    let psnAuth200 = makePSNAuth(npsso: "NPSSO-1", refresh: nil)
    check("PSN: 没有重定向 → invalidCredential（提示用户重新取 NPSSO）",
          await psnErrorIsInvalidCredential {
              _ = try await psnAuth200.exchangeNPSSOForAccessCode("NPSSO-1")
          })

    ExternalImportStub.install { _ in .init(status: 302, headers: ["Location": "https://x.invalid/no-code"]) }
    let psnAuthNoCode = makePSNAuth(npsso: "NPSSO-1", refresh: nil)
    check("PSN: 重定向里没有 code → invalidCredential",
          await psnErrorIsInvalidCredential {
              _ = try await psnAuthNoCode.exchangeNPSSOForAccessCode("NPSSO-1")
          })

    // (c) 全链路：NPSSO → code → token。POST form + Basic 头，且 code 不进 URL。
    ExternalImportStub.install { request in
        (request.url?.path ?? "").hasSuffix("/authorize") ? redirectWithCode : tokenOK
    }
    let psnAuthExchange = makePSNAuth(npsso: "NPSSO-1", refresh: nil)
    let credentials = try? await psnAuthExchange.validCredentials()
    let tokenRequest = psnRequests("/token").first
    check("PSN: NPSSO → code → access token 全链路走通", credentials?.accessToken == "AT")
    check("PSN: 全链路是先 authorize 再 token", psnRequests("/authorize").count == 1)
    check("PSN: token 端点走 POST form + Basic 授权头",
          tokenRequest?.httpMethod == "POST"
          && tokenRequest?.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded"
          && (tokenRequest?.value(forHTTPHeaderField: "Authorization") ?? "").hasPrefix("Basic "))
    check("PSN: grant_type=authorization_code 且带 token_format=jwt",
          (tokenRequest.flatMap(stubBody) ?? "").contains("grant_type=authorization_code")
          && (tokenRequest.flatMap(stubBody) ?? "").contains("token_format=jwt"))
    check("PSN: code **不在 URL 里**",
          !(tokenRequest?.url?.absoluteString ?? "").contains("v3.CODE"))
    check("PSN: 换到的 refresh_token 会交给调用方落盘（万一开始轮换也不至于某天突然失效）",
          sink.all == ["RT"])
    check("PSN: refresh_token 的到期时间被带出来（UI 要拿它说「约 X 天后需要重新登录」）",
          credentials?.refreshTokenExpiresAt != nil)

    // (d) 有 refresh_token 时优先走 refresh：不动 NPSSO（NPSSO 寿命有限、用一次少一次）。
    ExternalImportStub.install { request in
        (request.url?.path ?? "").hasSuffix("/authorize") ? redirectWithCode : tokenOK
    }
    let psnAuthRefresh = makePSNAuth(npsso: "NPSSO-1", refresh: "RT")
    let refreshed = try? await psnAuthRefresh.validCredentials()
    let refreshRequest = psnRequests("/token").first
    check("PSN: 有 refresh_token 就走 refresh", refreshed?.accessToken == "AT")
    check("PSN: refresh 的 grant_type 与 scope 与换 code 不同（两个 grant 形状不一样）",
          (refreshRequest.flatMap(stubBody) ?? "").contains("grant_type=refresh_token")
          && (refreshRequest.flatMap(stubBody) ?? "").contains("psn%3Amobile.v2.core"))
    check("PSN: 走 refresh 时**完全没碰** authorize 端点", psnRequests("/authorize").isEmpty)

    let requestsAfterDerive = ExternalImportStub.requests.count
    _ = try? await psnAuthRefresh.validCredentials()
    check("PSN: 1 小时内复用缓存（不缓存的话每次同步都多发一个换取请求）",
          ExternalImportStub.requests.count == requestsAfterDerive)

    // (e) refresh 被拒 → 落到 NPSSO 重登（那是 refresh 用完硬寿命后的唯一出路）。
    ExternalImportStub.install { request in
        if (request.url?.path ?? "").hasSuffix("/authorize") { return redirectWithCode }
        guard let body = stubBody(of: request), body.contains("grant_type=refresh_token") else {
            return tokenOK
        }
        return .init(status: 400, headers: ["Content-Type": "application/json"],
                     body: Data(#"{"error":"invalid_grant"}"#.utf8))
    }
    let psnAuthFallback = makePSNAuth(npsso: "NPSSO-1", refresh: "RT-DEAD")
    check("PSN: refresh 失效后自动用 NPSSO 重登（不让用户手动重绑）",
          (try? await psnAuthFallback.validCredentials())?.accessToken == "AT"
          && psnRequests("/authorize").count == 1)

    // (f) 网断了不该触发重登（白跑一趟还会掩盖真实原因）。
    ExternalImportStub.install { _ in .init(status: 503) }
    let psnAuthOffline = makePSNAuth(npsso: "NPSSO-1", refresh: "RT")
    check("PSN: 5xx 不触发 NPSSO 重登，原样上抛",
          await psnError { _ = try await psnAuthOffline.validCredentials() } == .server(503)
          && psnRequests("/authorize").isEmpty)

    // (g) 两条路都没有凭证 → authExpired。
    let psnAuthEmpty = makePSNAuth(npsso: nil, refresh: nil)
    check("PSN: 没有 NPSSO 也没有 refresh_token → authExpired",
          await psnError { _ = try await psnAuthEmpty.validCredentials() } == .authExpired)

    // (h) token 端点回 200 带 error → 不能被当成「拿到凭证了」。
    ExternalImportStub.install { request in
        (request.url?.path ?? "").hasSuffix("/authorize") ? redirectWithCode
            : .init(status: 200, headers: ["Content-Type": "application/json"],
                    body: Data(#"{"error":{"code":1,"message":"x"}}"#.utf8))
    }
    let psnAuthErr = makePSNAuth(npsso: "NPSSO-1", refresh: nil)
    check("PSN: token 端点 200 带 error → 报错，而不是拿一个空 token 用下去",
          await psnErrorIsAPIChanged {
              _ = try await psnAuthErr.validCredentials()
          })

    // ⑦ 游玩记录：解析、翻页、以及「200 带 error」不能变成 0 条成功。
    let gamesJSON = """
    {"titles":[
      {"titleId":"PPSA07950_00","name":"Zenless Zone Zero","localizedName":"绝区零",
       "imageUrl":"https://img.example/a.jpg","localizedImageUrl":"https://img.example/a-cn.jpg",
       "category":"ps5_native_game","service":"none","playCount":42,
       "concept":{"id":10009763,"titleIds":["PPSA07950_00","PPSA07949_00"],"name":"ZZZ","media":{}},
       "media":{"screenshotUrl":"https://x.invalid/s.jpg"},
       "firstPlayedDateTime":"2024-07-04T10:00:00Z",
       "lastPlayedDateTime":"2025-01-01T00:00:00.12Z",
       "playDuration":"PT228H56M33S"},
      {"titleId":"CUSA01433_00","name":"Rocket League","localizedName":"",
       "imageUrl":"https://img.example/b.jpg","category":"ps4_game","playCount":100,
       "concept":{"id":10009763},
       "firstPlayedDateTime":"2015-07-10T19:40:19Z","lastPlayedDateTime":"2016-01-01T00:00:00Z"},
      {"titleId":"","name":"没有 id 的孤儿","category":"ps4_game"},
      {"titleId":"BLUS00000","name":"   ","category":"ps4_game"}
    ],"totalItemCount":4,"nextOffset":200}
    """
    let gamesPage = try ExternalHTTPClient.decode(PSNAPI.PlayedGamesResponse.self,
                                                 from: Data(gamesJSON.utf8))
    let psnRecords = PSNGameService.records(from: gamesPage.titles ?? [],
                                           fallbackPlatform: AccountProvider.playstation.fallbackPlatform)

    check("PSN: 未声明的 concept.titleIds / media 不会让整次解码失败", psnRecords.count == 2)
    let zzz = psnRecords.first { $0.titleId == "PPSA07950_00" }
    check("PSN: 标题优先本地化名", zzz?.titleName == "绝区零")
    check("PSN: ps5_native_game → PS5", zzz?.platform == "PS5")
    check("PSN: concept.id 转成字符串存下来（PS4/PS5 双版本的合并键）",
          zzz?.conceptId == "10009763")
    check("PSN: duration 解析成秒", zzz?.playedSeconds == 824_193)
    check("PSN: playCount 收得下", zzz?.playCount == 42)
    check("PSN: 图片优先本地化版本", zzz?.imageURLString == "https://img.example/a-cn.jpg")
    check("PSN: 两位小数秒的 lastPlayedAt 能解出来", zzz?.lastPlayedAt != nil)

    let rocket = psnRecords.first { $0.titleId == "CUSA01433_00" }
    check("PSN: 本地化名为空则退回原名", rocket?.titleName == "Rocket League")
    check("PSN: ps4_game → PS4", rocket?.platform == "PS4")
    check("PSN: **没有 playDuration** 落 nil（PS3/Vita 拿不到时长是 Sony 的硬缺口）",
          rocket?.playedSeconds == nil)
    check("PSN: 没有时长但照样有 playCount —— 两个字段互不影响", rocket?.playCount == 100)
    check("PSN: PS4 版与 PS5 版是**两条**记录（不在这里合并，交给 GameLinker 按 conceptId 关联）",
          psnRecords.filter { $0.conceptId == "10009763" }.count == 2)
    check("PSN: 缺 id 或缺名字的条目被丢弃", psnRecords.count == 2)
    check("PSN: 最近玩过的排前面", psnRecords.first?.titleId == "PPSA07950_00")

    // 翻页 / 错误体：桩按 offset 分流。
    func psnGameStub(pages: @escaping (Int) -> ExternalImportStub.Stub)
        -> (URLRequest) -> ExternalImportStub.Stub {
        { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/authorize") { return redirectWithCode }
            if path.hasSuffix("/token") { return tokenOK }
            let offset = (request.url.flatMap {
                URLComponents(url: $0, resolvingAgainstBaseURL: false)
            })?.queryItems?.first { $0.name == "offset" }?.value
            return pages(Int(offset ?? "0") ?? 0)
        }
    }

    // (a) 两页：第一页 2 条 + totalItemCount=4 → 继续；第二页 1 条且总数收敛到 3 → 收满即停。
    ExternalImportStub.install(psnGameStub { offset in
        offset == 0
            ? .init(status: 200, body: Data(gamesJSON.utf8))
            : .init(status: 200, body: Data("""
              {"titles":[{"titleId":"CUSA99999_00","name":"第三页","category":"ps4_game"}],
               "totalItemCount":3}
              """.utf8))
    })
    let psnGameAuth = makePSNAuth(npsso: "NPSSO-1", refresh: "RT")
    let paged = try? await PSNGameService(auth: psnGameAuth, accountId: "1234567890", http: psnHTTP)
        .fetchRecords()
    check("PSN: 自动翻页收满（2 + 1 = 3 条）", paged?.count == 3)
    check("PSN: 翻页共发 2 次请求（收满即停，不多打也不无限翻）", psnRequests("/titles").count == 2)
    check("PSN: 第二页用 offset=200",
          psnRequests("/titles").last?.url?.query?.contains("offset=200") == true)
    check("PSN: 请求带 Bearer 与 limit=200",
          (psnRequests("/titles").first?.value(forHTTPHeaderField: "Authorization") ?? "").hasPrefix("Bearer ")
          && psnRequests("/titles").first?.url?.query?.contains("limit=200") == true)

    // (b) 服务端在原地打转（每页都返回同一批、totalItemCount 又虚高）→ 必须自己停下来。
    //     没有这条护栏就会老老实实翻满 50 页，打 50 次请求。
    ExternalImportStub.install(psnGameStub { _ in
        .init(status: 200, body: Data(gamesJSON.utf8))
    })
    let psnGameAuthStuck = makePSNAuth(npsso: "NPSSO-1", refresh: "RT")
    let stuck = try? await PSNGameService(auth: psnGameAuthStuck, accountId: "1", http: psnHTTP)
        .fetchRecords()
    check("PSN: 服务端重复返回同一页时自己停下（2 次请求而不是翻满 50 页）",
          psnRequests("/titles").count == 2 && stuck?.count == 2)

    // (c) 200 带 error：**必须报错**，不能静默变成「你的账号里没有游戏」。
    ExternalImportStub.install(psnGameStub { _ in
        .init(status: 200, headers: ["Content-Type": "application/json"],
              body: Data(#"{"error":{"code":2101,"message":"x"}}"#.utf8))
    })
    let psnGameAuth2 = makePSNAuth(npsso: "NPSSO-1", refresh: "RT")
    check("PSN: 200 带 error 的响应**不会**被当成空库成功",
          await psnErrorIsAPIChanged {
              _ = try await PSNGameService(auth: psnGameAuth2, accountId: "1", http: psnHTTP).fetchRecords()
          })

    // (d) 401：access token 在「以为还有效」的窗口里被拒 → 重取一次再试。
    ExternalImportStub.install(psnGameStub { _ in .init(status: 401) })
    let psnGameAuth3 = makePSNAuth(npsso: "NPSSO-1", refresh: "RT")
    check("PSN: 401 时重取凭证再试一次，第二次仍失败就上抛",
          await psnError {
              _ = try await PSNGameService(auth: psnGameAuth3, accountId: "1", http: psnHTTP).fetchRecords()
          } == .authExpired
          && psnRequests("/titles").count == 2)

    // ⑧ 身份解析：accountId 两条路径 + 在线 ID / 头像的优雅降级。
    func psnIdentityStub(trophy: ExternalImportStub.Stub, devices: ExternalImportStub.Stub,
                         profile: ExternalImportStub.Stub) -> (URLRequest) -> ExternalImportStub.Stub {
        { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/authorize") { return redirectWithCode }
            if path.hasSuffix("/token") { return tokenOK }
            if path.hasSuffix("/trophySummary") { return trophy }
            if path.hasSuffix("/profiles") { return profile }
            return devices
        }
    }
    let trophyOK = ExternalImportStub.Stub(status: 200, body: Data(#"{"accountId":"12345678901234567","trophyLevel":"300"}"#.utf8))
    let profileOK = ExternalImportStub.Stub(status: 200, body: Data("""
    {"onlineId":"PlayerOne","avatars":[{"size":"s","url":"https://img.example/s.png"},
                                       {"size":"l","url":"https://img.example/l.png"}]}
    """.utf8))

    ExternalImportStub.install(psnIdentityStub(trophy: trophyOK, devices: .init(status: 404),
                                               profile: profileOK))
    let identity = try? await PSNAccountService(
        auth: makePSNAuth(npsso: "NPSSO-1", refresh: "RT"), http: psnHTTP).resolveIdentity()
    check("PSN: 从 trophySummary 拿到 accountId", identity?.externalAccountId == "12345678901234567")
    check("PSN: 在线 ID 当展示名", identity?.displayName == "PlayerOne" && identity?.hasRealOnlineId == true)
    check("PSN: 头像取最后一张（顺序未经核实，取错只是分辨率差一点）",
          identity?.avatarURLString == "https://img.example/l.png")

    ExternalImportStub.install(psnIdentityStub(
        trophy: .init(status: 500),
        devices: .init(status: 200, body: Data(#"{"accountId":"99988877766655544"}"#.utf8)),
        profile: profileOK))
    let fallbackIdentity = try? await PSNAccountService(
        auth: makePSNAuth(npsso: "NPSSO-1", refresh: "RT"), http: psnHTTP).resolveIdentity()
    check("PSN: trophySummary 挂了就退到设备端点拿 accountId（端点变了不该让绑定失败）",
          fallbackIdentity?.externalAccountId == "99988877766655544")

    ExternalImportStub.install(psnIdentityStub(trophy: trophyOK, devices: .init(status: 404),
                                               profile: .init(status: 500)))
    let noProfile = try? await PSNAccountService(
        auth: makePSNAuth(npsso: "NPSSO-1", refresh: "RT"), http: psnHTTP).resolveIdentity()
    check("PSN: 资料取不到照样能绑定，退到可读的兜底展示名",
          noProfile?.externalAccountId == "12345678901234567"
          && noProfile?.hasRealOnlineId == false
          && noProfile?.displayName.contains("12345678901234567".suffix(4)) == true)

    ExternalImportStub.clear()
}

// ============================================================================
// 18. 导入协调层：匹配引擎 / 幂等 upsert / 自动墓碑 / 绑定与合并 / 封面下载
// ============================================================================
do {
    func mkCandidate(_ names: [String], _ clues: [(String, String?)]) -> GameLinker.LinkCandidate {
        GameLinker.LinkCandidate(names: names,
                                 clues: clues.map { GameLinker.Clue(titleId: $0.0, conceptId: $0.1) })
    }
    func mkDTO(_ titleId: String, _ name: String, platform: String = "Nintendo Switch",
               concept: String? = nil, seconds: Int? = nil, image: String? = nil,
               first: Date? = nil, last: Date? = nil, platformRaw: String? = nil) -> ExternalGameRecordDTO {
        ExternalGameRecordDTO(titleId: titleId, conceptId: concept, titleName: name,
                              platform: platform, platformRaw: platformRaw, versionType: nil,
                              firstPlayedAt: first, lastPlayedAt: last, playedSeconds: seconds,
                              playCount: nil, imageURLString: image)
    }

    // ① 标题归一化。它决定了「跨来源的同一个游戏」认不认得出来。
    check("归一化: 全角与半角等价（Ｔ == T）",
          GameLinker.normalizedTitle("ＭＯＮＳＴＥＲ ＨＵＮＴＥＲ") == "monsterhunter"
          && GameLinker.normalizedTitle("Monster Hunter") == "monsterhunter")
    check("归一化: 变音符号折叠（Pokémon → pokemon）",
          GameLinker.normalizedTitle("Pokémon") == "pokemon")
    check("归一化: ™/®/标点/空格全部消失",
          GameLinker.normalizedTitle("The Legend of Zelda™: Breath of the Wild")
          == "thelegendofzeldabreathofthewild")
    check("归一化: **汉字与假名必须保留**（用 [a-z0-9] 过滤会整条变空串，中日文永远匹配不上）",
          GameLinker.normalizedTitle("ゼルダの伝説") == "ゼルダの伝説"
          && GameLinker.normalizedTitle("塞尔达传说") == "塞尔达传说")
    check("归一化: 只有符号的标题归一化为空串（调用方据此判「没有可用键」）",
          GameLinker.normalizedTitle("™®©") == "" && GameLinker.normalizedTitle("   ") == "")

    // ①a 列表搜索口径（`GameLinker.matches`）—— 账号记录列表 / 关联选择器 / 合并选择器
    // 三处共用，所以这里钉住的就是三处的行为。
    check("搜索: 空查询一律通过（调用方不必自己判空，判空写三遍就有一遍会写反）",
          GameLinker.matches(query: "", title: "任意")
          && GameLinker.matches(query: "   ", title: "任意"))
    check("搜索: 主标题按归一化**包含**匹配（不是全等：列表筛选看错一行没有代价）",
          GameLinker.matches(query: "zelda", title: "The Legend of Zelda™: Breath of the Wild"))
    check("搜索: 全角 / 大小写一律折叠（用户可能用日文输入法打英文）",
          GameLinker.matches(query: "ＺＥＬＤＡ", title: "Zelda"))
    check("搜索: 中日文标题照常（归一化保留了汉字假名）",
          GameLinker.matches(query: "ゼルダ", title: "ゼルダの伝説"))
    check("搜索: 命中 extras 里的已关联条目名 —— 用户按「我库里叫 Yakuza 2」找一条 龍が如く２ 的记录",
          GameLinker.matches(query: "Yakuza", title: "龍が如く２", extras: ["Yakuza 2"]))
    check("搜索: 编号按**卡片上显示的写法**搜得到（库里存 CUSA01887_00，界面显示 CUSA-01887）",
          GameLinker.matches(query: "CUSA-01887", title: "T", extras: ["CUSA01887_00"])
          && GameLinker.matches(query: "cusa01887_00", title: "T", extras: ["CUSA01887_00"]))
    check("搜索: 平台名折叠后也认（\"PS Vita\" / \"psvita\" 是同一次搜索）",
          GameLinker.matches(query: "psvita", title: "T", extras: ["PS Vita", "PS4"]))
    check("搜索: extras 里的 nil 直接跳过，不影响其余字段命中",
          GameLinker.matches(query: "PS4", title: "T", extras: [nil, "PS4"])
          && !GameLinker.matches(query: "PS5", title: "T", extras: [nil, "PS4"]))
    check("搜索: 三处都不命中才为 false",
          !GameLinker.matches(query: "Mario", title: "Zelda", extras: ["Nintendo Switch", "T-ZELDA"]))
    check("搜索: 多名字重载（`Game.allNames`）第一个当主标题、其余当附加字段",
          GameLinker.matches(query: "塞尔达", names: ["Zelda", "塞尔达传说"])
          && GameLinker.matches(query: "zelda", names: ["Zelda", "塞尔达传说"]))

    // ①b 标题的**文字种类**：请求的语言 ≠ 拿回来的语言。
    //
    // 真账号实测（2026-09-16，151 个导入条目，`Gentry-Locale: zh-TW`，请求本身没被拒）：
    // 只有 62 条真拿到繁體中文，76 条回落成英文、13 条回落成日文。而旧实现是「请求了 zh-*
    // 就把标题写进 nameZh」—— 那 151 条全进了中文名槽，其中 89 条是英文/日文的谎话，
    // 13 条真日文标题反倒无处可去。判据只能看字符本身（见 `TitleScript`）。
    check("文字: 汉字 / 假名 / 拉丁 各归各的",
          TitleScript.of("異度神劍 終極版") == .han
          && TitleScript.of("スプラトゥーン3") == .kana
          && TitleScript.of("Mario Kart 8 Deluxe") == .other)
    check("文字: 空串、纯符号、纯数字判为 none（不冒充任何一种语言）",
          TitleScript.of("") == .none && TitleScript.of("   ") == .none
          && TitleScript.of("™ 123 -") == .none)
    check("文字: 混排时假名 > 汉字 > 其它（中日文标题里混拉丁词是常态）",
          TitleScript.of("異度神劍 2 Nintendo Switch 2 Edition") == .han
          && TitleScript.of("ケイデンス・オブ・ハイラル: クリプト・オブ・ネクロダンサー") == .kana)
    check("文字: 片假名中点 ・ 不算假名（中日文都拿它当分隔符）",
          TitleScript.of("三國志・曹操傳") == .han
          && TitleScript.of("三國志曹操傳") == .han)
    check("文字: 匹配判据按语言分支（zh 只认汉字；ja 认假名与汉字；en 认拉丁）",
          TitleScript.han.matches(localeCode: "zh-TW")
          && !TitleScript.other.matches(localeCode: "zh-TW")
          && TitleScript.han.matches(localeCode: "ja-JP")
          && TitleScript.kana.matches(localeCode: "ja-JP")
          && !TitleScript.other.matches(localeCode: "ja-JP")
          && TitleScript.other.matches(localeCode: "en-GB"))
    check("文字: 不认识的 locale 一律算匹配（宁可什么都不说，也不凭猜拦掉正确数据）",
          TitleScript.other.matches(localeCode: "ko-KR")
          && TitleScript.none.matches(localeCode: ""))
    check("文字: 槽位由**标题自己**决定，不由请求的语言决定",
          TitleScript.other.languageSlot(requestedLocale: "zh-TW") == nil
          && TitleScript.other.languageSlot(requestedLocale: "ja-JP") == nil
          && TitleScript.han.languageSlot(requestedLocale: "zh-TW") == "zh"
          && TitleScript.han.languageSlot(requestedLocale: "ja-JP") == "ja"
          && TitleScript.kana.languageSlot(requestedLocale: "zh-TW") == "ja")

    // ② 匹配引擎：三条强键 + 歧义保护 + 弱键拒绝。
    let zeldaCandidate = mkCandidate(["The Legend of Zelda", "塞尔达传说"], [("T-ZELDA", nil)])
    let marioCandidate = mkCandidate(["Super Mario Odyssey"], [])

    check("匹配: titleId 命中（同一个来源条目，或另一个账号上的同一条）",
          GameLinker.match(mkDTO("T-ZELDA", "随便什么名字"), among: [marioCandidate, zeldaCandidate])?.index == 1)
    check("匹配: 归一化全等命中 —— 跨 provider 认亲靠的就是这一条",
          GameLinker.match(mkDTO("PSN-X", "THE LEGEND OF ZELDA™"),
                           among: [marioCandidate, zeldaCandidate])?.basis
          == .exactName("thelegendofzelda"))
    check("匹配: 弱键（包含）**不**命中 —— 错并一次不可逆，宁可留在待绑定",
          GameLinker.match(mkDTO("X", "Zelda II"), among: [marioCandidate, zeldaCandidate]) == nil)
    check("匹配: 两个 Game 同名时不猜（提示用户手动选）",
          GameLinker.match(mkDTO("X", "Zelda"), among: [mkCandidate(["Zelda"], []),
                                                        mkCandidate(["Zelda"], [])]) == nil)
    check("匹配: 一个 Game 的「名字与自己别名相同」不算歧义（按 Game 分组传名，不摊平）",
          GameLinker.match(mkDTO("X", "Zelda"), among: [mkCandidate(["Zelda", "zelda"], [])])?.index == 0)

    let tsushimaCandidate = mkCandidate(["Ghost of Tsushima"], [("CUSA13323_00", "10009763")])
    check("匹配: conceptId 命中（PS4/PS5 双版本合并的官方依据）",
          GameLinker.match(mkDTO("PPSA01325_00", "Ghost of Tsushima Director's Cut",
                                 concept: "10009763"),
                           among: [marioCandidate, tsushimaCandidate])?.basis == .conceptId("10009763"))
    check("匹配: conceptId 不同、名字也不同 → 不命中",
          GameLinker.match(mkDTO("PPSA01325_00", "Ghost of Tsushima Director's Cut",
                                 concept: "999"),
                           among: [marioCandidate, tsushimaCandidate]) == nil)
    check("匹配: 标题为空（只有符号）时不靠名字瞎猜",
          GameLinker.match(mkDTO("X", "™"), among: [marioCandidate, zeldaCandidate]) == nil)

    // 强键两侧都 trim 再比。协调器处处以 trim 后的值落库（那是唯一键的第 3 段），
    // 而传进本函数的 DTO 是**原始**值 —— 不统一的话，一条末尾带空格的来源记录既匹配不上
    // 任何线索、又和库里 trim 过的那条撞不成同一个 key，结果是被当成新条目重复导入。
    check("匹配: titleId 两侧带空白照样命中（协调器 trim 落库，比对必须同口径）",
          GameLinker.match(mkDTO("  T-ZELDA\n", "随便什么名字"),
                           among: [marioCandidate, zeldaCandidate])?.index == 1)
    check("匹配: 线索侧带空白、DTO 干净，同样命中",
          GameLinker.match(mkDTO("T-ZELDA", "随便什么名字"),
                           among: [mkCandidate(["Other"], [(" T-ZELDA ", nil)])])?.index == 0)
    check("匹配: 纯空白的 titleId 不算键（不会退化成「第一个候选」）",
          GameLinker.match(mkDTO("   ", "Zelda II"), among: [marioCandidate, zeldaCandidate]) == nil)
    check("匹配: conceptId 两侧带空白照样命中",
          GameLinker.match(mkDTO("PPSA01325_00", "Ghost of Tsushima Director's Cut",
                                 concept: " 10009763 "),
                           among: [marioCandidate, tsushimaCandidate])?.basis == .conceptId("10009763"))

    check("匹配闸门: 体验版/试玩版永不自动匹配（并进正片会让用户以为玩过正片）",
          !GameLinker.allowsAutoMatching(.demo) && !GameLinker.allowsAutoMatching(.trial))
    check("匹配闸门: 正式版与未知类型照常",
          GameLinker.allowsAutoMatching(.full) && GameLinker.allowsAutoMatching(.unknown))

    // ③ 封面下载的两道闸（URL 来自服务端，不是我们写死的常量）。
    check("封面: 只认 https",
          ArtworkFetcher.safeImageURL("https://img.example/a.png") != nil
          && ArtworkFetcher.safeImageURL("http://img.example/a.png") == nil)
    check("封面: file:// 被拒（否则服务端给的 URL 能读本机文件）",
          ArtworkFetcher.safeImageURL("file:///etc/passwd") == nil)
    check("封面: 空值 / 空白 / 无 host 都拒",
          ArtworkFetcher.safeImageURL(nil) == nil
          && ArtworkFetcher.safeImageURL("   ") == nil
          && ArtworkFetcher.safeImageURL("https:relative.png") == nil)
    check("封面: 魔数认得出 PNG / JPEG / GIF / WEBP / HEIC",
          ArtworkFetcher.looksLikeImage(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
          && ArtworkFetcher.looksLikeImage(Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0]))
          && ArtworkFetcher.looksLikeImage(Data("GIF89a".utf8))
          && ArtworkFetcher.looksLikeImage(Data(Array("RIFF".utf8) + [0, 0, 0, 0] + Array("WEBP".utf8)))
          && ArtworkFetcher.looksLikeImage(Data([0, 0, 0, 0x18] + Array("ftypheic".utf8))))
    check("封面: HTML / JSON 错误体不被当成图（否则 404 页面会被存成封面）",
          !ArtworkFetcher.looksLikeImage(Data("<!DOCTYPE html>".utf8))
          && !ArtworkFetcher.looksLikeImage(Data(#"{"error":"x"}"#.utf8))
          && !ArtworkFetcher.looksLikeImage(Data()))

    func makeArtworkFetcher() -> ArtworkFetcher {
        ArtworkFetcher(http: ExternalHTTPClient(protocolClasses: [ExternalImportStub.self]))
    }
    let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    ExternalImportStub.install { _ in .init(status: 200, body: pngBytes) }
    check("封面: 下载成功返回字节",
          await makeArtworkFetcher().artworkData(from: "https://img.example/a.png")?.count == 8)

    ExternalImportStub.install { _ in .init(status: 404, body: Data("<!DOCTYPE html>".utf8)) }
    check("封面: 404 页面拿不到图，也不抛错",
          await makeArtworkFetcher().artworkData(from: "https://img.example/a.png") == nil)

    ExternalImportStub.install { _ in .init(status: 500) }
    check("封面: 服务端 5xx 静默失败（封面是装饰，不影响数据）",
          await makeArtworkFetcher().artworkData(from: "https://img.example/a.png") == nil)

    ExternalImportStub.install { _ in .init(status: 200, body: pngBytes) }
    check("封面: 非 https 的 URL 根本不发请求",
          await makeArtworkFetcher().artworkData(from: "file:///etc/passwd") == nil
          && ExternalImportStub.requests.isEmpty)
    ExternalImportStub.clear()

    // ④ 导入协调：幂等 upsert / 自动匹配 / 建库 / 墓碑 / 健壮性。
    let importSchema = Schema([Game.self, Completion.self, GameGroup.self, PhysicalCopy.self,
                               LinkedAccount.self, ExternalGameRecord.self])
    guard let importContainer = try? ModelContainer(
        for: importSchema,
        configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]) else {
        print("FAIL: cannot create import ModelContainer")
        exit(1)
    }
    let coordinator = ImportCoordinator(modelContainer: importContainer)

    // 每次都用**新 context** 读：观察协调器（独立 actor 的 context）写进去的结果。
    func allGames() -> [Game] {
        (try? ModelContext(importContainer).fetch(FetchDescriptor<Game>())) ?? []
    }
    func allRecords() -> [ExternalGameRecord] {
        (try? ModelContext(importContainer).fetch(FetchDescriptor<ExternalGameRecord>())) ?? []
    }
    func allAccounts() -> [LinkedAccount] {
        (try? ModelContext(importContainer).fetch(FetchDescriptor<LinkedAccount>())) ?? []
    }
    func inContext(_ body: (ModelContext) throws -> Void) {
        let context = ModelContext(importContainer)
        try? body(context)
        try? context.save()
    }

    let setup = ModelContext(importContainer)
    let nintendoA = LinkedAccount(provider: .nintendo, externalAccountId: "NA-1",
                                  displayName: "账号一", sourceLocale: "en-GB")
    let nintendoB = LinkedAccount(provider: .nintendo, externalAccountId: "NA-2",
                                  displayName: "账号二", sourceLocale: "en-GB")
    let psnAccount = LinkedAccount(provider: .playstation, externalAccountId: "PSN-1",
                                   displayName: "PlayerOne", sourceLocale: "en")
    setup.insert(nintendoA); setup.insert(nintendoB); setup.insert(psnAccount)
    try? setup.save()

    let firstRound = try await coordinator.importRecords(
        [mkDTO("T1", "The Legend of Zelda"), mkDTO("T2", "Super Mario Odyssey")],
        intoAccount: nintendoA.localId, sourceLocale: "en-GB")
    check("导入: 首轮两条记录全部建库",
          firstRound.createdRecords == 2 && firstRound.createdGames == 2
          && firstRound.autoLinked == 0 && firstRound.updatedRecords == 0
          && allRecords().count == 2 && allGames().count == 2)

    let secondRound = try await coordinator.importRecords(
        [mkDTO("T1", "The Legend of Zelda"), mkDTO("T2", "Super Mario Odyssey")],
        intoAccount: nintendoA.localId, sourceLocale: "en-GB")
    check("导入: 重复同步幂等 —— 0 新建 / 2 刷新 / 0 建库 / 2 已关联",
          secondRound.createdRecords == 0 && secondRound.updatedRecords == 2
          && secondRound.createdGames == 0 && secondRound.alreadyLinked == 2
          && allRecords().count == 2 && allGames().count == 2)

    // 两个 Nintendo 账号并存：记录各归各的，但同一个 titleId 指向同一个 Game。
    let roundB = try await coordinator.importRecords(
        [mkDTO("T1", "The Legend of Zelda")],
        intoAccount: nintendoB.localId, sourceLocale: "en-GB")
    check("导入: 第二个 Nintendo 账号的记录独立入库，靠 titleId 并到同一个 Game",
          roundB.createdRecords == 1 && roundB.createdGames == 0 && roundB.autoLinked == 1
          && allRecords().count == 3 && allGames().count == 2)
    let zeldaRecords = allRecords().filter { $0.titleId == "T1" }
    check("导入: 同 titleId 跨两账号 = 两条记录、同一个 Game",
          zeldaRecords.count == 2
          && zeldaRecords.compactMap { $0.externalAccountId }.sorted() == ["NA-1", "NA-2"]
          && Set(zeldaRecords.compactMap { $0.game?.persistentModelID }).count == 1)

    // 同一个游戏横跨 Nintendo 与 PSN：靠归一化同名认亲。
    let roundPSN = try await coordinator.importRecords(
        [mkDTO("CUSA00001_00", "THE LEGEND OF ZELDA™", platform: "PS4")],
        intoAccount: psnAccount.localId, sourceLocale: "en")
    check("导入: 同一游戏在 Nintendo + PSN 两边 → 归一到同一个 Game",
          roundPSN.createdGames == 0 && roundPSN.autoLinked == 1 && allGames().count == 2)

    // PS4/PS5 双版本：两个 titleId，一个 conceptId → 两条记录、一个 Game。
    let roundPS5 = try await coordinator.importRecords(
        [mkDTO("PPSA00002_00", "Ghost of Tsushima", platform: "PS5", concept: "10009763"),
         mkDTO("CUSA13323_00", "Ghost of Tsushima", platform: "PS4", concept: "10009763")],
        intoAccount: psnAccount.localId, sourceLocale: "en")
    check("导入: PS4/PS5 双版本 = 建 1 个库 + 并 1 条（靠 conceptId）",
          roundPS5.createdRecords == 2 && roundPS5.createdGames == 1 && roundPS5.autoLinked == 1)
    let tsushimaRecords = allRecords().filter { $0.conceptId == "10009763" }
    check("导入: 双版本各留一条记录（**不**在解析层合并），都挂到那个 Game",
          tsushimaRecords.count == 2
          && Set(tsushimaRecords.compactMap { $0.game?.persistentModelID }).count == 1
          && Set(tsushimaRecords.compactMap { $0.titleId }).count == 2)

    // 体验版：入库留档，但不进游戏库。
    let roundDemo = try await coordinator.importRecords(
        [mkDTO("T-DEMO", "Metroid Dread 体験版")],
        intoAccount: nintendoA.localId, sourceLocale: "ja-JP")
    check("导入: 体验版只记录不建库，也不并进正片",
          roundDemo.createdRecords == 1 && roundDemo.excludedByVersion == 1
          && roundDemo.createdGames == 0 && allRecords().first { $0.titleId == "T-DEMO" }?.game == nil)

    let roundDemon = try await coordinator.importRecords(
        [mkDTO("T-DEMON", "Demon's Souls")],
        intoAccount: nintendoA.localId, sourceLocale: "en-GB")
    check("导入: Demon's Souls 不被误判成体验版（含 demo 子串但整词不匹配）",
          roundDemon.excludedByVersion == 0 && roundDemon.createdGames == 1)

    // 语言槽 + 首次游玩时间缺失 + 时长缺失。
    _ = try await coordinator.importRecords(
        [mkDTO("T-JA", "スプラトゥーン3"), mkDTO("T-NODATE", "Untitled Goose Game")],
        intoAccount: nintendoA.localId, sourceLocale: "ja-JP")
    // 定位用 `allNames`（不是 `name`）：中日文标题现在只落语言槽，主名是空的。
    func game(named title: String) -> Game? {
        allGames().first { $0.allNames.contains(title) }
    }
    check("导入: 日文标题只落 nameJa，**主名留空**（旧版会把日文也写进「英文名」那一栏）",
          game(named: "スプラトゥーン3")?.nameJa == "スプラトゥーン3"
          && game(named: "スプラトゥーン3")?.name == ""
          && game(named: "スプラトゥーン3")?.nameZh == nil)
    check("导入: 英文来源落主名，且不占用中日文槽位（认不出来就不写其它槽）",
          game(named: "Super Mario Odyssey")?.name == "Super Mario Odyssey"
          && game(named: "Super Mario Odyssey")?.nameJa == nil
          && game(named: "Super Mario Odyssey")?.nameZh == nil)

    // 请求中文、来源却**逐条**回落（真账号上 151 条里 89 条如此）：槽位按标题自己判。
    _ = try await coordinator.importRecords(
        [mkDTO("T-ZH1", "Xenoblade Chronicles 2"),
         mkDTO("T-ZH2", "異度神劍 終極版"),
         mkDTO("T-ZH3", "ケイデンス・オブ・ハイラル")],
        intoAccount: nintendoA.localId, sourceLocale: "zh-TW")
    check("导入: 请求中文但来源回落成英文 → 中文名槽**留空**（旧实现写进去，库里从此谎称有中文名）",
          game(named: "Xenoblade Chronicles 2")?.nameZh == nil
          && game(named: "Xenoblade Chronicles 2")?.nameJa == nil
          && game(named: "Xenoblade Chronicles 2")?.name == "Xenoblade Chronicles 2")
    check("导入: 真中文标题落进 nameZh，主名留空",
          game(named: "異度神劍 終極版")?.nameZh == "異度神劍 終極版"
          && game(named: "異度神劍 終極版")?.name == "")
    check("导入: 请求中文却拿回日文标题 → 落 nameJa（旧实现把这 13 条直接丢掉）",
          game(named: "ケイデンス・オブ・ハイラル")?.nameJa == "ケイデンス・オブ・ハイラル"
          && game(named: "ケイデンス・オブ・ハイラル")?.nameZh == nil
          && game(named: "ケイデンス・オブ・ハイラル")?.name == "")

    // 上一版落到槽里的脏值：**不改语言**的普通重新同步也要修掉。
    // 用另一个 context 造这份脏数据 —— 协调器第一次见它，从 store 现取，不吃自己的缓存。
    inContext { context in
        if let game = try context.fetch(FetchDescriptor<Game>())
            .first(where: { $0.allNames.contains("Xenoblade Chronicles 2") }) {
            game.nameZh = "Xenoblade Chronicles 2"   // ← beta 3.1 写下的假中文名
        }
    }
    _ = try await coordinator.importRecords(
        [mkDTO("T-ZH1", "Xenoblade Chronicles 2")],
        intoAccount: nintendoA.localId, sourceLocale: "zh-TW")
    check("导入: 重新同步清掉上一版写错槽位的英文名（只清「还是来源那个标题」的值）",
          game(named: "Xenoblade Chronicles 2")?.nameZh == nil)

    // 旧版无条件把来源标题也写一份进主名 → 「英文名」那一栏里躺着中文。
    // 用户不重装、不清库，**普通的一次重新同步**就该把它搬回语言槽。
    inContext { context in
        if let game = try context.fetch(FetchDescriptor<Game>())
            .first(where: { $0.allNames.contains("異度神劍 終極版") }) {
            game.name = "異度神劍 終極版"   // ← 旧版写在主名里的那份
            game.nameZh = nil
        }
    }
    _ = try await coordinator.importRecords(
        [mkDTO("T-ZH2", "異度神劍 終極版")],
        intoAccount: nintendoA.localId, sourceLocale: "zh-TW")
    check("导入: 旧版留在主名里的中文标题被搬回 nameZh（主名清空，「英文名」不再躺中文）",
          game(named: "異度神劍 終極版")?.name == ""
          && game(named: "異度神劍 終極版")?.nameZh == "異度神劍 終極版")
    let noDate = allRecords().first { $0.titleId == "T-NODATE" }
    check("导入: 首次游玩时间与时长都缺失是正常的，不阻断入库",
          noDate != nil && noDate?.firstPlayedAt == nil && noDate?.playedSeconds == nil
          && noDate?.game != nil)

    // 封面：抓到就落槽；抓不到不影响记录与建库；已有封面绝不覆盖。
    ExternalImportStub.install { _ in .init(status: 200, body: pngBytes) }
    let roundArt = try await coordinator.importRecords(
        [mkDTO("T-ART", "Astro's Playroom", platform: "PS5", image: "https://img.example/a.png")],
        intoAccount: psnAccount.localId, sourceLocale: "en", artworkFetcher: makeArtworkFetcher())
    check("导入: 封面抓到并落进封面槽",
          roundArt.artworkFetched == 1
          && allGames().first { $0.name == "Astro's Playroom" }?.artwork(.poster)?.count == 8)

    ExternalImportStub.install { _ in .init(status: 500) }
    let roundArtFail = try await coordinator.importRecords(
        [mkDTO("T-ART2", "Returnal", platform: "PS5", image: "https://img.example/b.png")],
        intoAccount: psnAccount.localId, sourceLocale: "en", artworkFetcher: makeArtworkFetcher())
    check("导入: 封面下载失败**不影响**记录入库与建库",
          roundArtFail.artworkFailed == 1 && roundArtFail.createdRecords == 1
          && roundArtFail.createdGames == 1
          && allGames().first { $0.name == "Returnal" }?.artwork(.poster) == nil)

    ExternalImportStub.install { _ in .init(status: 200, body: Data("GIF89a".utf8)) }
    let roundArtAgain = try await coordinator.importRecords(
        [mkDTO("T-ART", "Astro's Playroom", platform: "PS5", image: "https://img.example/a.png")],
        intoAccount: psnAccount.localId, sourceLocale: "en", artworkFetcher: makeArtworkFetcher())
    check("导入: 已有封面绝不被覆盖（连请求都不发）",
          roundArtAgain.artworkFetched == 0 && roundArtAgain.artworkFailed == 0
          && ExternalImportStub.requests.isEmpty
          && allGames().first { $0.name == "Astro's Playroom" }?.artwork(.poster)?.count == 8)
    ExternalImportStub.clear()

    // 落哪个槽由**图自己的宽高比**决定（用户 2026-09-16：「抓回来的官方图标放在方形封面
    // 这一栏」）。判定函数是 `ImportCoordinator.looksSquare` → `AppImage.isSquareArtwork`；
    // **显示层用的是另一个判据**（`AppImage.letterboxes(inBoxAspect:)`，见下面那组用例）——
    // 一个回答"进哪个槽"，一个回答"放进这个框会不会被裁"，共用同一个容差。
    func png(width: Int, height: Int) -> Data {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let data = rep.representation(using: .png, properties: [:]) else { return Data() }
        return data
    }
    let squarePNG = png(width: 512, height: 512)
    let portraitPNG = png(width: 600, height: 900)
    check("封面: 1:1 判为方形、2:3 不是、解不出来的魔数也不冒充方形",
          ImportCoordinator.looksSquare(squarePNG)
          && !ImportCoordinator.looksSquare(portraitPNG)
          && !ImportCoordinator.looksSquare(pngBytes))

    // ── 「留白还是裁切」的判据（2026-09-17 用户实测：PS3 / Vita 封面被裁） ─────────
    // 旧显示层只有「方 / 非方」两档，而 320×176 的横图落在"非方"那一档 → 裁切 →
    // 竖版格子里只剩中间一条（用户原话「被放大然后裁切了」）。新判据问的是
    // 「这张图放进**这个比例的框**会不会被裁」—— 下面把改造前后的每一档都钉住。
    if let sqImg = AppImage(data: squarePNG),
       let portImg = AppImage(data: portraitPNG),
       let landImg = AppImage(data: png(width: 320, height: 176)) {   // 真库实测的 PS3/Vita 尺寸
        let box23 = 2.0 / 3.0, box11 = 1.0, box34 = 3.0 / 4.0
        check("留白判据: 框 2:3 —— 竖版封面裁切、方图留白、横图留白（改造前横图被裁成一条）",
              !portImg.letterboxes(inBoxAspect: box23)
              && sqImg.letterboxes(inBoxAspect: box23)
              && landImg.letterboxes(inBoxAspect: box23))
        check("留白判据: 框 1:1（方形网格）—— 方图与竖图都裁切（§55 决策不动）、横图留白",
              !sqImg.letterboxes(inBoxAspect: box11)
              && !portImg.letterboxes(inBoxAspect: box11)
              && landImg.letterboxes(inBoxAspect: box11))
        check("留白判据: 框 3:4（分组选择器）—— 同样只有横图留白",
              !portImg.letterboxes(inBoxAspect: box34)
              && sqImg.letterboxes(inBoxAspect: box34)
              && landImg.letterboxes(inBoxAspect: box34))
        check("留白判据: 框比例非法（0）时返回裁切，不做除零",
              !landImg.letterboxes(inBoxAspect: 0))
    } else {
        check("留白判据: 三种比例的探针图都能解码（探针坏了，下面的判据没被验到）", false)
    }

    ExternalImportStub.install { _ in .init(status: 200, body: squarePNG) }
    let roundSquare = try await coordinator.importRecords(
        [mkDTO("T-SQ", "Icon Probe", image: "https://img.example/icon.png")],
        intoAccount: nintendoA.localId, sourceLocale: "zh-TW", artworkFetcher: makeArtworkFetcher())
    let sqGame = allGames().first { $0.name == "Icon Probe" }
    check("封面: 1:1 图标落进**方形槽**，竖版槽留空",
          roundSquare.artworkFetched == 1
          && sqGame?.artwork(.square)?.count == squarePNG.count && sqGame?.artwork(.poster) == nil)
    check("封面: 只有方图时「封面位」照样读得到它（网格卡不会变空白），且判为方形",
          sqGame?.coverImage != nil && sqGame?.coverImage?.isSquareArtwork == true)
    ExternalImportStub.clear()

    // 上一版把这张方图写进了竖版槽 → 普通重新同步在**本地**搬回去，不发一次请求。
    inContext { context in
        if let game = try context.fetch(FetchDescriptor<Game>())
            .first(where: { $0.name == "Icon Probe" }) {
            game.setArtwork(.poster, game.artwork(.square))
            game.setArtwork(.square, nil)
        }
    }
    ExternalImportStub.install { _ in .init(status: 200, body: squarePNG) }
    _ = try await coordinator.importRecords(
        [mkDTO("T-SQ", "Icon Probe", image: "https://img.example/icon.png")],
        intoAccount: nintendoA.localId, sourceLocale: "zh-TW", artworkFetcher: makeArtworkFetcher())
    check("封面: 上一版放进竖版槽的方图被本地搬回方形槽（不下载、不覆盖用户挑的竖版封面）",
          allGames().first { $0.name == "Icon Probe" }?.artwork(.square) != nil
          && allGames().first { $0.name == "Icon Probe" }?.artwork(.poster) == nil
          && ExternalImportStub.requests.isEmpty)
    ExternalImportStub.clear()

    ExternalImportStub.install { _ in .init(status: 200, body: portraitPNG) }
    let roundPortrait = try await coordinator.importRecords(
        [mkDTO("T-PORT", "Portrait Probe", image: "https://img.example/p.png")],
        intoAccount: nintendoA.localId, sourceLocale: "en", artworkFetcher: makeArtworkFetcher())
    let portGame = allGames().first { $0.name == "Portrait Probe" }
    check("封面: 竖图仍落竖版槽（PSN 的竖封面照旧），也不被判成方形",
          roundPortrait.artworkFetched == 1
          && portGame?.artwork(.poster)?.count == portraitPNG.count
          && portGame?.artwork(.square) == nil && portGame?.coverImage?.isSquareArtwork == false)
    ExternalImportStub.clear()

    // ── 方形网格的槽位优先级 ──────────────────────────────────────────────
    // 2026-09-17 用户实测反馈：「库内原有游戏的方形网格视图没有用方形封面而是竖向封面」。
    // 根因：`coverImage` 的规矩是「2:3 竖版优先」（`Artwork.swift`），方形网格照搬它就会把
    // 竖版封面塞进 1:1 的格子 —— 用户库里 278 款有 125 款两槽都有，全都中招。
    // 修法：方形网格有自己的读法 `squareGridImage`（方图优先、竖版兜底），与 `coverImage`
    // **并列**而不是替代 —— 所以下面同时验证两条读法各自还对。
    inContext { context in
        let twoSlot = Game(name: "TwoSlot Probe")
        context.insert(twoSlot)
        twoSlot.setArtwork(.poster, portraitPNG)
        twoSlot.setArtwork(.square, squarePNG)
        context.insert(Game(name: "NoSlot Probe"))
    }
    let twoSlot = allGames().first { $0.name == "TwoSlot Probe" }
    let noSlotGame = allGames().first { $0.name == "NoSlot Probe" }
    if let twoSlot, let grid = twoSlot.squareGridImage,
       let cover = twoSlot.coverImage, let square = twoSlot.squareImage {
        check("方形网格: 两槽都有时读**方图**（用户实测反馈的那一条），竖版网格照旧读竖版封面",
              grid.size == square.size && grid.size != cover.size
              && square.isSquareArtwork && !cover.isSquareArtwork)
    } else {
        check("方形网格: 两槽都有时读方图（探针游戏的图没能解码）", false)
    }
    check("方形网格: 只有方图 → 读方图；只有竖图 → 退到竖版封面；都没有 → nil",
          sqGame?.squareGridImage?.size == sqGame?.squareImage?.size
          && sqGame?.squareImage != nil
          && portGame?.squareGridImage?.size == portGame?.coverImage?.size
          && portGame?.squareImage == nil
          && noSlotGame?.squareGridImage == nil)

    // 来源侧换了名字（= 换了语言）→ 同步替我建的条目要重抓图。
    // 这正是用户 2026-09-16 的反馈「标题已经是繁體中文了，封面还是英文的」：改语言后标题更新了，
    // 但旧实现从不重抓已经填过的封面。
    ExternalImportStub.install { _ in .init(status: 200, body: squarePNG) }
    _ = try await coordinator.importRecords(
        [mkDTO("T-REBRAND", "Rebrand Probe", image: "https://img.example/en.png")],
        intoAccount: nintendoA.localId, sourceLocale: "en-US", artworkFetcher: makeArtworkFetcher())
    let beforeRebrand = allGames().first { $0.allNames.contains("Rebrand Probe") }
    ExternalImportStub.install { _ in .init(status: 200, body: portraitPNG) }
    let rebrand = try await coordinator.importRecords(
        [mkDTO("T-REBRAND", "改名探测", image: "https://img.example/zh.png")],
        intoAccount: nintendoA.localId, sourceLocale: "zh-TW", artworkFetcher: makeArtworkFetcher())
    let rebranded = allGames().first { $0.allNames.contains("改名探测") }
    check("封面: 来源侧换了名字时重抓图，且**换掉**旧语言那张（不是两个槽各留一张）",
          beforeRebrand?.artwork(.square) != nil
          && rebrand.updatedRecords == 1 && rebrand.artworkRefreshed == 1
          && rebranded?.artwork(.poster)?.count == portraitPNG.count
          && rebranded?.artwork(.square) == nil)
    // 顺带：名字从拉丁换成中文时，主名里那份旧的拉丁名**留着**（它是真的英文名，有用），
    // 中文落 nameZh —— 「英文名」栏躺中文才是要修的那个毛病，反向不该发生。
    check("改名: 拉丁 → 中文时主名保留旧英文名，中文进 nameZh（两条信息并存，不互相覆盖）",
          rebranded?.name == "Rebrand Probe" && rebranded?.nameZh == "改名探测")

    // 名字没变 → 图不重抓（重抓的一轮之后必须收敛，否则每次同步都在下载）。
    ExternalImportStub.install { _ in .init(status: 200, body: portraitPNG) }
    _ = try await coordinator.importRecords(
        [mkDTO("T-REBRAND", "改名探测", image: "https://img.example/zh.png")],
        intoAccount: nintendoA.localId, sourceLocale: "zh-TW", artworkFetcher: makeArtworkFetcher())
    check("封面: 名字没变的那一轮不下载（上一次重抓是收敛的，不是每轮都抓）",
          ExternalImportStub.requests.isEmpty
          && allGames().first { $0.allNames.contains("改名探测") }?.artwork(.poster)?.count == portraitPNG.count)
    ExternalImportStub.clear()

    // 来源侧这次没给的字段不清空（PSN 对 PS3/Vita 常常不给时长）。
    _ = try await coordinator.importRecords(
        [mkDTO("T-KEEP", "Bloodborne", platform: "PS4", concept: "1000", seconds: 3_600,
               first: Date(timeIntervalSince1970: 1_600_000_000))],
        intoAccount: psnAccount.localId, sourceLocale: "en")
    _ = try await coordinator.importRecords(
        [mkDTO("T-KEEP", "Bloodborne", platform: "PS4")],
        intoAccount: psnAccount.localId, sourceLocale: "en")
    let kept = allRecords().first { $0.titleId == "T-KEEP" }
    check("导入: 来源侧这次缺的字段**不清空**（清空 = 用户库里的时长凭空消失且不可恢复）",
          kept?.playedSeconds == 3_600 && kept?.conceptId == "1000"
          && kept?.firstPlayedAt == Date(timeIntervalSince1970: 1_600_000_000))

    // 删除游戏 → 名下的外来记录被标成「已忽略」，下次同步不把它建回来。
    // 走的是**真实的那条删除路径**（`GameMerger.ignoreRecords` + `context.delete`），
    // 而不是直接 delete：直接删只会让记录变成孤儿，下次同步照样重建。
    inContext { context in
        if let goose = try context.fetch(FetchDescriptor<Game>())
            .first(where: { $0.name == "Untitled Goose Game" }) {
            GameMerger.ignoreRecords(linkedTo: goose, in: context)
            context.delete(goose)
        }
    }
    let roundTombstone = try await coordinator.importRecords(
        [mkDTO("T-NODATE", "Untitled Goose Game")],
        intoAccount: nintendoA.localId, sourceLocale: "en-GB")
    let ignoredAfterDelete = allRecords().first { $0.titleId == "T-NODATE" }
    check("导入: 用户删掉的游戏不会被下次同步建回来（记录被标成已忽略）",
          roundTombstone.ignored == 1 && roundTombstone.createdGames == 0
          && ignoredAfterDelete?.game == nil && ignoredAfterDelete?.isIgnored == true)

    // 手动忽略：用户说了「这条别再进我的库」。与「解除关联」是两件事。
    _ = try await coordinator.importRecords(
        [mkDTO("T-NOSYNC", "Ring Fit Adventure")],
        intoAccount: nintendoA.localId, sourceLocale: "en-GB")
    inContext { context in
        if let record = try context.fetch(FetchDescriptor<ExternalGameRecord>())
            .first(where: { $0.titleId == "T-NOSYNC" && $0.externalAccountId == "NA-1" }) {
            GameMerger.setIgnored(true, on: record)
            GameMerger.unbind(record)   // 忽略 ≠ 解绑，两步都做才是用户看到的那套动作
        }
    }
    let roundIgnored = try await coordinator.importRecords(
        [mkDTO("T-NOSYNC", "Ring Fit Adventure")],
        intoAccount: nintendoA.localId, sourceLocale: "en-GB")
    let nosyncRecord = allRecords().first { $0.titleId == "T-NOSYNC" && $0.externalAccountId == "NA-1" }
    check("导入: 已忽略的记录只刷新、不建库、不匹配",
          roundIgnored.ignored == 1 && roundIgnored.createdGames == 0
          && nosyncRecord?.game == nil && nosyncRecord?.isIgnored == true)

    // 撤消忽略 → 下一轮重新参加匹配与建库（这是「恢复导入」该有的效果）。
    inContext { context in
        if let record = try context.fetch(FetchDescriptor<ExternalGameRecord>())
            .first(where: { $0.titleId == "T-NOSYNC" && $0.externalAccountId == "NA-1" }) {
            GameMerger.setIgnored(false, on: record)
        }
    }
    let roundUnignored = try await coordinator.importRecords(
        [mkDTO("T-NOSYNC", "Ring Fit Adventure")],
        intoAccount: nintendoA.localId, sourceLocale: "en-GB")
    check("导入: 撤销忽略后重新参与自动匹配（可逆）",
          roundUnignored.ignored == 0 && roundUnignored.autoLinked == 1
          && allRecords().first { $0.titleId == "T-NOSYNC" }?.game != nil)

    // 来源侧不再返回的记录：标记，不删。
    let roundAbsent = try await coordinator.importRecords(
        [mkDTO("T1", "The Legend of Zelda")],
        intoAccount: nintendoA.localId, sourceLocale: "en-GB")
    let dropped = allRecords().first { $0.titleId == "T2" && $0.externalAccountId == "NA-1" }
    check("导入: 来源侧不再返回的记录标 presentInLastSync = false，**不删**",
          dropped != nil && dropped?.presentInLastSync == false && roundAbsent.absent >= 1)

    let roundEmpty = try await coordinator.importRecords([], intoAccount: nintendoA.localId)
    check("导入: 整批为空时不动 presentInLastSync（更可能是响应形状变了，不是账号被清空）",
          roundEmpty.absent == 0 && roundEmpty.processed == 0
          && allRecords().first { $0.titleId == "T1" && $0.externalAccountId == "NA-1" }?
              .presentInLastSync == true)

    // 单条坏记录不拖垮整批。
    let roundBad = try await coordinator.importRecords(
        [mkDTO("", "Broken"), mkDTO("T-OK", "Kentucky Route Zero")],
        intoAccount: nintendoA.localId, sourceLocale: "en-GB")
    check("导入: 单条 titleId 空的坏记录被跳过，同批其余记录照常入库",
          roundBad.failed == 1 && roundBad.createdRecords == 1 && roundBad.processed == 1)

    // ⑤ 手动绑定 / 解绑（`GameMerger`）。
    let bindCtx = ModelContext(importContainer)
    let celesteGame = Game(name: "Celeste", platform: "Nintendo Switch")
    let celesteRecord = ExternalGameRecord(provider: .nintendo, externalAccountId: "NA-1",
                                           titleId: "T-CELESTE", titleName: "Celeste",
                                           platform: "Nintendo Switch")
    bindCtx.insert(celesteGame); bindCtx.insert(celesteRecord)
    try? bindCtx.save()

    GameMerger.bind(celesteRecord, to: celesteGame)
    check("绑定: 手动绑定后记录挂上 Game",
          celesteRecord.game?.persistentModelID == celesteGame.persistentModelID)
    GameMerger.unbind(celesteRecord)
    check("解绑: 只摘关联 —— 可逆，不置「已忽略」（下次同步匹配上会重新自动关联）",
          celesteRecord.game == nil && celesteRecord.isIgnored == false)
    GameMerger.setIgnored(true, on: celesteRecord)
    GameMerger.bind(celesteRecord, to: celesteGame)
    check("绑定: 手动绑定顺手清掉「已忽略」（两个状态不该同时挂着）",
          celesteRecord.isIgnored == false
          && celesteRecord.game?.persistentModelID == celesteGame.persistentModelID)

    // 手动绑定过的记录，重新同步后原样保留。
    inContext { context in
        let record = try context.fetch(FetchDescriptor<ExternalGameRecord>())
            .first { $0.titleId == "T-NODATE" && $0.externalAccountId == "NA-1" }
        let restored = Game(name: "Untitled Goose Game")
        context.insert(restored)
        if let record { GameMerger.bind(record, to: restored) }
    }
    let roundManual = try await coordinator.importRecords(
        [mkDTO("T-NODATE", "Untitled Goose Game")],
        intoAccount: nintendoA.localId, sourceLocale: "en-GB")
    check("导入: 用户手动绑定的记录在重新同步后**原样保留**",
          roundManual.alreadyLinked == 1 && roundManual.createdGames == 0
          && allRecords().first { $0.titleId == "T-NODATE" }?.game != nil)

    // ⑥ 合并两个 Game。
    let mergeCtx = ModelContext(importContainer)
    let mergeTarget = Game(name: "NieR: Automata", nameZh: "尼尔：机械纪元", platform: "PS4",
                           developer: "PlatinumGames")
    let mergeSource = Game(name: "Nier Automata", aliases: ["ニーア オートマタ"],
                           platform: "PC", publisher: "Square Enix",
                           coverData: Data([0x89, 0x50, 0x4E, 0x47]),
                           reviewTitle: "神作", reviewBody: "E 结局")
    let mergeCompletion = Completion(platform: "PC", date: Date(timeIntervalSince1970: 1_700_000_000),
                                     degree: "E 结局", playtime: 60)
    let mergeCopy = PhysicalCopy(version: "数字版", count: 1)
    let mergeGroup = GameGroup(name: "白金工作室")
    let mergeRecord = ExternalGameRecord(provider: .playstation, externalAccountId: "PSN-1",
                                         titleId: "CUSA04480_00", titleName: "NieR:Automata",
                                         platform: "PS4")
    for object in [mergeTarget, mergeSource] { mergeCtx.insert(object) }
    mergeCtx.insert(mergeCompletion); mergeCtx.insert(mergeCopy)
    mergeCtx.insert(mergeGroup); mergeCtx.insert(mergeRecord)
    mergeCompletion.game = mergeSource
    mergeCopy.game = mergeSource
    mergeGroup.games = [mergeSource]
    mergeRecord.link(to: mergeSource)
    try? mergeCtx.save()

    let gamesBeforeMerge = allGames().count
    let report = GameMerger.merge(mergeSource, into: mergeTarget, in: mergeCtx)
    try? mergeCtx.save()

    check("合并: 通关记录 / 持有 / 分组 / 外部记录全部搬过去",
          report.completions == 1 && report.copies == 1 && report.groups == 1 && report.records == 1)

    let merged = allGames().first { $0.name == "NieR: Automata" }
    check("合并: 子对象改挂成功，且 source 已被删除（级联没带走任何东西）",
          allGames().count == gamesBeforeMerge - 1
          && merged?.completions.count == 1 && merged?.copies.count == 1
          && merged?.groups.count == 1 && merged?.externalRecords.count == 1
          && merged?.externalRecords.first?.game?.persistentModelID == merged?.persistentModelID)
    check("合并: 标量字段 target 优先、source 补空",
          merged?.developer == "PlatinumGames"      // target 有 → 不动
          && merged?.publisher == "Square Enix"     // target 空 → 从 source 取
          && merged?.reviewTitle == "神作" && merged?.reviewBody == "E 结局")
    check("合并: 别名取并集，source 的原名仍然搜得到",
          merged?.aliases.contains("Nier Automata") == true
          && merged?.aliases.contains("ニーア オートマタ") == true)
    check("合并: 只补缺的图（target 没封面 → 从 source 搬），别的图类不动",
          merged?.artwork(.poster)?.count == 4 && merged?.artwork(.square) == nil)

    inContext { context in
        if let same = try context.fetch(FetchDescriptor<Game>())
            .first(where: { $0.name == "NieR: Automata" }) {
            let noop = GameMerger.merge(same, into: same, in: context)
            check("合并: 自己并自己 = 空操作（不删任何东西）",
                  noop == GameMerger.MergeReport()
                  && (try? context.fetch(FetchDescriptor<Game>()))?.contains {
                      $0.persistentModelID == same.persistentModelID } == true)
        }
    }

    // ⑦ 手动绑定的弱键候选（只出列表，不改数据）。
    let suggestPool = [Game(name: "Hades II"), Game(name: "Hades"), Game(name: "Bastion")]
    let suggestProbe = ExternalGameRecord(provider: .nintendo, externalAccountId: "X",
                                          titleId: "T-X", titleName: "hades", platform: "")
    let suggested = GameMerger.suggestions(for: suggestProbe, among: suggestPool)
    check("候选建议: 全等排第一、包含排其后、无关的不出现",
          suggested.count == 2 && suggested.first?.name == "Hades"
          && suggested.last?.name == "Hades II")
    check("候选建议: 太短的标题不出候选（一个字母会匹配上半个库）",
          GameMerger.suggestions(
              for: ExternalGameRecord(provider: .nintendo, externalAccountId: "X",
                                      titleId: "T-Y", titleName: "a", platform: ""),
              among: suggestPool).isEmpty)

    // ⑧ 幂等键**先落盘**：两个不同的 ImportCoordinator 实例（= 两个 ModelContext）。
    //
    // 这是 beta 3.1「每个游戏被同步加进库两次」的回归测试，修之前必然失败：那一版的唯一
    // 一次 save 在函数最末尾、前面是上百次封面下载，于是整个导入期间 `(provider, accountId,
    // titleId)` 这个去重键都没落盘，第二个 context 什么都查不到、整批重建一遍。
    // 生产路径每次 `ExternalSyncDriver.sync` 都是一套新 context，所以**必须换实例**测。
    let idemAccount = LinkedAccount(provider: .nintendo, externalAccountId: "NA-IDEM",
                                    displayName: "幂等", sourceLocale: "en-GB")
    inContext { $0.insert(idemAccount) }
    let idemRecordsBefore = allRecords().count
    let idemGamesBefore = allGames().count
    let coordinatorA = ImportCoordinator(modelContainer: importContainer)
    let roundIdemA = try await coordinatorA.importRecords(
        [mkDTO("T-IDEM-1", "Idem One"), mkDTO("T-IDEM-2", "Idem Two")],
        intoAccount: idemAccount.localId, sourceLocale: "en-GB")
    let coordinatorB = ImportCoordinator(modelContainer: importContainer)
    let roundIdemB = try await coordinatorB.importRecords(
        [mkDTO("T-IDEM-1", "Idem One"), mkDTO("T-IDEM-2", "Idem Two")],
        intoAccount: idemAccount.localId, sourceLocale: "en-GB")
    check("导入: 换一个 ImportCoordinator 实例再导同一批 = 0 新建 / 2 刷新 / 0 建库",
          roundIdemA.createdRecords == 2 && roundIdemA.createdGames == 2
          && roundIdemB.createdRecords == 0 && roundIdemB.updatedRecords == 2
          && roundIdemB.createdGames == 0 && roundIdemB.alreadyLinked == 2
          && allRecords().count == idemRecordsBefore + 2
          && allGames().count == idemGamesBefore + 2)

    // ⑨ 自动建库的条目：状态是「未分类」、带来源标记、平台按 titleId 前缀而不是一律 Switch。
    check("导入: 自动建库的条目落在「未分类」并带 isAutoCreated 标记",
          allGames().first { $0.name == "Idem One" }?.statusValue == .unclassified
          && allGames().first { $0.name == "Idem One" }?.isAutoCreated == true)

    // ⑩ 平台识别：titleId 前缀（社区逆向归纳，不是官方文档，见 NintendoTitleId 头注释）。
    check("平台: titleId 前缀 → Wii U / Switch / Switch 2 / 未知",
          NintendoTitleId.platform(forTitleId: "0005000010101D00") == "Wii U"
          && NintendoTitleId.platform(forTitleId: "0100152000022000") == "Nintendo Switch"
          && NintendoTitleId.platform(forTitleId: "0400000000000000") == "Nintendo Switch 2"
          && NintendoTitleId.platform(forTitleId: "1234567890ABCDEF") == nil)
    // （前缀认不出来时退回来源机型的那一档由 §16 的 `9999ZZZ` 用例覆盖 —— 那要过
    //   `NintendoPlayHistoryClient` 的解析路径，比在这里直调内部类型更贴近真实。）
    _ = try await coordinatorB.importRecords(
        [mkDTO("T-PLAT", "Xenoblade Chronicles X", platform: "Nintendo Switch",
               platformRaw: "wiiu")],
        intoAccount: idemAccount.localId, sourceLocale: "en-GB")
    check("导入: 来源给的原始平台字符串落库（唯一能校对映射表的证据，丢了就永远校对不了）",
          allRecords().first { $0.titleId == "T-PLAT" }?.platformRaw == "wiiu")

    // ⑪ 清空该账号导入数据：删记录 + 删「同步替我建的、我没碰过」的条目，保留有用户数据的。
    let purgeAccount = LinkedAccount(provider: .nintendo, externalAccountId: "NA-PURGE",
                                     displayName: "清理", sourceLocale: "en-GB")
    inContext { $0.insert(purgeAccount) }
    let purgeCoordinator = ImportCoordinator(modelContainer: importContainer)
    _ = try await purgeCoordinator.importRecords(
        [mkDTO("T-PURGE-1", "Purge Fresh"), mkDTO("T-PURGE-2", "Purge Touched")],
        intoAccount: purgeAccount.localId, sourceLocale: "en-GB")
    // 用户在其中一条上写过东西（一条评价）→ 它必须被保留。
    inContext { context in
        if let touched = try context.fetch(FetchDescriptor<Game>())
            .first(where: { $0.name == "Purge Touched" }) {
            touched.reviewBody = "我自己写的"
        }
    }
    var purgeReport: ExternalAccountBinder.PurgeReport?
    let purgeRunContext = ModelContext(importContainer)
    if let account = try? purgeRunContext.fetch(FetchDescriptor<LinkedAccount>())
        .first(where: { $0.externalAccountId == "NA-PURGE" }) {
        purgeReport = try? ExternalAccountBinder.purgeImportedData(account, in: purgeRunContext)
    }
    check("清空: 删掉该账号的记录与「同步替我建的」条目，保留用户写过数据的条目",
          purgeReport?.deletedRecords == 2 && purgeReport?.deletedGames == 1
          && purgeReport?.keptGames == 1
          && allRecords().allSatisfy { $0.externalAccountId != "NA-PURGE" }
          && allGames().contains { $0.name == "Purge Touched" }
          && !allGames().contains { $0.name == "Purge Fresh" })
    check("清空: 保留的条目不会变成孤儿 —— 它只是没有来源记录了（重新同步会再匹配上）",
          allAccounts().contains { $0.externalAccountId == "NA-PURGE" })

    // ⑫ 清空：一个 Game 挂着**多条**记录时，「同秒指纹」必须认任意一条。
    //
    // 真机现场：两批导入各建了一套记录，其中一套被强键（titleId）关联到另一套建出来的那个
    // Game 上 —— 于是它挂着两条 `firstSeenAt` 不同的记录。旧实现只拿「先取到的那条」去比指纹，
    // 那条恰好不同秒，于是判定「这是用户自己的条目」并保留，留下一个没被清掉的导入条目
    // （真机上就是那个 Bayonetta）。
    let multiAccount = LinkedAccount(provider: .nintendo, externalAccountId: "NA-PURGE-2",
                                     displayName: "清理2", sourceLocale: "en-GB")
    inContext { $0.insert(multiAccount) }
    let multiCoordinator = ImportCoordinator(modelContainer: importContainer)
    _ = try await multiCoordinator.importRecords(
        [mkDTO("T-PURGE-3", "Purge Multi")],
        intoAccount: multiAccount.localId, sourceLocale: "en-GB")
    inContext { context in
        guard let game = try context.fetch(FetchDescriptor<Game>())
                .first(where: { $0.name == "Purge Multi" }),
              let first = try context.fetch(FetchDescriptor<ExternalGameRecord>())
                .first(where: { $0.titleId == "T-PURGE-3" }) else { return }
        // 还原 bug 时代的两个特征：条目没有来源标记（那时字段还不存在，只能靠指纹认），
        // 且先取到的那条记录与 Game 不同秒。
        game.isAutoCreated = false
        first.firstSeenAt = game.createdAt.addingTimeInterval(-70)
        let mate = ExternalGameRecord(provider: .nintendo, externalAccountId: "NA-PURGE-2",
                                      titleId: "T-PURGE-3", titleName: "Purge Multi",
                                      platform: "Nintendo Switch",
                                      firstSeenAt: game.createdAt)
        context.insert(mate)
        mate.game = game
    }
    var multiReport: ExternalAccountBinder.PurgeReport?
    let multiRunContext = ModelContext(importContainer)
    if let account = try? multiRunContext.fetch(FetchDescriptor<LinkedAccount>())
        .first(where: { $0.externalAccountId == "NA-PURGE-2" }) {
        multiReport = try? ExternalAccountBinder.purgeImportedData(account, in: multiRunContext)
    }
    check("清空: 同一 Game 挂多条记录时，同秒指纹认其中任意一条（旧实现漏掉一个条目）",
          multiReport?.deletedRecords == 2 && multiReport?.deletedGames == 1
          && !allGames().contains { $0.name == "Purge Multi" })

    // ⑫b 空壳清理（`pruneOrphanImportGames` / `pruneIfOrphaned`）—— 绑定 / 解绑 / 同步把记录
    // 改指之后，替导入把地上的碎屑捡掉。**这是本批唯一一处会删数据的改动**，所以五条边界
    // 各立一个用例：每一条判错的方向都是「删掉用户的东西」。
    //
    // 真库干跑核对（2026-09-17，本机 385 个条目的只读副本）：全库恰好只有 1 个条目同时满足
    // 「isAutoCreated + 0 记录指向 + 无用户数据」，正是用户报的那条 PS3「龍が如く2」
    // （Z_PK 806，unclassified，0 通关记录 / 0 持有 / 0 分组 / 非最爱 / 无别名 / 无评价 /
    // 只有 coverData）—— 另 384 个条目一条都不会动。
    do {
        let pruneContext = ModelContext(importContainer)
        // 造一个「导入自动建的」空壳：`makeGame` 建出来的样子（unclassified + isAutoCreated）。
        func shell(_ name: String) -> Game {
            let game = Game(name: name, platform: "PlayStation 3",
                            status: .unclassified, isAutoCreated: true)
            pruneContext.insert(game)
            return game
        }
        _ = shell("Prune 空壳")
        // 导入自己会写这两个封面槽（`ImportCoordinator.fetchArtwork`），所以**有封面不能算
        // 「用户经手过」** —— 2026-09-18 用户报的那 5 个僵尸条目个个都是「方形槽有图、其余
        // 三槽全空」，旧判据把它们全判成用户数据、一个都清不掉。这两条是那次修正的钉子。
        let covered = shell("Prune 只有方形封面")
        covered.setArtwork(.square, Data([0x89, 0x50, 0x4E, 0x47]))
        let postered = shell("Prune 只有竖版封面")
        postered.setArtwork(.poster, Data([0x89, 0x50, 0x4E, 0x47]))
        // 反面：横向 / 背景 / Logo 导入**从不写**，有图就只可能是用户自己挑的 → 留。
        let landscaped = shell("Prune 有横向图")
        landscaped.setArtwork(.landscape, Data([0x89, 0x50, 0x4E, 0x47]))
        shell("Prune 想玩").statusValue = .backlog
        shell("Prune 有日期").releaseDate = Date(timeIntervalSince1970: 0)
        pruneContext.insert(Game(name: "Prune 用户自建", platform: "PlayStation 3"))
        let referenced = shell("Prune 仍有记录")
        let mate = ExternalGameRecord(provider: .playstation, externalAccountId: "PSN-PRUNE",
                                      titleId: "T-PRUNE", titleName: "Prune 仍有记录",
                                      platform: "PlayStation 3")
        pruneContext.insert(mate)
        mate.game = referenced
        try? pruneContext.save()

        let pruned = (try? ExternalAccountBinder.pruneOrphanImportGames(in: pruneContext)) ?? -1
        check("空壳清理: 自动建 + 0 记录 + 无用户数据 → **删**（用户报的「合并了但库里还是两条」）",
              pruned == 3 && !allGames().contains { $0.name == "Prune 空壳" })
        check("空壳清理: 只有**方形**封面不算用户数据 → 删（导入自己写的槽，旧判据在这里漏了 5 条）",
              !allGames().contains { $0.name == "Prune 只有方形封面" })
        check("空壳清理: 只有**竖版**封面同样不算用户数据 → 删",
              !allGames().contains { $0.name == "Prune 只有竖版封面" })
        check("空壳清理: **横向图**是用户自己挑的 → 留（导入从不写这三类图）",
              allGames().contains { $0.name == "Prune 有横向图" })
        check("空壳清理: 自动建但**用户设过状态**（想玩）→ 留 —— 旧判据会把它当空壳删掉",
              allGames().contains { $0.name == "Prune 想玩" })
        check("空壳清理: 自动建但**填过发行日期** → 留（导入从不写这四个元数据）",
              allGames().contains { $0.name == "Prune 有日期" })
        check("空壳清理: `isAutoCreated == false` 的用户自建条目 + 0 记录 → 留（硬门）",
              allGames().contains { $0.name == "Prune 用户自建" })
        check("空壳清理: 自动建但**仍有记录指向它** → 留",
              allGames().contains { $0.name == "Prune 仍有记录" })

        // 单条版本（绑定 / 解绑用）与全库版本同源：同一条空壳，单条判定也认。
        let singleContext = ModelContext(importContainer)
        let single = Game(name: "Prune 单条", platform: "PlayStation 3",
                          status: .unclassified, isAutoCreated: true)
        singleContext.insert(single)
        try? singleContext.save()
        let removed = (try? ExternalAccountBinder.pruneIfOrphaned(single, in: singleContext)) ?? false
        check("空壳清理: 单条版本（绑定/解绑路径）与全库版本同源 —— 同样认得出、删得掉",
              removed && !allGames().contains { $0.name == "Prune 单条" })
        // 反向：用户自建的条目在单条路径下也绝不删。
        let singleUser = Game(name: "Prune 单条用户", platform: "PlayStation 3")
        singleContext.insert(singleUser)
        try? singleContext.save()
        check("空壳清理: 单条版本对用户自建条目返回 false（硬门在两条路径上是同一个）",
              (try? ExternalAccountBinder.pruneIfOrphaned(singleUser, in: singleContext)) == false
              && allGames().contains { $0.name == "Prune 单条用户" })
    }

    // ⑫c 回归：新收紧的判据不该把「导入建、但我设成了想玩」的条目当空壳删掉。
    // 上面那条 `statusValue == .unclassified` 同时修掉了 `purgeImportedData` 的这个漏洞。
    let backlogAccount = LinkedAccount(provider: .nintendo, externalAccountId: "NA-PURGE-3",
                                       displayName: "清理3", sourceLocale: "en-GB")
    inContext { context in
        context.insert(backlogAccount)
        let game = Game(name: "Purge Backlog", platform: "Nintendo Switch",
                        status: .unclassified, isAutoCreated: true)
        context.insert(game)
        game.statusValue = .backlog
        let record = ExternalGameRecord(provider: .nintendo, externalAccountId: "NA-PURGE-3",
                                        titleId: "T-PURGE-3", titleName: "Purge Backlog",
                                        platform: "Nintendo Switch")
        context.insert(record)
        record.game = game
    }
    var backlogReport: ExternalAccountBinder.PurgeReport?
    let backlogRunContext = ModelContext(importContainer)
    if let account = try? backlogRunContext.fetch(FetchDescriptor<LinkedAccount>())
        .first(where: { $0.externalAccountId == "NA-PURGE-3" }) {
        backlogReport = try? ExternalAccountBinder.purgeImportedData(account, in: backlogRunContext)
    }
    check("清空: 「导入建但我设成了想玩」的条目**不再**被当空壳删掉（弹窗承诺的是保留）",
          backlogReport?.deletedRecords == 1 && backlogReport?.deletedGames == 0
          && backlogReport?.keptGames == 1
          && allGames().contains { $0.name == "Purge Backlog" })

    // ⑫d 收走「已被游玩记录覆盖的奖杯记录」（`removeSupersededRecords`）。
    //
    // 这是用户 2026-09-18 拍板的**全清**：旧规则在真账号上造出 6 条跨世代幽灵记录
    // （PS3,PS4 共用一个奖杯套 → 被当成 PS3 游戏多建一条），其中 2 条用户自己绑过。
    // 用户明确选择「连我绑过的那 2 条一起清」—— 所以这里的用例要**钉住它确实会删已绑定的记录**，
    // 不能只测「删没绑的」，否则将来有人把「已绑定就保留」当成善意补丁加回来，本用例不会响。
    do {
        let supersedeContext = ModelContext(importContainer)
        let bound = Game(name: "Supersede 已绑定", platform: "PlayStation 3")
        supersedeContext.insert(bound)
        // ① 本账号 + 认领集合里 + 遗留平台 → **删**（哪怕用户绑过）。
        let boundLegacy = ExternalGameRecord(provider: .playstation,
                                             externalAccountId: "PSN-SUPERSEDE",
                                             titleId: "NPWR07319_00", titleName: "龍が如く０",
                                             platform: "PS3")
        supersedeContext.insert(boundLegacy)
        boundLegacy.game = bound
        // ② 本账号 + 认领集合里 + Vita → **删**。
        let vita = ExternalGameRecord(provider: .playstation,
                                      externalAccountId: "PSN-SUPERSEDE",
                                      titleId: "NPWR07057_00", titleName: "P4G",
                                      platform: "PS Vita")
        supersedeContext.insert(vita)
        // ③ 本账号但**不在**认领集合里 → 留（这是「只在 PS3 上玩过」的真记录）。
        let unclaimed = ExternalGameRecord(provider: .playstation,
                                           externalAccountId: "PSN-SUPERSEDE",
                                           titleId: "NPWR00845_00", titleName: "Resistance",
                                           platform: "PS3")
        supersedeContext.insert(unclaimed)
        // ④ 本账号 + 认领集合里但平台是 PS4 → 留（纵深：这条路径只管遗产平台，
        //    正常的 PS4/PS5 记录归别的机制管，越界删会吃掉整整一代的游玩记录）。
        let modern = ExternalGameRecord(provider: .playstation,
                                        externalAccountId: "PSN-SUPERSEDE",
                                        titleId: "CUSA01174_00", titleName: "人中之龍０",
                                        platform: "PS4")
        supersedeContext.insert(modern)
        // ⑤ **另一个账号**的同 titleId 记录 → 留（每个账号的奖杯进度是各自的）。
        let otherAccount = ExternalGameRecord(provider: .playstation,
                                              externalAccountId: "PSN-OTHER",
                                              titleId: "NPWR07319_00", titleName: "龍が如く０",
                                              platform: "PS3")
        supersedeContext.insert(otherAccount)
        try? supersedeContext.save()

        let claims: Set<String> = ["NPWR07319_00", "NPWR07057_00", "CUSA01174_00"]
        let removed = (try? ExternalAccountBinder.removeSupersededRecords(
            titleIds: claims, provider: .playstation,
            externalAccountId: "PSN-SUPERSEDE", in: supersedeContext)) ?? -1
        let left = (try? supersedeContext.fetch(FetchDescriptor<ExternalGameRecord>())) ?? []
            .filter { $0.isLive }
        func stillThere(_ id: String, _ account: String) -> Bool {
            left.contains { $0.titleId == id && $0.externalAccountId == account }
        }
        check("收走: 本账号 + 已认领 + 遗留平台 → 删，**包括用户亲手绑过的那条**（用户选的全清）",
              removed == 2 && !stillThere("NPWR07319_00", "PSN-SUPERSEDE"))
        check("收走: PS Vita 记录同样算遗产平台",
              !stillThere("NPWR07057_00", "PSN-SUPERSEDE"))
        check("收走: 不在认领集合里的 PS3 记录一条不动（「只在 PS3 上玩过」的真记录）",
              stillThere("NPWR00845_00", "PSN-SUPERSEDE"))
        check("收走: 认领集合里的 PS4 记录不动 —— 这条路径只清遗留平台，不越界吃现代记录",
              stillThere("CUSA01174_00", "PSN-SUPERSEDE"))
        check("收走: 另一个账号的同 titleId 记录不动（奖杯进度是按账号算的）",
              stillThere("NPWR07319_00", "PSN-OTHER"))
        check("收走: 被收走的记录原来指向的条目留着（游戏条目归空壳清理管，两条路径不重叠）",
              allGames().contains { $0.name == "Supersede 已绑定" })

        // 认领集合为空 = 名字那一遍与按 id 那一路都没认下任何套 → 一条都不删。
        // （`claimedTrophySets` 为空是常态：Nintendo 账号、或奖杯接口整个没取到时。）
        let emptyRemoved = (try? ExternalAccountBinder.removeSupersededRecords(
            titleIds: [], provider: .playstation,
            externalAccountId: "PSN-OTHER", in: supersedeContext)) ?? -1
        check("收走: 认领集合为空 → 0，一条都不删（接口没取到时不能顺手清库）",
              emptyRemoved == 0)
    }

    // ⑬ 卡片删除守卫的判据：**`isDeleted` 守不住，`isLive` 才守得住**。
    //
    // 这不是吹毛求疵。`context.delete(x)` 之后 `isDeleted == true`，但 `save()` 之后它会
    // **翻回 false**，而那一刻模型才真正销毁 —— 刚好是唯一需要守卫的时刻。真机崩溃
    // （2026-09-16）与随后的独立探针都验证过：删除落盘后读 `coverData` 直接
    // `Fatal error: This backing data was detached from a context without resolving
    // attribute faults`。探针**不**放进本套件 —— 它会 abort 掉整个进程。
    let doomedContext = ModelContext(importContainer)
    let doomed = Game(name: "Deleted Probe")
    doomedContext.insert(doomed)
    try? doomedContext.save()
    check("删除守卫: 活着的模型 isLive == true（守卫据此放行正常渲染）", doomed.isLive)
    doomedContext.delete(doomed)
    try? doomedContext.save()
    check("删除守卫: save 之后 isLive 翻 false（卡片据此跳过渲染，不去读已销毁的属性）",
          !doomed.isLive)
    check("删除守卫: 同一刻 isDeleted 已经是 false —— 拿它写守卫等于没写",
          !doomed.isDeleted)
}

// --- 19. 奖杯层（PSN）：平台映射 / 宽松解码 / 合并规则 / 语言阶梯 ---
//
// 这一段是「PS3 / PS Vita 补全 + 奖杯数量」两件事的唯一自动化证据 —— 真账号那一步必须
// 用户操作（见 HANDOVER 待验证项）。合并规则里每一条都是「猜错就往库里写错数据」的判断，
// 所以四条各立一个用例，而不是合成一个大 case。
do {
    // ① 平台映射：`trophyTitlePlatform` 可以是逗号分隔的多值，认不出的**只丢那一项**。
    check("奖杯: \"PS5\" → [PS5]", PSNAPI.platforms(forTrophyPlatform: "PS5") == ["PS5"])
    check("奖杯: \"PS3\" → [PS3]（gamelist 覆盖不到的那个平台）",
          PSNAPI.platforms(forTrophyPlatform: "PS3") == ["PS3"])
    check("奖杯: \"VITA\" → [PS Vita]", PSNAPI.platforms(forTrophyPlatform: "VITA") == ["PS Vita"])
    check("奖杯: \"PS4,PSVITA\" → [PS4, PS Vita]（跨平台共用奖杯套，顺序保留）",
          PSNAPI.platforms(forTrophyPlatform: "PS4,PSVITA") == ["PS4", "PS Vita"])
    check("奖杯: 列表里认不出的那一项只丢自己，不牵连旁边的 PS4",
          PSNAPI.platforms(forTrophyPlatform: "PS4,PS9") == ["PS4"])
    check("奖杯: 去重（\"PS4,ps4\" 只要一个）",
          PSNAPI.platforms(forTrophyPlatform: "PS4,ps4") == ["PS4"])
    check("奖杯: 空 / 纯空白 → 空数组（兜底是调用方的决定，不是解析层的）",
          PSNAPI.platforms(forTrophyPlatform: nil).isEmpty
          && PSNAPI.platforms(forTrophyPlatform: "   ").isEmpty)

    // ①b 奖杯卡头部那两行：平台列表 + 来源编号（`ExternalGameRecord` 上的两个派生属性）。
    // 这两个值直接出现在用户眼前（「PS3/PS4 · NPWR-08547」），所以每一档形状都钉一条。
    func psnRecord(titleId: String, platform: String, platformRaw: String?) -> ExternalGameRecord {
        ExternalGameRecord(provider: .playstation, externalAccountId: "PSN-T",
                           titleId: titleId, titleName: "T", platform: platform,
                           platformRaw: platformRaw)
    }
    check("平台列表: 真库里的 \"PS3,PS4\" → PS3/PS4（用户点名的港版人中之龙 0）",
          psnRecord(titleId: "NPWR08547_00", platform: "PS3", platformRaw: "PS3,PS4")
              .psnPlatformDisplay == "PS3/PS4")
    check("平台列表: \"PSVITA,PS4\" → PS Vita/PS4（真库里 2 条）",
          psnRecord(titleId: "X", platform: "PS Vita", platformRaw: "PSVITA,PS4")
              .psnPlatformDisplay == "PS Vita/PS4")
    check("平台列表: \"PS3,PSVITA\" → PS3/PS Vita",
          psnRecord(titleId: "X", platform: "PS3", platformRaw: "PS3,PSVITA")
              .psnPlatformDisplay == "PS3/PS Vita")
    check("平台列表: 认不出的那一项只丢自己（\"PS4,PS9\" → PS4）",
          psnRecord(titleId: "X", platform: "PS4", platformRaw: "PS4,PS9")
              .psnPlatformDisplay == "PS4")
    check("平台列表: 不带逗号的 gamelist category（\"ps4_game\"）照样认得出 → PS4",
          psnRecord(titleId: "X", platform: "PS4", platformRaw: "ps4_game")
              .psnPlatformDisplay == "PS4")
    check("平台列表: 不带逗号的奖杯单值（\"PSVITA\"）也认得出 → PS Vita",
          psnRecord(titleId: "X", platform: "PS Vita", platformRaw: "PSVITA")
              .psnPlatformDisplay == "PS Vita")
    check("平台列表: 两种形状都认不出（\"unknown\"）退回折算后的 platform，绝不返回空",
          psnRecord(titleId: "X", platform: "PS4", platformRaw: "unknown")
              .psnPlatformDisplay == "PS4")
    check("平台列表: platformRaw 为 nil 时退回 platform",
          psnRecord(titleId: "X", platform: "PS5", platformRaw: nil)
              .psnPlatformDisplay == "PS5")
    check("平台列表: Nintendo 记录没有这一行（返回 nil，卡片不渲染副标题）",
          ExternalGameRecord(provider: .nintendo, externalAccountId: "NA-T",
                             titleId: "0100000000010000", titleName: "T",
                             platform: "Nintendo Switch").psnPlatformDisplay == nil)

    check("编号美化: CUSA01887_00 → CUSA-01887（用户点名的港版人中之龙 0 编号）",
          psnRecord(titleId: "CUSA01887_00", platform: "PS4", platformRaw: nil)
              .titleCodeDisplay == "CUSA-01887")
    check("编号美化: NPWR08547_00 → NPWR-08547（奖杯套编号）",
          psnRecord(titleId: "NPWR08547_00", platform: "PS3", platformRaw: nil)
              .titleCodeDisplay == "NPWR-08547")
    check("编号美化: PCAS05139_00 → PCAS-05139（港版 PS4 TLOU 2）",
          psnRecord(titleId: "PCAS05139_00", platform: "PS4", platformRaw: nil)
              .titleCodeDisplay == "PCAS-05139")
    check("编号美化: ECAS00056_00 → ECAS-00056（港版 PS5 TLOU 2）",
          psnRecord(titleId: "ECAS00056_00", platform: "PS5", platformRaw: nil)
              .titleCodeDisplay == "ECAS-00056")
    check("编号美化: 没有数字段的形状原样返回，不猜",
          psnRecord(titleId: "NPWR", platform: "PS3", platformRaw: nil)
              .titleCodeDisplay == "NPWR")
    check("编号美化: 已经带连字符的原样返回（不插第二个）",
          psnRecord(titleId: "CUSA-01887", platform: "PS4", platformRaw: nil)
              .titleCodeDisplay == "CUSA-01887")
    check("编号美化: Nintendo 的十六进制 titleId 原样返回（字母段之后又出现数字，形状不合）",
          ExternalGameRecord(provider: .nintendo, externalAccountId: "NA-T",
                             titleId: "0100000000ABCD00", titleName: "T",
                             platform: "Nintendo Switch").titleCodeDisplay == "0100000000ABCD00")
    check("编号美化: 全数字的 titleId 原样返回（没有字母段）",
          psnRecord(titleId: "0100000000010000", platform: "PS4", platformRaw: nil)
              .titleCodeDisplay == "0100000000010000")

    // ①c 来源记录的平台并入 `platformList`（用户 2026-09-18：「一个本身没有 PS 的游戏在绑定了
    // PS 记录后应当也将 PS 视为一个平台」）。**派生值**：跟着绑定关系走，不动用户填的主平台 ——
    // 所以解绑之后平台会自动消失，不会留下一个说不通的「PS4 游戏」。
    do {
        let platformContext = ModelContext(container)
        let merged = Game(name: "Platform Merge", platform: "Xbox One")
        platformContext.insert(merged)
        let ps4 = ExternalGameRecord(provider: .playstation, externalAccountId: "PSN-PLAT",
                                     titleId: "CUSA01174_00", titleName: "人中之龍０",
                                     platform: "PS4")
        let ps3 = ExternalGameRecord(provider: .playstation, externalAccountId: "PSN-PLAT",
                                     titleId: "NPWR07319_00", titleName: "龍が如く０",
                                     platform: "PS3")
        platformContext.insert(ps4)
        platformContext.insert(ps3)
        ps4.game = merged
        ps3.game = merged
        try? platformContext.save()

        check("平台: 绑了 PS 记录后平台列表里有 PS4/PS3（用户只填了 Xbox One）—— 按平台筛选不再隐形",
              merged.platformList == ["Xbox One", "PS4", "PS3"])
        check("平台: 主平台字段本身**没被改**（派生，不写回用户的声明）",
              merged.platform == "Xbox One")

        ps4.game = nil
        ps3.game = nil
        try? platformContext.save()
        check("平台: 解绑后 PS4/PS3 从列表里消失（不会留下一个说不通的平台）",
              merged.platformList == ["Xbox One"])

        // 回归：主平台与来源平台**不是同一个值**时不会重复（去重靠 `Presets.ordered`）。
        let native = Game(name: "Platform Native", platform: "PS4")
        platformContext.insert(native)
        let nativeRecord = ExternalGameRecord(provider: .playstation,
                                              externalAccountId: "PSN-PLAT",
                                              titleId: "CUSA05070_00", titleName: "人中之龍０",
                                              platform: "PS4")
        platformContext.insert(nativeRecord)
        nativeRecord.game = native
        try? platformContext.save()
        check("平台: 主平台与来源平台相同时只出现一次（不会变成两个 PS4）",
              native.platformList == ["PS4"])

        // 用户 2026-09-18 点名的场景：**一个 Switch 条目绑了 PSN 的 PS Vita 奖杯记录**
        // （他的 Persona 4 Golden：Vita 奖杯套 `NPWR03761_00` 绑在自动建的 Switch 条目上）。
        // 要求是「这个条目就要也被视为 PS Vita 游戏」—— 来源记录的平台是 "PS Vita"，
        // 所以派生的那一路上来就对，这里把它钉死。
        let hybrid = Game(name: "Platform Hybrid", platform: "Nintendo Switch")
        platformContext.insert(hybrid)
        let vita = ExternalGameRecord(provider: .playstation, externalAccountId: "PSN-PLAT",
                                      titleId: "NPWR03761_00", titleName: "Persona 4 The GOLDEN",
                                      platform: "PS Vita", platformRaw: "PSVITA")
        platformContext.insert(vita)
        vita.game = hybrid
        try? platformContext.save()
        check("平台: Switch 条目绑了 PSN 的 PS Vita 奖杯记录后，也算 PS Vita 游戏",
              hybrid.platformList == ["Nintendo Switch", "PS Vita"])
        check("平台: 那条 Vita 记录的卡片副标题读的是 PS Vita（不是 PVITA 之类的原始值）",
              vita.psnPlatformDisplay == "PS Vita")
        check("平台: 主平台仍是 Nintendo Switch（派生不写回）", hybrid.platform == "Nintendo Switch")
    }

    // ② 宽松解码 + 计数归一。数字用 `Double` 收，缺字段按 0，platinum 夹到 0/1。
    let lenientJSON = """
    {"trophyTitles":[
      {"npCommunicationId":"NPWR00001_00","trophyTitleName":"宽松用例",
       "trophyTitleIconUrl":"https://img.example/n1.png","trophyTitlePlatform":"PS3",
       "definedTrophies":{"bronze":4.6,"gold":1,"platinum":5},
       "earnedTrophies":{"bronze":1,"silver":2},
       "progress":11.5,"hiddenFlag":false,"lastUpdatedDateTime":"2026-01-01T00:00:00Z"}
    ],"totalItemCount":1}
    """
    let lenientPage = try? ExternalHTTPClient.decode(PSNAPI.TrophyTitlesResponse.self,
                                                     from: Data(lenientJSON.utf8))
    check("奖杯: 字段缺失 / 数字是浮点都解得出来（宽松解析，不因一处结构变动整次同步失败）",
          lenientPage?.trophyTitles?.count == 1)
    let lenientEntry = lenientPage?.trophyTitles?.first
    let lenientProgress = PSNAPI.trophyProgress(defined: lenientEntry?.definedTrophies,
                                                earned: lenientEntry?.earnedTrophies,
                                                percent: lenientEntry?.progress)
    check("奖杯: 缺的等级按 0 算，浮点四舍五入（4.6 → 5）",
          lenientProgress?.bronzeDefined == 5 && lenientProgress?.goldDefined == 1
          && lenientProgress?.silverDefined == 0)
    check("奖杯: platinum 夹到 0/1（服务端给 5 也不当真）",
          lenientProgress?.platinumDefined == 1)
    check("奖杯: 浮点百分比收得下（11.5 → 12）", lenientProgress?.displayPercent == 12)
    check("奖杯: defined / earned **都缺** → nil（= 来源没有奖杯数据），而不是一个全 0 的值",
          PSNAPI.trophyProgress(defined: nil, earned: nil, percent: 30) == nil)
    check("奖杯: 全 0 是合法状态（有奖杯套但一个没拿），必须给值 —— 否则「0/42」会显示成「—」",
          PSNAPI.trophyProgress(defined: PSNAPI.TrophyCounts(bronze: 42, silver: nil,
                                                            gold: nil, platinum: nil),
                               earned: PSNAPI.TrophyCounts(bronze: 0, silver: 0,
                                                           gold: 0, platinum: 0),
                               percent: 0) != nil)
    check("奖杯: 来源没给百分比时按计数现算（0/42 → 0%）",
          PSNAPI.trophyProgress(defined: PSNAPI.TrophyCounts(bronze: 40, silver: nil,
                                                            gold: nil, platinum: nil),
                               earned: PSNAPI.TrophyCounts(bronze: 10, silver: nil,
                                                           gold: nil, platinum: nil),
                               percent: nil)?.displayPercent == 25)
    check("奖杯: 来源给了百分比就用来源的（索尼自己算的，与计数不一致也照实显示）",
          PSNAPI.trophyProgress(defined: PSNAPI.TrophyCounts(bronze: 40, silver: nil,
                                                            gold: nil, platinum: nil),
                               earned: PSNAPI.TrophyCounts(bronze: 10, silver: nil,
                                                           gold: nil, platinum: nil),
                               percent: 99)?.displayPercent == 99)

    // ③ 合并规则。四条各一个用例。
    func gDTO(_ titleId: String, _ name: String, _ platform: String) -> ExternalGameRecordDTO {
        ExternalGameRecordDTO(titleId: titleId, titleName: name, platform: platform)
    }
    /// 用 JSON 造条目（顺带把解码也过一遍，不手搓 memberwise init）。
    func trophyEntryJSON(_ id: String, _ name: String, _ platform: String,
                         earnedBronze: Double = 2, hidden: Bool = false) -> Data {
        Data("""
        {"npCommunicationId":"\(id)","trophyTitleName":"\(name)",
         "trophyTitleIconUrl":"https://img.example/\(id).png",
         "trophyTitlePlatform":"\(platform)",
         "definedTrophies":{"bronze":10,"silver":4,"gold":2,"platinum":1},
         "earnedTrophies":{"bronze":\(earnedBronze),"silver":1,"gold":0,"platinum":0},
         "progress":15,"hiddenFlag":\(hidden)}
        """.utf8)
    }
    func trophyEntry(_ id: String, _ name: String, _ platform: String,
                     earnedBronze: Double = 2, hidden: Bool = false) -> PSNAPI.TrophyTitleEntry? {
        try? ExternalHTTPClient.decode(PSNAPI.TrophyTitleEntry.self,
                                       from: trophyEntryJSON(id, name, platform,
                                                             earnedBronze: earnedBronze,
                                                             hidden: hidden))
    }

    // ③-1 PS3 标题：gamelist 里没有 → **新建**一条记录（这正是「PS3 游戏一条都没有」的修法）。
    //
    // 合并现在是两遍（`attachByName` → `finish`），与 `ExternalSyncDriver.fetchRecords` 的分工
    // 逐字一致 —— 下面这个 helper 就是那三步里的前两步，`byTitleId` 默认空（= 按 id 那一路
    // 没取到任何东西），需要它的用例自己传。
    func mergeAll(_ gamelist: [ExternalGameRecordDTO], _ trophies: [PSNAPI.TrophyTitleEntry],
                  byTitleId: [String: PSNTrophyService.TitleTrophies] = [:]
    ) -> PSNTrophyService.MergeOutcome {
        PSNTrophyService.finish(PSNTrophyService.attachByName(gamelist: gamelist, trophies: trophies),
                                trophies: trophies, byTitleId: byTitleId)
    }
    let ps3Entries = [trophyEntry("NPWR00845_00", "Resistance: Fall of Man", "PS3")].compactMap { $0 }
    let ps3Merged = mergeAll([gDTO("CUSA00001_00", "Astro Bot", "PS5")], ps3Entries).records
    let ps3New = ps3Merged.first { $0.titleId == "NPWR00845_00" }
    check("奖杯: PS3 标题**新建**记录，titleId 用 npCommunicationId",
          ps3Merged.count == 2 && ps3New?.platform == "PS3")
    check("奖杯: 新建的 PS3 记录带上奖杯、图标，且时长/次数为 nil（索尼不提供，不是 0）",
          ps3New?.trophies?.earnedTotal == 3 && ps3New?.imageURLString == "https://img.example/NPWR00845_00.png"
          && ps3New?.playedSeconds == nil && ps3New?.playCount == nil)
    check("奖杯: 新记录排到末尾（两个时间都是 nil，按「最近游玩优先」自然沉底）",
          ps3Merged.first?.titleId == "CUSA00001_00")

    // ③-2 PS4 标题：gamelist 里已有同名同平台的记录 → **贴上去，不新建**。
    let ps4Merged = mergeAll(
        [gDTO("CUSA01433_00", "Rocket League", "PS4")],
        [trophyEntry("NPWR00002_00", "Rocket League", "PS4")].compactMap { $0 }).records
    check("奖杯: PS4 标题贴到已有记录上，**不新建**（否则会在面板里显示成重复导入）",
          ps4Merged.count == 1 && ps4Merged[0].trophies?.earnedTotal == 3)

    // ③-3 同名但平台对不上：PS5 的奖杯套不能贴到 PS4 那条记录上。
    let crossMerged = mergeAll(
        [gDTO("CUSA01433_00", "Rocket League", "PS4")],
        [trophyEntry("PPSA00003_00", "Rocket League", "PS5")].compactMap { $0 }).records
    check("奖杯: 同名但平台不符 → **一条都不贴**（PS4/PS5 是两个独立的奖杯套，贴错就是脏数据）",
          crossMerged.count == 1 && crossMerged[0].trophies == nil)

    // ③-4 同名同平台有两条记录 → 不唯一，一条都不贴。
    let ambiguousMerged = mergeAll(
        [gDTO("CUSA01433_00", "Rocket League", "PS4"),
         gDTO("CUSA01434_00", "Rocket League", "PS4")],
        [trophyEntry("NPWR00004_00", "Rocket League", "PS4")].compactMap { $0 }).records
    check("奖杯: 匹配到多条 → 一条都不贴（宁可显示「—」，也不给一份不知道属于哪条的进度）",
          ambiguousMerged.count == 2 && ambiguousMerged.allSatisfy { $0.trophies == nil })

    // ③-5 归一化口径与 GameLinker 一致：大小写/标点/全半角不同也算同一个名字。
    let looseMerged = mergeAll(
        [gDTO("CUSA01433_00", "ROCKET LEAGUE™", "PS4")],
        [trophyEntry("NPWR00005_00", "rocket-league", "PS4")].compactMap { $0 }).records
    check("奖杯: 名字归一化走 GameLinker 那一套（与「自动关联到已有游戏」同一口径）",
          looseMerged[0].trophies != nil)

    // ③-6 用户在奖杯列表里隐藏了的标题整条跳过（那是显式动作）。
    let hiddenMerged = mergeAll(
        [],
        [trophyEntry("NPWR00846_00", "Hidden Game", "PS3", hidden: true)].compactMap { $0 }).records
    check("奖杯: hiddenFlag == true 的标题整条跳过（包括不贴到已有记录）",
          hiddenMerged.isEmpty)

    // ③-7 已经在 gamelist 里的 titleId 不会被再建一条（防自撞保险）。
    let dupMerged = mergeAll([gDTO("NPWR00845_00", "别的名字", "Nintendo Switch")],
                             ps3Entries).records
    check("奖杯: titleId 已存在就不再新建一条（同一个键落两次会自撞）",
          dupMerged.count == 1)

    // ③-8 **规则 ④：已经被游玩记录认领的奖杯套，一条记录都不建。**
    //
    // 这是用户 2026-09-18 报的「龍が如く０ 读到的不是 CUSA01174 而是 NPWR07319」的修法。
    // 取名与平台都照真库取证抄：gamelist 给的名字是商店商品名（中文），与奖杯套名（日文）
    // 归一化后对不上，所以名字那一遍认不下；真正把它认下来的是按 id 取奖杯那一路。
    let yakuzaZeroTrophies = [trophyEntry("NPWR07319_00", "龍が如く０　誓いの場所",
                                           "PS3,PS4", earnedBronze: 1)].compactMap { $0 }
    let yakuzaZeroClaims = ["CUSA01174_00": PSNTrophyService.TitleTrophies(
        progress: PSNAPI.trophyProgress(defined: PSNAPI.TrophyCounts(bronze: 46, silver: 6,
                                                                     gold: 2, platinum: 1),
                                        earned: PSNAPI.TrophyCounts(bronze: 1, silver: 0,
                                                                    gold: 0, platinum: 0),
                                        percent: 1),
        communicationIds: ["NPWR07319_00"])]
    let claimed = mergeAll([gDTO("CUSA01174_00", "人中之龍０　誓約的場所", "PS4")],
                           yakuzaZeroTrophies, byTitleId: yakuzaZeroClaims)
    check("跨世代: 已被人认领的奖杯套**不再建** PS3 记录（旧规则会凭空造一个 PS3 游戏）",
          claimed.records.count == 1 && !claimed.records.contains { $0.titleId == "NPWR07319_00" })
    check("跨世代: 认领集合把「有主」的套如实带出来（同步收尾据它清旧账）",
          claimed.claimedTrophySets == ["NPWR07319_00"])
    check("跨世代: 按 id 取回的进度落在真正的主人那条记录上（1/55）",
          claimed.records[0].trophies?.earnedTotal == 1)

    // ③-9 反面：**无主**的跨世代套照旧建记录 —— 「只在没人认领时才建」的另一半。
    // 用户只在 PS3 上玩过、gamelist 里没有对应 PC/PS4/PS5 条目时，这条记录必须留下。
    let orphanSet = mergeAll([gDTO("CUSA01174_00", "人中之龍０　誓約的場所", "PS4")],
                            yakuzaZeroTrophies)
    check("跨世代: 无人认领的套仍然建记录（保住「只在 PS3 上玩过」的真记录）",
          orphanSet.records.count == 2 && orphanSet.claimedTrophySets.isEmpty)

    // ③-10 名字那一遍认下的套同样算「有主」—— 否则一条靠名字认下的记录拥有的套会被
    // 误判成无主，重新长出 PS3 幽灵记录（这正是「只问没认下的那些」仍然安全的原因）。
    let nameClaimed = mergeAll(
        [gDTO("CUSA01433_00", "Rocket League", "PS4")],
        [trophyEntry("NPWR00010_00", "Rocket League", "PS3,PS4")].compactMap { $0 })
    check("跨世代: 名字匹配认下的跨世代套也算有主，不再另建一条 PS3 记录",
          nameClaimed.records.count == 1 && nameClaimed.claimedTrophySets == ["NPWR00010_00"])

    // ③-11 by id 的结果**只填空白**：名字那一遍已经贴上的不被覆盖
    //（换掉会让同一份数据两次同步得到不同结果）。
    let keepByName = mergeAll(
        [gDTO("CUSA01433_00", "Rocket League", "PS4")],
        [trophyEntry("NPWR00011_00", "Rocket League", "PS4", earnedBronze: 7)].compactMap { $0 },
        byTitleId: ["CUSA01433_00": PSNTrophyService.TitleTrophies(
            progress: PSNAPI.trophyProgress(defined: PSNAPI.TrophyCounts(bronze: 10),
                                            earned: PSNAPI.TrophyCounts(bronze: 0),
                                            percent: 0),
            communicationIds: ["NPWR00011_00"])])
    check("跨世代: 名字匹配贴上的进度不被按 id 的结果覆盖（这一套 8 个 ≠ 那一路的 0 个）",
          keepByName.records[0].trophies?.earnedTotal == 8)

    // ③-12 遗留平台判定只有一处（建记录与同步收尾清删共用它）。
    check("跨世代: 遗留平台只有 PS3 / PS Vita 两个",
          PSNTrophyService.isLegacyPlatform("PS3") && PSNTrophyService.isLegacyPlatform("PS Vita")
          && !PSNTrophyService.isLegacyPlatform("PS4") && !PSNTrophyService.isLegacyPlatform("PS5"))

    // ④ 语言阶梯：五个档位 + 「跟随 App 语言」必须是 nil（由调用方拿当前语言现算，
    //    在这里定死一个默认值会把「跟随」变成「固定」）。
    check("语言: followApp 的 Accept-Language 是 nil（跟随 App = 由调用方现算）",
          ExternalTitleLocale.followApp.acceptLanguage == nil)
    check("语言: 繁體走降级阶梯（zh-Hant-TW,zh-Hant,zh-TW）",
          ExternalTitleLocale.zhHant.acceptLanguage == "zh-Hant-TW,zh-Hant,zh-TW")
    check("语言: 简体阶梯", ExternalTitleLocale.zhHans.acceptLanguage == "zh-Hans-CN,zh-Hans,zh-CN")
    check("语言: 日文阶梯", ExternalTitleLocale.ja.acceptLanguage == "ja-JP,ja")
    check("语言: 英文阶梯", ExternalTitleLocale.en.acceptLanguage == "en-US,en")
    check("语言: Nintendo 侧取值不变（rawValue 逐字不动 → 库里已有数据零迁移）",
          ExternalTitleLocale.followApp.explicitGentryLocale == nil
          && ExternalTitleLocale.zhHant.explicitGentryLocale == "zh-TW"
          && ExternalTitleLocale.zhHans.explicitGentryLocale == "zh-CN"
          && ExternalTitleLocale.ja.explicitGentryLocale == "ja-JP"
          && ExternalTitleLocale.en.explicitGentryLocale == "en-US")
    // 阶梯是**逗号列表**，但落语言槽靠前缀判（`TitleScript.languageSlot`），所以只要
    // 首个标签就是目标语言，整条串传进去照样得到正确槽位 —— 顺序不能改，这个用例守住它。
    check("语言: 阶梯的首个标签就是目标语言（否则落槽会落错）",
          ExternalTitleLocale.zhHant.acceptLanguage?.hasPrefix("zh-Hant") == true
          && ExternalTitleLocale.ja.acceptLanguage?.hasPrefix("ja") == true
          && ExternalTitleLocale.en.acceptLanguage?.hasPrefix("en") == true
          && TitleScript.of("戰神：諸神黃昏")
              .languageSlot(requestedLocale: ExternalTitleLocale.zhHant.acceptLanguage ?? "") == "zh")

    // ⑤ 取数链路：翻页 + `Accept-Language` + 「200 带 error」。
    let trophyHTTP = ExternalHTTPClient(defaultHeaders: ["Accept": "application/json"],
                                        protocolClasses: [ExternalImportStub.self])
    let trophyToken = ExternalImportStub.Stub(status: 200, body: Data("""
    {"access_token":"AT","refresh_token":"RT","expires_in":3600,"refresh_token_expires_in":5184000}
    """.utf8))
    func trophyAuth(refresh: String?) -> PSNAuthService {
        PSNAuthService(http: trophyHTTP,
                       npssoProvider: { "NPSSO-1" },
                       refreshTokenProvider: { refresh },
                       refreshTokenSink: { _ in })
    }
    func trophyRequests() -> [URLRequest] {
        ExternalImportStub.requests.filter { ($0.url?.path ?? "").hasSuffix("/trophyTitles") }
    }

    let page1 = ExternalImportStub.Stub(status: 200, body: Data("""
    {"trophyTitles":[
      {"npCommunicationId":"NPWR00010_00","trophyTitleName":"甲","trophyTitlePlatform":"PS3"},
      {"npCommunicationId":"NPWR00011_00","trophyTitleName":"乙","trophyTitlePlatform":"PS Vita"}
    ],"totalItemCount":3}
    """.utf8))
    let page2 = ExternalImportStub.Stub(status: 200, body: Data("""
    {"trophyTitles":[
      {"npCommunicationId":"NPWR00012_00","trophyTitleName":"丙","trophyTitlePlatform":"PS5"}
    ],"totalItemCount":3}
    """.utf8))

    ExternalImportStub.install { request in
        let path = request.url?.path ?? ""
        if path.hasSuffix("/token") { return trophyToken }
        let offset = (request.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        })?.queryItems?.first { $0.name == "offset" }?.value
        return (offset ?? "0") == "0" ? page1 : page2
    }
    let trophyPage = try? await PSNTrophyService(
        auth: trophyAuth(refresh: "RT"), accountId: "1234567890",
        acceptLanguage: ExternalTitleLocale.zhHant.acceptLanguage,
        http: trophyHTTP).fetchTrophyTitles()
    check("奖杯: 自动翻页收满（2 + 1 = 3 条）", trophyPage?.count == 3)
    check("奖杯: 翻页共发 2 次请求（收满即停）", trophyRequests().count == 2)
    check("奖杯: 第二页用 offset=800（该端点的上限，不是游玩记录那个 200）",
          trophyRequests().last?.url?.absoluteString.contains("offset=800") == true)
    check("奖杯: 请求带 Bearer、limit=800 与账号级 Accept-Language",
          trophyRequests().first?.value(forHTTPHeaderField: "Authorization") == "Bearer AT"
          && trophyRequests().first?.url?.absoluteString.contains("limit=800") == true
          && trophyRequests().first?.value(forHTTPHeaderField: "Accept-Language")
              == "zh-Hant-TW,zh-Hant,zh-TW")

    // 「200 里带 error」：不探的话会解成 0 条 —— 一次看起来成功的空同步。
    ExternalImportStub.install { request in
        (request.url?.path ?? "").hasSuffix("/token")
            ? trophyToken
            : .init(status: 200, headers: ["Content-Type": "application/json"],
                    body: Data(#"{"error":{"code":-1,"message":"server free text"}}"#.utf8))
    }
    var trophyError: ExternalAPIError?
    do {
        _ = try await PSNTrophyService(auth: trophyAuth(refresh: "RT"), accountId: "1",
                                       http: trophyHTTP).fetchTrophyTitles()
    } catch let error as ExternalAPIError {
        trophyError = error
    } catch {}
    check("奖杯: 200 带 error 的响应**不会**被当成空库成功",
          trophyError == .apiChanged("psn api returned an error object inside a 200 response"))
    check("奖杯: 错误描述里不带服务端自由文本",
          !String(describing: trophyError!).contains("server free text"))

    // ⑥ 按 npTitleId 精确对号。**这是在用户真库上量出来的主力路径**：101 条 PS4/PS5 记录，
    //    纯名字匹配只认下 31 条（`gamelist` 的 name 是商店商品名，不是奖杯套名），
    //    剩下那 70 条靠这条路。
    func byIdRequests() -> [URLRequest] {
        ExternalImportStub.requests.filter { ($0.url?.path ?? "").hasSuffix("/titles/trophyTitles") }
    }
    func npTitleIds(in request: URLRequest) -> [String] {
        (request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })?
            .queryItems?.first { $0.name == "npTitleIds" }?.value?
            .split(separator: ",").map(String.init) ?? []
    }
    /// 造一个「按 id 分组」的响应。**奖杯套名故意写成与游玩记录完全不同** ——
    /// 这条路径要是偷偷用了名字，下面的断言就会挂。
    ///
    /// 每个标题名下**故意挂两套**：第一套可见，第二套 `hiddenFlag: true` 且计数更大。
    /// 这一个形状同时钉住两件事 —— 进度取可见的那套（隐藏整条跳过），而**认领集合两套都要收**
    /// （隐藏是用户在奖杯列表里的显示偏好，不代表这个套不属于这个标题；漏收会让同步收尾把
    /// 一条已经有人认领的 PS3 幽灵记录当成合法记录留着）。
    func byIdBody(_ ids: [String]) -> Data {
        let entries = ids.map { id in
            """
            {"npTitleId":"\(id)","trophyTitles":[
              {"npCommunicationId":"NPWR-\(id)","trophyTitleName":"与游玩记录里的名字毫不相干",
               "trophyTitlePlatform":"PS4",
               "definedTrophies":{"bronze":10,"silver":4,"gold":2,"platinum":1},
               "earnedTrophies":{"bronze":3,"silver":1,"gold":0,"platinum":0},
               "progress":20},
              {"npCommunicationId":"HIDDEN-\(id)","trophyTitleName":"隐藏的那一套",
               "trophyTitlePlatform":"PS3",
               "definedTrophies":{"bronze":99},
               "earnedTrophies":{"bronze":99},
               "progress":100,"hiddenFlag":true}
            ]}
            """
        }.joined(separator: ",")
        return Data("{\"titles\":[\(entries)]}".utf8)
    }
    func byIdService() -> PSNTrophyService {
        PSNTrophyService(auth: trophyAuth(refresh: "RT"), accountId: "1234567890",
                         acceptLanguage: ExternalTitleLocale.zhHant.acceptLanguage,
                         http: trophyHTTP)
    }

    // ⑥-1 分批：12 个 id → 5 + 5 + 2（5 是服务端硬上限，超一个整批被拒）。
    let batchIds = (1...12).map { "CUSA000\($0)_00" }
    ExternalImportStub.install { request in
        if (request.url?.path ?? "").hasSuffix("/token") { return trophyToken }
        return .init(status: 200, body: byIdBody(npTitleIds(in: request)))
    }
    let byId = try? await byIdService().fetchTrophies(forTitleIds: batchIds)
    check("奖杯(id): 12 个 id 分 3 批（5 / 5 / 2）", byIdRequests().count == 3)
    check("奖杯(id): 每批都不超过 5 个 id（服务端硬上限，超了整批被拒）",
          byIdRequests().allSatisfy { npTitleIds(in: $0).count <= 5 })
    check("奖杯(id): 结果按**回显的 npTitleId** 建键 —— 与奖杯套名字完全无关",
          byId?.count == 12 && byId?["CUSA0003_00"]?.progress?.earnedTotal == 4)
    check("奖杯(id): 顺带把每个标题名下**全部套**的编号带出来（含隐藏的）—— 同步收尾靠它判「有主」",
          byId?["CUSA0003_00"]?.communicationIds == ["NPWR-CUSA0003_00", "HIDDEN-CUSA0003_00"])
    check("奖杯(id): 进度只认真实可见的那一套（隐藏的 99 个铜杯不能顶掉 4）",
          byId?["CUSA0003_00"]?.progress?.bronzeDefined == 10)
    check("奖杯(id): 请求带 Bearer 与账号级 Accept-Language",
          byIdRequests().first?.value(forHTTPHeaderField: "Authorization") == "Bearer AT"
          && byIdRequests().first?.value(forHTTPHeaderField: "Accept-Language")
              == "zh-Hant-TW,zh-Hant,zh-TW")

    // ⑥-2 去重：同一个 id 重复传只占一个名额（同捆包 SKU 与本体 SKU 会撞）。
    ExternalImportStub.install { request in
        if (request.url?.path ?? "").hasSuffix("/token") { return trophyToken }
        return .init(status: 200, body: byIdBody(npTitleIds(in: request)))
    }
    let deduped = try? await byIdService().fetchTrophies(forTitleIds: ["CUSA1", "CUSA1", "CUSA2", ""])
    check("奖杯(id): 重复 id 与空串都只算一个（一批就够，不白花名额）",
          byIdRequests().count == 1 && npTitleIds(in: byIdRequests()[0]).count == 2
          && deduped?.count == 2)

    // ⑥-3 整批被拒 → 逐条重试。文档写明「查询不存在的 titleId 返回 Resource not found」——
    //      那是**整批**失败，一个坏 id 会把同批另外 4 个一起带走。
    ExternalImportStub.install { request in
        if (request.url?.path ?? "").hasSuffix("/token") { return trophyToken }
        let ids = npTitleIds(in: request)
        return ids.count > 1 ? .init(status: 404) : .init(status: 200, body: byIdBody(ids))
    }
    let rescued = try? await byIdService().fetchTrophies(forTitleIds: ["CUSA1", "CUSA2", "CUSA3"])
    check("奖杯(id): 整批被拒 → 逐条重试，好的那些照常拿回（1 次批 + 3 次单条）",
          byIdRequests().count == 4 && rescued?.count == 3)

    // ⑥-4 一条都拿不回来 → 抛错。上层据此置 `trophyUnavailable`；静默的话
    //      「奖杯一个都没有」会与「功能没做」长得一模一样。
    ExternalImportStub.install { request in
        (request.url?.path ?? "").hasSuffix("/token") ? trophyToken : .init(status: 404)
    }
    var byIdError: ExternalAPIError?
    do {
        _ = try await byIdService().fetchTrophies(forTitleIds: ["CUSA1", "CUSA2"])
    } catch let error as ExternalAPIError {
        byIdError = error
    } catch {}
    check("奖杯(id): 一条都没拿回来就抛错（不静默）", byIdError != nil)

    // ⑥-5 空输入不发请求（没有要补的就别打接口）。
    ExternalImportStub.install { _ in trophyToken }
    let emptyBy = try? await byIdService().fetchTrophies(forTitleIds: [])
    check("奖杯(id): 没有要补的 id 时一次请求都不发",
          byIdRequests().isEmpty && emptyBy?.isEmpty == true)

    // ⑥-6 `bestProgress`：一个 id 带多个奖杯套时取总数最多的（顺序在服务端没有承诺）。
    func byIdEntry(_ id: String, bronze: Double, hidden: Bool = false)
        -> PSNAPI.TrophyTitleEntry? {
        try? ExternalHTTPClient.decode(PSNAPI.TrophyTitleEntry.self, from: Data("""
        {"npCommunicationId":"\(id)","trophyTitleName":"x","trophyTitlePlatform":"PS4",
         "definedTrophies":{"bronze":\(bronze)},"earnedTrophies":{"bronze":1},
         "progress":10,"hiddenFlag":\(hidden)}
        """.utf8))
    }
    check("奖杯(id): 一个 id 带多套时取总数最多的那一套",
          PSNTrophyService.bestProgress(in: [byIdEntry("a", bronze: 10),
                                             byIdEntry("b", bronze: 40)].compactMap { $0 })?
              .definedTotal == 40)
    check("奖杯(id): 隐藏的奖杯套整套跳过（与名字匹配那条路径同口径）",
          PSNTrophyService.bestProgress(in: [byIdEntry("a", bronze: 10, hidden: true)]
              .compactMap { $0 }) == nil)
    check("奖杯(id): 空数组 / nil 都返回 nil（= 这个 id 没有奖杯数据，不是 0 个）",
          PSNTrophyService.bestProgress(in: []) == nil
          && PSNTrophyService.bestProgress(in: nil) == nil)
    // 一条完全没带计数的条目（服务端可能只回个壳）不能被当成「有奖杯」。
    let bareEntry = try? ExternalHTTPClient.decode(PSNAPI.TrophyTitleEntry.self,
                                                   from: Data(#"{"npTitleId":"CUSA1_00"}"#.utf8))
    check("奖杯(id): 没有计数数据的条目不算「有奖杯」（否则界面上会出现 0/0）",
          PSNTrophyService.bestProgress(in: [bareEntry].compactMap { $0 }) == nil)

    ExternalImportStub.clear()
}

// ============================================================================
// 20. 游玩记录卡（Nintendo）：三项口径 + 入场判据
// ============================================================================
do {
    let paContext = ModelContext(container)
    let paGame = Game(name: "PlayActivity Game", platform: "Nintendo Switch")
    paContext.insert(paGame)

    let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    let t1 = Date(timeIntervalSince1970: 1_710_000_000)

    func paRecord(_ provider: AccountProvider, first: Date? = nil, last: Date? = nil,
                  seconds: Int? = nil) -> ExternalGameRecord {
        let r = ExternalGameRecord(provider: provider, externalAccountId: "ACC-PA",
                                   titleId: "0100000000010000", titleName: "PlayActivity Title",
                                   platform: "Nintendo Switch",
                                   firstPlayedAt: first, lastPlayedAt: last, playedSeconds: seconds)
        paContext.insert(r)
        r.game = paGame
        return r
    }

    // --- 三项口径：`hasAny` 是「这一行 / 这张卡画不画」的唯一判据（两位调用方共用）---
    check("游玩三项: 三项全 nil → 没有内容", !PlayActivity.hasAny(firstPlayedAt: nil, lastPlayedAt: nil, hours: nil))
    check("游玩三项: 只有首次也算有内容",
          PlayActivity.hasAny(firstPlayedAt: t0, lastPlayedAt: nil, hours: nil))
    check("游玩三项: 只有最近也算有内容",
          PlayActivity.hasAny(firstPlayedAt: nil, lastPlayedAt: t1, hours: nil))
    check("游玩三项: 只有时长也算有内容",
          PlayActivity.hasAny(firstPlayedAt: nil, lastPlayedAt: nil, hours: 3))
    check("游玩三项: 三项齐全当然有内容",
          PlayActivity.hasAny(firstPlayedAt: t0, lastPlayedAt: t1, hours: 189))

    // --- 入场判据：`showsPlayActivityCard` ---
    check("游玩卡: Nintendo + 两个日期 + 时长 → 出卡",
          paRecord(.nintendo, first: t0, last: t1, seconds: 680_400).showsPlayActivityCard)
    check("游玩卡: Nintendo 只有时长（时长是唯一非 nil）→ 出卡",
          paRecord(.nintendo, seconds: 3_600).showsPlayActivityCard)
    check("游玩卡: Nintendo 只有日期 → 出卡",
          paRecord(.nintendo, last: t1).showsPlayActivityCard)
    check("游玩卡: Nintendo 什么都没有 → **不出卡**（只剩一个品牌名的卡比不显示更糟）",
          !paRecord(.nintendo).showsPlayActivityCard)
    // 这条是本判据存在的理由：PSN 记录走的是奖杯卡，不能同一份数据出两张卡说两遍。
    check("游玩卡: **PSN 记录即使三项齐全也不出这张卡**（它走奖杯卡）",
          !paRecord(.playstation, first: t0, last: t1, seconds: 680_400).showsPlayActivityCard)

    // 时长归零的边界：`displayHours` 是 `max(1, …)`，所以「有 playedSeconds 但是 0」
    // 也会被当成「1 小时」——出卡，且数值与账号记录行一致（那边 `metaText` 读同一个属性）。
    let zeroSeconds = paRecord(.nintendo, seconds: 0)
    check("游玩卡: 0 秒的记录照样出卡，且小时数走同一个 displayHours（不会一边有一边没有）",
          zeroSeconds.showsPlayActivityCard && zeroSeconds.displayHours == 1)
}

// ============================================================================
// 21. Xbox 层（OpenXBL）：响应外壳 / 平台映射 / 时长批量 / 图片升级 / 身份 / 取数编排 / 成就
// ============================================================================
do {
    // ① 响应外壳。**成功与失败的形状不对称** —— 成功是数字 `200`，失败是字符串 `"ERROR"`。
    //    只声明一种的话，另一种会让**整个响应**解码失败，后果是把「key 无效」误报成
    //    「接口变了」（用户该做的动作完全不同：重新绑 vs 等我们修）。
    let okBody = Data(#"{"content":{"profileUsers":[{"id":"2535410324111447"}]},"code":200}"#.utf8)
    let okDecoded = try? XboxAPI.decode(XboxAPI.AccountResponse.self, from: okBody)
    check("Xbox 外壳: 成功响应（数字 code + content）能解出 content",
          okDecoded?.profileUsers?.first?.id == "2535410324111447")

    func envelopeError(_ json: String) -> ExternalAPIError? {
        guard let envelope = try? ExternalHTTPClient.decode(
            XboxAPI.Envelope<XboxAPI.AccountResponse>.self, from: Data(json.utf8)) else { return nil }
        return XboxAPI.failure(in: envelope)
    }
    check("Xbox 外壳: 数字 code 200/201 → 不算失败",
          envelopeError(#"{"code":200,"content":{}}"#) == nil
          && envelopeError(#"{"code":201,"content":{}}"#) == nil)
    var nonOKIsServer = false
    if case .server(500) = envelopeError(#"{"code":500}"#) { nonOKIsServer = true }
    check("Xbox 外壳: 数字 code 非 2xx → server(status)", nonOKIsServer)
    var tokenIsChanged = false
    if case .apiChanged = envelopeError(#"{"code":"ERROR","message":"whatever"}"#) { tokenIsChanged = true }
    check("Xbox 外壳: 2xx 里出现字符串 code → apiChanged（不静默当成「服务端没给这个字段」）",
          tokenIsChanged)
    check("Xbox 外壳: 没有 code 字段时不判失败（由 content 在不在决定）",
          envelopeError(#"{"content":{}}"#) == nil)
    // 实测过的唯一一种字符串 code 是 `"ERROR"`，且它**总是伴随 HTTP 401**（已被共享层
    // 归成 `.authExpired`）。所以这里刻意**不建错误码表** —— 编一张表就是拿猜测冒充事实。
    check("Xbox 外壳: 不认识的字符串 code 一律 apiChanged，绝不编一张码表",
          envelopeError(#"{"code":"RATE_LIMIT"}"#) != nil)

    let tokenIn2xx = Data(#"{"code":"ERROR","message":"server free text 不要泄漏"}"#.utf8)
    do {
        _ = try XboxAPI.decode(XboxAPI.AccountResponse.self, from: tokenIn2xx)
        check("Xbox 外壳: 2xx 里带字符串 code 必须抛错", false)
    } catch let error as ExternalAPIError {
        check("Xbox 外壳: 服务端的 message 绝不进错误描述",
              !(error.errorDescription ?? "").contains("server free text")
              && !String(describing: error).contains("server free text"))
    } catch {
        check("Xbox 外壳: 抛的是 ExternalAPIError", false)
    }
    var noContentIsChanged = false
    do { _ = try XboxAPI.decode(XboxAPI.AccountResponse.self, from: Data(#"{"code":200}"#.utf8)) }
    catch let error as ExternalAPIError { if case .apiChanged = error { noContentIsChanged = true } }
    catch {}
    check("Xbox 外壳: 既没有 content 也没有错误 code → apiChanged（而不是「0 条记录」）",
          noContentIsChanged)

    // ② `devices`（一份**可用平台列表**）→ 平台。
    check("Xbox 平台: XboxSeries → Xbox Series X|S",
          XboxAPI.platform(forDevices: ["XboxSeries"]) == "Xbox Series X|S")
    check("Xbox 平台: XboxOne → Xbox One", XboxAPI.platform(forDevices: ["XboxOne"]) == "Xbox One")
    check("Xbox 平台: Xbox360 → Xbox 360", XboxAPI.platform(forDevices: ["Xbox360"]) == "Xbox 360")
    check("Xbox 平台: Win32 → PC（归一化器认不出这个紧凑写法，显式表兜住）",
          XboxAPI.platform(forDevices: ["Win32"]) == "PC")
    // 取列表里**最老的一代** = 这个标题**原生**属于的那一代。
    // ⚠️ 这条判据 2026-09-18 翻过一次（原来是「取最新」），翻的理由是用户报回来的两条实例 ——
    // 下面两条就是那两个实例的**回归位**，改动它们之前先读 `XboxAPI.platform(forDevices:)` 的说明。
    check("Xbox 平台: 只有次世代 → Xbox Series X|S（原生次世代游戏不受本次改动影响）",
          XboxAPI.platform(forDevices: ["XboxSeries"]) == "Xbox Series X|S")
    check("Xbox 平台: XboxOne+XboxSeries → **Xbox One**（Dark Souls III 的形状：One 游戏向下兼容）",
          XboxAPI.platform(forDevices: ["XboxOne", "XboxSeries"]) == "Xbox One")
    check("Xbox 平台: Xbox360+XboxOne+XboxSeries → **Xbox 360**（Avatar / CoD 2 的形状：360 游戏向下兼容）",
          XboxAPI.platform(forDevices: ["Xbox360", "XboxOne", "XboxSeries"]) == "Xbox 360")
    check("Xbox 平台: PC+XboxOne+XboxSeries → Xbox One（PC 不是世代，排在三代之后）",
          XboxAPI.platform(forDevices: ["PC", "XboxOne", "XboxSeries"]) == "Xbox One")
    check("Xbox 平台: Xbox360+XboxOne → Xbox 360（360 原生）",
          XboxAPI.platform(forDevices: ["Xbox360", "XboxOne"]) == "Xbox 360")
    // ⚠️ 已知局限（**不写成断言**，因为它没有可判定的期望值）：跨世代**真原生**双版本
    // （如 Halo Infinite，`XboxOne+XboxSeries`）与「One 游戏向下兼容」在这份数据里长得
    // **一模一样**，两者都会落 `Xbox One`。列表里没有任何字段能区分它们，所以不猜 ——
    // 「它能在哪几台上玩」这个事实由成就卡副标题按完整列表展开，一个字没丢。
    // 实测出现过的那条 `Nintendo Switch` 靠共享归一化器兜住。
    check("Xbox 平台: 认不出的取值退给共享归一化器（实测见过一条 Nintendo Switch）",
          XboxAPI.platform(forDevices: ["Nintendo Switch"]) == "Nintendo Switch")
    check("Xbox 平台: 认不出来的形状返回 nil（兜底是调用方的决定，不是解析层的）",
          XboxAPI.platform(forDevices: ["Atari"]) == nil
          && XboxAPI.platform(forDevices: nil) == nil
          && XboxAPI.platform(forDevices: []) == nil)
    check("Xbox 平台: 映射出的每个平台都是合法预设值（否则入库会出现界面筛不到的野值）",
          ["Xbox Series X|S", "Xbox One", "Xbox 360", "Xbox", "PC"].allSatisfy(Presets.platforms.contains))
    check("Xbox 平台: 原样落库的 platformRaw（校对映射表唯一的证据）",
          XboxAPI.platformRaw(forDevices: ["PC", "XboxOne"]) == "PC,XboxOne"
          && XboxAPI.platformRaw(forDevices: nil) == nil)

    // ②b `mediaItemType` —— **来源自己说的「这是哪一类的游戏」**，不再靠 `devices` 的顺序推。
    //
    // 实测 330 条：Application 288 / Xbox360Game 32 / XboxArcadeGame 8 / XboxOriginalGame 2。
    // 关键实测事实（下面那条「两个集合不相交」的断言就是它）：`devices` 含 `Xbox360` 的 **42 条
    // 全部**是非 `Application`，而 288 条 `Application` **一条都不含** `Xbox360`。
    check("Xbox 媒体类型: Xbox360Game → Xbox 360",
          XboxAPI.platform(forMediaItemType: "Xbox360Game") == "Xbox 360")
    check("Xbox 媒体类型: XboxArcadeGame → Xbox 360（Xbox Live Arcade 是 360 世代的数字发行）",
          XboxAPI.platform(forMediaItemType: "XboxArcadeGame") == "Xbox 360")
    check("Xbox 媒体类型: XboxOriginalGame → **Xbox**（初代，预设里与 GameCube / PS2 同代）",
          XboxAPI.platform(forMediaItemType: "XboxOriginalGame") == "Xbox")
    check("Xbox 媒体类型: Application **没有回答**「One 还是 Series」→ nil（不是「没有平台」）",
          XboxAPI.platform(forMediaItemType: "Application") == nil)
    check("Xbox 媒体类型: 没见过的取值 / 空串 / nil 一律 nil（认不出就不猜）",
          XboxAPI.platform(forMediaItemType: "XboxSeriesGame") == nil
          && XboxAPI.platform(forMediaItemType: "   ") == nil
          && XboxAPI.platform(forMediaItemType: nil) == nil)

    // 两级的意义：**事实在时用事实，事实没有才折叠 devices**。
    // Ninja Gaiden Black / Morrowind 的形状：初代游戏，`devices` 里也含 `Xbox360`（能在 360 上跑），
    // 折叠会得到 `Xbox 360` —— 那是向下兼容，不是它原本属于哪一代。来源既然明说了就以来源为准。
    check("Xbox 平台: 初代游戏归 **Xbox**（折叠 devices 会错标成 Xbox 360 —— 那是兼容不是原生）",
          XboxAPI.platform(forMediaItemType: "XboxOriginalGame",
                           devices: ["Xbox360", "XboxOne", "XboxSeries"]) == "Xbox")
    check("Xbox 平台: 360 游戏由来源事实定（不经过 devices 的顺序）",
          XboxAPI.platform(forMediaItemType: "Xbox360Game",
                           devices: ["Xbox360", "XboxOne", "XboxSeries"]) == "Xbox 360")
    check("Xbox 平台: Application 没有事实可用 → 落到 devices 折叠（Dark Souls III 由此得 Xbox One）",
          XboxAPI.platform(forMediaItemType: "Application",
                           devices: ["XboxOne", "XboxSeries"]) == "Xbox One"
          && XboxAPI.platform(forMediaItemType: "Application",
                              devices: ["XboxSeries"]) == "Xbox Series X|S")
    check("Xbox 平台: 事实缺位时折叠照常兜底（媒体类型 nil / 认不出都不影响入库）",
          XboxAPI.platform(forMediaItemType: nil, devices: ["XboxOne", "XboxSeries"]) == "Xbox One"
          && XboxAPI.platform(forMediaItemType: "X什么", devices: ["Xbox360"]) == "Xbox 360")

    // ⚠️ **这是「本次改动不改变任何既有条目落库结果」的那条不变量**，别删：
    // 实测里 360 那一类的两级结论**逐字相同**（两个集合不相交所致），所以加这一层只是把
    // 判断依据从顺序换成事实 + 归正初代那 2 条，不会让任何一条已有的记录换平台。
    do {
        let buckets: [[String]] = [["XboxSeries"], ["XboxOne"], ["XboxOne", "XboxSeries"],
                                   ["PC", "XboxSeries"], ["PC", "XboxOne", "XboxSeries"],
                                   ["PC"], ["Win32"], ["Xbox360", "XboxOne", "XboxSeries"]]
        // 360 及更早那一桶：事实与折叠必须给出同一个答案（初代那 2 条是**有意的**例外，
        // 见上面「归正到 Xbox」那条 —— 所以这里单独放行 `Xbox`）。
        let modern = buckets.filter { !$0.contains("Xbox360") }
        let agree = modern.allSatisfy { devices in
            XboxAPI.platform(forMediaItemType: "Application", devices: devices)
                == XboxAPI.platform(forDevices: devices)
        }
        check("Xbox 平台: 本世代那一桶 · 两级结论逐字一致（= 本次改动不动既有条目）", agree)
        check("Xbox 平台: 360 那一桶 · 事实与折叠也一致（唯一例外是初代归正到 Xbox）",
              XboxAPI.platform(forMediaItemType: "Xbox360Game",
                               devices: ["Xbox360", "XboxOne", "XboxSeries"])
                  == XboxAPI.platform(forDevices: ["Xbox360", "XboxOne", "XboxSeries"]))
    }
    // 共享归一化器补的两个别名：`xboxseries` ≠ `key("Xbox Series X|S")` = `xboxseriess`，
    // 而 `win32` 在预设里根本没有对位物 —— 只有这两个对不上，其余三种本来就命中。
    check("Xbox 平台: 归一化器也认得 XboxSeries / Win32（别名表已补）",
          ExternalPlatformNormalizer.canonical(fromRaw: "XboxSeries") == "Xbox Series X|S"
          && ExternalPlatformNormalizer.canonical(fromRaw: "Win32") == "PC")

    // ③ 封面地址升级。实测来源给的是 `http://store-images.s-microsoft.com/...`，
    //    而本项目**没有任何 ATS 例外** —— 原样丢给 URLSession 会被挡掉，表现是
    //    「封面一条都下不来，日志里什么都没有」。同路径 https 实测 200（2160×2160）。
    check("Xbox 图片: http 升级成 https，主机与路径不动",
          XboxAPI.secureImageURL("http://store-images.s-microsoft.com/image/apps.1")
              == "https://store-images.s-microsoft.com/image/apps.1")
    check("Xbox 图片: 已经是 https 的原样返回",
          XboxAPI.secureImageURL("https://store-images.s-microsoft.com/image/apps.1")
              == "https://store-images.s-microsoft.com/image/apps.1")
    check("Xbox 图片: 认不出来的形状原样返回（不猜、不拼）",
          XboxAPI.secureImageURL("//cdn.example/x") == "//cdn.example/x")
    check("Xbox 图片: 空值 → nil", XboxAPI.secureImageURL(nil) == nil
          && XboxAPI.secureImageURL("   ") == nil)

    // ④ `LenientInt`：`value` 实测是**字符串**，但 OpenXBL 是第三方包装，随时可能改类型
    //    —— 字段类型一变，整个响应（330 条）解码失败会让整次同步报「接口变了」。
    func statValue(_ json: String) -> Int? {
        let decoded = try? ExternalHTTPClient.decode(XboxAPI.PlayerStatsResponse.self,
                                                     from: Data(json.utf8))
        return decoded?.statlistscollection?.first?.stats?.first?.value?.value
    }
    check("Xbox 静音数字: 字符串 \"1527\" → 1527",
          statValue(#"{"statlistscollection":[{"stats":[{"titleid":"1","name":"MinutesPlayed","value":"1527"}]}]}"#) == 1527)
    check("Xbox 静音数字: 真数字 1527 也认（上游改成数字不会让整批失败）",
          statValue(#"{"statlistscollection":[{"stats":[{"titleid":"1","name":"MinutesPlayed","value":1527}]}]}"#) == 1527)
    check("Xbox 静音数字: null / 非数字串 → nil（= 这条没有数据，不补 0）",
          statValue(#"{"statlistscollection":[{"stats":[{"titleid":"1","name":"MinutesPlayed","value":null}]}]}"#) == nil
          && statValue(#"{"statlistscollection":[{"stats":[{"titleid":"1","name":"MinutesPlayed","value":"abc"}]}]}"#) == nil)

    // ⑤ `titles[]` → DTO。**一条 titleId 一条 DTO。**
    func titleEntry(_ json: String) -> XboxAPI.TitleEntry? {
        try? ExternalHTTPClient.decode(XboxAPI.TitleEntry.self, from: Data(json.utf8))
    }
    let halo = titleEntry(#"{"titleId":"2131196662","name":"Halo","devices":["PC","XboxSeries"],"titleHistory":{"lastTimePlayed":"2026-09-15T01:20:50.0474465Z"},"displayImage":"http://store-images.s-microsoft.com/image/apps.1"}"#)
    check("Xbox 解析: titleId 与 name 都在才算可用",
          halo.flatMap { XboxGameService.usableTitleId($0) } == "2131196662")
    check("Xbox 解析: 缺名字的条目丢掉（半条记录进库只会变成永远匹配不上的孤儿）",
          titleEntry(#"{"titleId":"888","name":"  ","devices":["PC"]}"#)
              .flatMap { XboxGameService.usableTitleId($0) } == nil
          && titleEntry(#"{"titleId":"","name":"X","devices":["PC"]}"#)
              .flatMap { XboxGameService.usableTitleId($0) } == nil)

    let mapped = halo.map {
        XboxGameService.records(from: [$0], minutes: ["2131196662": 1527],
                                fallbackPlatform: AccountProvider.xbox.fallbackPlatform)
    } ?? []
    check("Xbox 解析: 时长是**整分钟**，统一换算成秒", mapped.first?.playedSeconds == 1527 * 60)
    check("Xbox 解析: 七位小数秒的时间戳能解出来", mapped.first?.lastPlayedAt != nil)
    // 来源 330 条里一个字都没有「首次游玩」，所以恒为 nil —— **不编**。
    check("Xbox 解析: firstPlayedAt 恒为 nil（来源不提供这个字段）",
          mapped.first?.firstPlayedAt == nil)
    // `modernTitleId` 的语义没实测确认过，而 conceptId 是 GameLinker 自动合并的依据 ——
    // 猜错会静默合并两个不同的游戏，所以先不填。
    check("Xbox 解析: conceptId 留 nil（来源没有对位物，不拿未验证的 modernTitleId 冒充）",
          mapped.first?.conceptId == nil)
    check("Xbox 解析: 平台走 devices 映射，图片 http→https",
          mapped.first?.platform == "Xbox Series X|S"
          && mapped.first?.platformRaw == "PC,XboxSeries"
          && (mapped.first?.imageURLString ?? "").hasPrefix("https://"))
    // PSN 的奖杯体系与 Xbox 的成就**计数口径完全不同**（奖杯分级 vs 成就点数），
    // 所以 Xbox 不填 `trophies` —— 那会让奖杯卡显示出 0/0 这种假数据。
    check("Xbox 解析: 不填 trophies（那是 PSN 的奖杯体系，两者口径不同）",
          mapped.first?.trophies == nil)

    // 没有时长数据的条目：`playedSeconds` 落 nil（界面显示「—」），**不补 0** ——
    // 「没玩过」与「来源不提供」必须长得不一样（实测：Xbox 360 的 42 个标题一个都没有时长）。
    let silent = titleEntry(#"{"titleId":"999","name":"Xbox 360 Game","devices":["Xbox360"]}"#)
        .map { XboxGameService.records(from: [$0], minutes: [:], fallbackPlatform: "Xbox Series X|S") } ?? []
    check("Xbox 解析: 批量端点没回的 titleId → playedSeconds 是 nil，**不是 0**",
          silent.first?.playedSeconds == nil)
    check("Xbox 解析: 没有时长的条目仍然入库（游玩记录本身是拿到了的）",
          silent.first?.titleName == "Xbox 360 Game" && silent.first?.platform == "Xbox 360")

    // ⑥ 入库路径真的读了 `mediaItemType` —— 上面那些是在测判据本身，这条在测**接线**。
    //    曾经出过一次「清单/判据写对了但调用点没接上」的漏（§63.8 GAP 1），所以两级折叠
    //    落地之后，这里必须有一条从 JSON 一路到 DTO 的断言。
    let ninja = titleEntry(#"{"titleId":"111","name":"Ninja Gaiden Black","mediaItemType":"XboxOriginalGame","devices":["Xbox360","XboxOne","XboxSeries"]}"#)
        .map { XboxGameService.records(from: [$0], minutes: [:], fallbackPlatform: "Xbox Series X|S") } ?? []
    check("Xbox 入库: 初代游戏经 mediaItemType 落 **Xbox**（不是折叠出来的 Xbox 360）",
          ninja.first?.platform == "Xbox")
    check("Xbox 入库: 但 platformRaw 仍是**完整可用列表**（副标题要说清它能在哪几台上玩）",
          ninja.first?.platformRaw == "Xbox360,XboxOne,XboxSeries")
    let ds3 = titleEntry(#"{"titleId":"222","name":"DARK SOULS III","mediaItemType":"Application","devices":["XboxOne","XboxSeries"]}"#)
        .map { XboxGameService.records(from: [$0], minutes: [:], fallbackPlatform: "Xbox Series X|S") } ?? []
    check("Xbox 入库: Dark Souls III 的形状（Application + One/Series）→ **Xbox One**",
          ds3.first?.platform == "Xbox One")

    // 排序：与 Nintendo / PSN 共用同一处（`ExternalGameRecordDTO.sortedByRecency`）。
    let recent = ExternalGameRecordDTO(titleId: "a", titleName: "Recent",
                                       platform: "PC", lastPlayedAt: Date(timeIntervalSince1970: 2_000))
    let old = ExternalGameRecordDTO(titleId: "b", titleName: "Old",
                                    platform: "PC", lastPlayedAt: Date(timeIntervalSince1970: 1_000))
    let noDate = ExternalGameRecordDTO(titleId: "c", titleName: "NoDate", platform: "PC")
    check("Xbox 排序: 最近玩过的在前，没有时间的落末尾",
          ExternalGameRecordDTO.sortedByRecency([noDate, old, recent]).map(\.titleId) == ["a", "b", "c"])
    check("Xbox 排序: 时间相同时按时长降序",
          ExternalGameRecordDTO.sortedByRecency([
              ExternalGameRecordDTO(titleId: "short", titleName: "S", platform: "PC",
                                    lastPlayedAt: recent.lastPlayedAt, playedSeconds: 60),
              ExternalGameRecordDTO(titleId: "long", titleName: "L", platform: "PC",
                                    lastPlayedAt: recent.lastPlayedAt, playedSeconds: 600),
          ]).map(\.titleId) == ["long", "short"])
    // PSN 侧的入口名要转发到同一处（`PSNTrophyService.finish` 也调它）。
    check("Xbox 排序: PSN 侧入口名转发到同一处（口径不可能漂）",
          PSNGameService.sortedByRecency([noDate, old, recent]).map(\.titleId) == ["a", "b", "c"])

    // ⑥ 请求头。**凭证只在这里进 HTTP 头，绝不进 URL query**（URL 会进系统网络日志）。
    let headers = XboxAPI.headers(apiKey: "K-1", acceptLanguage: "ja-JP")
    check("Xbox 请求头: 用 X-Authorization（**不是** Authorization —— 写错实测 401）",
          headers["X-Authorization"] == "K-1" && headers["Authorization"] == nil)
    check("Xbox 请求头: Accept-Language 传了才带", headers["Accept-Language"] == "ja-JP"
          && XboxAPI.headers(apiKey: "K-1")["Accept-Language"] == nil)

    // ⑦ 鉴权层：拿不到 key 与另外两家「凭证不在了」的收场一致 —— 界面显示「需要重新登录」。
    let missingKeyAuth = XboxAuthService(apiKeyProvider: { nil })
    let blankKeyAuth = XboxAuthService(apiKeyProvider: { "   " })
    let paddedKeyAuth = XboxAuthService(apiKeyProvider: { "  K-1\n" })
    var missingIsAuthExpired = false
    do { _ = try await missingKeyAuth.apiKey() } catch { missingIsAuthExpired = (error as? ExternalAPIError) == .authExpired }
    var blankIsAuthExpired = false
    do { _ = try await blankKeyAuth.apiKey() } catch { blankIsAuthExpired = (error as? ExternalAPIError) == .authExpired }
    check("Xbox 鉴权: Keychain 里没有 key → authExpired（不是「同步失败」）",
          missingIsAuthExpired && blankIsAuthExpired)
    check("Xbox 鉴权: 取到的 key 先去掉首尾空白", (try? await paddedKeyAuth.apiKey()) == "K-1")

    // ⑧ 身份解析（走桩，一条真网络都不打）。
    let xblHTTP = ExternalHTTPClient(defaultHeaders: ["Accept": "application/json"],
                                     protocolClasses: [ExternalImportStub.self])
    let xblAuth = XboxAuthService(apiKeyProvider: { "K-1" })
    func xblRequests(_ suffix: String) -> [URLRequest] {
        ExternalImportStub.requests.filter { ($0.url?.path ?? "").hasSuffix(suffix) }
    }

    ExternalImportStub.install { _ in
        ExternalImportStub.Stub(status: 200, body: Data("""
        {"code":200,"content":{"profileUsers":[{"id":"2535410324111447",
          "hostId":"2535410324111447","isSponsoredUser":false,"settings":[
            {"id":"Gamertag","value":"jill114514"},
            {"id":"GameDisplayPicRaw","value":"http://images-eds.xboxlive.com/image?x"}]}]}}
        """.utf8))
    }
    let identity = try? await XboxAccountService(auth: xblAuth, http: xblHTTP).resolveIdentity()
    check("Xbox 身份: 取到 xuid 与 Gamertag（xuid 是入库唯一键的第 2 段，拿不到必须失败）",
          identity?.externalAccountId == "2535410324111447"
          && identity?.displayName == "jill114514")
    check("Xbox 身份: 头像地址同样升级成 https",
          (identity?.avatarURLString ?? "").hasPrefix("https://"))
    check("Xbox 身份: 只打一个端点（GET /v2/account）",
          xblRequests("/v2/account").count == 1 && xblRequests("/v2/titles").isEmpty)
    check("Xbox 身份: 凭证进 X-Authorization 头，不进 URL",
          xblRequests("/v2/account").first?.value(forHTTPHeaderField: "X-Authorization") == "K-1"
          && !(xblRequests("/v2/account").first?.url?.absoluteString ?? "").contains("K-1"))

    // 没有 Gamertag 时退到可读的兜底名（品牌名 + xuid 后四位）——
    // 多个 Xbox 账号并存是明确支持的场景，两行都叫「Xbox Live」用户就分不清了。
    ExternalImportStub.install { _ in
        ExternalImportStub.Stub(status: 200, body: Data("""
        {"code":200,"content":{"profileUsers":[{"id":"2535410324111447","settings":[]}]}}
        """.utf8))
    }
    let anon = try? await XboxAccountService(auth: xblAuth, http: xblHTTP).resolveIdentity()
    check("Xbox 身份: 没有 Gamertag 时用兜底名（绝不留空串）",
          anon?.displayName == "Xbox Live ···1447")
    check("Xbox 身份: hostId 与 id 同值时也有兜底（实测两者同值）",
          XboxAccountService.fallbackDisplayName(xuid: "2535410324111447")
              == "Xbox Live ···1447")

    ExternalImportStub.install { _ in
        ExternalImportStub.Stub(status: 200, body: Data(#"{"code":200,"content":{"profileUsers":[]}}"#.utf8))
    }
    var noXuidIsChanged = false
    do { _ = try await XboxAccountService(auth: xblAuth, http: xblHTTP).resolveIdentity() }
    catch let error as ExternalAPIError { if case .apiChanged = error { noXuidIsChanged = true } }
    catch {}
    check("Xbox 身份: 拿不到 xuid 就报 apiChanged（编一个会让换绑后的记录撞在一起）",
          noXuidIsChanged)

    // ⑨ 取数编排：两次请求合成一份 DTO 列表（游玩记录 + 批量时长）。
    let titlesJSON = """
    {"code":200,"content":{"xuid":"2535410324111447","titles":[
      {"titleId":"2131196662","name":"Halo Infinite","devices":["PC","XboxSeries"],
       "achievement":{"currentAchievements":10,"totalAchievements":20,
                      "currentGamerscore":100,"totalGamerscore":200},
       "titleHistory":{"lastTimePlayed":"2026-09-15T01:20:50.0474465Z"},
       "displayImage":"http://store-images.s-microsoft.com/image/apps.1"},
      {"titleId":"999","name":"Xbox 360 Game","devices":["Xbox360"],
       "titleHistory":{"lastTimePlayed":"2020-01-02T03:04:05Z"}},
      {"titleId":"","name":"没有 id 的条目","devices":["PC"]},
      {"titleId":"888","name":"   ","devices":["PC"]}
    ]}}
    """
    let statsJSON = """
    {"code":200,"content":{"statlistscollection":[{"stats":[
      {"titleid":"2131196662","name":"MinutesPlayed","value":"1527"},
      {"titleid":"999","name":"MinutesPlayed"}
    ]}]}}
    """
    ExternalImportStub.install { request in
        if (request.url?.path ?? "").hasSuffix("/v2/player/stats") {
            return ExternalImportStub.Stub(status: 200, body: Data(statsJSON.utf8))
        }
        return ExternalImportStub.Stub(status: 200, body: Data(titlesJSON.utf8))
    }
    let fetched = try? await XboxGameService(auth: xblAuth, xuid: "2535410324111447",
                                             acceptLanguage: "ja-JP", http: xblHTTP).fetch()
    check("Xbox 取数: 四个条目里两条可用（缺 id / 缺名字的丢掉）",
          fetched?.records.count == 2)
    check("Xbox 取数: 时长贴回对应的 titleId 并换算成秒",
          fetched?.records.first(where: { $0.titleId == "2131196662" })?.playedSeconds == 1527 * 60)
    // 「没回」= 这条**没有时长数据**（实测：把没回的单独再问一次仍然不回），不是被条数上限截掉。
    check("Xbox 取数: 服务端没回时长的条目不补 0（落 nil，界面显示「—」）",
          fetched?.records.first(where: { $0.titleId == "999" })?.playedSeconds == nil)
    // 成就四项在 `/v2/titles` 的**同一条响应**里（不另取一趟）—— 有就用，没有就是「没有数据」。
    check("Xbox 取数: 成就四项从 achievement 对象贴进记录",
          fetched?.records.first(where: { $0.titleId == "2131196662" })?.achievements
          == AchievementProgress(earned: 10, total: 20, gamerscoreEarned: 100, gamerscoreTotal: 200))
    check("Xbox 取数: 响应里没有 achievement 的条目 → achievements 为 nil（不编一个全 0）",
          fetched?.records.first(where: { $0.titleId == "999" })?.achievements == nil)
    check("Xbox 取数: Xbox 记录不带奖杯（两套体系不互相折算）",
          fetched?.records.allSatisfy { $0.trophies == nil } == true)
    check("Xbox 取数: 两次请求都打了，且 Accept-Language 只加在取标题那一次",
          xblRequests("/v2/titles").count == 1 && xblRequests("/v2/player/stats").count == 1
          && xblRequests("/v2/titles").first?.value(forHTTPHeaderField: "Accept-Language") == "ja-JP"
          && xblRequests("/v2/player/stats").first?.value(forHTTPHeaderField: "Accept-Language") == nil)
    check("Xbox 取数: 时长那一路是 POST，且只读数据（不改任何东西）",
          xblRequests("/v2/player/stats").first?.httpMethod == "POST")
    // ⚠️ 请求体里是**驼峰** `titleId`，而响应里是全小写 `titleid` —— 两边都是实测值，不是笔误。
    let statsBody = xblRequests("/v2/player/stats").first.flatMap { stubBody(of: $0) } ?? ""
    check("Xbox 取数: 请求体带 xuid 与驼峰 titleId（响应回的是全小写，故意的）",
          statsBody.contains("2535410324111447") && statsBody.contains("\"titleId\"")
          && statsBody.contains("MinutesPlayed"))
    check("Xbox 取数: 时长取到了就不报 playtimeUnavailable",
          fetched?.playtimeUnavailable == false)

    // ⑩ 时长那一路失败**不牵连整次同步**：游玩记录已经拿到了，为一条辅助数据把 330 条
    //    一起丢掉是更糟的结果。但**必须说出来** —— 不说的话用户看到满屏「—」，
    //    会以为 Xbox 根本不给时长（实测这是错的：193/330 有值）。
    ExternalImportStub.install { request in
        if (request.url?.path ?? "").hasSuffix("/v2/player/stats") {
            return ExternalImportStub.Stub(status: 500, body: Data())
        }
        return ExternalImportStub.Stub(status: 200, body: Data(titlesJSON.utf8))
    }
    let degraded = try? await XboxGameService(auth: xblAuth, xuid: "2535410324111447",
                                              acceptLanguage: nil, http: xblHTTP).fetch()
    check("Xbox 取数: 时长端点挂了仍然交出全部游玩记录", degraded?.records.count == 2)
    check("Xbox 取数: 时长端点挂了要如实置 playtimeUnavailable（不静默降级）",
          degraded?.playtimeUnavailable == true)
    check("Xbox 取数: 降级时每条记录的时长都是 nil（没有半真半假的值）",
          degraded?.records.allSatisfy { $0.playedSeconds == nil } == true)

    // 游玩记录本身挂了才是真失败 —— 那时必须抛出去，不能交出一份空列表。
    ExternalImportStub.install { request in
        if (request.url?.path ?? "").hasSuffix("/v2/player/stats") {
            return ExternalImportStub.Stub(status: 200, body: Data(statsJSON.utf8))
        }
        return ExternalImportStub.Stub(status: 401,
                                       body: Data(#"{"code":"ERROR","message":"Invalid API key."}"#.utf8))
    }
    var titlesAuthExpired = false
    do {
        _ = try await XboxGameService(auth: xblAuth, xuid: "2535410324111447", http: xblHTTP).fetch()
    } catch let error as ExternalAPIError { titlesAuthExpired = error == .authExpired }
    check("Xbox 取数: key 被拒（401）→ authExpired，界面据此提示重新绑定",
          titlesAuthExpired)

    // ⑪ 分批：330 个 titleId 一次问不完（免费档 150 次/小时，逐游戏 GET 是可行性问题）。
    //    桩只回第一条 stat 也无所谓 —— 这里断言的是**请求次数**。
    let manyTitles = (0..<250).map {
        #"{"titleId":"T\#($0)","name":"Game \#($0)","devices":["PC"]}"#
    }.joined(separator: ",")
    ExternalImportStub.install { request in
        if (request.url?.path ?? "").hasSuffix("/v2/player/stats") {
            return ExternalImportStub.Stub(status: 200, body: Data(#"{"code":200,"content":{"statlistscollection":[]}}"#.utf8))
        }
        return ExternalImportStub.Stub(status: 200,
                                       body: Data(#"{"code":200,"content":{"titles":[\#(manyTitles)]}}"#.utf8))
    }
    let bulk = try? await XboxGameService(auth: xblAuth, xuid: "2535410324111447", http: xblHTTP).fetch()
    check("Xbox 分批: 250 条按 100 一批 → 3 次请求（100 / 100 / 50）",
          xblRequests("/v2/player/stats").count == 3)
    check("Xbox 分批: 每条 titleId 都被问到了（分批不丢条目）",
          xblRequests("/v2/player/stats").allSatisfy { request in
              guard let body = stubBody(of: request) else { return false }
              let asked = body.components(separatedBy: "\"titleId\"").count - 1
              return asked == 100 || asked == 50
          })
    check("Xbox 分批: 250 条记录一条不少地拿回来", bulk?.records.count == 250)

    // 标题端点为空的账号（新号 / 全隐藏）：不该打时长端点，也不该报「没取到时长」。
    ExternalImportStub.install { _ in
        ExternalImportStub.Stub(status: 200, body: Data(#"{"code":200,"content":{"titles":[]}}"#.utf8))
    }
    let empty = try? await XboxGameService(auth: xblAuth, xuid: "2535410324111447", http: xblHTTP).fetch()
    check("Xbox 取数: 一条标题都没有时不打时长端点，也不报「没取到时长」",
          empty?.records.isEmpty == true && empty?.playtimeUnavailable == false
          && xblRequests("/v2/player/stats").isEmpty)

    ExternalImportStub.clear()
}

// ============================================================================
// 22. Xbox 成就：四项的组装规则 / 两格文本 / 读写口 / 平台列表展开 / 成就卡入场判据
// ============================================================================
do {
    // ① 组装规则：四个可空原始值 → `AchievementProgress?`。
    //    **四个都缺 → nil**（= 这条没有成就数据），而全 0 是「有成就套但一个都没拿到」的
    //    合法状态 —— 两者在界面上必须长得不一样（`—` vs `0 / 52`），同 `playedSeconds` 的纪律。
    check("成就组装: 四个都缺 → nil（不是全 0 的值）",
          AchievementProgress(earned: nil, total: nil,
                              gamerscoreEarned: nil, gamerscoreTotal: nil) == nil)
    check("成就组装: 只有成就数也算有数据",
          AchievementProgress(earned: 10, total: 20,
                              gamerscoreEarned: nil, gamerscoreTotal: nil) != nil)
    check("成就组装: 只有 Gamerscore 也算有数据",
          AchievementProgress(earned: nil, total: nil,
                              gamerscoreEarned: 5, gamerscoreTotal: 0) != nil)
    // 缺的那几个按 0 收（值类型里没有可空字段），不错位到别的格子上。
    let partial = AchievementProgress(earned: 3, total: nil, gamerscoreEarned: nil, gamerscoreTotal: 2000)
    check("成就组装: 缺的字段按 0 收，不错位",
          partial?.earned == 3 && partial?.total == 0
          && partial?.gamerscoreEarned == 0 && partial?.gamerscoreTotal == 2000)

    // 负数（服务端自相矛盾）按 0 收 —— 同 `PSNAPI.trophyProgress`。
    // **不整条丢掉**：一个负分不该把同一响应里其余三个正确的数一起判死。
    let negative = AchievementProgress(earned: -5, total: 20, gamerscoreEarned: -1, gamerscoreTotal: -2)
    check("成就组装: 负数按 0 收，其余字段照留",
          negative?.earned == 0 && negative?.gamerscoreEarned == 0
          && negative?.gamerscoreTotal == 0 && negative?.total == 20)

    // ② 两格文本。总数 0 → nil（那一格显示 `—`）：Xbox 上确实有条目带 `totalAchievements = 0`
    //    与 `totalGamerscore = 0`（没有成就的游戏 / 应用），写 `0 / 0` 看起来像坏了。
    check("成就文本: 「已得 / 总数」",
          AchievementProgress(earned: 25, total: 52, gamerscoreEarned: 1240, gamerscoreTotal: 2000)?
              .achievementsText == "25 / 52")
    // 一个都没拿是**合法状态**，照实写 0 / 52，不能退化成「—」。
    check("成就文本: 一个都没拿也照实写 0 / 52（不是「—」）",
          AchievementProgress(earned: 0, total: 52, gamerscoreEarned: 0, gamerscoreTotal: 1000)?
              .achievementsText == "0 / 52")
    check("成就文本: 总数 0 → nil（界面显示「—」）",
          AchievementProgress(earned: 0, total: 0, gamerscoreEarned: 0, gamerscoreTotal: 0)?
              .achievementsText == nil)
    check("游戏分数文本: 同口径（有总数才成文本）",
          AchievementProgress(earned: nil, total: nil, gamerscoreEarned: 1240, gamerscoreTotal: 2000)?
              .gamerscoreText == "1240 / 2000"
          && AchievementProgress(earned: nil, total: nil, gamerscoreEarned: 0, gamerscoreTotal: 0)?
              .gamerscoreText == nil)
    check("成就格: hasDisplayableValue 只在两格里至少一格有数字时为真",
          AchievementProgress(earned: 0, total: 0, gamerscoreEarned: 0, gamerscoreTotal: 0)?
              .hasDisplayableValue == false
          && AchievementProgress(earned: 0, total: 52, gamerscoreEarned: 0, gamerscoreTotal: 0)?
              .hasDisplayableValue == true)

    // ②b Gamerscore 完成度环的那个百分比（2026-09-18 成就卡新增环）。
    check("成就环: 百分比按 Gamerscore 算（1240 / 2000 → 62）",
          AchievementProgress(earned: 25, total: 52, gamerscoreEarned: 1240, gamerscoreTotal: 2000)?
              .gamerscorePercent == 62)
    // ⚠️ 这两条是**故意不一样**的：环量的是 Gamerscore，不是成就数。
    //    每个成就 5–100 点、由发行方自定，两者在真实数据上并不相等（用户点名的就是 gamerscore）。
    check("成就环: 量的是 Gamerscore 不是成就数（一半成就 ≠ 一半分）",
          AchievementProgress(earned: 26, total: 52, gamerscoreEarned: 200, gamerscoreTotal: 2000)?
              .gamerscorePercent == 10)
    check("成就环: 总分为 0 → nil（整只环不画，而不是画一只 0% 的空槽）",
          AchievementProgress(earned: 10, total: 52, gamerscoreEarned: 0, gamerscoreTotal: 0)?
              .gamerscorePercent == nil
          && AchievementProgress(earned: nil, total: nil, gamerscoreEarned: nil, gamerscoreTotal: nil) == nil)
    // 「有套但一分没拿」是另一种合法状态，必须画得出来 —— 与上面那条分得开。
    check("成就环: 有总分但一分没拿 → 0（画空槽，不是不画）",
          AchievementProgress(earned: 0, total: 52, gamerscoreEarned: 0, gamerscoreTotal: 1000)?
              .gamerscorePercent == 0)
    check("成就环: 已得 > 总数（服务端自相矛盾）夹到 100，不画出超过一圈的弧",
          AchievementProgress(earned: 52, total: 52, gamerscoreEarned: 3000, gamerscoreTotal: 2000)?
              .gamerscorePercent == 100)
    check("成就环: 四舍五入到整数（1 / 8 → 13，3 / 8 → 38）",
          AchievementProgress(earned: nil, total: nil, gamerscoreEarned: 1, gamerscoreTotal: 8)?
              .gamerscorePercent == 13
          && AchievementProgress(earned: nil, total: nil, gamerscoreEarned: 3, gamerscoreTotal: 8)?
              .gamerscorePercent == 38)
    // ⚠️ 环的比例由 `ExternalRing` 从这个整数现算（环只收 `percent`）——
    //    这条钉住「中心那行字与弧长永远一致」这个构造性约束在模型侧的取值形状。
    check("成就环: 总分为 0 而分数不为 0（服务端自相矛盾）仍按「没有数据」处理 → nil",
          AchievementProgress(earned: nil, total: nil, gamerscoreEarned: 500, gamerscoreTotal: 0)?
              .gamerscorePercent == nil)

    // ③ `ExternalGameRecord.achievements` 是四个字段的唯一读写口（拼/拆都在那一处）。
    let acContext = ModelContext(container)
    let acGame = Game(name: "成就卡游戏", platform: "Xbox Series X|S")
    acContext.insert(acGame)

    func acRecord(provider: AccountProvider = .xbox,
                  achievements: AchievementProgress? = nil,
                  last: Date? = nil, seconds: Int? = nil,
                  titleId: String = "2131196662") -> ExternalGameRecord {
        let r = ExternalGameRecord(provider: provider, externalAccountId: "ACC-AC",
                                   titleId: titleId, titleName: "Achievement Title",
                                   platform: "Xbox Series X|S",
                                   lastPlayedAt: last, playedSeconds: seconds,
                                   achievements: achievements)
        acContext.insert(r)
        r.game = acGame
        return r
    }

    let halo = acRecord(achievements: AchievementProgress(earned: 10, total: 20,
                                                          gamerscoreEarned: 100, gamerscoreTotal: 200))
    check("成就读写口: init 传进去的四个数原样读回",
          halo.achievements == AchievementProgress(earned: 10, total: 20,
                                                   gamerscoreEarned: 100, gamerscoreTotal: 200))
    check("成就读写口: 一个字段都没设 → 读回 nil",
          acRecord().achievements == nil)
    // 写 nil 要把四个字段一起清空（不能只清掉一个，留三个孤儿值）。
    let cleared = acRecord(achievements: AchievementProgress(earned: 1, total: 2,
                                                             gamerscoreEarned: 3, gamerscoreTotal: 4))
    cleared.achievements = nil
    check("成就读写口: 写 nil 四个字段一起清空",
          cleared.achievements == nil && cleared.achievementEarned == nil
          && cleared.achievementTotal == nil && cleared.gamerscoreEarned == nil
          && cleared.gamerscoreTotal == nil)
    // 单写一个字段也能读出一个值（不全缺 → 有数据），读回来的另外三个是 0 而不是 nil。
    let single = acRecord()
    single.gamerscoreTotal = 1000
    check("成就读写口: 只落一个字段也算有数据（另外三个按 0 读回）",
          single.achievements == AchievementProgress(earned: 0, total: 0,
                                                     gamerscoreEarned: 0, gamerscoreTotal: 1000))

    // ④ 平台列表展开：`platformRaw`（逗号分隔）→ 每个平台各自的 canonical 值。
    check("平台展开: 两个世代的 devices 展开成两个平台",
          XboxAPI.platforms(forRawPlatforms: "XboxOne,XboxSeries") == ["Xbox One", "Xbox Series X|S"])
    check("平台展开: 保留来源给的顺序",
          XboxAPI.platforms(forRawPlatforms: "Xbox360,XboxOne") == ["Xbox 360", "Xbox One"])
    check("平台展开: 重复项去重",
          XboxAPI.platforms(forRawPlatforms: "PC,PC") == ["PC"])
    check("平台展开: 认不出的那一项丢掉，不整条归兜底",
          XboxAPI.platforms(forRawPlatforms: "XboxSeries,Wat") == ["Xbox Series X|S"])
    check("平台展开: 空格与空串被剔掉",
          XboxAPI.platforms(forRawPlatforms: " PC , ,XboxOne ") == ["PC", "Xbox One"])
    check("平台展开: nil / 空串 → 空数组",
          XboxAPI.platforms(forRawPlatforms: nil).isEmpty
          && XboxAPI.platforms(forRawPlatforms: "  ").isEmpty)

    // 成就卡头部那行「哪个版本」—— **只在有 platformRaw 时才有**，否则退回折算后的单值。
    check("成就卡副标题: 平台列表拼成 `Xbox One/Xbox Series X|S`",
          acRecord(titleId: "T-PLAT-1").xboxPlatformDisplay == "Xbox Series X|S")   // 没 raw → 退回 platform
    let rawRecord = acRecord(titleId: "T-PLAT-2")
    rawRecord.platformRaw = "XboxOne,XboxSeries"
    check("成就卡副标题: 有 platformRaw 时按**列表**展开（不塌成单值）",
          rawRecord.xboxPlatformDisplay == "Xbox One/Xbox Series X|S")
    check("成就卡副标题: 非 Xbox 记录没有这一行",
          acRecord(provider: .playstation, titleId: "T-PLAT-3").xboxPlatformDisplay == nil)

    // ④b 搜索要匹配的**来源事实清单** —— 它之所以在模型上而不在账号页视图里，就是为了这一段。
    // 这条漏真发生过（2026-09-18 对等审计 GAP 1）：清单原本在视图里现拼，于是漏掉了 Xbox 的
    // 平台列表，用户在账号页按来源侧的平台搜不到那条记录，而 PSN 侧同样情形搜得到。
    let searchXbox = acRecord(titleId: "T-SEARCH-1")
    searchXbox.platformRaw = "XboxOne,XboxSeries"
    check("搜索来源事实: Xbox 记录收 canonical 平台 + 平台列表 + 编号",
          searchXbox.searchExtras.compactMap { $0 }
              == ["Xbox Series X|S", "Xbox One/Xbox Series X|S", "T-SEARCH-1"])
    // 入场判据：`platform` 被折算成「最新的一代」，来源列表里那个旧世代只能靠 display 找到。
    check("搜索来源事实: 按来源列表里的另一个世代搜得到（GAP 1 的回归位）",
          GameLinker.matches(query: "Xbox One", title: searchXbox.titleName,
                             extras: searchXbox.searchExtras))
    // 反证：少了平台列表这一项就搜不到 —— 说明上一条断言真的在测那件事，不是在测标题。
    check("搜索来源事实: 拿掉平台列表就搜不到（反证上一条不是靠标题蒙对的）",
          !GameLinker.matches(query: "Xbox One", title: searchXbox.titleName,
                              extras: [searchXbox.platform, searchXbox.titleId]))
    // 没有 `platformRaw` 时 display 退回 `platform`，于是同一串值出现两次。**无害**
    //（`matches` 只是逐个 contains，重复项不多花什么），但把它钉住 —— 免得下次有人把它当 bug。
    check("搜索来源事实: 无 platformRaw 时 display 退回 platform（同值出现两次，无害）",
          acRecord(titleId: "T-SEARCH-2").searchExtras.compactMap { $0 }
              == ["Xbox Series X|S", "Xbox Series X|S", "T-SEARCH-2"])
    // 每家只收**自己**那份平台列表：另一家的显示字段对本家恒为 nil，不会把别人的平台名带进来。
    let searchPSN = acRecord(provider: .playstation, titleId: "T-SEARCH-3")
    searchPSN.platformRaw = "PS3,PS4"
    check("搜索来源事实: PSN 记录收 PSN 的平台列表，Xbox 那条为 nil",
          searchPSN.xboxPlatformDisplay == nil
          && searchPSN.searchExtras.compactMap { $0 }.contains("PS3/PS4"))

    // ⑤ 成就卡入场判据：**三类卡互斥** + 有内容才出卡。
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    check("成就卡: Xbox + 成就 → 出卡",
          acRecord(achievements: AchievementProgress(earned: 1, total: 2,
                                                     gamerscoreEarned: 5, gamerscoreTotal: 10),
                   titleId: "T-CARD-1").showsXboxAchievementCard)
    check("成就卡: Xbox 没有成就、只有最近游玩 → 出卡",
          acRecord(last: t0, titleId: "T-CARD-2").showsXboxAchievementCard)
    check("成就卡: Xbox 没有成就、只有时长 → 出卡",
          acRecord(seconds: 3_600, titleId: "T-CARD-3").showsXboxAchievementCard)
    check("成就卡: Xbox 什么都没有 → **不出卡**（只剩一个品牌名的卡比不显示更糟）",
          !acRecord(titleId: "T-CARD-4").showsXboxAchievementCard)
    // 「有 achievement 对象、但两个总数都是 0」—— 两格都会印 `—`，不算有内容。
    check("成就卡: achievements 非 nil 但两格都是「—」→ 不出卡（判 hasDisplayableValue 不判 != nil）",
          !acRecord(achievements: AchievementProgress(earned: 0, total: 0,
                                                      gamerscoreEarned: 0, gamerscoreTotal: 0),
                    titleId: "T-CARD-5").showsXboxAchievementCard)
    // 本判据存在的理由：三类卡在详情页并列摆在同一块区域，同一条记录不能出两张卡说两遍话。
    check("成就卡: **PSN 记录即使有成就数据也不出这张卡**（它走奖杯卡）",
          !acRecord(provider: .playstation,
                    achievements: AchievementProgress(earned: 1, total: 2,
                                                      gamerscoreEarned: 5, gamerscoreTotal: 10),
                    titleId: "T-CARD-6").showsXboxAchievementCard)
    check("成就卡: Nintendo 记录同理不出这张卡（它走游玩记录卡）",
          !acRecord(provider: .nintendo, last: t0, seconds: 3_600,
                    titleId: "T-CARD-7").showsXboxAchievementCard)
}

// 三语文案的齐平**不在这里验**：`L10n` 查的是 `Bundle.main` 的 lproj，而本脚本是一个裸
// 二进制（没有资源包），查不到会原样回 key —— 那样的断言永远是假绿。齐平由
// 「`diff` 三份 Localizable.strings 的 key 集合 + `plutil -lint`」那一步负责。
// 少一条的表现是界面上直接显示 key 字面量 —— 用户一眼看得见，但只有那一步能提前拦住它。
// 本批新加的两条是 `game.xbox.achievements` / `game.xbox.gamerscore`（成就卡那四格的标签
// 里，另外两格复用既有的 `game.activity.playtime` / `game.activity.lastPlayed`）。

print(failures == 0 ? "DATA SMOKE TEST PASSED" : "DATA SMOKE TEST FAILED: \(failures) failures")
exit(failures == 0 ? 0 : 1)
