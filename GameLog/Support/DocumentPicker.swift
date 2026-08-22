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
        guard let root = Self.topMostViewController() else { return }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = false
        let coordinator = Coordinator(onPicked: onPicked, onCancel: onCancel)
        picker.delegate = coordinator
        holders.append(coordinator)
        print("[DocPicker] present types=\(types.map(\.identifier)) topVC=\(Swift.type(of: root))")
        root.present(picker, animated: true) {
            print("[DocPicker] PICKER PRESENTED")
        }
    }

    private static func topMostViewController(base: UIViewController? = nil) -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        let resolved = base ?? scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
            ?? scene?.windows.first?.rootViewController
        if let nav = resolved as? UINavigationController,
           let visible = nav.visibleViewController {
            return topMostViewController(base: visible)
        }
        if let tab = resolved as? UITabBarController,
           let selected = tab.selectedViewController {
            return topMostViewController(base: selected)
        }
        if let presented = resolved?.presentedViewController {
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
            print("[DocPicker] DID PICK count=\(urls.count)")
            release()
            guard let url = urls.first else { return }
            // 推迟到下一个 runloop：picker 正在 dismiss，避免在 presentation 过渡中同步改 SwiftUI 状态。
            DispatchQueue.main.async { self.onPicked(url) }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            print("[DocPicker] DID CANCEL")
            release()
            DispatchQueue.main.async { self.onCancel?() }
        }

        private func release() {
            DocumentPicker.holders.removeAll { $0 === self }
        }
    }
}
#endif
