import SwiftUI
#if !os(macOS)
import PhotosUI
import UIKit
#endif

extension View {
    /// iOS 图片来源选择：点击「添加图片」先弹底部菜单（相册 / 文件 / 拍照），再调起对应选择器。
    /// - isPresented: 菜单开关（true 弹底部菜单）
    /// - maxSelectionCount: 相册最大可选数量（>1 表示多选；文件 / 拍照每次一张）
    /// - onImages: 用户选完图片后的回调（图片原始 Data）。相机不可用时（模拟器）菜单自动隐藏「拍照」。
    ///
    /// macOS 不启用（各调用处均已用 `#if !os(macOS)` 守卫）。
    func imageSourcePicker(
        isPresented: Binding<Bool>,
        maxSelectionCount: Int = 1,
        onImages: @escaping ([Data]) -> Void
    ) -> some View {
        #if os(macOS)
        return self
        #else
        return modifier(
            ImageSourcePickerModifier(
                isPresented: isPresented,
                maxSelectionCount: maxSelectionCount,
                onImages: onImages
            )
        )
        #endif
    }
}

#if !os(macOS)
/// iOS 图片来源选择实现：底部菜单 + 相册（PhotosPicker）/ 文件（DocumentPicker）/ 拍照（相机）。
private struct ImageSourcePickerModifier: ViewModifier {
    @Binding var isPresented: Bool
    var maxSelectionCount: Int
    var onImages: ([Data]) -> Void

    @Environment(\.appLanguageCode) private var language

    private enum Source {
        case photos, file, camera
    }

    @State private var pendingSource: Source?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showPhotosPicker = false
    @State private var showCamera = false
    /// 相机不可用时点「拍照」的提示开关。
    @State private var showingNoCamera = false

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func body(content: Content) -> some View {
        content
            .platformConfirmDialog(
                L10n.tr("image.pickSource", lang: language),
                isPresented: $isPresented,
                cancelTitle: L10n.tr("common.cancel", lang: language),
                actions: sourceActions
            )
            .onChange(of: pendingSource) { _, source in
                guard let source else { return }
                // 等底部菜单完全收起再弹出下一个选择器，避免同时 present 冲突。
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    switch source {
                    case .photos: showPhotosPicker = true
                    case .file:
                        // 裸 UIDocumentPickerViewController（DocumentPicker），不走 SwiftUI fileImporter。
                        DocumentPicker.present(types: [.image]) { url in
                            if let data = try? Data(contentsOf: url) {
                                self.onImages([data])
                            }
                        }
                    case .camera:
                        if cameraAvailable {
                            showCamera = true
                        } else {
                            showingNoCamera = true
                        }
                    }
                    pendingSource = nil
                }
            }
            .photosPicker(
                isPresented: $showPhotosPicker,
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
            .fullScreenCover(isPresented: $showCamera) {
                CameraCaptureView(
                    onCapture: { image in
                        showCamera = false
                        if let data = image.jpegData(compressionQuality: 0.9) {
                            onImages([data])
                        }
                    },
                    onCancel: { showCamera = false }
                )
            }
            .platformConfirmDialog(
                L10n.tr("image.cameraUnavailable", lang: language),
                isPresented: $showingNoCamera,
                cancelTitle: L10n.tr("common.confirm", lang: language),
                actions: []
            )
    }

    /// 底部菜单项：相册 / 文件 / 拍照（相机不可用时点击给提示，但选项始终显示，保证菜单完整）。
    private var sourceActions: [ConfirmAction] {
        [
            ConfirmAction(title: L10n.tr("image.fromPhotos", lang: language)) { pendingSource = .photos },
            ConfirmAction(title: L10n.tr("image.fromFiles", lang: language)) { pendingSource = .file },
            ConfirmAction(title: L10n.tr("image.takePhoto", lang: language)) { pendingSource = .camera }
        ]
    }
}

/// 相机拍摄视图（UIImagePickerController 封装）：拍摄后回调 UIImage，取消回调 onCancel。
private struct CameraCaptureView: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        let onCancel: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}
#endif
