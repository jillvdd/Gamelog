import SwiftUI
#if os(macOS)
import PhotosUI
#endif

extension View {
    /// 照片图库选择器（macOS）：调起系统 Photos picker（进程外独立浮动窗口，免相册权限），
    /// 选完逐个 `loadTransferable(type: Data.self)` 取原始字节回调。
    /// - isPresented: 选择窗口开关
    /// - maxSelectionCount: 最大可选数量（>1 表示多选）
    /// - onImages: 选完图片后的回调（图片原始 Data，HEIC 等格式不转码）
    ///
    /// iOS 不启用（iOS 侧统一走 `imageSourcePicker` 的相册分支），返回 self 保持调用点免 `#if`。
    func photoLibraryPicker(
        isPresented: Binding<Bool>,
        maxSelectionCount: Int = 1,
        onImages: @escaping ([Data]) -> Void
    ) -> some View {
        #if os(macOS)
        return modifier(
            MacPhotoLibraryPickerModifier(
                isPresented: isPresented,
                maxSelectionCount: maxSelectionCount,
                onImages: onImages
            )
        )
        #else
        return self
        #endif
    }
}

#if os(macOS)
/// macOS 照片图库选择实现：`.photosPicker` + onChange 取数，
/// 取数形态与 iOS `ImageSourcePickerModifier` 的相册分支逐行同构（含 try? 容错跳过）。
private struct MacPhotoLibraryPickerModifier: ViewModifier {
    @Binding var isPresented: Bool
    var maxSelectionCount: Int
    var onImages: ([Data]) -> Void

    @State private var pickerItems: [PhotosPickerItem] = []

    func body(content: Content) -> some View {
        content
            .photosPicker(
                isPresented: $isPresented,
                selection: $pickerItems,
                maxSelectionCount: max(maxSelectionCount, 1),
                matching: .images
            )
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                let limit = max(maxSelectionCount, 1)
                Task {
                    var datas: [Data] = []
                    for item in items.prefix(limit) {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            datas.append(data)
                        }
                    }
                    pickerItems = []
                    if !datas.isEmpty {
                        onImages(datas)
                    }
                }
            }
    }
}
#endif
