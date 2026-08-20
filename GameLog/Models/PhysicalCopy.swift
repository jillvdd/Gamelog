import Foundation
import SwiftData

// MARK: - 藏品档案枚举（各自 CaseIterable，标签平铺进 L10n；不在枚举内做子分组）

/// 介质（7 档）：实体三类 + 数字三类。
/// `isPhysical` 判定实体（物理光盘/卡带/兑换码）vs 数字。
/// 旧 schema 存的是 `physical`/`digital`/`code`（beta 1.x 三态），迁移到新细分见 `migrate`。
enum CopyMedia: String, CaseIterable, Identifiable, LabelKeyed {
    case physicalStandard  // 实体标准版
    case physicalSpecial   // 实体特别版（首发、封套、铁盒、幻彩…）
    case physicalLimited   // 实体限定版（限量版、收藏版…）
    case digitalStandard   // 数字标准版
    case digitalPremium    // 数字高级版（高级版、豪华版…）
    case digitalUpgrade    // 数字升级包（Game Pass、数字版升级…）
    case physicalCode      // 实体版（内附游戏兑换码）
    var id: String { rawValue }
    var labelKey: String { "copy.media.\(rawValue)" }

    /// 实体类（光盘 / 卡带 / 兑换码）：true；数字类（标准/高级/升级）：false。
    var isPhysical: Bool {
        switch self {
        case .physicalStandard, .physicalSpecial, .physicalLimited, .physicalCode: true
        default: false
        }
    }

    /// 旧三态 → 新细分（未知兜底标准版）。
    static func migrate(_ raw: String) -> CopyMedia {
        if let v = CopyMedia(rawValue: raw) { return v }
        switch raw {
        case "physical": return .physicalStandard
        case "digital":  return .digitalStandard
        case "code":     return .physicalCode
        default:         return .physicalStandard
        }
    }
}

/// 版本区分（10 档）：地区 / 版本维度，与介质正交。
/// ⚠️ §29 规格未列成员，按合理 zh 优先列表重建，待用户在验收时核对/调整。
enum CopyRegional: String, CaseIterable, Identifiable, LabelKeyed {
    case standard  // 标准版
    case cn         // 国行
    case hk         // 港版
    case tw         // 台版
    case jp         // 日版
    case us         // 美版
    case eu         // 欧版
    case kr         // 韩版
    case asia       // 亚版
    case asiaEn     // 亚英版
    var id: String { rawValue }
    var labelKey: String { "copy.regional.\(rawValue)" }

    static func migrate(_ raw: String) -> CopyRegional {
        CopyRegional(rawValue: raw) ?? .standard
    }
}

/// 品相（7 档）：仅实体类有意义（`hasCondition = media.isPhysical`）。
/// ⚠️ §29 规格未列成员，按合理 zh 优先列表重建，待用户在验收时核对/调整。
enum CopyCondition: String, CaseIterable, Identifiable, LabelKeyed {
    case sealed    // 全新未拆
    case mint      // 近全新
    case excellent  // 极好
    case good      // 良好
    case fair      // 一般
    case worn      // 有使用痕迹
    case damaged   // 有瑕疵 / 破损
    var id: String { rawValue }
    var labelKey: String { "copy.condition.\(rawValue)" }

    static func migrate(_ raw: String) -> CopyCondition {
        CopyCondition(rawValue: raw) ?? .good
    }
}

/// 来源（11 档）：去掉旧 `firstHand`(首发) / `secondHand`(二手)，二手拆三档，
/// 新增 5 档海淘类，保留数字商店 / 兑换 / 其他。
enum CopyAcquisition: String, CaseIterable, Identifiable, LabelKeyed {
    case officialChannelOverseas    // 官方渠道海淘
    case dealerChannelOverseas      // 经销商渠道海淘
    case overseasDirectShipping     // 境外直邮
    case proxy                      // 代购
    case thirdPartyStore            // 第三方店铺购入
    case secondHandStoreOverseas    // 二手店海淘
    case personalSecondHandOverseas // 个人二手海淘
    case personalSecondHand         // 个人二手
    case digitalStore               // 数字商店
    case redemption                 // 兑换
    case other                      // 其他
    var id: String { rawValue }
    var labelKey: String { "copy.acquisition.\(rawValue)" }

    /// 旧两态 → 新值（未知兜底 other）。
    static func migrate(_ raw: String) -> CopyAcquisition {
        if let v = CopyAcquisition(rawValue: raw) { return v }
        switch raw {
        case "firstHand":  return .officialChannelOverseas
        case "secondHand": return .personalSecondHand
        default:           return .other
        }
    }
}

