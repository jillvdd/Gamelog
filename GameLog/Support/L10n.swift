import SwiftUI

// MARK: - 环境变量：当前界面语言（locale code）

private struct AppLanguageKey: EnvironmentKey {
    static let defaultValue = AppLanguage.chinese.localeCode
}

extension EnvironmentValues {
    var appLanguageCode: String {
        get { self[AppLanguageKey.self] }
        set { self[AppLanguageKey.self] = newValue }
    }
}

// MARK: - 手动三语切换的字符串解析

/// 与系统 locale 无关，按选中的语言（appLanguageCode）从对应 lproj 查表。
enum L10n {
    static func tr(_ key: String, lang: String) -> String {
        bundle(for: lang).localizedString(forKey: key, value: nil, table: "Localizable")
    }

    static func tr(_ key: String, _ args: [CVarArg], lang: String) -> String {
        let format = bundle(for: lang).localizedString(forKey: key, value: nil, table: "Localizable")
        return args.isEmpty ? format : String(format: format, arguments: args)
    }

    private static func bundle(for lang: String) -> Bundle {
        guard let path = Bundle.main.path(forResource: lang, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }
}

/// 本地化文本视图：自动响应语言切换。
struct LText: View {
    let key: String
    var args: [CVarArg] = []
    @Environment(\.appLanguageCode) private var language

    init(key: String, args: [CVarArg] = []) {
        self.key = key
        self.args = args
    }

    /// 无标签写法：`LText("common.back")`（代码库惯例）。
    init(_ key: String, args: [CVarArg] = []) {
        self.key = key
        self.args = args
    }

    var body: some View {
        Text(verbatim: args.isEmpty ? L10n.tr(key, lang: language) : L10n.tr(key, args, lang: language))
    }
}
