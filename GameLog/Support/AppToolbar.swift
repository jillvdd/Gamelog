import SwiftUI
#if os(macOS)
import AppKit
#endif

/// macOS 全屏工具栏毛玻璃处理 + 「隐藏上方毛玻璃」开关（全局应用，各顶层页面共用）。
///
/// - 默认（开关关）：工具栏玻璃 + 标题恒在；全屏下玻璃比工具栏布局（contentLayoutRect/safeArea 都返回 52）
///   多延伸约一行（24pt）盖住内容顶端——这是系统渲染行为，无法用 API 压缩，故全屏时把内容
///   `.safeAreaPadding(.top, 24)` 下推到玻璃下沿之下（Library / 详情 / 统计等页面同一套处理）。
/// - 开关开启：隐藏工具栏玻璃（macOS 15+ 用 `toolbarBackgroundVisibility`；14 尽力透明），全屏也不下推。
///
/// 全屏状态变更必须包 `DispatchQueue.main.async`（在 `.onReceive` 回调里同步改 @State 会踩「视图更新期间发布变更」，
/// 曾导致 UI 挂死），详见 HANDOVER §6.28。iOS 无窗口全屏毛玻璃问题，本 modifier 在 iOS 为 no-op。
struct AppToolbarModifier: ViewModifier {
    @AppStorage(UserCustomization.hideToolbarGlassKey) private var hideToolbarGlass = false
    #if os(macOS)
    @State private var isFullScreen = false
    #endif

    func body(content: Content) -> some View {
        #if os(macOS)
        return content
            .modifier(ToolbarGlassModifier(hidden: hideToolbarGlass))
            .onAppear { setFullScreen(windowIsFullScreen) }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)) { _ in
                setFullScreen(true)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willExitFullScreenNotification)) { _ in
                setFullScreen(false)
            }
            .safeAreaPadding(.top, (!hideToolbarGlass && isFullScreen) ? 24 : 0)
        #else
        return content
        #endif
    }

    #if os(macOS)
    private func setFullScreen(_ value: Bool) {
        DispatchQueue.main.async {
            guard isFullScreen != value else { return }
            isFullScreen = value
        }
    }

    private var windowIsFullScreen: Bool {
        let win = NSApp.windows.first(where: { $0.isVisible }) ?? NSApp.mainWindow
        return win?.styleMask.contains(.fullScreen) ?? false
    }
    #endif
}

#if os(macOS)
/// 隐藏窗口工具栏毛玻璃（「隐藏上方毛玻璃」开关）。
/// macOS 15+ 用 `.toolbarBackgroundVisibility`（能真正隐藏）；macOS 14 无对应 API，尽力用透明背景。
private struct ToolbarGlassModifier: ViewModifier {
    let hidden: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbarBackgroundVisibility(hidden ? .hidden : .automatic, for: .windowToolbar)
        } else if hidden {
            content.toolbarBackground(Color.clear, for: .windowToolbar)
        } else {
            content
        }
    }
}
#endif

extension View {
    /// 全局应用全屏工具栏毛玻璃处理与「隐藏上方毛玻璃」开关。
    /// 应用到所有带工具栏的顶层页面（库 / 详情 / 统计 / 整体排名）。
    func appToolbar() -> some View {
        modifier(AppToolbarModifier())
    }
}
