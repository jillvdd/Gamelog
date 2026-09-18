import SwiftUI

/// 库查询与排序的**唯一**归属（2026-08-29 深化）。
/// 此前：7 个排序项在同一文件里逐字写了两遍（macOS 工具栏 / iOS 更多菜单，64 行重复且已
/// 结构性漂移）；filter+排序链内联在 LibraryView.visibleGames；稳定平级裁决（显示名→创建时间，
/// 修过「并列条目跳动」bug）在 GroupGamePickerView 缺席——并列游戏会在重渲染时换位。
/// 深化后：排序项 = 一个 case + labelKey + 一条比较器，菜单与管线一处改、处处同步、可测试。
enum LibrarySort: String, CaseIterable, Identifiable {
    case name
    case releaseDate
    case completionDate
    case scoreAscending
    case scoreDescending
    case recentEdit
    case valueDescending

    var id: String { rawValue }

    /// 菜单文案 key（library.sortBy* 三语）。
    var labelKey: String {
        switch self {
        case .name: "library.sortByName"
        case .releaseDate: "library.sortByRelease"
        case .completionDate: "library.sortByCompletion"
        case .scoreAscending: "library.sortByScoreAsc"
        case .scoreDescending: "library.sortByScoreDesc"
        case .recentEdit: "library.sortByRecentEdit"
        case .valueDescending: "library.sortByValueDesc"
        }
    }

    /// 菜单展示顺序（最近编辑置顶——历史定案）。
    static var menuOrder: [LibrarySort] {
        [.recentEdit, .name, .releaseDate, .completionDate, .scoreAscending, .scoreDescending, .valueDescending]
    }

    /// 主比较器（a 是否排在 b 前）。nil 处理沿用历史：未评分/无日期/无估值沉底。
    func areInOrder(_ a: Game, _ b: Game, language: String) -> Bool {
        switch self {
        case .name:
            a.displayName(for: language).localizedCaseInsensitiveCompare(b.displayName(for: language)) == .orderedAscending
        case .releaseDate:
            (a.releaseDate ?? .distantPast) > (b.releaseDate ?? .distantPast)
        case .completionDate:
            (a.latestCompletionDate ?? .distantPast) > (b.latestCompletionDate ?? .distantPast)
        case .scoreAscending:
            // 未评分（nil）按无穷大处理，排在已评分之后。
            (a.rawLibraryScore(platform: nil) ?? .greatestFiniteMagnitude) < (b.rawLibraryScore(platform: nil) ?? .greatestFiniteMagnitude)
        case .scoreDescending:
            // 未评分（nil）按 -1 处理，排在已评分之后。
            (a.rawLibraryScore(platform: nil) ?? -1) > (b.rawLibraryScore(platform: nil) ?? -1)
        case .recentEdit:
            // 最近编辑：无编辑记录退回创建时间；越新越靠前。
            a.lastEditedAt > b.lastEditedAt
        case .valueDescending:
            // 价值最高（总估值，按当前语言）；无估值（nil）排最后。
            (a.totalEstimate(for: language) ?? -1) > (b.totalEstimate(for: language) ?? -1)
        }
    }
}

enum LibraryQuery {

    /// 库过滤：分组（双向关系直取）/平台/状态/搜索，各层可选。
    static func filter(games: [Game], group: GameGroup?, platform: String?,
                       status: GameStatus?, search: String) -> [Game] {
        var result: [Game]
        if let group {
            // 分组视图直接以双向关系为准：关系变化（右键移出/加入）立即反映。
            result = group.games
        } else {
            result = games
        }
        if let platform {
            result = result.filter { $0.platformList.contains(platform) }
        }
        if let status {
            result = result.filter { $0.statusValue == status }
        }
        if !search.isEmpty {
            result = result.filter { $0.matches(search: search) }
        }
        return result
    }

