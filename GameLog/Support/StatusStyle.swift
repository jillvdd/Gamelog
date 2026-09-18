import SwiftUI

// MARK: - 状态样式家（2026-08-29 深化）

/// GameStatus 的展示样式（颜色 / SF Symbol）与游戏徽章视图的**唯一**归属。
/// 此前 color 私有在 GameCardView、icon 私有在 GameDetailView，徽章规则
/// 「已通关/长线显示评分、未评不占位、否则状态胶囊」在三种卡形各写一遍
/// （宽卡曾与网格卡漂移过一次，靠手工对齐回来）。深化后一处改、三卡同步。
extension GameStatus {
    /// 状态主题色（卡片徽章 / 状态胶囊用）。
    var color: Color {
        switch self {
        case .backlog: .blue
        case .playing: .green
        case .paused: .orange
        case .dropped: .gray
        case .longRunning: .purple
        case .completed: .primary
        // 未分类 = 中性灰：它不该和任何一个真状态抢注意力（`.dropped` 的灰是「弃坑」的语义色，
        // 这里是「还没表过态」，所以用自适应的 `.secondary` 而不是固定灰）。
        case .unclassified: .secondary
        }
    }

    /// 状态 SF Symbol（详情页状态条等）。
    var statusIcon: String {
        switch self {
        case .backlog: "bookmark"
        case .playing: "play.circle"
        case .paused: "pause.circle"
        case .dropped: "xmark.circle"
        case .longRunning: "infinity"
        case .completed: "checkmark.circle"
        case .unclassified: "questionmark.circle"
        }
    }
}

/// 游戏徽章：右上角「评分 / 状态」的统一入口，规则即不变量——
/// 已通关/长线游玩显示库评分（未评分不渲染、不占位）；轻量状态显示状态胶囊。
///
/// - `.glass`：液态玻璃胶囊（评分 = 黑 30% 染色玻璃白字；状态 = 品牌色 55% 染色玻璃白字），
///   高 22、字号 12（bold 评分 / semibold 状态）、水平内边距 8——网格卡与 iOS 宽卡同款。
/// - `.plain`：列表行样式——评分 = 裸文字 15pt bold（未评分显示「未评分」secondary），
///   状态 = 小号非玻璃胶囊（字号 12、内边距 6×2、88% 实色底）。视觉与历史实现逐像素一致。
struct GameBadge: View {
    let game: Game
    let style: Style

    enum Style { case glass, plain }

    @Environment(\.appLanguageCode) private var language

    var body: some View {
        if game.isCompletedOrLongRunning {
            scoreBadge
        } else {
            statusBadge
        }
    }

    @ViewBuilder
    private var scoreBadge: some View {
        if let score = game.libraryScore {
            switch style {
            case .glass:
                Text(verbatim: Self.formatScore(score))
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .glassCapsuleBadge(tint: Color.black.opacity(0.30),
                                       fallback: Color.black.opacity(0.72))
            case .plain:
                Text(verbatim: Self.formatScore(score))
                    .font(.system(size: 15, weight: .bold))
                    .monospacedDigit()
            }
        } else if style == .plain {
            // 列表行已通关但未评分：显示「未评分」占位（历史行为）。
            LText("score.unrated")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        // .glass 未评分不渲染、不占位（历史行为）。
    }

    private var statusBadge: some View {
        let status = game.statusValue
        switch style {
        case .glass:
            return AnyView(
                Text(verbatim: L10n.tr(status.labelKey, lang: language))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .glassCapsuleBadge(tint: status.color.opacity(0.55),
                                       fallback: status.color.opacity(0.88))
            )
        case .plain:
            return AnyView(
                Text(verbatim: L10n.tr(status.labelKey, lang: language))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(status.color.opacity(0.88), in: Capsule())
            )
        }
    }

    /// 库分显示格式（去掉多余小数：9.0 → "9.0"、9.15 → "9.2"——历史 formatScore 语义）。
    static func formatScore(_ score: Double) -> String {
        String(format: "%.1f", score)
    }
}
