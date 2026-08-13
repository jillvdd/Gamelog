import SwiftUI
import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - 跨平台类型别名

/// 跨平台图像类型：macOS = NSImage，iOS = UIImage。
#if os(macOS)
typealias AppImage = NSImage
#else
typealias AppImage = UIImage
#endif

/// 跨平台颜色类型：macOS = NSColor，iOS = UIColor。
#if os(macOS)
typealias AppColor = NSColor
#else
typealias AppColor = UIColor
#endif

/// 系统语义颜色（macOS/iOS 成员名不同，用统一枚举入口映射）。
enum AppSystemColor {
    case quaternarySystemFill
    case separator
    case controlBackground
    case textBackground
}

// MARK: - SwiftUI 桥接

extension Color {
    /// 用平台色创建 Color（macOS: NSColor / iOS: UIColor）。
    init(appColor: AppColor) {
        #if os(macOS)
        self.init(nsColor: appColor)
        #else
        self.init(uiColor: appColor)
        #endif
    }

    /// 系统语义颜色统一入口。
    static func semantic(_ name: AppSystemColor) -> Color {
        switch name {
        case .quaternarySystemFill:
            #if os(macOS)
            return Color(nsColor: .quaternarySystemFill)
            #else
            return Color(uiColor: .quaternarySystemFill)
            #endif
        case .separator:
            #if os(macOS)
            return Color(nsColor: .separatorColor)
            #else
            return Color(uiColor: .separator)
            #endif
        case .controlBackground:
            #if os(macOS)
            return Color(nsColor: .controlBackgroundColor)
            #else
            return Color(uiColor: .secondarySystemBackground)
            #endif
        case .textBackground:
            #if os(macOS)
            return Color(nsColor: .textBackgroundColor)
            #else
            return Color(uiColor: .systemBackground)
            #endif
        }
    }
}

extension Image {
    /// 用平台图像创建 SwiftUI Image。
    init(appImage: AppImage) {
        #if os(macOS)
        self.init(nsImage: appImage)
        #else
        self.init(uiImage: appImage)
        #endif
    }
}

// MARK: - 平台图像工具

extension AppImage {
    /// 从 CGImage 构造（pixelSize 用于 macOS 指定逻辑尺寸；iOS 直接用 cgImage）。
    static func fromCGImage(_ cg: CGImage, pixelSize: CGSize) -> AppImage {
        #if os(macOS)
        return NSImage(cgImage: cg, size: NSSize(width: pixelSize.width, height: pixelSize.height))
        #else
        return UIImage(cgImage: cg)
        #endif
    }

    /// 底层 CGImage。
    var cgImageValue: CGImage? {
        #if os(macOS)
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #else
        return cgImage
        #endif
    }

    /// 压缩为 JPEG：最长边 ≤ maxEdge、quality（尺寸未超限只转 JPEG，不放大）。
    func compressedJPEGData(maxEdge: CGFloat = 1600, quality: CGFloat = 0.8) -> Data? {
        #if os(macOS)
        let maxDim = max(size.width, size.height)
        let scale = maxDim > maxEdge ? maxEdge / maxDim : 1.0
        let target = NSSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(target.width), pixelsHigh: Int(target.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = target
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(in: NSRect(origin: .zero, size: target))
        NSGraphicsContext.current?.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        #else
        let maxDim = max(size.width, size.height)
        let scale = maxDim > maxEdge ? maxEdge / maxDim : 1.0
        let target = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let renderer = UIGraphicsImageRenderer(size: target)
        let drawn = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        return drawn.jpegData(compressionQuality: quality)
        #endif
    }
}

/// 从 URL 读取图像文件。
func loadAppImage(from url: URL) -> AppImage? {
    #if os(macOS)
    return AppImage(contentsOf: url)
    #else
    return AppImage(contentsOfFile: url.path)
    #endif
}

#if os(macOS)
extension NSImage {
    /// PNG 数据（iOS 上 UIImage.pngData() 为系统提供，此处只补 macOS）。
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
#endif
