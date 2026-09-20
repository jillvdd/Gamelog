import CoreGraphics
import Foundation
import SwiftData

/// 六维评分维度。顺序即全局显示顺序（滑块 / 条形图 / 分享卡一致）。
enum Dimension: String, CaseIterable, Identifiable {
    case gameplay
    case design
    case story
    case art
    case music
    case performance

    var id: String { rawValue }

    /// 本地化 key，见 Localizable.strings（dimension.story 等）。
    var labelKey: String { "dimension.\(rawValue)" }
}

/// 游戏状态机：想玩 / 在玩 / 搁置 / 弃坑 / 长线游玩 / 已通关 / 未分类。
/// 想玩/在玩/搁置/弃坑是轻量状态：不挂通关记录（详情页隐藏记录区）；流转到 `completed` 或 `longRunning` 才挂记录。
/// 长线游玩对应已通关：挂通关记录、卡片显示评分（而非状态标签），用于长期运营游戏。
/// 存储 rawValue，展示走 L10n（status.backlog 等）。
///
/// ⚠️ `unclassified` **必须留在最后**：它是「还没有人来分过类」的 catch-all，不是状态机的一站。
/// 排在中间会让详情页状态滑块把「已通关」和「未分类」画成相邻两格，看起来像可以来回降级。
enum GameStatus: String, CaseIterable, Identifiable {
    case backlog
    case playing
    case paused
    case dropped
    case longRunning
    case completed
    /// 外部账号导入自动建库时的初始状态（`ImportCoordinator.makeGame`）。
    /// 语义 = 「这条是同步替我建的，我还没表过态」。用户一旦在详情页动过状态，它就和别的档位一样了。
    case unclassified

    var id: String { rawValue }
    var labelKey: String { "status.\(rawValue)" }

    /// 是否「已通关」或「长线游玩」：两者都挂通关记录、详情页显示记录区、卡片显示评分。
    var isCompletedOrLongRunning: Bool {
        self == .completed || self == .longRunning
    }
}

/// 详情页横幅里 Logo 的三档显示尺寸（宽度 = 横幅宽度 × 系数，随窗等比联动）。
enum LogoBannerSize: String, CaseIterable, Identifiable, LabelKeyed {
    case small
    case medium
    case large

    var id: String { rawValue }
    /// 横幅宽度占比：small ≈ 封面横向口径、medium = 基线 ×1.5、large 再放大。
    var widthRatio: CGFloat { switch self { case .small: 0.13; case .medium: 0.195; case .large: 0.26 } }
    var labelKey: String { "logo.size.\(rawValue)" }
}

/// 详情页横幅里 Logo 的垂直位置（在剩余空白中的锚点；默认 bottom——用户定稿）。
enum LogoBannerVertical: String, CaseIterable, Identifiable, LabelKeyed {
    case top
    case center
    case bottom

    var id: String { rawValue }
    var labelKey: String { "logo.vertical.\(rawValue)" }
}

/// 详情页横幅里 Logo 的水平位置。
enum LogoBannerHorizontal: String, CaseIterable, Identifiable, LabelKeyed {
    case leading
    case center
    case trailing

    var id: String { rawValue }
    var labelKey: String { "logo.horizontal.\(rawValue)" }
}

/// 游戏版本：普通完整版（默认无标记/nil）/ 试玩版（Demo）/ 其他（如 Apple Music 等软件、或 RetroArch 等侧载 homebrew）。
enum GameVersion: String, CaseIterable, Identifiable, LabelKeyed {
    case demo
    case other

    var id: String { rawValue }
    var labelKey: String { "game.version.\(rawValue)" }
}

