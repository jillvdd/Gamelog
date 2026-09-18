import Foundation

/// Nintendo 的 titleId → 平台归属。
///
/// ⚠️ **Undocumented / reverse-engineered**：任天堂没有公开这套编号规则，
/// 下面的前缀是**从真实账号实测归纳**出来的（2026-09-16，用户账号 187 条记录的现场核对，
/// 见 HANDOVER §54），**不是**官方文档。归纳依据有三条互相独立的证据：
///
/// 1. **编号本身**：`0100…` 是 Switch 卡带的商品编号段，`0005…` 是 Wii U 的（`00050000` 开头），
///    `0400…` 出现在 2026 年的 Switch 2 独占作品上（Splatoon Raiders / Donkey Kong Bananza /
///    Yakuza Kiwami 3 等）。`0004…` 是 3DS 段（本账号没有 3DS 记录，按同一套编号习惯登记）。
/// 2. **图片 CDN 与之一致**：Wii U 那批的 `imageUrl` 全在 `idbe-img-lp1.cdn.nintendo.net/wiiu/…`，
///    Switch / Switch 2 那批全在 `atum-img-lp1.cdn.nintendo.net/i/c/…` —— 接口自己就是按平台分图床的。
/// 3. **现场分布自洽**：187 条里 13 / 150 / 24 条分入 Wii U / Switch / Switch 2，
///    且分入 Wii U 的是 MARIO KART 8、Mii Maker、Internet Browser、Nintendo eShop 这类
///    只存在于 Wii U 的条目 —— 没有一条是靠我们猜错的。
///
/// **认不出来就返回 nil**（由调用方继续退到 `entry.system` 和 provider 兜底平台）：
/// 编号段会随新主机扩张，遇到不认识的段时宁可落回兜底值，也不要硬塞进某个平台。
enum NintendoTitleId {
    /// 前缀 → `Presets.platforms` 的 canonical 值。
    ///
    /// 用 `hasPrefix` 而非等值比较：后半段是商品序号，每款游戏都不同。
    private static let prefixes: [(prefix: String, platform: String)] = [
        ("0005", "Wii U"),
        ("0004", "3DS"),
        ("0100", "Nintendo Switch"),
        ("0400", "Nintendo Switch 2"),
    ]

    /// 按 titleId 前缀判断这个**游戏**属于哪个平台。认不出来返回 nil。
    ///
    /// ⚠️ 它回答的是「这个游戏是哪个平台的商品」，不是「用户在哪台机器上玩的」。
    /// 两者在「同一个 Switch 1 游戏在 Switch 2 上玩」时会不一致 —— 那种情况下我们取前者，
    /// 因为用户要的是「这个游戏属于哪个平台」这个筛选维度（详见 `NintendoPlayHistoryClient`）。
    static func platform(forTitleId titleId: String) -> String? {
        let trimmed = titleId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return nil }
        return prefixes.first { trimmed.hasPrefix($0.prefix) }?.platform
    }
}
