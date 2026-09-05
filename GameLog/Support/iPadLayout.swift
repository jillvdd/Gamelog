import Foundation

#if os(iOS)
import UIKit
#endif

/// iPad 与 iPhone 的版式分界（设备级判定 + 宽度档位）。消费方：
/// HomeCarousel（轮播横屏扁比例）、GameDetailView（hero 横幅版式 / 横幅高度上限 /
/// 宽窗头部）、LibraryView / GameWideCardView（宽卡双列卡高分档）。
///
/// 判定用 `UIDevice.current.userInterfaceIdiom == .pad`（硬件设备）而非
/// horizontalSizeClass——iPhone Pro Max 横屏 sizeClass 同样是 regular，而用户语义
/// 「iPad 版」是设备级：iPhone 任何朝向布局必须保持现状不误伤。iPad 分屏/侧拉
/// 变窄时由 wideThreshold 宽度阈值自然回落窄版式，无需 sizeClass 参与。
///
/// macOS 也编译此类型（GameCardView.swift 双平台共享文件）：isPad 恒 false，
/// 所有 iPad 分支在 macOS 上天然跳过，不影响现有布局。
enum iPadLayout {
    #if os(iOS)
    /// 当前设备是否 iPad（进程生命周期内不变，iPhone 恒 false → 所有 iPad 分支跳过）。
    static let isPad: Bool = UIDevice.current.userInterfaceIdiom == .pad
    #else
    /// macOS 恒 false：iPad 分支只为 iOS 编译存在。
    static let isPad: Bool = false
    #endif

    /// 宽版式阈值：iPad mini 竖屏宽 ~744 / 横屏 ~1133（iPad 11" 820/1180），
    /// ≥ 此值按横屏/超宽版式（hero 横幅、轮播扁比例、宽卡高档卡高）。
    /// 13" iPad 竖屏宽 1024 也会过阈——大屏竖屏走宽版式不违和，接受。
    static let wideThreshold: CGFloat = 950

    // MARK: - 宽卡（GameWideCardView）横竖屏分档（2026-09-05 需求①）

    /// iPad 双列宽卡：横屏走横版卡（左图右文），竖屏走竖版卡（上图下文）。
    /// GameCardView 双平台编译，此计算属性 macOS 恒 false 不参与。
    /// 判定依据调用点 GeometryReader 实测宽（viewWidth），非 UIDevice 朝向——
    /// 分屏/浮窗下与实际可用宽一致。
    static func isPadLandscapeCard(viewWidth: CGFloat) -> Bool {
        isPad && viewWidth >= wideThreshold
    }

    /// iPad 竖屏竖版卡几何（需求①）：封面边长 = 列宽（LibraryView 传实测值），
    /// 文字块定高：两行 15pt 标题（~40）+ 平台行（~20）+ 元数据五项升档
    /// （值 12pt 单/双行、标题 9pt，~150 含间距）+ 上下内距 22。
    static let padPortraitTextBlockHeight: CGFloat = 190
}
