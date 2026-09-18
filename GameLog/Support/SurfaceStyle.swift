import SwiftUI

/// 卡片 / 面板外观的唯一归属。
///
/// **唯一归属，别在调用处另起一套数值**（同 `StatusStyle` / `TagLabel` / `BrandPalette`
/// 的集中口径）。`Color.semantic(.controlBackground)` + 圆角这个组合此前在 6 个文件里
/// 手抄了十几遍，圆角值散落 9/10/12/14 四种 —— 同一视觉层级却不同数值，改一处永远找不齐。
///
/// 两档语义（沿用现有绝大多数站点的既有数值，**不改观感**）：
/// - **卡片** `cardRadius = 10`：库里的游戏卡 / 通关记录卡 / 统计小格 / 平台分布格。
/// - **面板** `panelRadius = 12`：整块统计区块（大数字格）。
///
/// 只覆盖 `controlBackground` 这一种底色。`HomeCarousel` 用的是自有的
/// `cardShape`（radius 16 `.continuous`，且 `clipShape` / `strokeBorder` 共用同一个形状）——
/// 那已经是单一归属，不并进来。
enum SurfaceStyle {

    /// 卡片圆角（游戏卡 / 记录卡 / 统计小格）。
    static let cardRadius: CGFloat = 10

    /// 面板圆角（整块统计区块）。
    static let panelRadius: CGFloat = 12

    // MARK: - 分段滑块

    /// 滑块胶囊的选中块底色。
    static let segmentHighlight = Color.accentColor.opacity(0.18)

    /// 滑块胶囊的描边色。
    static let segmentTrack = Color.accentColor.opacity(0.45)

    /// 滑块位移动画。`DetailStatusPicker` / `detailTabPicker` / `SegmentSlider` /
    /// `HoldingsView` 四处共用同一手感，改速度请改这里。
    static let segmentSpring: Animation = .spring(response: 0.3, dampingFraction: 0.78)
}

extension View {

    /// 卡片底色（radius 10 + `controlBackground`）。
    func appCardSurface() -> some View {
        background(RoundedRectangle(cornerRadius: SurfaceStyle.cardRadius)
            .fill(Color.semantic(.controlBackground)))
    }

    /// 面板底色（radius 12 + `controlBackground`）。
    func appPanelSurface() -> some View {
        background(RoundedRectangle(cornerRadius: SurfaceStyle.panelRadius)
            .fill(Color.semantic(.controlBackground)))
    }
}
