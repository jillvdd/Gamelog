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
            PlatformMigration.sanitizeDefaultStore()
            let container = try ModelContainer(for: schema)
            PlatformMigration.sanitizeDatabase(at: container.configurations.first?.url)
            // 平台旧名迁移：改写有副作用（fetch 全量实体 → save），挪到后台异步执行，
            // 避免大库冷启动在主线程同步遍历全部实体造成白屏卡顿（2026-09-18 iOS 真机问题）。
            // 迁移幂等：一次性 UserDefaults 闸门保证只跑一次，多次启动无害。
            Task.detached(priority: .utility) {
                do {
                    try PlatformMigration.migrate(in: ModelContext(container))
                } catch {
                    NSLog("GameLog: PlatformMigration save failed: \(error)")
                }
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
            // 「关联设置」紧跟在系统「设置…」(⌘,) 的正下方 —— `CommandGroupPlacement.appSettings`
            // 正是系统 Settings 项的位置。它开的是独立窗口而不是第二个设置面板：这一页装的是
            // 外部服务凭证 / 账号绑定 / 整库导入导出，跟「本机偏好」不是一类东西（见 LinkSettingsView）。
            CommandGroup(after: .appSettings) {
                Button {
                    openWindow(id: "linkSettings")
                } label: {
                    Text(L10n.tr("links.menu", lang: languageCode))
                }
                .keyboardShortcut(",", modifiers: [.command, .shift])
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

        // 关联设置独立窗口（App 菜单「关联设置…」⌘⇧, 打开）：SteamGridDB key / 游戏账号 /
        // 数据备份。⚠️ 这一页用 `@Query` 与 `modelContext`，`modelContainer` 必须给上；
        // ⚠️ 窗口标题由这里给，页面自己也**不**设 `navigationTitle` —— 否则「隐藏上方毛玻璃」
        // 会把标题置空，独立窗口就变成无名窗口。
        Window(L10n.tr("links.title", lang: languageCode), id: "linkSettings") {
            LinkSettingsView()
                .environment(\.appLanguageCode, languageCode)
                .environment(\.locale, Locale(identifier: languageCode))
        }
        .modelContainer(container)
        .defaultSize(width: 560, height: 780)

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