/// 一个游戏（库条目）。创建时带首条通关记录，之后可追加。
/// 多语言名字：`name` 为英文名（必须、canonical），`nameZh`/`nameJa` 可选；
/// 展示时按当前语言用 `displayName(for:)` 回退（中文→nameZh，日文→nameJa，其余→name；
/// 槽为空时一律退到 `primaryName`）。
@Model
final class Game {
    /// 主名（canonical，存储用；展示按语言回退）。
    ///
    /// ⚠️ **可以是空串**（2026-09-16 起）：这条不变量从「必须有英文名」改成了
    /// 「**必须有一种语言的名称**」。导入进来的游戏，来源标题若是中日文就只进对应的语言槽
    /// （见 `ImportCoordinator.applyTitleLanguage`），`name` 留空 —— 用户要的是「选了繁體中文
    /// 就只填中文」，而不是把中文也复制进英文名那一栏。编辑页的校验随之改成「三种语言至少填一个」。
    ///
    /// 因此**不要**假定它非空：要拿「一个名字」用 `primaryName`，要按语言拿用 `displayName(for:)`。
    /// Schema 不变（`String` 换成空值不需要迁移）。
    var name: String
    /// 中文名（可选）。
    var nameZh: String?
    /// 日文名（可选）。
    var nameJa: String?
    var aliases: [String]
    /// 游戏主平台（状态机轻量状态无通关记录时用于展示/筛选；已通关时与通关记录平台合并去重）。
    var platform: String = ""
    var releaseDate: Date?
    /// 厂商（开发者，可选）。
    var developer: String?
    /// 发行商（可选）。
    var publisher: String?
    /// 游戏类型（如 RPG / AVG，可选，自由文本）。
    var genre: String?
    /// 五类图片一律 .externalStorage：数据落行外文件、按需懒加载。
    /// 内联 BLOB 在库上数百 MB 时，任何 @Query 重取/保存都会把全部图片一起物化，
    /// 是整页卡顿的结构性根因（2026-08-29 性能修复，改前 store 已快照）。
    @Attribute(.externalStorage) var coverData: Data?
    /// 1:1 方形封面（SteamGridDB 方形 grid；可选）。iOS 单列卡大图主格式。
    @Attribute(.externalStorage) var squareData: Data?
    /// 横向封面（SteamGridDB 920×430 横版 grid；可选）。展示位置待设计，先只做录入与存储。
    @Attribute(.externalStorage) var landscapeData: Data?
    /// 背景图（SteamGridDB heroes 宽幅横图；可选）。展示位置待设计。
    @Attribute(.externalStorage) var heroData: Data?
    /// 游戏 Logo（SteamGridDB logos 透明 PNG；可选）。详情页横幅在背景图之上展示。
    @Attribute(.externalStorage) var logoData: Data?
    /// Logo 横幅展示三档调节（源图尺寸/比例各异，用户按游戏微调；默认 = 基线观感）。
    var logoSize: String = LogoBannerSize.medium.rawValue
    var logoVertical: String = LogoBannerVertical.bottom.rawValue
    var logoHorizontal: String = LogoBannerHorizontal.leading.rawValue
    var reviewTitle: String = ""
    var reviewBody: String = ""
    var createdAt: Date
    /// 最近一次编辑时间（编辑详情保存时更新）；nil = 从未编辑（排序时退回 createdAt）。
    var updatedAt: Date?
    /// 状态机状态（GameStatus.rawValue）。默认已通关；想玩/在玩等轻量状态无通关记录。
    var status: String = GameStatus.completed.rawValue
    /// 我的最爱（用户标记；虚拟分组「我的最爱」的成员依据）。
    var isFavorite: Bool = false

    /// 是否是**外部账号导入**自动建出来的库条目（`ImportCoordinator.makeGame` 置 true）。
    ///
    /// 只为一件事存在：「清空该账号的导入数据」要能区分「同步替我建的、我还没碰过」与
    /// 「我自己建/改过的」。没有这个标记时两者在库里长得一模一样，清理就只能靠猜。
    /// **用户一旦编辑过这个游戏，标记不撤销** —— 撤销与否由清理动作自己判断（见
    /// `ExternalAccountBinder.purgeImportedData`：有用户数据的一律保留）。
    var isAutoCreated: Bool = false

    /// 版本类型（GameVersion.rawValue；nil 或空为标准完整版，"demo" 为试玩版，"other" 为其他软件/工具）。
    var versionTypeRaw: String? = nil

