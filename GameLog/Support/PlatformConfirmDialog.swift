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
    /// - iOS/iPadOS：系统 `UIAlertController(.actionSheet)`（自动带液态玻璃外观）。
    ///
    /// 为什么不直接用 SwiftUI `.confirmationDialog`：它在 iOS 26 上呈现为带指向触发元素尖角的浮窗，
    /// 与本 app 的「无源元素」语义不符，改用 UIKit 自行控制呈现锚点。
    ///
    /// ⚠️ iOS 26 起 `.actionSheet` 在 iPhone 上**不再是贴底弹层**，而是浮在下半屏的圆角卡 +
    /// 横排胶囊按钮（系统新原生外观，`modalPresentationStyle = .fullScreen` 也无法改回贴底）。
    /// 这是系统行为，不要为「恢复贴底」而自绘弹层——那会偏离系统观感并需自行处理深色模式、
    /// Dynamic Type、VoiceOver、长文案换行与行数自适应高度（2026-09-30 已评估并否决，见 HANDOVER §90.6）。
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
/// iOS/iPadOS 确认弹窗：用 `UIAlertController(.actionSheet)` 呈现（系统液态玻璃样式）。
/// 外观随系统版本：iOS 26 上 iPhone 为浮卡 + 横排胶囊按钮，iPad 为无箭头 popover 卡。
private struct IOSActionSheetModifier: ViewModifier {
    let title: String
    let message: String?
    let cancelTitle: String
    @Binding var isPresented: Bool
    let actions: [ConfirmAction]

    /// 重试计数：只为让 `updateUIViewController` 再跑一次（无窗口锚点时延后重挂）。
    @State private var attempt = 0

    func body(content: Content) -> some View {
        content.background {
            Presenter(
                title: title,
                message: message,
                cancelTitle: cancelTitle,
                isPresented: $isPresented,
                actions: actions,
                attempt: attempt,
                retry: { attempt += 1 }
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
        /// 参与相等性：变化即触发一次 `updateUIViewController`，配合 `retry` 实现有界重试。
        let attempt: Int
        let retry: () -> Void

        func makeCoordinator() -> Coordinator { Coordinator() }

        func makeUIViewController(context: Context) -> UIViewController {
            UIViewController()
        }

        func updateUIViewController(_ viewController: UIViewController, context: Context) {
            let coordinator = context.coordinator
            coordinator.dismiss = { isPresented = false }
            coordinator.retry = retry
            if !isPresented {
                coordinator.isAlertPresented = false
                coordinator.attemptsLeft = maxAnchoringAttempts
                return
            }
            guard !coordinator.isAlertPresented else { return }
            // 呈现锚点必须是**挂在窗口上的最顶层 VC**，而不是本 Representable 自带的那个
            // 0×0 UIViewController（2026-09-29 审计 P3）：
            // - iPad 的 `.actionSheet` 走 popover，`sourceView` 所在 view 没有 window 时系统
            //   直接硬崩 `"Popovers cannot be presented from a view which does not have a window"`
            //   —— 首帧未完成、或弹窗挂在正在转场/sheet 内的视图上时就会踩到。
            // - 顺带修掉「sheet 被 SwiftUI 的 0×0 背景视图遮住、层级不对」的老毛病。
            // 拿不到锚点时**不 present、也不复位绑定**（复位等于把这次点击吞掉），改为短暂延时重试，
            // 有界重试耗尽后才放弃并复位，避免绑定永久滞留 true 让按钮看起来失灵。
            guard let anchor = topPresentedViewController(), anchor.view.window != nil else {
                if coordinator.attemptsLeft > 0 {
                    coordinator.attemptsLeft -= 1
                    coordinator.scheduleRetry()
                } else {
                    // 放弃：复位绑定要等本次视图更新结束，否则就是「在 view update 里改状态」。
                    DispatchQueue.main.async { isPresented = false }
                }
                return
            }
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
            // popover 锚点**只在 iPad 设置**：iPad 的 `.actionSheet` 走 popover，缺 sourceView 会硬崩；
            // iPhone 上设置 sourceView 会让 iOS 26 直接不渲染「取消」行（2026-09-30 变体矩阵取证：
            // 设了锚点的 v1/v5/v6 均无「取消」，未设的 v2/v3 正常）。
            // 用锚点 VC 的 traitCollection 而非 UIDevice：anchor 已在窗口层级里，idiom 取值准确。
            if anchor.traitCollection.userInterfaceIdiom == .pad,
               let popover = alert.popoverPresentationController {
                popover.sourceView = anchor.view
                popover.sourceRect = CGRect(
                    x: anchor.view.bounds.midX,
                    y: anchor.view.bounds.midY,
                    width: 0,
                    height: 0
                )
                popover.permittedArrowDirections = []
            }
            // 点外部/下滑关闭（iPad popover）时 UIAlertController 无完成回调，
            // 用 presentation controller delegate 兜底复位绑定，防止绑定滞留 true。
            alert.presentationController?.delegate = coordinator
            anchor.present(alert, animated: true)
            coordinator.isAlertPresented = true
        }

        /// 无窗口锚点的容忍次数（× 0.1s ≈ 1s）。首帧转场期足够完成，超时视为真的没有可呈现的场景。
        private let maxAnchoringAttempts = 10

        final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
            var isAlertPresented = false
            var dismiss: (() -> Void)?
            var retry: (() -> Void)?
            var attemptsLeft = 10

            func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
                isAlertPresented = false
                dismiss?()
            }

            /// 0.1s 后再走一遍 `updateUIViewController`（`attempt` 变了 → SwiftUI 重算 → 重新调用）。
            func scheduleRetry() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.retry?()
                }
            }
        }
    }
}
#endif
