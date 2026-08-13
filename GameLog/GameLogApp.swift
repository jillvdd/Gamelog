import SwiftUI
import SwiftData

@main
struct GameLogApp: App {
    @AppStorage("appLanguage") private var languageCode = AppLanguage.chinese.localeCode
    @Environment(\.openWindow) private var openWindow

    /// 各场景共享同一个容器实例。
    private let container: ModelContainer = {
        let schema = Schema([Game.self, Completion.self, GameGroup.self])
        do {
            let container = try ModelContainer(for: schema)
            // 启动即迁移平台旧名（Switch → Nintendo Switch），UI 展示前完成，幂等。
            PlatformMigration.migrate(in: ModelContext(container))
            return container
        } catch {
            fatalError("无法创建数据容器: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.appLanguageCode, languageCode)
                .environment(\.locale, Locale(identifier: languageCode))
                .onAppear { UserCustomization.applyDockIcon() }
        }
        .modelContainer(container)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button {
                    openWindow(id: "about")
                } label: {
                    Text(L10n.tr("about.menu", lang: languageCode))
                }
            }
        }

        Settings {
            SettingsView()
                .environment(\.appLanguageCode, languageCode)
                .environment(\.locale, Locale(identifier: languageCode))
        }
        .modelContainer(container)

        Window(L10n.tr("app.menu", lang: languageCode), id: "about") {
            AboutView()
                .environment(\.appLanguageCode, languageCode)
                .environment(\.locale, Locale(identifier: languageCode))
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 380, height: 300)
    }
}
