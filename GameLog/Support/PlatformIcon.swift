import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// 平台图标：有 PNG 就显示 PNG（灰阶 → 模板着色随主题；彩色/方形 logo → 原样），无则回退 SF Symbol。
/// 使用处（菜单/侧边栏/统计条等）在平台名左侧放一个即可。
struct PlatformIcon: View {
    let platform: String
    var size: CGFloat = 16
    /// 是否放大显示（非白底图标统一 ×1.5、PS 系 ×1.2）。密集行（统计条）传 false 保持原始尺寸。
    var enlarge: Bool = true
    @AppStorage(UserCustomization.platformIconsKey) private var showPlatformIcons = true

    var body: some View {
        if !showPlatformIcons {
            EmptyView()
        } else {
            iconBody
        }
    }

    private var iconBody: some View {
        let fileName = Presets.platformIconFile(for: platform)
        let image = fileName.flatMap { PlatformIconLoader.image(named: $0) }
        // 白底宽字标（SFC 等）已按烘焙比例加宽显示，保持原尺寸；
        // 其余所有图标（方形 logo 与 SF Symbol 兜底）统一放大显示，PS 系 1.2 倍、其余 1.5 倍。
        // enlarge=false 时（密集行如统计条）不放大，保持传入的原始 size。
        let isWide = fileName.map(PlatformIconLoader.needsWhiteBackground) ?? false
        let iconSize = isWide ? size : (enlarge ? size * Self.iconScale(for: fileName) : size)
        return Group {
            if let fileName, let image {
                PlatformIconImage(
                    image: image,
                    size: iconSize,
                    isTemplate: PlatformIconLoader.isTemplate(named: fileName),
                    whiteBackground: PlatformIconLoader.needsWhiteBackground(named: fileName)
                )
            } else {
                Image(systemName: Presets.platformIconSymbol(for: platform) ?? "gamecontroller")
                    .font(.system(size: iconSize * 0.75))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: iconSize)
    }

    /// PlayStation 系图标（PS5/PS4/PS3/PS2/PS1/PSP/PS Vita）logo 观感偏大，统一 1.2 倍；其余非白底 1.5 倍。
    private static let psFileNames: Set<String> = ["PS5", "PS4", "PS3", "PS2", "PS1", "PSP", "PS-Vita"]
    private static func iconScale(for fileName: String?) -> CGFloat {
        fileName.map { psFileNames.contains($0) } ?? false ? 1.2 : 1.5
    }

    /// 该平台图标在给定高度下的渲染宽度（白底图标含白块；SF Symbol 兜底按约 0.9×高估算）。
    /// 用于「图标 + 名字能否同行放得下」的判断。
    static func displayWidth(platform: String, size: CGFloat, enlarge: Bool = true) -> CGFloat {
        guard let fileName = Presets.platformIconFile(for: platform),
              let aspect = PlatformIconLoader.aspect(named: fileName) else {
            // SF Symbol 兜底（PC/其他/自定义平台）：放大时约 1.5×0.9 宽，不放大约 0.9×宽。
            return size * (enlarge ? 1.5 : 1.0) * 0.9
        }
        // 白底宽字标已把白块烘焙进图片，宽度 = 按烘焙后比例，保持原尺寸。
        if PlatformIconLoader.needsWhiteBackground(named: fileName) {
            return size * aspect
        }
        // 其余图标（方形 logo / Xbox 透明）放大时按图标缩放系数（PS 系 1.2 倍、其余 1.5 倍），仍封顶 3×。
        return size * (enlarge ? Self.iconScale(for: fileName) : 1.0) * min(max(aspect, 0.5), 3.0)
    }

    /// 文本在系统默认字体的自然宽度（近似），用于判断文字是否会被省略。
    static func textWidth(_ text: String, fontSize: CGFloat) -> CGFloat {
        #if os(macOS)
        let font = NSFont.systemFont(ofSize: fontSize)
        #else
        let font = UIFont.systemFont(ofSize: fontSize)
        #endif
        return (text as NSString).size(withAttributes: [.font: font]).width
    }
}

/// 单张平台图标：白底图标的白块已烘焙进图片；模板图标在渲染时按当前 colorScheme 烘焙文字色（深色=白/浅色=黑），
/// 使 macOS 菜单（忽略 SwiftUI template 着色）也能正确显示。macOS 同时把逻辑尺寸设为显示尺寸（菜单按自然尺寸渲染）。
private struct PlatformIconImage: View {
    @Environment(\.colorScheme) private var colorScheme
    let image: AppImage
    let size: CGFloat
    let isTemplate: Bool
    let whiteBackground: Bool

