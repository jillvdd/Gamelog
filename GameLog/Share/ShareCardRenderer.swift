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

    /// 实际生效的输出倍率（预览降采样与超限自动缩小后的结果）——面板据此提示大选择降质。
    static func effectiveScale(canvas: CGSize, scale: CGFloat) -> CGFloat {
        min(max(scale, 0.05), maxBitmapDimension / max(canvas.width, canvas.height))
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
        theme: ShareTheme = .brand,
        scale: CGFloat = 1,
        format: OutputFormat = .png
    ) -> Data? {
        let view = ShareCardView(content: content, theme: theme)
            .environment(\.appLanguageCode, language)
        return renderView(view, canvas: content.canvasSize, scale: scale, format: format)
    }

    /// 通用出口：任意已定义尺寸的视图 → 位图 → 编码（九宫格方图补齐等定制构型复用）。
    private static func renderView<V: View>(
        _ view: V, canvas: CGSize, scale: CGFloat, format: OutputFormat
    ) -> Data? {
        let clamped = min(max(scale, 0.05), maxBitmapDimension / max(canvas.width, canvas.height))
        let renderer = ImageRenderer(content: view.frame(width: canvas.width, height: canvas.height))
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

    // MARK: - 朋友圈九宫格（≤9 张 1:1 方图，按选择顺序连续分块）

    /// 把游戏按顺序均分成 ≤9 块（块间数量差 ≤1）。纯函数，便于测试断言。
    static func grid9Chunks(games: [Game]) -> [[Game]] {
        let n = games.count
        guard n > 0 else { return [] }
        let chunks = min(n, 9)
        let base = n / chunks
        let extra = n % chunks
        var out: [[Game]] = []
        var start = 0
        for i in 0..<chunks {
            let size = base + (i < extra ? 1 : 0)
            out.append(Array(games[start..<start + size]))
            start += size
        }
        return out
    }

    /// 渲染九宫格多图（每张严格 1:1 方图：总览卡高度不足时用主题底色补齐，
    /// 保证朋友圈九宫格每张同尺寸；标题自动带 i/9 序号）。
    static func renderGrid9Data(
        games: [Game], title: String, language: String, theme: ShareTheme,
        format: OutputFormat = .jpeg(quality: 0.9)
    ) -> [Data] {
        let chunks = grid9Chunks(games: games)
        return chunks.indices.compactMap { i in
            let chunkTitle = chunks.count > 1 ? "\(title) \(i + 1)/\(chunks.count)" : title
            let content = ShareCardContent.overview(chunks[i], title: chunkTitle, size: .square)
            let base = content.canvasSize
            let side = max(base.width, base.height)
            let view = ZStack(alignment: .top) {
                theme.background
                ShareCardView(content: content, theme: theme)
            }
            .frame(width: side, height: side)
            .environment(\.appLanguageCode, language)
            return renderView(view, canvas: CGSize(width: side, height: side), scale: 1, format: format)
        }
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
