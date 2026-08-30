import SwiftUI

/// 主页横幅背景裁切面板（beta 2.8 末次修改二：小窗口自选背景区域）。
/// 把 SGDB 任意画面比例（hero / 342×482 / 660×930…）的选图放进 **2.8:1 宽幅小窗**里
/// 拖拽 / 缩放来选定作为背景的部分，确定后裁出该区域并放大到 `1440×514`（≈2.8:1）PNG
/// 存为横幅背景——裁出图的比例与横幅一致，做背景时 `scaledToFill` 不再异常。
///
/// 画布宽自适应（§46 末）：macOS 定值 560；iPhone 屏宽仅 ~400pt，定宽直接溢出——
/// iOS 用 GeometryReader 取「sheet 可用宽 − 边距」与 560 取小，裁切几何全部以
/// 传入的画布宽计算（输出尺寸只决定放大倍率，与画布宽无关）。
struct BannerCropSheet: View {
    let sourceImage: AppImage
    var onCancel: () -> Void
    var onConfirm: (AppImage) -> Void

    @Environment(\.appLanguageCode) private var language
    @State private var offset: CGSize = .zero
    /// 本次拖拽前的累计偏移基准（同 ImageCropSheet 的累积语义）。
    @State private var dragBase: CGSize = .zero
    @State private var scale: CGFloat = 1.0

    /// 横幅固定比例（与 HomeCarousel.aspectRatio 的 macOS 值一致 2.8）。
    static let aspect: CGFloat = 2.8
    /// 画布最大宽（macOS 定值；iOS 在此与可用宽取小）。
    static let maxCanvasWidth: CGFloat = 560
    /// 输出像素宽；高随比例。
    static let targetWidth: Int = 1440
    private static var targetHeight: Int { Int((Double(targetWidth) / Double(aspect)).rounded()) }

    var body: some View {
        #if os(macOS)
        sheetContent(canvasWidth: Self.maxCanvasWidth)
        #else
        GeometryReader { geo in
            sheetContent(canvasWidth: min(Self.maxCanvasWidth, max(260, geo.size.width - 32)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        #endif
    }

    private func sheetContent(canvasWidth: CGFloat) -> some View {
        let canvasHeight = canvasWidth / Self.aspect
        return VStack(spacing: 14) {
            LText("crop.titleBanner")
                .font(.headline)

            canvas(canvasWidth: canvasWidth, canvasHeight: canvasHeight)

            HStack(spacing: 12) {
                LText("crop.zoom")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $scale, in: 0.8...8)
                Button {
                    offset = .zero
                    dragBase = .zero
                    scale = 1.0
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .frame(width: 32, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help(L10n.tr("crop.reset", lang: language))
            }
            .frame(width: canvasWidth)

            HStack {
                Button(L10n.tr("common.cancel", lang: language)) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Text(verbatim: L10n.tr("crop.titleBannerHint", lang: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                Button(L10n.tr("common.save", lang: language)) { confirm(canvasWidth: canvasWidth) }
                    .keyboardShortcut(.defaultAction)
            }
            .frame(width: canvasWidth)
        }
        .padding(20)
    }

    // MARK: - 画布（整窗 = 裁区：拖拽/缩放把想要的背景部分放进窗口）

    private func canvas(canvasWidth: CGFloat, canvasHeight: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.semantic(.textBackground))
            Image(appImage: sourceImage)
                .resizable()
                // **scaledToFill**：图始终填满小窗（任何比例都不会留白）——用户拖/缩选背景区域；
                // 此前 scaledToFit 在竖版源图时两侧留空，裁出 PNG 带透明边 → 横幅里图变中间一条（§46 修正）。
                .scaledToFill()
                .frame(width: canvasWidth, height: canvasHeight)
                .scaleEffect(scale, anchor: .center)
                .offset(offset)
            // 裁区即窗口：描边 + 三分参考线帮助构图。
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.accentColor.opacity(0.8), lineWidth: 2)
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
        }
        .frame(width: canvasWidth, height: canvasHeight)
        .clipped()
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                // 偏移按每轴可滑范围钳制：缩放后图比窗口大才能平移，且图始终保持盖住窗口。
                .onChanged { value in
                    let mo = maxOffset(canvasWidth: canvasWidth)
                    offset = CGSize(width: clampAxis(dragBase.width + value.translation.width, mo.width),
                                    height: clampAxis(dragBase.height + value.translation.height, mo.height))
                }
                .onEnded { _ in
                    dragBase = offset
                }
        )
    }

    /// 每轴允许的最大平移量 =（填充后图像显示尺寸 − 窗口尺寸）/ 2；图像未超窗的那轴不允许平移。
    private func maxOffset(canvasWidth: CGFloat) -> CGSize {
        guard let cg = sourceImage.cgImageValue else { return .zero }
        let pw = CGFloat(cg.width), ph = CGFloat(cg.height)
        let canvasHeight = canvasWidth / Self.aspect
        let fitted = max(canvasWidth / pw, canvasHeight / ph)
        let ds = fitted * scale
        return CGSize(width: max(0, (pw * ds - canvasWidth) / 2),
                      height: max(0, (ph * ds - canvasHeight) / 2))
    }

    private func clampAxis(_ v: CGFloat, _ limit: CGFloat) -> CGFloat {
        min(max(v, -limit), limit)
    }

    // MARK: - 确认出图（宽幅几何映射：整窗区域映射回源像素，裁出并放大到目标尺寸）

    private func confirm(canvasWidth: CGFloat) {
        guard let cg = sourceImage.cgImageValue,
              let result = Self.renderCropped(cg, offset: offset, scale: scale, canvasWidth: canvasWidth) else { return }
        onConfirm(result)
    }

    static func renderCropped(_ source: CGImage, offset: CGSize, scale: CGFloat, canvasWidth: CGFloat) -> AppImage? {
        let pw = CGFloat(source.width)
        let ph = CGFloat(source.height)
        // 画布把图 scaledToFill 进画布窗再缩放/平移：显示倍率 = fitted*scale（fitted 取 **max**，
        // 与填满一致——任一比例源图都被放大到铺满窗口，裁区始终在源图内、输出无透明边）。
        let canvasHeight = canvasWidth / aspect
        let fitted = max(canvasWidth / pw, canvasHeight / ph)
        let displayScale = fitted * scale

        // 窗口中心相对图片中心 = -offset（SwiftUI → CG 需翻转 y）；窗口即裁区。
        let cropW = canvasWidth / displayScale
        let cropH = canvasHeight / displayScale
        let cx = pw / 2 + (-offset.width) / displayScale
        let cy = ph / 2 + (offset.height) / displayScale
        let cropRect = CGRect(x: cx - cropW / 2, y: cy - cropH / 2, width: cropW, height: cropH)

        let tW = targetWidth
        let tH = targetHeight
        guard let ctx = CGContext(
            data: nil, width: tW, height: tH, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.clear(CGRect(x: 0, y: 0, width: tW, height: tH))
        let s = CGFloat(tW) / cropRect.width
        ctx.scaleBy(x: s, y: s)
        ctx.translateBy(x: -cropRect.minX, y: -cropRect.minY)
        ctx.draw(source, in: CGRect(origin: .zero, size: CGSize(width: pw, height: ph)))
        guard let outCG = ctx.makeImage() else { return nil }
        return AppImage.fromCGImage(outCG, pixelSize: CGSize(width: tW, height: tH))
    }
}
