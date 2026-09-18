import SwiftUI

/// 双平台开屏界面：窗口/启动立即显示品牌页（图标 + app 名 + 细进度条），
/// 底层主界面同时构建（数据加载在后台进行），就绪后淡出开屏。
///
/// 2026-08-29 新增（用户需求「直接显示开屏界面，不要静默加载」）：
/// 旧启动链上 ModelContainer 创建 + 启动检查同步编码 771MB 备份，白屏数秒。
/// 现在容器创建留在 GameLogApp（已在启动检查轻量化后毫秒级），开屏只等首帧布局稳定。
///
/// - iOS：系统 UILaunchScreen 静态开屏（点图标瞬间显示）→ 本视图无缝接力（同一底色），
///   首帧稳定后淡出；总时长钳制 0.6–1.4s，保证「看得到」但不拖沓。
/// - macOS：窗口创建即渲染本视图（主内容隐藏构建），淡出后进入 RootView。
struct LaunchGate<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.appLanguageCode) private var language

    /// false = 开屏在屏；true = 主界面已接管。
    @State private var isReady = false
    /// 淡出透明度（1 → 0 过渡后整体移除）。
    @State private var splashOpacity: Double = 1
    /// 最短展示（用户要「直接显示的开屏」，至少让它稳定可辨）。
    private let minimumSplash: TimeInterval = 0.7
    /// 最长兜底（后台初始化异常时开屏也不能永久挡住主界面）。
    private let maximumSplash: TimeInterval = 3.0

    var body: some View {
        ZStack {
            content
                .opacity(isReady ? 1 : 0)
                .allowsHitTesting(isReady)

            if !isReady {
                splashView
                    .opacity(splashOpacity)
                    .transition(.opacity)
            }
        }
        .task {
            let start = Date()
            // 让首帧（开屏）先上屏，再等主界面完成首次布局。
            try? await Task.sleep(nanoseconds: 200_000_000)
            // 主界面构建完成信号：让出一轮 runloop 即认为 content 已可渲染。
            await Task.yield()
            let elapsed = Date().timeIntervalSince(start)
            if elapsed < minimumSplash {
                try? await Task.sleep(nanoseconds: UInt64((minimumSplash - elapsed) * 1_000_000_000))
            }
            withAnimation(.easeOut(duration: 0.35)) {
                splashOpacity = 0
                isReady = true
            }
            // 兜底：极端情况下动画被系统冻结时强制放行。
            try? await Task.sleep(nanoseconds: UInt64(maximumSplash * 1_000_000_000))
            if !isReady { isReady = true; splashOpacity = 0 }
        }
    }

    private var splashView: some View {
        ZStack {
            // 双平台同一品牌底色（与分享卡品牌深色一致）
            BrandPalette.background
                .ignoresSafeArea()

            VStack(spacing: 18) {
                AppIconBadge()
                    .frame(width: 96, height: 96)
                Text(L10n.tr("app.menu", lang: language))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(BrandPalette.accent)
                SplashProgress()
                    .frame(width: 120, height: 3)
            }
        }
    }
}

/// app 图标徽章：从 asset catalog 读 AppIcon（双平台各自的单 1024 图 / 多尺寸集），
/// 圆角裁切 + 细描边。读不到时退化为琥珀橙底 + 书本符号。
struct AppIconBadge: View {
    var body: some View {
        ZStack {
            if let icon = Self.appIconImage() {
                Image(appImage: icon)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(BrandPalette.accent)
                    .overlay {
                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.black.opacity(0.7))
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
    }

    /// 读 bundle 主图标：macOS 走 NSApplication.icon（应用实例已就绪），
    /// iOS 图标已编译进 Assets.car（裸 PNG 不在 bundle），走 UIImage(named:)。
    private static func appIconImage() -> AppImage? {
        #if os(macOS)
        let img = NSApplication.shared.applicationIconImage
        return (img?.size.width ?? 0) > 1 ? img : nil
        #else
        // AppIcon 集不能经 UIImage(named:) 读；开屏用普通 imageset「LaunchIcon」
        // （内容 = AppIcon-iOS-1024.png，与主图标同源）。
        return UIImage(named: "LaunchIcon")
        #endif
    }
}

/// 开屏细进度条：不确定型往返动画（琥珀橙），不假装有真实进度。
private struct SplashProgress: View {
    @State private var phase: Bool = false

    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.12))
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(BrandPalette.accent)
                    .frame(width: 44)
                    .offset(x: phase ? 76 : 0)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: phase)
            }
            .clipShape(Capsule())
            .onAppear { phase = true }
    }
}
