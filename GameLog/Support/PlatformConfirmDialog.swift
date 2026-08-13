import SwiftUI
#if !os(macOS)
import UIKit
#endif

/// 确认弹窗的单个动作（对应底部 action sheet / confirmationDialog 的按钮）。
struct ConfirmAction {
    var title: String
    var isDestructive: Bool = false
    var action: () -> Void = {}
}

extension View {
    /// 平台化确认弹窗：
    /// - macOS：系统 `confirmationDialog`（弹窗，带取消按钮）。
    /// - iOS：系统底部 action sheet（液态玻璃材质，破坏性按钮红色）。
    ///
    /// iOS 26 液态玻璃下，SwiftUI `.confirmationDialog` 呈现为居中、带指向触发元素尖角的浮窗，
    /// 不符合 iOS「底部 action sheet」的设计规范，这里改用 UIKit `UIAlertController(.actionSheet)`
    /// 强制从屏幕底部弹出（系统标准样式，自动带液态玻璃外观）。
    func platformConfirmDialog(
        _ title: String,
        isPresented: Binding<Bool>,
        message: String? = nil,
        cancelTitle: String,
        actions: [ConfirmAction]
    ) -> some View {
        #if os(macOS)
        return self.confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible) {
            ForEach(actions.indices, id: \.self) { index in
                let action = actions[index]
                if action.isDestructive {
                    Button(action.title, role: .destructive, action: action.action)
                } else {
                    Button(action.title, action: action.action)
                }
            }
            Button(cancelTitle, role: .cancel) {}
        } message: {
            if let message { Text(verbatim: message) }
        }
        #else
        return self.modifier(
            IOSActionSheetModifier(
                title: title,
                message: message,
                cancelTitle: cancelTitle,
                isPresented: isPresented,
                actions: actions
            )
        )
        #endif
    }
}

#if !os(macOS)
/// iOS 底部 action sheet：用 `UIAlertController(.actionSheet)` 从底部弹出（系统液态玻璃样式）。
private struct IOSActionSheetModifier: ViewModifier {
    let title: String
    let message: String?
    let cancelTitle: String
    @Binding var isPresented: Bool
    let actions: [ConfirmAction]

    func body(content: Content) -> some View {
        content.background {
            Presenter(
                title: title,
                message: message,
                cancelTitle: cancelTitle,
                isPresented: $isPresented,
                actions: actions
            )
            .frame(width: 0, height: 0)
        }
    }

    /// 挂载一个空 UIViewController 作为 present 锚点；`isPresented` 变 true 时弹出 action sheet。
    private struct Presenter: UIViewControllerRepresentable {
        let title: String
        let message: String?
        let cancelTitle: String
        @Binding var isPresented: Bool
        let actions: [ConfirmAction]

        func makeUIViewController(context: Context) -> UIViewController {
            UIViewController()
        }

        func updateUIViewController(_ viewController: UIViewController, context: Context) {
            guard isPresented else { return }
            let alert = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)
            for action in actions {
                alert.addAction(
                    UIAlertAction(
                        title: action.title,
                        style: action.isDestructive ? .destructive : .default
                    ) { _ in
                        action.action()
                    }
                )
            }
            alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel) { _ in })
            // iPhone 恒为底部 action sheet；iPad 需要 popover 锚点（居中、无箭头）。
            if let popover = alert.popoverPresentationController {
                popover.sourceView = viewController.view
                popover.sourceRect = CGRect(
                    x: viewController.view.bounds.midX,
                    y: viewController.view.bounds.midY,
                    width: 0,
                    height: 0
                )
                popover.permittedArrowDirections = []
            }
            viewController.present(alert, animated: true)
            // present 后立即复位，避免同一绑定反复触发；关闭由用户点按钮或点外部完成。
            DispatchQueue.main.async {
                isPresented = false
            }
        }
    }
}
#endif
