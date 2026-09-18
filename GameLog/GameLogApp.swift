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
        // 外部账号同步（beta 3.1）新增 LinkedAccount / ExternalGameRecord 两个实体，
        // 并在 Game 上加了一条 .nullify 反向关系。纯增量 + 全部声明处带默认值 →
        // SwiftData 轻量迁移可覆盖，无需 VersionedSchema / MigrationStage，不删字段不重建库。
        let schema = Schema([
            Game.self, Completion.self, GameGroup.self,
            LinkedAccount.self, ExternalGameRecord.self
        ])
        do {
            let container = try ModelContainer(for: schema)
            // 启动即迁移平台旧名（Switch → Nintendo Switch），UI 展示前完成，幂等。
            // save 失败不阻断启动（迁移幂等，下次启动重跑）；此前 try? 吞错会让闸门
            // 置位而数据未迁移（2026-09-05 审计）。
            do {
                try PlatformMigration.migrate(in: ModelContext(container))
            } catch {
                NSLog("GameLog: PlatformMigration save failed: \(error)")
            }
            return container
        } catch {
            fatalError("无法创建数据容器: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            // LaunchGate：开屏界面（品牌图标 + app 名 + 进度条），主界面就绪后淡出接管。
            // iOS 另有系统 UILaunchScreen 静态开屏（点图标瞬间显示，底色一致无缝衔接）。
            LaunchGate {
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
            .environment(\.appLanguageCode, languageCode)
            .environment(\.locale, Locale(identifier: languageCode))
        }
        .modelContainer(container)
        #if os(macOS)
        // 尺寸契约与内容对齐：`RootView` 自己声明了 `minWidth: 980, minHeight: 600`，
        // 但 scene 侧此前什么也没说 —— 首启窗口按系统默认尺寸开出，比内容下限还小，
        // 而且能被拖到下限以下（内容被压扁）。`windowResizability` 让窗口下限就是内容下限。
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
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
        // 这一整块已经在 `#if os(macOS)` 里（见上），不必再套一层 —— 此前多包的那层
        // 让「哪些 scene 是 macOS 专属」读起来比实际更绕。
        .defaultSize(width: 760, height: 520)
        #endif
    }
}