    var body: some View {
        let aspect = image.size.width / image.size.height
        let width = whiteBackground ? size * aspect : size * min(max(aspect, 0.5), 3.0)
        let display = preparedImage(width: width, height: size)
        return Image(appImage: display)
            .resizable()
            .renderingMode(.original)
            .frame(width: width, height: size, alignment: .center)
            .clipped()
    }

    private func preparedImage(width: CGFloat, height: CGFloat) -> AppImage {
        var cg = image.cgImageValue
        if isTemplate && !whiteBackground, let base = cg {
            // 显式按 colorScheme 取色：深色=白、浅色=黑，动态 labelColor 在渲染上下文解析不稳定。
            let isDark = colorScheme == .dark
            let t: (r: CGFloat, g: CGFloat, b: CGFloat) = isDark ? (1, 1, 1) : (0, 0, 0)
            cg = PlatformIconLoader.tint(base, r: t.r, g: t.g, b: t.b)
        }
        #if os(macOS)
        if let cg {
            return NSImage(cgImage: cg, size: NSSize(width: width, height: height))
        }
        #else
        if let cg {
            return UIImage(cgImage: cg)
        }
        #endif
        return image
    }
}

/// 图标加载与「是否灰阶模板」判定（按文件名缓存）。
enum PlatformIconLoader {
    private static var templateCache: [String: Bool] = [:]
    private static var aspectCache: [String: CGFloat] = [:]
    /// 需要白底承托的图标（稀疏深色/彩色字标在深浅主题下都看不清，如 SFC、各代任天堂字标）：
    /// 渲染时垫一块白底圆角块，宽度上限 5× 高（比普通图标更宽，文字不被压扁）。
    private static let whiteBackgroundIcons: Set<String> = [
        "SFC-SNES", "3DS", "NDS", "N64", "FC-NES", "GBA", "Game-Boy-Color", "Game-Boy",
    ]

    /// 图标宽高比（宽/高），仅读文件头不解码整图，按文件名缓存。
    static func aspect(named: String) -> CGFloat? {
        if let cached = aspectCache[named] { return cached }
        guard let url = Bundle.main.url(forResource: named, withExtension: "png"),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              h > 0 else { return nil }
        let a = CGFloat(w / h)
        aspectCache[named] = a
        return a
    }

    /// 当前主题文字色（深色=白，浅色=黑），用于给模板图标着色。
    static func labelTint() -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        #if os(macOS)
        let c = NSColor.labelColor.usingColorSpace(.sRGB) ?? NSColor.black
        return (c.redComponent, c.greenComponent, c.blueComponent)
        #else
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor.label.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
        #endif
    }

    /// 把图片非透明像素重染成指定颜色（保持 alpha，边缘平滑）。用于模板图标烘焙主题色，
    /// 使 macOS 菜单（忽略 SwiftUI template 着色）也能正确显示深色/浅色。
    static func tint(_ cg: CGImage, r: CGFloat, g: CGFloat, b: CGFloat) -> CGImage {
        let w = cg.width, h = cg.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return cg }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let ir = Int(r * 255), ig = Int(g * 255), ib = Int(b * 255)
        for i in stride(from: 0, to: buf.count, by: 4) {
            let a = Int(buf[i + 3])
            if a > 0 {
                buf[i]     = UInt8(ir * a / 255)
                buf[i + 1] = UInt8(ig * a / 255)
                buf[i + 2] = UInt8(ib * a / 255)
            }
        }
        return ctx.makeImage() ?? cg
    }

    static func image(named: String) -> AppImage? {
        guard let url = Bundle.main.url(forResource: named, withExtension: "png") else { return nil }
        #if os(macOS)
        return NSImage(contentsOf: url)
        #else
        return UIImage(contentsOfFile: url.path)
        #endif
    }

    /// 图标是否需要白底承托。
    static func needsWhiteBackground(named: String) -> Bool {
        whiteBackgroundIcons.contains(named)
    }

    /// 灰阶（全像素近灰）→ 模板着色；有彩色像素（含方形 logo）→ 原样显示。
    static func isTemplate(named: String) -> Bool {
        if let cached = templateCache[named] { return cached }
        let result = computeIsTemplate(named: named)
        templateCache[named] = result
        return result
    }

    private static func computeIsTemplate(named: String) -> Bool {
        guard let url = Bundle.main.url(forResource: named, withExtension: "png"),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return false }
        let w = image.width, h = image.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let step = max(1, min(w, h) / 32)
        for y in stride(from: 0, to: h, by: step) {
            for x in stride(from: 0, to: w, by: step) {
                let i = (y * w + x) * 4
                if Int(buf[i + 3]) > 20 {
                    let r = Int(buf[i]), g = Int(buf[i + 1]), b = Int(buf[i + 2])
                    if max(r, g, b) - min(r, g, b) > 24 { return false }
                }
            }
        }
        return true
    }
}
