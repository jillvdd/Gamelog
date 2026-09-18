import SwiftUI

// MARK: - 凭证状态样式（2026-09-16）

/// 「游戏账号」这一批界面共用的外观归属。
enum AccountUI {
    /// 同步按钮的图标。四处（账号列表的「全部同步」、详情页的状态区 / 语言区 / 清空回执）
    /// 必须是同一个字形，否则同一次操作在不同位置长得不一样。
    static let syncIcon = "arrow.triangle.2.circlepath"

    /// 记录行「已关联到某个游戏」那一行的色（与未关联的 `.secondary` 成对使用）。
    ///
    /// 只在本模块的**关联结果**这一个语义上生效 —— 别把它当成「本模块的绿色」：
    /// 旁边 `CredentialBadge` 的绿是「凭证可用」（`AccountCredentialState.tint`），
    /// 两者语义不同，只是恰好都取系统绿。
    static let linkedTint = Color.green
}

/// `AccountCredentialState` 的展示样式归属，与 `StatusStyle.swift` 里 `GameStatus` 的
/// `color` 同一套做法：颜色一处定义，所有徽章同步。
extension AccountCredentialState {
    /// 凭证状态主题色。
    var tint: Color {
        switch self {
        case .active: .green
        case .expired: .orange
        case .missing: .red
        case .none: .secondary
        }
    }
}

/// 凭证状态徽章。**只表达状态，不含任何凭证内容** —— 用户需要知道的只是
/// 「这个账号还能不能用」，那是 `AccountCredentialState` 的职责，不是 token 的。
struct CredentialBadge: View {
    let state: AccountCredentialState

    @Environment(\.appLanguageCode) private var language

    var body: some View {
        TagLabel(text: L10n.tr(state.labelKey, lang: language), tint: state.tint)
    }
}
