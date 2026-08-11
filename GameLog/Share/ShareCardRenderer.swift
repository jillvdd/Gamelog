import SwiftUI
import AppKit

extension NSImage {
    /// 转成 PNG 数据。
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

/// 把分享卡片视图渲染成目标像素尺寸的 PNG。
/// 主题跟随系统当前深浅色；文字语言使用传入的 appLanguageCode。
/// ImageRenderer 及其属性均为 MainActor，因此整个枚举需要 @MainActor。
@MainActor
enum ShareCardRenderer {

    static func renderPNG(content: ShareCardContent, language: String) -> Data? {
        let scheme = currentScheme()
        let theme = ShareTheme.forScheme(scheme)
        let canvas = content.canvasSize

        let view = ShareCardView(content: content, theme: theme)
            .environment(\.appLanguageCode, language)
            .environment(\.colorScheme, scheme)
            .frame(width: canvas.width, height: canvas.height)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.proposedSize = .init(width: canvas.width, height: canvas.height)
        guard let nsImage = renderer.nsImage else { return nil }
        return nsImage.pngData()
    }

    private static func currentScheme() -> ColorScheme {
        let match = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
        return match == .darkAqua ? .dark : .light
    }
}
