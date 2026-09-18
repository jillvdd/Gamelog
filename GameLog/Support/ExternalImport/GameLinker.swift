import Foundation

/// 外部记录 → 库里现有 `Game` 的匹配引擎。
///
/// **只用强键，弱键一律不自动合并。** 三条强键，按可靠性排序：
///
/// 1. **`titleId`** —— 同一个来源侧的同一个条目。库里已有别的记录用同一个 titleId 绑到了
///    某个 Game，那就是最硬的证据（可能来自另一个账号，也可能来自另一次同步）。
/// 2. **`conceptId`** —— PSN 官方给出的「同一游戏的不同版本」合并键（PS4 版与 PS5 版共享它）。
///    Nintendo 侧恒为 nil，所以这条天然只在 PSN 内部生效。
/// 3. **归一化后完全相等**的标题名 —— 启发式，所以只认全等。
///
/// **为什么坚持全等**：`contains` / 前缀 / 编辑距离这类弱键的失败方向是**不可逆的** ——
/// 把《最终幻想 VII》并进《最终幻想 VII 重制版》，用户看到的是两边的评分与记录混在一起，
/// 而原始归属已经没了。少匹配十条只是留在「待绑定」列表里等用户点一下；
/// 错误合并一次就是数据损坏。所以弱键只出现在 Phase 7 的**手动**绑定 UI 里，那里用户看得见。
///
/// 判定逻辑完全不碰 SwiftData：入参是值类型快照（`LinkCandidate`），返回的是下标。
/// 于是它可以脱离数据库离线断言（见 `Scripts/DataSmokeTest` 第 18 节）。
enum GameLinker {

    // MARK: - 匹配依据

    /// 命中的强键。关联值是**键的原文**（`exactName` 是归一化后的产物，不是标题原文）。
    enum Basis: Equatable, CustomStringConvertible {
        case titleId(String)
        case conceptId(String)
        case exactName(String)

        var description: String {
            switch self {
            case .titleId(let value): "titleId(\(value))"
            case .conceptId(let value): "conceptId(\(value))"
            case .exactName(let value): "exactName(\(value))"
            }
        }
    }

    /// 库里一条**已经绑到某个 Game** 的外部记录给出的线索。
    ///
    /// 只收 `titleId` / `conceptId` 两个键：其余字段（标题名、平台、时长）都是弱信息，
    /// 不参与强键匹配。未绑定的记录不产生线索 —— 它自己没有指向任何 Game。
    struct Clue: Equatable {
        let titleId: String
        let conceptId: String?
    }

    /// 匹配引擎看到的候选：把 SwiftData 对象压成值类型的快照。
    ///
    /// `names` 是**同一个 Game** 的全部名字（英文名 / 中文名 / 日文名 / 别名）——
    /// 必须按 Game 分组而不是摊平成一个数组，否则「一个 Game 的名字与它自己的别名相同」
    /// 会被数成两个候选，判定结果反过来变成「有歧义，不匹配」。
    struct LinkCandidate: Equatable {
        var names: [String]
        var clues: [Clue]

        init(names: [String] = [], clues: [Clue] = []) {
            self.names = names
            self.clues = clues
        }
    }

    // MARK: - 判定

    /// 这条记录该并入哪个候选。
    ///
    /// - Parameters:
    ///   - dto: 来源侧解析出来的记录。
    ///   - candidates: 库里全部 Game 的快照，**顺序即调用方的 Game 数组顺序**（返回值是它的下标）。
    /// - Returns: `(候选下标, 依据)`；nil = 三条强键都没命中。
    static func match(_ dto: ExternalGameRecordDTO,
                      among candidates: [LinkCandidate]) -> (index: Int, basis: Basis)? {
        // ① titleId：同一个来源条目。命中多个也取第一个 —— 同一个 titleId 只可能属于一个 Game
        //    （它是记录的唯一键的一部分，两条同名记录不会存在）。
        //
        //    ⚠️ 两边都 trim 过再比：协调器处处以 trim 后的 titleId 落库（那是唯一键的第 3 段），
        //    而传进本函数的 DTO 是**原始**值。不统一的话，一条末尾带空格的来源记录会既匹配
        //    不上任何线索（退化成名字启发式），又和库里 trim 过的那条记录撞不成同一个 key。
        if let titleId = normalizedKey(dto.titleId),
           let index = candidates.firstIndex(where: { candidate in
               candidate.clues.contains { normalizedKey($0.titleId) == titleId }
           }) {
            return (index, .titleId(titleId))
        }

        // ② conceptId：PSN 官方的版本合并键。
        //    与 ① 同口径：两边都归一化（trim）过再比，避免线索侧带尾空格时对不上。
        if let conceptId = normalizedKey(dto.conceptId),
           let index = candidates.firstIndex(where: { candidate in
               candidate.clues.contains { normalizedKey($0.conceptId) == conceptId }
           }) {
            return (index, .conceptId(conceptId))
        }

        // ③ 归一化全等同名。
        let target = normalizedTitle(dto.titleName)
        guard !target.isEmpty else { return nil }

        var hit: Int?
        for (index, candidate) in candidates.enumerated() {
            guard candidate.names.contains(where: { normalizedTitle($0) == target }) else { continue }
            // 两个候选同名时不猜：并错了不可逆，留给用户手动选。
            if hit != nil { return nil }
            hit = index
        }
        guard let index = hit else { return nil }
        return (index, .exactName(target))
    }

