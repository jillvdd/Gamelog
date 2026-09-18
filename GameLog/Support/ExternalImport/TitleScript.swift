import Foundation

/// 一个标题**实际**是用什么文字写的 —— 不是「我们请求了什么语言」。
///
/// ## 为什么必须能判
///
/// 任天堂的 `titleName` 只返回**它有的那一种**语言，没有就回落到别的语言，而响应里
/// **没有任何字段说明这次回落发生了**。真账号实测（2026-09-16，151 个自动建库条目，
/// `Gentry-Locale: zh-TW`，请求本身没有被拒 —— `localeFallbackFrom` 是空的）：
///
/// | 返回的标题实际是什么 | 条数 |
/// |---|---|
/// | 汉字（真的繁體中文） | 62 |
/// | 拉丁字母（回落成英文） | 76 |
/// | 假名（回落成日文） | 13 |
///
/// 而改这一版之前的代码是「请求了 `zh-*` 就把标题写进 `nameZh`」—— 于是 **89 条英文/日文
/// 标题被写进了中文名槽**。中文界面看起来一切正常（`nameZh ?? name` 拿到的是同一串字符），
/// 但库里从此**谎称**这些游戏有中文名：编辑页打开显示「中文名已填」，用户以为已经好了；
/// `propagateTitle` 的「用户没改过这个字段」判据也在拿英文串做比对。
///
/// 判据只能看**字符本身** —— 这是唯一不依赖接口行为的证据。
///
/// ⚠️ 已知的判不准之处，如实记下：**纯汉字的日文标题**（「信長の野望」「幻想水滸伝」这类
/// 没有假名的）会被归成 `.han`，于是请求日文时它进 `nameJa`（正确），请求中文时它进
/// `nameZh`（把日文名当中文名）。要区分得靠简繁/和制汉字表，那是另一个量级的复杂度，
/// 而旧行为比这更差（一律照写），所以先接受这个边界。
enum TitleScript {
    /// 含汉字、不含假名 —— 中文（见上面那条边界）。
    case han
    /// 含假名 —— 一定是日文（中文标题里不会出现假名）。
    case kana
    /// 有字母但不是中日文（拉丁为主，也含希腊/西里尔）—— 一般是「来源没有这个语言的标题」。
    case other
    /// 空串、纯符号、纯数字。
    case none

    /// 判一个标题的文字种类。**优先级：假名 > 汉字 > 其它** ——
    /// 因为中日文标题里混拉丁词是常态（`異度神劍 終極版 Nintendo Switch 2 Edition`、
    /// `ケイデンス・オブ・ハイラル: … feat. ゼルダの伝説`），反过来不成立。
    static func of(_ title: String) -> TitleScript {
        var sawHan = false
        var sawOther = false
        for scalar in title.unicodeScalars {
            if isKana(scalar) { return .kana }
            if isHan(scalar) { sawHan = true; continue }
            if CharacterSet.letters.contains(scalar) { sawOther = true }
        }
        if sawHan { return .han }
        return sawOther ? .other : .none
    }

    /// 这个标题能不能当作 `localeCode` 那个语言的标题用。
    ///
    /// 用途：① `NintendoPlayHistoryClient` 判断「主 locale 吃满了没」，据此决定要不要
    /// 再试同语言的其它区域写法；② 界面统计「来源侧到底有多少条真的拿到了目标语言」。
    func matches(localeCode: String) -> Bool {
        let code = localeCode.lowercased()
        if code.hasPrefix("zh") { return self == .han }
        // 日文标题可能是纯汉字（「信長の野望」），所以汉字也算匹配。
        if code.hasPrefix("ja") { return self == .kana || self == .han }
        if code.hasPrefix("en") { return self == .other }
        // 不认识的 locale：不做判断。宁可什么都不说，也不要凭猜拦掉正确的数据。
        return true
    }

    /// 这个标题该写进库里的哪个语言槽（nil = 哪个都不写）。
    ///
    /// ⚠️ 判据是**标题本身**，不是「请求了什么」：
    /// - 拉丁标题（服务端回落成了英文）→ **哪个中文/日文槽都不写**。写了就是库里谎称有中文名。
    /// - 请求中文却拿回假名标题 → 那确实是这个游戏的日文名，写 `nameJa`
    ///   （改这一版之前是直接丢掉，那 13 条日文标题一个都没落到日文槽）。
    /// - 请求日文拿回汉字标题 → 写 `nameJa`（纯汉字的日文名，不能当中文名）。
    func languageSlot(requestedLocale: String) -> String? {
        switch self {
        case .kana: return "ja"
        case .han: return requestedLocale.lowercased().hasPrefix("ja") ? "ja" : "zh"
        case .other, .none: return nil
        }
    }

    // MARK: - 字符判定

    /// 汉字：CJK 统一表意文字 + 扩展 A + 兼容表意文字。
    private static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF: return true
        default: return false
        }
    }

    /// 假名：平假名 + 片假名。
    ///
    /// 排除 `・`（U+30FB，片假名中点）—— 它是中性分隔符，中日文标题都可能用它当间隔。
    /// 保留 `ー`（U+30FC，长音符）：它在中文里几乎不出现，而在日文里出现频率极高。
    private static func isKana(_ scalar: Unicode.Scalar) -> Bool {
        guard scalar.value != 0x30FB else { return false }
        switch scalar.value {
        case 0x3041...0x309F, 0x30A0...0x30FF: return true
        default: return false
        }
    }
}
