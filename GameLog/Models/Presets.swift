import Foundation

/// 预设值的类别，决定展示翻译用哪张词表。
enum PresetCategory {
    case platform
    case degree
}

/// 平台与通关程度的预设选项。UI 里提供"预设 + 自定义"：自定义时用户可直接输入任意字符串。
/// 存储始终使用 canonical 值（预设即中文词条，兼容历史数据）；展示层按当前语言翻译预设值，
/// 自定义值原样返回。这样筛选/统计按 canonical 分组，切换语言不会产生混杂数据。
enum Presets {
    static let platforms = [
        "PC", "Steam Deck", "Switch", "PS5", "PS4", "PS3",
        "Xbox Series X|S", "Xbox One", "手机", "掌机", "其他"
    ]

    static let degrees = [
        "主线通关", "全支线", "全结局", "全收集/白金", "多周目", "速通", "其他"
    ]

    private struct LocalizedPreset {
        let zh: String
        let ja: String
        let en: String
    }

    /// 仅收录需要翻译的词条；语言中性的预设（PC、Switch 等）不在表里，直接原样显示。
    private static let localized: [PresetCategory: [String: LocalizedPreset]] = [
        .platform: [
            "手机": .init(zh: "手机", ja: "スマホ", en: "Mobile"),
            "掌机": .init(zh: "掌机", ja: "携帯機", en: "Handheld"),
            "其他": .init(zh: "其他", ja: "その他", en: "Other"),
        ],
        .degree: [
            "主线通关": .init(zh: "主线通关", ja: "メインクリア", en: "Main Story"),
            "全支线": .init(zh: "全支线", ja: "全サブクエスト", en: "All Side Quests"),
            "全结局": .init(zh: "全结局", ja: "全エンディング", en: "All Endings"),
            "全收集/白金": .init(zh: "全收集/白金", ja: "全収集/プラチナ", en: "All Collectibles / Platinum"),
            "多周目": .init(zh: "多周目", ja: "周回", en: "Multiple Playthroughs"),
            "速通": .init(zh: "速通", ja: "スピードラン", en: "Speedrun"),
            "其他": .init(zh: "其他", ja: "その他", en: "Other"),
        ],
    ]

    /// 展示本地化：预设值返回当前语言文案；自定义值原样返回。
    static func display(_ value: String, category: PresetCategory, language: String) -> String {
        guard let entry = localized[category]?[value] else { return value }
        switch language {
        case "ja": return entry.ja
        case "en": return entry.en
        default: return entry.zh
        }
    }
}
