import Foundation
#if !os(macOS)
import UIKit

/// iOS 系统分享单（UIActivityViewController）直接呈现。
/// 规避 SwiftUI sheet 内嵌 ShareLink 在 iOS 26 静默失败的问题（备份导出与分享面板共用此入口）。
@discardableResult
func presentShareSheet(url: URL) -> Bool {
    guard let top = topPresentedViewController() else { return false }
    let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    // iPad 上 activity 控制器需 popover 锚点；iPhone 无需。
    if let popover = vc.popoverPresentationController {
        popover.sourceView = top.view
        popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
        popover.permittedArrowDirections = []
    }
    top.present(vc, animated: true)
    return true
}

/// 找当前窗口栈最顶层的 presented view controller，作为 UIKit 呈现锚点。
func topPresentedViewController() -> UIViewController? {
    guard let windowScene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first(where: { $0.activationState == .foregroundActive }),
        let root = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
    else { return nil }
    var top = root
    while let presented = top.presentedViewController {
        top = presented
    }
    return top
}
#endif