    /// 这条记录是否允许参与自动匹配 / 自动建库。
    ///
    /// **体验版与试玩版永不自动匹配**：它跟正片是两个东西，自动并进正片的 Game 会让用户
    /// 看到「玩过体验版」被记成玩过正片。这类记录照常入库（来源事实要留档），
    /// 只是不进游戏库，等用户手动决定。
    ///
    /// ⚠️ 这里**不**判「已忽略」（`record.isIgnored`）—— 那是「这条记录我不要了」，
    /// 属于用户对这条记录的处置而不是记录内容的性质，由 `ImportCoordinator`
    /// 在调用本引擎**之前**判掉（那里的决策阶梯第 ② 档）。
    static func allowsAutoMatching(_ versionType: ExternalVersionType) -> Bool {
        !versionType.isExcludedByDefault
    }

    // MARK: - 列表搜索

    /// 列表搜索的匹配口径 —— **三个账号列表共用这一处**（账号记录列表、关联选择器、合并选择器），
    /// 免得同一串关键词在一处搜得到、在另一处搜不到。
    ///
    /// 空查询一律通过 —— 调用方不必自己判空（判空写三遍就有一遍会写反）。
    ///
    /// **两边都走 `normalizedTitle`，平台与来源编号这类「代码」字段也不例外。** 这一条值得
    /// 说清楚：直觉上代码该原样包含（`_` 会被归一化吃掉），但**查询串同样被归一化**，所以
    /// 下划线不构成障碍；反过来，卡片上显示的是美化写法 `CUSA-01887`，而库里存的是
    /// `CUSA01887_00` —— 只有两边都归一（`cusa01887` ⊂ `cusa0188700`）用户照着屏幕打才搜得到，
    /// 原样包含恰恰**搜不到**。归一同时吃掉大小写、全半角与变音符，
    /// 于是 `psvita` / `PS Vita` / `ＰＳ　Ｖｉｔａ` 是同一次搜索。
    ///
    /// ⚠️ 这是**列表筛选**口径，与 `match(_:among:)` 的强键判定是两件事：那个回答「是不是同一个
    /// 游戏」（只认全等，并错不可逆），这个回答「用户想不想看见这一行」（包含即可，看错无代价）。
    ///
    /// - Parameters:
    ///   - query: 用户输入。
    ///   - title: 主标题（记录标题名 / 条目主名）。
    ///   - extras: 其余可搜字段（平台、来源编号、已关联条目的名字…）。nil 项直接跳过。
    static func matches(query: String, title: String, extras: [String?] = []) -> Bool {
        let needle = normalizedTitle(query)
        guard !needle.isEmpty else { return true }
        if normalizedTitle(title).contains(needle) { return true }
        return extras.contains { extra in
            guard let extra else { return false }
            return normalizedTitle(extra).contains(needle)
        }
    }

    /// 同一个口径的便捷重载：入参是一个条目的**全部名字**（`Game.allNames` 那种：
    /// 主名 + 中/日文名 + 别名）。第一个当主标题，其余当附加字段 —— 两处游戏选择器
    /// 若各自写一遍 `names.first ?? ""`，就会各自错一次。
    static func matches(query: String, names: [String]) -> Bool {
        matches(query: query, title: names.first ?? "", extras: Array(names.dropFirst()))
    }

    // MARK: - 标题归一化

    /// 标题归一化：大小写 / 全半角 / 变音符号折叠 → 只留字母与数字。
    ///
    /// 一次 `folding` 覆盖三件事，比分三步写更不容易漏：
    /// - `.caseInsensitive` —— `DEMO` / `demo`
    /// - `.widthInsensitive` —— 全角 `Ｔ` / 半角 `T`、全角空格（日文来源里很常见）
    /// - `.diacriticInsensitive` —— `Pokémon` / `Pokemon`（欧洲发行版标题的常态）
    ///
    /// 然后只保留 `alphanumerics`（Unicode 的 L* + N* 类），于是标点、空格、
    /// `™` `®` `©` 这类符号（So 类）全部消失，而汉字/假名/西里尔字母照常保留。
    /// `CharacterSet.alphanumerics` 不是 ASCII 集合 —— 这一条很关键，用 `[a-z0-9]` 过滤
    /// 会把《塞尔达传说》整条归一化成空串，于是中日文标题永远匹配不上。
    ///
    /// **只用于「是否同一个游戏」的判定，绝不回写**：库里的标题名始终是原样保存的。
    static func normalizedTitle(_ raw: String) -> String {
        let folded = raw.folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive],
                                 locale: nil)
        var out = String.UnicodeScalarView()
        for scalar in folded.unicodeScalars where CharacterSet.alphanumerics.contains(scalar) {
            out.append(scalar)
        }
        return String(out)
    }

    /// 可选键的归一化：空串与纯空白都算「没有」。
    private static func normalizedKey(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
