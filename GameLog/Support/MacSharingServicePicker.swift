#if os(macOS)
import AppKit
import SwiftUI

/// 按钮位系统分享面板（NSSharingServicePicker，含 AirDrop）。
///
/// 用法：把 `MacSharingAnchor` 挂到按钮的 `.background`，点击动作里生成好待分享内容后
/// 把 `isPresented` 置 true——锚点视图收到更新后在下一轮 runloop 从自身位置弹出分享面板。
///
/// 要点：
/// - picker 必须强持有到用户选完/关闭（WebKit bug 194301 先例：show 后无系统保活，
///   过早释放会向已释放对象发消息崩溃），由 Coordinator 持有、didChoose 回调里释放。
/// - `show(relativeTo:)` 必须在 mouseDown 时机之外的 runloop 轮次调用
///   （经 DispatchQueue.main.async），同步在 updateNSView 里调会重入 SwiftUI 更新。
struct MacSharingAnchor: NSViewRepresentable {
    @Binding var isPresented: Bool
    let itemsProvider: () -> [Any]

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        return view
    }

    final class Coordinator: NSObject, NSSharingServicePickerDelegate {
        weak var view: NSView?
        /// 强引用正在显示的分享面板；用户选中某服务或关闭面板后释放。
        /// 非 nil 即面板仍在屏上——连点触发源时不再 show 第二张（NSSharingServicePicker
        /// 自身不防重入，重复 show 会叠开多个 popover）。
        var heldPicker: NSSharingServicePicker?

        func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
            heldPicker = nil
        }
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard isPresented else { return }
        // 防重入：上一张面板还开着（用户未选服务也未关）就不再弹新的。
        guard context.coordinator.heldPicker == nil else {
            isPresented = false
            return
        }
        // items 在此刻捕获，避免闭包稍后读到已变化的 state。
        let items = itemsProvider()
        let coordinator = context.coordinator
        DispatchQueue.main.async {
            // 复位与 show 同轮执行（异步块内改绑定不会踩「视图更新期间修改状态」）。
            self.isPresented = false
            let picker = NSSharingServicePicker(items: items)
            picker.delegate = coordinator
            coordinator.heldPicker = picker
            picker.show(relativeTo: nsView.bounds, of: nsView, preferredEdge: .minY)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
}
#endif
