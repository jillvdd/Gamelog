import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// 把分享卡片视图渲染成目标像素尺寸的图片数据。
/// 固定深色品牌主题（ShareTheme.brand）；文字语言使用传入的 appLanguageCode。
/// ImageRenderer 及其属性均为 MainActor，因此整个枚举需要 @MainActor。
@MainActor
enum ShareCardRenderer {

    /// 位图最长边安全上限：超过时自动整体缩小输出倍率，保证巨量游戏的总览图也能出图。
    /// （经验临界在 ~16384px；留出余量。）
    static let maxBitmapDimension: CGFloat = 12000

    /// 预览降采样倍率：实时预览用小图，导出才全尺寸。
    static let previewScale: CGFloat = 0.5

    enum OutputFormat {
        case png
        case jpeg(quality: CGFloat)
    }

    // MARK: - 兼容入口（测试 / 既有调用）

    static func renderPNG(content: ShareCardContent, language: String) -> Data? {
        renderData(content: content, language: language, format: .png)
    }

    // MARK: - 主入口

    /// 渲染并编码。`scale` 为输出倍率（预览可传 previewScale）；
    /// 画布超过 maxBitmapDimension 时自动进一步缩小，保证不超位图上限。
    static func renderData(
        content: ShareCardContent,
        language: String,
        scale: CGFloat = 1,
        format: OutputFormat = .png
    ) -> Data? {
        let canvas = content.canvasSize
        let clamped = min(max(scale, 0.05), maxBitmapDimension / max(canvas.width, canvas.height))

        let view = ShareCardView(content: content, theme: .brand)
            .environment(\.appLanguageCode, language)
            .frame(width: canvas.width, height: canvas.height)

        let renderer = ImageRenderer(content: view)
        renderer.scale = clamped
        renderer.proposedSize = .init(width: canvas.width, height: canvas.height)
        #if os(macOS)
        guard let nsImage = renderer.nsImage else { return nil }
        return encode(nsImage, format: format)
        #else
        guard let uiImage = renderer.uiImage else { return nil }
        return encode(uiImage, format: format)
        #endif
    }

    // MARK: - 编码

    #if os(macOS)
    private static func encode(_ image: NSImage, format: OutputFormat) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        switch format {
        case .png:
            return rep.representation(using: .png, properties: [:])
        case .jpeg(let quality):
            return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        }
    }
    #else
    private static func encode(_ image: UIImage, format: OutputFormat) -> Data? {
        switch format {
        case .png:
            return image.pngData()
        case .jpeg(let quality):
            return image.jpegData(compressionQuality: quality)
        }
    }
    #endif
}