/// 持有记录（收藏家模式）：一个版本 + 数量 + 最多 6 张收藏照片 + 藏品档案。
@Model
final class PhysicalCopy {
    /// 版本名（必填，如「日版初版」「美版」）。
    var version: String
    /// 该版本持有数量（≥1）。
    var count: Int
    /// 收藏照片（最多 6 张）。「保存原图」关时存压缩 JPEG，开时存原图数据。
    var images: [Data]
    /// 添加先后（持有列表排序用）。
    var createdAt: Date

    /// 所属游戏（inverse 在 Game.copies 上声明）。
    var game: Game?

    // MARK: - 藏品档案（枚举存 rawValue，声明处给默认值以兼容 SwiftData 轻量迁移）

    /// 介质（7 档）。
    var mediaRaw: String = CopyMedia.physicalStandard.rawValue
    /// 版本区分（10 档，地区 / 版本维度，与介质正交）。
    var regionalRaw: String = CopyRegional.standard.rawValue
    /// 品相（7 档，仅实体类有意义）。
    var conditionRaw: String = CopyCondition.good.rawValue
    /// 来源（11 档）。
    var acquisitionRaw: String = CopyAcquisition.officialChannelOverseas.rawValue

    /// 三语价格各自独立槽位（按当前语言取单一槽位，未填 nil，不跨语言回退）。
    var priceZh: Double?
    var priceJa: Double?
    var priceEn: Double?
    /// 三语估值各自独立槽位。
    var estValueZh: Double?
    var estValueJa: Double?
    var estValueEn: Double?

    /// 购买日期（nil = 无）。
    var purchaseDate: Date?
    /// 备注。
    var notes: String = ""

    init(version: String, count: Int = 1, images: [Data] = [], createdAt: Date = .now,
         media: CopyMedia = .physicalStandard, regional: CopyRegional = .standard,
         condition: CopyCondition = .good, acquisition: CopyAcquisition = .officialChannelOverseas,
         priceZh: Double? = nil, priceJa: Double? = nil, priceEn: Double? = nil,
         estValueZh: Double? = nil, estValueJa: Double? = nil, estValueEn: Double? = nil,
         purchaseDate: Date? = nil, notes: String = "") {
        self.version = version
        self.count = count
        self.images = images
        self.createdAt = createdAt
        self.game = nil
        self.mediaRaw = media.rawValue
        self.regionalRaw = regional.rawValue
        self.conditionRaw = condition.rawValue
        self.acquisitionRaw = acquisition.rawValue
        self.priceZh = priceZh
        self.priceJa = priceJa
        self.priceEn = priceEn
        self.estValueZh = estValueZh
        self.estValueJa = estValueJa
        self.estValueEn = estValueEn
        self.purchaseDate = purchaseDate
        self.notes = notes
    }
}

// MARK: - 藏品档案派生访问

extension PhysicalCopy {
    /// 介质（读取走 migrate 兜底未知值，写入存 rawValue）。
    var media: CopyMedia {
        get { CopyMedia.migrate(mediaRaw) }
        set { mediaRaw = newValue.rawValue }
    }

    /// 版本区分。
    var regional: CopyRegional {
        get { CopyRegional.migrate(regionalRaw) }
        set { regionalRaw = newValue.rawValue }
    }

    /// 品相。
    var condition: CopyCondition {
        get { CopyCondition.migrate(conditionRaw) }
        set { conditionRaw = newValue.rawValue }
    }

    /// 来源。
    var acquisition: CopyAcquisition {
        get { CopyAcquisition.migrate(acquisitionRaw) }
        set { acquisitionRaw = newValue.rawValue }
    }

    /// 品相是否有意义：仅实体类（光盘 / 卡带 / 兑换码）。
    var hasCondition: Bool { media.isPhysical }

    /// 按当前语言取价格（严格单槽位，未填 nil，不跨语言回退）。
    func price(for language: String) -> Double? {
        switch language {
        case "zh-Hans": return priceZh
        case "ja":       return priceJa
        default:         return priceEn
        }
    }

    /// 按当前语言取估值（严格单槽位，未填 nil，不跨语言回退）。
    func estValue(for language: String) -> Double? {
        switch language {
        case "zh-Hans": return estValueZh
        case "ja":       return estValueJa
        default:         return estValueEn
        }
    }

    /// 把当前语言的价格写入对应槽位（其余槽位不动）。
    func setPrice(_ value: Double?, for language: String) {
        switch language {
        case "zh-Hans": priceZh = value
        case "ja":       priceJa = value
        default:         priceEn = value
        }
    }

    /// 把当前语言的估值写入对应槽位。
    func setEstValue(_ value: Double?, for language: String) {
        switch language {
        case "zh-Hans": estValueZh = value
        case "ja":       estValueJa = value
        default:         estValueEn = value
        }
    }
}
