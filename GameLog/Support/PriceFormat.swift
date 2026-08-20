import Foundation

/// 按语言把金额格式化为货币字符串。
/// zh-Hans → 人民币（¥），ja → 日元（¥），其余 → 美元（$）。
/// 传入 nil 或 0 以下不调用（调用方负责「未填显示 —」）。
enum PriceFormat {
    /// 语言 locale code → 货币格式化器（缓存避免重复构造）。
    private static var formatters: [String: NumberFormatter] = [:]

    private static func formatter(for language: String) -> NumberFormatter {
        if let cached = formatters[language] { return cached }
        let locale: Locale
        switch language {
        case "zh-Hans": locale = Locale(identifier: "zh_CN")
        case "ja":       locale = Locale(identifier: "ja_JP")
        default:         locale = Locale(identifier: "en_US")
        }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = locale
        f.maximumFractionDigits = 0
        formatters[language] = f
        return f
    }

    /// 格式化金额（nil 时返回 nil，调用方显示「—」）。
    static func string(_ value: Double?, language: String) -> String? {
        guard let value else { return nil }
        return formatter(for: language).string(from: NSNumber(value: value))
    }
}
