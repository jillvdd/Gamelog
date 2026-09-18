import SwiftUI

/// 品牌配色唯一归属：暖调近黑底 + 琥珀橙强调。
///
/// **唯一归属，别在调用处另起一套数值**（同 `StatusStyle` / `TagLabel` / `PlatformIcon`
/// 的集中口径）。这组数值此前在 5 个文件里各抄一遍（`LaunchGate` / `HomeCarousel` ×10 /
/// `SettingsView` / `SharePanelView` / `ShareCardView`），改一处就要人肉找齐其余四处。
///
/// ## 为什么 `surface` 与 `gradientTop` 是两个常量
///
/// 它们**不是同一个颜色**：分享卡的卡片底色是 `0.13/0.118/0.10`，
/// 而开屏之外的横幅渐变顶端用的是 `0.13/0.115/0.09`（蓝通道差 0.01）。
/// 收敛时**逐字保留**了两组数值而不是取其一统一 —— 本批的前提是「只给已有的数值起名字，
/// 零观感变化」，顺手改掉任何一个都会让已定版的页面出现肉眼可辨的色偏。
/// 将来若要真正统一，先定哪一个是准的，再单独做一次有截图的改动。
///
/// ## 第 4 份拷贝（无法收敛的那一份）
///
/// `Assets.xcassets/LaunchBackground.colorset` 里还存着一份 `background` 的等价色值。
/// 那是**资产目录**、由系统在 LaunchScreen 阶段直接读取，Swift 常量够不着它 ——
/// 这是本组数值唯一必须重复的地方。改 `background` 时记得同步那个 colorset。
enum BrandPalette {

    /// 品牌底色：开屏背景、分享卡背景、分享预览底衬、横幅渐变底端。
    static let background = Color(red: 0.075, green: 0.067, blue: 0.055)

    /// 品牌卡面：分享卡等深色面板的底色。
    static let surface = Color(red: 0.13, green: 0.118, blue: 0.10)

    /// 横幅渐变顶端色（与 `surface` 有意不同，见上）。
    static let gradientTop = Color(red: 0.13, green: 0.115, blue: 0.09)

    /// 琥珀橙强调色：开屏标题 / 进度条、轮播高亮与描边、分享卡 accent。
    static let accent = Color(red: 1.0, green: 0.72, blue: 0.42)
}
