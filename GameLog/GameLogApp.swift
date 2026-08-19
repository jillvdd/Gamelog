import SwiftUI
import SwiftData

@main
struct GameLogApp: App {
    @AppStorage("appLanguage") private var languageCode = AppLanguage.chinese.localeCode
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

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
            // AutoBackupContainer：启动时执行自动备份的启动检查（启动备份/版本快照/空库检测恢复）。
            AutoBackupContainer {
                Group {
                    #if os(macOS)
                    RootView()
                    #else
                    iOSRootView()
                    #endif
                }
                .environment(\.appLanguageCode, languageCode)
                .environment(\.locale, Locale(identifier: languageCode))
                #if os(macOS)
                .onAppear { UserCustomization.applyDockIcon() }
                #endif
            }
        }
        .modelContainer(container)
        #if os(macOS)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button {
                    openWindow(id: "about")
                } label: {
                    Text(L10n.tr("about.menu", lang: languageCode))
                }
            }
        }
        #endif

        #if os(macOS)
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

        // 评价编辑独立窗口（macOS 专属「写字台」）：详情页点「编辑评价」打开，
        // 保存才写回 reviewTitle/reviewBody。当前编辑目标经 ReviewEditorSession 共享。
        Window(L10n.tr("review.editor", lang: languageCode), id: "reviewEditor") {
            ReviewEditorView()
                .environment(\.appLanguageCode, languageCode)
                .environment(\.locale, Locale(identifier: languageCode))
        }
        .modelContainer(container)
        #if os(macOS)
        .defaultSize(width: 760, height: 520)
        #endif
        #endif
    }
}
