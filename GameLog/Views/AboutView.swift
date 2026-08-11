import SwiftUI
import AppKit

/// 关于：应用图标、名称、版本号、开发者信息。
/// 独立「关于」窗口内容，从 app 菜单（App 名菜单 → 关于）打开。
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
        VStack(spacing: 16) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                .resizable()
                .frame(width: 64, height: 64)
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
        .frame(width: 340)
    }
}