    var version: GameVersion? {
        get {
            guard let raw = versionTypeRaw, !raw.isEmpty else { return nil }
            return GameVersion(rawValue: raw)
        }
        set {
            versionTypeRaw = newValue?.rawValue
        }
    }

    @Relationship(deleteRule: .cascade, inverse: \Completion.game)
    var completions: [Completion]

    /// 持有记录（收藏家模式）：删除游戏级联删版本与照片。
    @Relationship(deleteRule: .cascade, inverse: \PhysicalCopy.game)
    var copies: [PhysicalCopy]

    /// 多对多：一个游戏可进多个分组。删除游戏不应级联删分组（分组可能属于其他游戏）。
    @Relationship(deleteRule: .nullify, inverse: \GameGroup.games)
    var groups: [GameGroup]

    /// 外部账号（Nintendo / PSN）同步来的游玩记录。
    ///
    /// `.nullify` 而非 `.cascade`：删掉这个游戏**不删**来源记录。两个理由——
    /// ① 来源记录是「账号上发生过的事实」，独立于用户的库条目；② 删游戏与记录的联系被
    /// 记在记录侧的 `isIgnored` 上（删除路径置位），下次同步不会把用户刚删掉的游戏又建回来。
    ///
    /// 声明处给 `= []` 是为了 SwiftData 轻量迁移：新增 to-many 关系不需要自定义迁移阶段。
    @Relationship(deleteRule: .nullify, inverse: \ExternalGameRecord.game)
    var externalRecords: [ExternalGameRecord] = []

    init(name: String, nameZh: String? = nil, nameJa: String? = nil,
         aliases: [String] = [], platform: String = "", releaseDate: Date? = nil,
         developer: String? = nil, publisher: String? = nil, genre: String? = nil,
         coverData: Data? = nil, squareData: Data? = nil, landscapeData: Data? = nil, heroData: Data? = nil,
         logoData: Data? = nil, logoSize: LogoBannerSize = .medium,
         logoVertical: LogoBannerVertical = .bottom, logoHorizontal: LogoBannerHorizontal = .leading,
         reviewTitle: String = "", reviewBody: String = "",
         createdAt: Date = .now, status: GameStatus = .completed,
         isFavorite: Bool = false, isAutoCreated: Bool = false,
         version: GameVersion? = nil) {
        self.name = name
        self.nameZh = nameZh
        self.nameJa = nameJa
        self.aliases = aliases
        self.platform = platform
        self.releaseDate = releaseDate
        self.developer = developer
        self.publisher = publisher
        self.genre = genre
        self.coverData = coverData
        self.squareData = squareData
        self.landscapeData = landscapeData
        self.heroData = heroData
        self.logoData = logoData
        self.logoSize = logoSize.rawValue
        self.logoVertical = logoVertical.rawValue
        self.logoHorizontal = logoHorizontal.rawValue
        self.reviewTitle = reviewTitle
        self.reviewBody = reviewBody
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.status = status.rawValue
        self.isFavorite = isFavorite
        self.isAutoCreated = isAutoCreated
        self.versionTypeRaw = version?.rawValue
        self.completions = []
        self.copies = []
        self.groups = []
        self.externalRecords = []
    }
}

// MARK: - 派生计算

extension Game {

    /// 这个实例是不是**还挂在某个 context 上**（即还活着、属性还能读）。
    ///
    /// 为什么需要这个判据：批量删除（「清空导入数据」一次删几百个条目、备份导入整库替换）
    /// 落盘之后，界面里那些「从 `@Query` 数组拿到的」Game 引用当场变成**已销毁模型**，
    /// 而 SwiftUI 可能还会拿旧数组再渲染一帧。读已销毁模型的属性会直接
    /// `Fatal error: This backing data was detached from a context without resolving
    /// attribute faults` —— 不是抛错，是整进程崩（2026-09-16 真机崩溃现场：卡片读
    /// `coverData`；外置存储的封面必须 fault 回 store，所以它必崩，而小的内联字段
    /// 恰好能从内存快照里读出来，这也是为什么崩溃点看起来只有封面）。
    ///
    /// ⚠️ **判据只能是 `modelContext == nil`，不能用 `isDeleted`**。真机探针实测：
    /// `context.delete(x)` 之后 `isDeleted == true`，但 `try context.save()` 之后
    /// **`isDeleted` 又翻回 `false`**，而 `modelContext` 保持 nil。用 `isDeleted`
    /// 写这道守卫，恰好守不住唯一需要它的那一刻（删除已落盘）。
    var isLive: Bool { modelContext != nil }

