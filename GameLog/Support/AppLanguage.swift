import Foundation

/// 界面语言。默认中文，设置里可切换中日英。
enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese
    case japanese
    case english

    var id: String { rawValue }

    var localeCode: String {
        switch self {
        case .chinese: "zh-Hans"
        case .japanese: "ja"
        case .english: "en"
        }
    }

    var displayName: String {
        switch self {
        case .chinese: "中文"
        case .japanese: "日本語"
        case .english: "English"
        }
    }

    /// 从 `localeCode` 反查。
    /// UI 层通过 `\.appLanguageCode` 拿到的是 localeCode 而不是 case，而网络层要的是 case
    /// （`Gentry-Locale` / `Accept-Language` 都由 case 决定），所以需要一个反查入口。
    /// 认不出来一律按中文 —— 与 `AppLanguage.chinese` 是全局默认值保持一致。
    init(localeCode: String) {
        switch localeCode {
        case AppLanguage.japanese.localeCode: self = .japanese
        case AppLanguage.english.localeCode: self = .english
        default: self = .chinese
        }
    }
}