    /// 稳定排序：主比较器并列时以「显示名 → 创建时间」裁决——Swift sort 非稳定、
    /// 分组关系数组顺序也不保证，并列条目每次重算可能互换跳动（此裁决曾是修过的 bug，
    /// 全部排序消费方必须经此入口，不得自带 sort）。
    static func sorted(_ games: [Game], by option: LibrarySort, language: String) -> [Game] {
        var result = games
        result.sort { a, b in
            if option.areInOrder(a, b, language: language) { return true }
            if option.areInOrder(b, a, language: language) { return false }
            let an = a.displayName(for: language), bn = b.displayName(for: language)
            if an.caseInsensitiveCompare(bn) == .orderedAscending { return true }
            if bn.caseInsensitiveCompare(an) == .orderedAscending { return false }
            return a.createdAt < b.createdAt
        }
        return result
    }
}


/// 库视图模式（**双平台共用**）。
///
/// macOS 与 iOS 此前各有一套互不相干的机制：macOS 是一个 `@AppStorage("useGridView")` Bool，
/// iOS 是一个三态字符串枚举。两个 Bool 表达不了三个状态，所以加 macOS 方形网格时先把它们
/// 合并成这一个枚举，再按平台给出各自可用的子集。
///
/// **`wideCard` 只在 iOS、`squareGrid` 只在 macOS**：宽卡是给 iPad 横竖屏分档用的版式
///（`GameWideCardView` 自算几何），桌面窗口用不上；方形网格是用户点名要的桌面第三种视图。
/// 可选集合由 `available` 统一给出，两个平台的菜单/Picker 都从它取，不会再漂移。
enum LibraryViewMode: String, CaseIterable, Identifiable {
    case grid
    case squareGrid
    case wideCard
    case list

    var id: String { rawValue }

    var labelKey: String {
        switch self {
        case .grid: "library.gridView"
        case .squareGrid: "library.squareGridView"
        case .wideCard: "library.wideCardView"
        case .list: "library.listView"
        }
    }

    /// 菜单/Picker 里的图标。此前这串三元表达式内联在 iOS 的 Picker 里，加第三态时顺手收进来。
    var systemImage: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .squareGrid: "square.grid.3x3"
        case .wideCard: "rectangle.ratio.16.to.9"
        case .list: "list.bullet"
        }
    }

    /// 本平台可选集合。
    static var available: [LibraryViewMode] {
        #if os(macOS)
        [.grid, .squareGrid, .list]
        #else
        [.grid, .wideCard, .list]
        #endif
    }

    /// 把任意来源的原始值收敛成本平台合法的模式：未知值或**本平台不支持的档位**一律回退网格。
    /// 后者防的是「同一个键被另一平台的旧版本写过」这类跨版本情形，回退比渲染一个本平台
    /// 没有对应分支的档位安全（那会落到 `switch` 的默认分支或直接不渲染）。
    static func resolved(_ raw: String) -> LibraryViewMode {
        let mode = LibraryViewMode(rawValue: raw) ?? .grid
        return available.contains(mode) ? mode : .grid
    }
}

/// 排序菜单项（macOS 工具栏与 iOS 更多菜单共用；勾选态随 selection）。
/// 此前 7 个 Button 在 LibraryView 内逐字写两遍，新增排序键要同步改两处。
struct LibrarySortMenuItems: View {
    /// 持久化排序值（@AppStorage rawValue 字符串）。
    @Binding var sortRaw: String

    @Environment(\.appLanguageCode) private var language

    private var selection: LibrarySort {
        LibrarySort(rawValue: sortRaw) ?? .completionDate
    }

    var body: some View {
        ForEach(LibrarySort.menuOrder) { option in
            Button {
                sortRaw = option.rawValue
            } label: {
                if selection == option {
                    Label(L10n.tr(option.labelKey, lang: language), systemImage: "checkmark")
                } else {
                    Text(verbatim: L10n.tr(option.labelKey, lang: language))
                }
            }
        }
    }
}