    /// 状态机状态（解析存储值，未知值兜底已通关）。
    var statusValue: GameStatus {
        get { GameStatus(rawValue: status) ?? .completed }
        set { status = newValue.rawValue }
    }

    /// Logo 横幅三档调节（解析存储值，未知值兜底默认档）。
    var logoSizeValue: LogoBannerSize {
        get { LogoBannerSize(rawValue: logoSize) ?? .medium }
        set { logoSize = newValue.rawValue }
    }
    var logoVerticalValue: LogoBannerVertical {
        get { LogoBannerVertical(rawValue: logoVertical) ?? .bottom }
        set { logoVertical = newValue.rawValue }
    }
    var logoHorizontalValue: LogoBannerHorizontal {
        get { LogoBannerHorizontal(rawValue: logoHorizontal) ?? .leading }
        set { logoHorizontal = newValue.rawValue }
    }

    /// 该游戏全部持有版本的总估值（按语言），无持有/无估值则 nil。
    /// 用于主页「价值最高」排序；与 HoldingsView/StatsView 的 totalEstimate 同口径。
    func totalEstimate(for language: String) -> Double? {
        let vals = copies.compactMap { $0.estValue(for: language) }
        return vals.isEmpty ? nil : vals.reduce(0, +)
    }

    /// 最近编辑时间（无编辑记录时退回创建时间），用于「最近编辑」排序。
    var lastEditedAt: Date {
        updatedAt ?? createdAt
    }

    /// 是否「已通关」或「长线游玩」：两者都挂通关记录、详情页显示记录区、卡片显示评分。
    var isCompletedOrLongRunning: Bool {
        statusValue == .completed || statusValue == .longRunning
    }

    /// 名字的兜底链：主名 → 中文名 → 日文名，全都为空才返回空串。
    ///
    /// **`name` 允许为空**（2026-09-16 起，见 `displayName(for:)` 的注释），所以凡是要拿
    /// 「一个名字」而不是「某个语言的名字」的地方（排序裁决、合并预览、搜索建议、封面搜索的
    /// 词条）都走这里，别再直接读 `name` 或自己拼 `?? name`。
    var primaryName: String {
        for candidate in [name, nameZh ?? "", nameJa ?? ""] where !candidate.isEmpty {
            return candidate
        }
        return ""
    }

    /// 参与同名匹配的全部名字（主名 / 中文名 / 日文名 / 别名），**去掉空的**。
    ///
    /// 空串在归一化后也是空串，`normalizedTitle` 的调用方本来就靠 `!isEmpty` 跳过它 ——
    /// 但那是每个调用方各写一遍的纪律；在这里滤掉，调用方就不必记得这件事。
    var allNames: [String] {
        ([name] + [nameZh, nameJa].compactMap { $0 } + aliases).filter { !$0.isEmpty }
    }

    /// 按当前语言的显示名：中文→中文名，日文→日文名，其余→主名；
    /// **当前语言的槽为空时退到 `primaryName`（而不是直接退到主名）**。
    ///
    /// 后半条是 2026-09-16 改的，配合「主名可以留空」这条新规矩：导入进来的游戏，
    /// 来源标题若是中日文就**只进它自己的语言槽**（不再往 `name` 里也塞一份，见
    /// `ImportCoordinator.applyTitleLanguage`）。于是会出现「`name` 为空、只有 `nameZh`
    /// 有值」的游戏 —— 英文界面必须退回那个中文名显示，否则卡片上是一片空白。
    ///
    /// 对旧数据（主名有值）行为完全不变：`nameZh` 为空时退到的 `primaryName` 就是 `name`。
    func displayName(for language: String) -> String {
        let preferred: String?
        switch language {
        case "zh-Hans": preferred = nameZh
        case "ja": preferred = nameJa
        default: preferred = nil
        }
        if let preferred, !preferred.isEmpty { return preferred }
        return primaryName
    }

