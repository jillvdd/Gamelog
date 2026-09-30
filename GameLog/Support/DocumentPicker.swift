import SwiftUI
#if !os(macOS)
import UIKit
import UniformTypeIdentifiers

/// iOS 文件导入：绕开 SwiftUI `.fileImporter` 封装，从最上层 VC 直接 present 裸
/// `UIDocumentPickerViewController(forOpeningContentTypes:asCopy:)`。
/// 写法与真机验证可用的最小复现 App 完全同构（HANDOVER §29.17 方向 1）：
/// 裸 pageSheet present + delegate 强持有，回调把 URL 丢回 SwiftUI 层。
enum DocumentPicker {
    /// 强持有协调器直到 didPick/cancel 回调结束，防 ARC 提前释放。
    private static var holders: [Coordinator] = []

    static func present(
        types: [UTType],
        onPicked: @escaping (URL) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        // 拿不到锚点必须留痕：`guard … else { return }` 静默返回时，用户点了「导入备份」
        // 却什么都没发生，也没有任何东西可查（2026-09-29 审计 P3）。
        guard let root = Self.topMostViewController() else {
            NSLog("GameLog DocumentPicker: no foreground window to present from")
            onCancel?()
            return
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = false
        let coordinator = Coordinator(onPicked: onPicked, onCancel: onCancel)
        picker.delegate = coordinator
        holders.append(coordinator)
        root.present(picker, animated: true)
    }

    private static func topMostViewController(base: UIViewController? = nil) -> UIViewController? {
        // 只认**前台激活**的场景：不过滤时 `.first` 可能取到后台/未连接窗口的 scene，
        // 拿到的 VC 没有 window → `present` 直接崩（iPad 上还会撞上 popover 无锚点的硬崩）。
        let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        guard let resolved = base
            ?? scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
            ?? scene?.windows.first?.rootViewController
        else { return nil }
        // 没有 window 的 VC 不能用来 present（与上面同源，2026-09-29 审计 P3）。
        guard resolved.view.window != nil || resolved.presentedViewController != nil else { return nil }
        if let nav = resolved as? UINavigationController,
           let visible = nav.visibleViewController {
            return topMostViewController(base: visible)
        }
        if let tab = resolved as? UITabBarController,
           let selected = tab.selectedViewController {
            return topMostViewController(base: selected)
        }
        if let presented = resolved.presentedViewController {
            return topMostViewController(base: presented)
        }
        return resolved
    }

    private final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPicked: (URL) -> Void
        let onCancel: (() -> Void)?

        init(onPicked: @escaping (URL) -> Void, onCancel: (() -> Void)?) {
            self.onPicked = onPicked
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            release()
            guard let url = urls.first else { return }
            // 推迟到下一个 runloop：picker 正在 dismiss，避免在 presentation 过渡中同步改 SwiftUI 状态。
            DispatchQueue.main.async { self.onPicked(url) }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            release()
            DispatchQueue.main.async { self.onCancel?() }
        }

        private func release() {
            DocumentPicker.holders.removeAll { $0 === self }
        }
    }
}
#endif
