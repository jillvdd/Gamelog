import SwiftUI
import AppKit

/// 裁切目标：头像（圆形）或 app 图标（macOS 圆角矩形）。
enum CropKind {
    case avatar
    case icon

    /// 输出图边长（像素）。
    var targetSize: Int {
        switch self {
        case .avatar: 256
        case .icon: 1024
        }
    }

    var shape: CropShape {
        switch self {
        case .avatar: .circle
        case .icon: .roundedRect
        }
    }

    var titleKey: String {
        switch self {
        case .avatar: "crop.titleAvatar"
        case .icon: "crop.titleIcon"
        }
    }
}

enum CropShape {
    case circle
    case roundedRect
}

/// 上传图片的裁切面板：拖拽平移 + 缩放滑杆 + 遮罩实时预览。
/// 确定后把遮罩内的图像区域按目标形状裁出，输出指定尺寸的 PNG（avatar 256² / icon 1024²）。
struct ImageCropSheet: View {
    let kind: CropKind
    let sourceImage: NSImage
    var onCancel: () -> Void
    var onConfirm: (NSImage) -> Void

    @Environment(\.appLanguageCode) private var language
    @State private var offset: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    @State private var canvasSide: CGFloat = 440

    /// 遮罩边长 = 画布边长 × 此比例。
    private let maskRatio: CGFloat = 0.85

    var body: some View {
        VStack(spacing: 16) {
            LText(kind.titleKey)
                .font(.headline)

            canvas
                .frame(width: 440, height: 440)

            HStack(spacing: 12) {
                LText("crop.zoom")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $scale, in: 0.8...8)
                Button {
                    offset = .zero
                    scale = 1.0
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("重置")
            }
            .frame(width: 440)

            HStack {
                Button(L10n.tr("common.cancel", lang: language)) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.tr("common.save", lang: language)) { confirm() }
                    .keyboardShortcut(.defaultAction)
            }
            .frame(width: 440)
        }
        .padding(24)
    }

    // MARK: - 画布

    private var canvas: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let maskSide = side * maskRatio
            ZStack {
                Rectangle()
                    .fill(Color(nsColor: .textBackgroundColor))

                Image(nsImage: sourceImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: side, height: side)
                    // 先以自身中心缩放，再整体平移 → 图片中心 = 画布中心 + offset（与输出几何一致）
                    .scaleEffect(scale, anchor: .center)
                    .offset(offset)

                // 遮罩外暗化：黑底 + destinationOut 挖洞
                ZStack {
                    Color.black.opacity(0.5)
                    maskShape(maskSide)
                        .fill(Color.black)
                        .frame(width: maskSide, height: maskSide)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                .frame(width: side, height: side)

                // 遮罩边框
                maskShape(maskSide)
                    .stroke(Color.white.opacity(0.95), lineWidth: 2)
                    .frame(width: maskSide, height: maskSide)
                    .shadow(color: .black.opacity(0.4), radius: 1)
            }
            .frame(width: side, height: side)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in offset = value.translation }
            )
            .onAppear { canvasSide = side }
        }
    }

    private func maskShape(_ side: CGFloat) -> AnyShape {
        switch kind.shape {
        case .circle:
            return AnyShape(Circle())
        case .roundedRect:
            return AnyShape(RoundedRectangle(cornerRadius: side * 0.2237))
        }
    }

    // MARK: - 确认出图

    private func confirm() {
        guard let cg = Self.cgImage(from: sourceImage),
              let result = Self.renderCropped(
                  cg,
                  canvasSide: canvasSide,
                  offset: offset,
                  scale: scale,
                  maskSide: canvasSide * maskRatio,
                  kind: kind
              ) else { return }
        onConfirm(result)
    }

    // MARK: - 几何映射与渲染

    private static func cgImage(from image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    /// 把「遮罩框在画布中的区域」映射回源图像素，按目标形状裁出并放大到目标尺寸。
    /// 坐标系：SwiftUI 画布 y 向下，CGImage y 向上；offset 为 SwiftUI 平移量。
    static func renderCropped(
        _ source: CGImage,
        canvasSide: CGFloat,
        offset: CGSize,
        scale: CGFloat,
        maskSide: CGFloat,
        kind: CropKind
    ) -> NSImage? {
        let pw = CGFloat(source.width)
        let ph = CGFloat(source.height)
        let fitted = min(canvasSide / pw, canvasSide / ph)
        let displayScale = fitted * scale

        // 遮罩中心相对图片中心 = -offset（SwiftUI）；转源像素时 y 需翻转
        let half = (maskSide / 2) / displayScale
        let cx = pw / 2 + (-offset.width) / displayScale
        let cy = ph / 2 + (offset.height) / displayScale
        let cropRect = CGRect(x: cx - half, y: cy - half, width: half * 2, height: half * 2)

        let t = kind.targetSize
        guard let ctx = CGContext(
            data: nil, width: t, height: t, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.clear(CGRect(x: 0, y: 0, width: t, height: t))
        ctx.saveGState()

        let full = CGRect(x: 0, y: 0, width: t, height: t)
        switch kind.shape {
        case .circle:
            ctx.addEllipse(in: full)
        case .roundedRect:
            ctx.addPath(CGPath(roundedRect: full, cornerWidth: CGFloat(t) * 0.2237, cornerHeight: CGFloat(t) * 0.2237, transform: nil))
        }
        ctx.clip()

        let s = CGFloat(t) / cropRect.width
        ctx.scaleBy(x: s, y: s)
        ctx.translateBy(x: -cropRect.minX, y: -cropRect.minY)
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: pw, height: ph))
        ctx.restoreGState()

        guard let outCG = ctx.makeImage() else { return nil }
        return NSImage(cgImage: outCG, size: NSSize(width: t, height: t))
    }
}
