import SwiftUI

extension View {
    /// 跨平台按钮外观：
    /// - iOS：系统标准 bordered 按钮（圆角胶囊、液态玻璃外观），避免 macOS 的文本/无边框按钮在 iOS 渲染成纯蓝字。
    /// - macOS：保持调用处原有样式不变。
    @ViewBuilder
    func appStandardButton() -> some View {
        #if os(iOS)
        buttonStyle(.bordered)
        #else
        self
        #endif
    }
}
