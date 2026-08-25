import SwiftUI

// MARK: - 页面顶部工具栏的液态玻璃行为（macOS）
//
// 官方 Liquid Glass 的「长胶囊 + 每钮圆形 hover 高亮」在 iOS 26 由系统交互玻璃渲染；
// macOS 的 SwiftUI 工具条目没有等价 API（`.buttonStyle(.glass)` 会浮在系统共享底玻璃上、
// `.sharedBackgroundVisibility` 在 macOS 不存在——均已实测），Apple 自家 macOS app 走的是
// AppKit NSToolbar 内部实现。因此这里的落地方式：
//   外观 = 系统工具栏自动画的分组玻璃长胶囊（不要自叠 glassEffect，会双层）；
//   行为 = 分段样式内复刻官方悬停形态——悬停分段浮现圆形毛玻璃亮斑 + 按压压缩回弹。
//
// - iOS 全部 no-op：iOS 26 工具栏原生即带交互玻璃。

extension View {
    /// 工具栏按钮的平台样式：macOS = 分段按压/悬停形变 + 圆形毛玻璃 hover 亮斑；
    /// iOS = 系统默认。
    @ViewBuilder
    func toolbarSegmentStyle() -> some View {
        #if os(macOS)
        buttonStyle(LiquidGlassSegmentPressStyle())
        #else
        self
        #endif
    }

    /// 封面徽章的液态玻璃胶囊（macOS/iOS 26+）：`.glassEffect` + 可选染色
    /// （评分徽章深色玻璃、状态徽章品牌色染色玻璃，白字保持可读与颜色语义）。
    /// 26 以下回退指定填充色胶囊（原材质外观）。
    @ViewBuilder
    func glassCapsuleBadge(tint: Color?, fallback: Color) -> some View {
        #if os(macOS)
        if #available(macOS 26.0, *) {
            if let tint {
                glassEffect(.regular.tint(tint), in: .capsule)
            } else {
                glassEffect(.regular, in: .capsule)
            }
        } else {
            background(fallback, in: .capsule)
        }
        #else
        if #available(iOS 26.0, *) {
            if let tint {
                glassEffect(.regular.tint(tint), in: .capsule)
            } else {
                glassEffect(.regular, in: .capsule)
            }
        } else {
            background(fallback, in: .capsule)
        }
        #endif
    }
}

/// 系统分组玻璃长胶囊内单个按钮的液态玻璃行为：
/// 悬停时该分段浮现圆形毛玻璃亮斑（官方分组玻璃的 hover 形态），按下压缩变淡、spring 回弹。
/// 固定内容高 30pt = 标准液态玻璃按钮高度。
struct LiquidGlassSegmentPressStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(height: 30)
            .padding(.horizontal, 10)
            .background {
                // 圆形毛玻璃 hover 亮斑：材质圆 + 轻微提白，spring 浮现/收起。
                Circle()
                    .fill(.regularMaterial)
                    .overlay(Circle().fill(Color.white.opacity(0.12)))
                    .frame(width: 36, height: 36)
                    .opacity(hovering ? 1 : 0)
                    .scaleEffect(hovering ? 1.0 : 0.5)
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: hovering)
            }
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.85 : 1.0)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: configuration.isPressed)
            #if os(macOS)
            .onHover { hovering = $0 }
            #endif
    }
}
