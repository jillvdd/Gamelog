import SwiftUI

/// 液态玻璃设计语言的统一按压/悬停反馈。
///
/// 适用两类场景（系统 `.bordered` / `.borderless` 按钮自带按压高亮与悬停效果，**不要**再套用）：
/// 1. 由 `onTapGesture` 改造而来的可点行 / 格子（此前点按无任何视觉响应，违背平台
///    「每个可点元素都有触控反馈」的基本预期）；
/// 2. 自定义分段控件（SegmentSlider / DetailStatusPicker 等）的分段按钮——选中滑块
///    已有 spring 动画，分段本体补上按压形变。
///
/// 平台差异：iOS = 按压缩放 + 变淡；macOS 额外带悬停轻微变淡（提示可点，
/// 与 macOS 26 液态玻璃的悬停高亮语言一致）。
struct PressFeedbackButtonStyle: ButtonStyle {
    /// 按压时的缩放（行/格子用默认 0.97，分段等小元素可传 0.94 更明显）。
    var pressedScale: CGFloat = 0.97
    /// 按压时的透明度。
    var pressedOpacity: Double = 0.65
    /// macOS 悬停时的透明度（轻微变淡提示可点；iOS 无悬停不生效）。
    var hoverOpacity: Double = 0.85

    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? pressedOpacity : (hovering ? hoverOpacity : 1))
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: hovering)
            #if os(macOS)
            .onHover { hovering = $0 }
            #endif
    }
}