    /// 通关记录按时间正序。
    var sortedCompletions: [Completion] {
        completions.sorted { $0.createdAt < $1.createdAt }
    }

    /// 最近一次通关日期（用于排序）。全部记录都无日期则 nil（排序时排最后）。
    var latestCompletionDate: Date? {
        completions.compactMap(\.date).max()
    }

    /// 该游戏出现过的所有平台，去重（通关记录平台 + 游戏主平台 + **来源记录的平台**）；
    /// 按平台预设的世代倒序排列，预设外的自定义值按字典序排在最后。
    ///
    /// 最后那一路是 2026-09-18 加的（用户原话：*「一个本身没有 PS 的游戏在绑定了 PS 记录后
    /// 应当也将 PS 视为一个平台」*）：他把三个地区的「人中之龙 0」PS 奖杯记录绑到自己的
    /// 「Yakuza 0」（平台只填了 Xbox One）上，可按 PS4 / PS3 筛选时那个条目是隐形的 ——
    /// 明明它下面挂着三条 PS 记录。
    ///
    /// 为什么是**派生**而不是把 `"PS4"` 写进 `platform`：写进去就不可逆 —— 解绑之后平台
    /// 还留着，用户只会觉得「它怎么还说自己是 PS4 游戏」。派生值跟着绑定关系走，解绑即消失，
    /// 而且**不动用户的声明**（他自己填的那个主平台永远是第一事实，编辑页读的也是它）。
    ///
    /// 这一处改了三条路径全部跟着走（库页的平台筛选 `LibraryQuery.filter`、统计页的
    /// 平台分布 `LibraryStats`、卡片上的平台图标）—— 与「判定只有一处」同一条纪律。
    var platformList: [String] {
        var list = completions.map(\.platform)
        if !platform.isEmpty { list.append(platform) }
        list.append(contentsOf: externalRecords.map(\.platform))
        return Presets.ordered(list)
    }

    /// 库显示分：已评分记录平均分的均值，取整到 0.1。无已评分记录则 nil。
    var libraryScore: Double? {
        libraryScore(platform: nil)
    }

    /// 库显示分（可限定某平台：只统计该平台下的通关记录）。
    func libraryScore(platform: String?) -> Double? {
        let averages = completions
            .filter { (platform == nil || $0.platform == platform) && $0.hasScores }
            .compactMap(\.recordAverage)
        return ScoreMath.libraryScore(recordAverages: averages)
    }

    /// 库内所有已评分记录平均分的原始均值（不取整）。无则 nil。排行榜按平均分排序用原始值，展示用取整值。
    func rawLibraryScore(platform: String?) -> Double? {
        let averages = completions
            .filter { (platform == nil || $0.platform == platform) && $0.hasScores }
            .compactMap(\.recordAverage)
        guard !averages.isEmpty else { return nil }
        return averages.reduce(0, +) / Double(averages.count)
    }

    /// 某维度在已评分记录上的均值（1–10），与 libraryScore 同一套已评分口径。无则 nil。
    func dimensionAverage(for dimension: Dimension) -> Double? {
        dimensionAverage(for: dimension, platform: nil)
    }

    /// 某维度均值（可限定某平台：只统计该平台下的通关记录）。
    /// 与 `recordAverage`/`libraryScore` 同一口径：越界分（<1 或 >10）不参与计算。
    func dimensionAverage(for dimension: Dimension, platform: String?) -> Double? {
        let values = completions
            .filter { (platform == nil || $0.platform == platform) && $0.hasScores }
            .compactMap { $0.score(for: dimension) }
            .filter { (1...10).contains($0) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// 搜索文本：主名 + 中文/日文名 + 全部别名，小写化（空值已由 `allNames` 滤掉）。
    var searchableText: String {
        allNames.map { $0.lowercased() }.joined(separator: " ")
    }

    /// 按名称或别名模糊匹配。
    func matches(search: String) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return true }
        return searchableText.contains(query)
    }
}
