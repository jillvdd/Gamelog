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
}
