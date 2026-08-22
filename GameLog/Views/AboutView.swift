import SwiftUI
#if os(macOS)
import AppKit
#endif

/// 关于：应用图标、名称、版本号、开发者信息。
/// macOS：独立「关于」窗口内容，从 app 菜单（App 名菜单 → 关于）打开；
/// iOS：设置页「关于我的游戏簿」入口以 sheet 呈现。
/// 版本号从 Bundle 动态读取，跟随 Xcode 的 MARKETING_VERSION，不写死。
struct AboutView: View {
    @Environment(\.appLanguageCode) private var language

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    private var appName: String {
        L10n.tr("app.menu", lang: language)
    }

    var body: some View {
        #if os(macOS)
        // macOS「关于」窗口（hiddenTitleBar, 380×300）：保持原固定内容宽。
        content
            .frame(width: 340)
        #else
        // iOS sheet：内容自适应宽度。
        content
            .frame(maxWidth: .infinity)
        #endif
    }

    private var content: some View {
        VStack(spacing: 16) {
            appIcon
            VStack(spacing: 2) {
                Text(verbatim: appName)
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(verbatim: "\(L10n.tr("about.version", lang: language)) \(version)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Divider()
            VStack(spacing: 10) {
                LabeledContent(L10n.tr("about.developer", lang: language)) {
                    Text(verbatim: "jill")
                }
                LabeledContent("GitHub") {
                    Text(verbatim: "@jillvdd")
                }
                LabeledContent("X (Twitter)") {
                    Text(verbatim: "@jill05617147")
                }
                LabeledContent("微博") {
                    Text(verbatim: "@JILL_MK3")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(24)
    }

    /// App 主图标：macOS 取 bundle 的 Finder 图标；iOS 读打包进 Info.plist 的主图标名。
    @ViewBuilder
    private var appIcon: some View {
        #if os(macOS)
        Image(appImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
            .resizable()
            .frame(width: 64, height: 64)
        #else
        if let icon = Self.primaryAppIcon() {
            Image(appImage: icon)
                .resizable()
                .frame(width: 64, height: 64)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: 44))
                .frame(width: 64, height: 64)
        }
        #endif
    }

    #if !os(macOS)
    private static func primaryAppIcon() -> AppImage? {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String],
              let name = files.last else { return nil }
        return AppImage(named: name)
    }
    #endif
}
