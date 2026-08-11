import SwiftUI
import AppKit

/// 关于：应用图标、名称、版本号、开发者信息。
/// 版本号从 Bundle 动态读取，跟随 Xcode 的 MARKETING_VERSION，不写死。
struct AboutView: View {
    @Environment(\.appLanguageCode) private var language

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? "GameLog"
    }

    var body: some View {
        Section(L10n.tr("settings.about", lang: language)) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                    .resizable()
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: appName)
                        .font(.headline)
                    Text(verbatim: "\(L10n.tr("about.version", lang: language)) \(version)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            LabeledContent(L10n.tr("about.developer", lang: language)) {
                Text(verbatim: "jill")
            }
            LabeledContent("GitHub") {
                Text(verbatim: "jillvdd")
            }
            LabeledContent("X (Twitter)") {
                Text(verbatim: "jill05617147")
            }
            LabeledContent("微博") {
                Text(verbatim: "JILL_MK3")
            }
        }
    }
}
