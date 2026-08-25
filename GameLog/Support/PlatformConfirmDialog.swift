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
    ///
    /// ⚠️ 绑定只能在「动作/取消执行完之后」才能复位——调用点的动作闭包普遍读取 pending 状态
    /// （如 `pendingDeleteCopy`），而绑定 set(false) 恰恰会清掉它。曾在 present 后立即异步复位，
    /// 导致用户点「删除」时状态已是 nil、删除静默失效（iOS 全部删除确认受影响）。
    private struct Presenter: UIViewControllerRepresentable {
        let title: String
        let message: String?
        let cancelTitle: String
        @Binding var isPresented: Bool
        let actions: [ConfirmAction]

        func makeCoordinator() -> Coordinator { Coordinator() }

        func makeUIViewController(context: Context) -> UIViewController {
            UIViewController()
        }

        func updateUIViewController(_ viewController: UIViewController, context: Context) {
            let coordinator = context.coordinator
            coordinator.dismiss = { isPresented = false }
            if !isPresented {
                coordinator.isAlertPresented = false
                return
            }
            guard !coordinator.isAlertPresented else { return }
            let alert = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)
            for action in actions {
                alert.addAction(
                    UIAlertAction(
                        title: action.title,
                        style: action.isDestructive ? .destructive : .default
                    ) { _ in
                        action.action()
                        isPresented = false
                    }
                )
            }
            alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel) { _ in
                isPresented = false
            })
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
            // 点外部/下滑关闭（iPad popover）时 UIAlertController 无完成回调，
            // 用 presentation controller delegate 兜底复位绑定，防止绑定滞留 true。
            alert.presentationController?.delegate = coordinator
            viewController.present(alert, animated: true)
            coordinator.isAlertPresented = true
        }

        final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
            var isAlertPresented = false
            var dismiss: (() -> Void)?

            func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
                isAlertPresented = false
                dismiss?()
            }
        }
    }
}
#endif
