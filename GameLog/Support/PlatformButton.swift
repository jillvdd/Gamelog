import SwiftUI

extension View {
    /// 跨平台按钮外观：双平台统一系统标准 bordered 按钮（圆角胶囊/圆角矩形边框）。
    /// 历史上 macOS 分支「保持原样」导致按钮渲染成可点文字（2026-08-24 按钮视觉审计后废弃该策略）。
    /// 图标工具栏类按钮不要用本修饰器（继续用 .borderless/.plain，系统 chrome 已提供可供性）。
    func appStandardButton() -> some View {
        buttonStyle(.bordered)
    }
}
