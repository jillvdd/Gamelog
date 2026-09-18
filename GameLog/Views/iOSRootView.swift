import SwiftUI
import SwiftData

#if os(iOS)

/// iOS 入口：底部 TabBar（库 / 统计 / 关联 / 设置）。
/// macOS 保持 NavigationSplitView 侧边栏（RootView）；iOS 用 TabBar 四个页签。
struct iOSRootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    @State private var tab = Tab.library
    /// AirDrop / 打开方式 收到的备份文件 URL（确认后导入）。
    @State private var incomingBackupURL: URL?
    @State private var showingIncomingImport = false

    private enum Tab: Hashable { case library, stats, links, settings }

    var body: some View {
        TabView(selection: $tab) {
            iOSLibraryTab()
                .tabItem {
                    Label(L10n.tr("tab.library", lang: language), systemImage: "books.vertical")
                }
                .tag(Tab.library)
            StatsView()
                .tabItem {
                    Label(L10n.tr("library.stats", lang: language), systemImage: "chart.bar.fill")
                }
                .tag(Tab.stats)
            // 「关联」（关联设置）：外部服务凭证 / 游戏账号 / 数据备份。与 macOS 的
            // App 菜单「关联设置…」是同一个页面、同一份内容，只是入口按平台各就各位。
            // 页签栏外观零设置 —— 液态玻璃是系统 TabBar 自己的皮（iPad 走同一个 root，
            // 系统会把页签栏按 iPadOS 规范摆到它认为对的位置，那是系统行为）。
            LinkSettingsView()
                .tabItem {
                    Label(L10n.tr("tab.links", lang: language), systemImage: "link")
                }
                .tag(Tab.links)
            SettingsView()
                .tabItem {
                    Label(L10n.tr("tab.settings", lang: language), systemImage: "gearshape.fill")
                }
                .tag(Tab.settings)
        }
        .onOpenURL { url in
            // AirDrop 备份 JSON：弹确认后导入（会替换当前数据）。
            incomingBackupURL = url
            showingIncomingImport = true
        }
        .platformConfirmDialog(
            L10n.tr("common.confirm", lang: language),
            isPresented: $showingIncomingImport,
            message: L10n.tr("backup.importConfirm", lang: language),
            cancelTitle: L10n.tr("common.cancel", lang: language),
            actions: [
                ConfirmAction(title: L10n.tr("common.confirm", lang: language)) {
                    importIncomingBackup()
                }
            ]
        )
    }

    /// 导入 AirDrop 收到的备份：走统一入口 importBackup（快照→后台重建→定制回写→广播→补备份）。
    /// 安全作用域内只同步读完 Data 就释放——`defer{stop}` 不可跨 await（2026-09-08），
    /// 后续异步链只传 Data 不传 URL。
    private func importIncomingBackup() {
        guard let url = incomingBackupURL else { return }
        incomingBackupURL = nil
        // 「文件」App 打开方式发来的 URL 是 security-scoped，直接读会无权限；AirDrop 路径系统已拷入沙盒可读。
        // 无条件 start：对 AirDrop URL 是 no-op（返回 false），对「文件」App 路径真正生效。
        let didStart = url.startAccessingSecurityScopedResource()
        guard let data = try? Data(contentsOf: url) else {
            if didStart { url.stopAccessingSecurityScopedResource() }
            return
        }
        if didStart { url.stopAccessingSecurityScopedResource() }
        let context = context
        Task { @MainActor in
            try? await AutoBackup.shared.importBackup(data, into: context) { _ in }
        }
    }
}

/// iOS 库页：分组 / 平台两个工具栏筛选菜单 + 新建分组与分组管理入口。
/// LibraryView 自身工具栏（排序/网格/分享/新建游戏）复用；分组与平台筛选由本页驱动。
struct iOSLibraryTab: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    @Query(sort: \GameGroup.name) private var groups: [GameGroup]
    @Query(sort: \Game.createdAt) private var games: [Game]

    @State private var groupFilter: GameGroup?
    @State private var platformFilter: String?
    /// 状态筛选（想玩/在玩/…），与分组/平台互斥单选。
    @State private var statusFilter: GameStatus?
    /// 虚拟分组「我的最爱」筛选（与分组/平台/状态互斥单选）。
    @State private var favoritesOnly = false
    @State private var showingGroupManager = false

    /// 还活着的游戏/分组。批量删除（整库替换 / 清空账号导入数据）之后 SwiftUI 会拿旧
    /// `@Query` 数组再渲染一帧，那时读已销毁模型就是 SwiftData fatal（判据见 `Game.isLive`）。
    private var liveGames: [Game] { games.filter(\.isLive) }
    private var liveGroups: [GameGroup] { groups.filter(\.isLive) }

    /// 库里出现过的平台：唯一归属 LibraryStats。
    private var platformsInUse: [String] { LibraryStats.platformsInUse(liveGames) }

    var body: some View {
        NavigationStack {
            LibraryView(groupFilter: groupFilter, platform: platformFilter, statusFilter: statusFilter, favoritesOnly: favoritesOnly)
                .toolbar {
                    // 筛选（分组/平台）整合为一个按钮放 leading，避免两个按钮误触；
                    // 新建游戏与「更多」在 LibraryView 的 trailing，避免触发系统折叠「…」。
                    ToolbarItem(placement: .topBarLeading) { filterMenu }
                }
        }
        .sheet(isPresented: $showingGroupManager) { iOSGroupManagerSheet() }
        // 分组被删除（分组管理页）后，若当前筛选正指向该分组，先清掉引用，
        // 避免 LibraryView 继续访问已删除的模型对象而崩溃（macOS 侧删除前先清选中态，iOS 靠这里兜底）。
        .onChange(of: groups) { _, newGroups in
            if let current = groupFilter,
               !newGroups.contains(where: { $0.persistentModelID == current.persistentModelID }) {
                groupFilter = nil
            }
        }
    }

    /// 整合的筛选菜单：状态 / 分组 / 平台 / 全部游戏互斥单选（与 macOS 侧边栏的导航一致）。
    /// 选中任一维度会清掉其他维度，不会同时生效，始终只有一个勾选。
    private var filterMenu: some View {
        Menu {
            Button {
                statusFilter = nil
                groupFilter = nil
                platformFilter = nil
                favoritesOnly = false
            } label: {
                if statusFilter == nil && groupFilter == nil && platformFilter == nil && !favoritesOnly {
                    Label(L10n.tr("library.all", lang: language), systemImage: "checkmark")
                } else {
                    Text(verbatim: L10n.tr("library.all", lang: language))
                }
            }

            Section(L10n.tr("game.status", lang: language)) {
                ForEach(GameStatus.allCases) { s in
                    Button {
                        statusFilter = s
                        groupFilter = nil
                        platformFilter = nil
                        favoritesOnly = false
                    } label: {
                        if statusFilter == s && groupFilter == nil && platformFilter == nil && !favoritesOnly {
                            Label(L10n.tr(s.labelKey, lang: language), systemImage: "checkmark")
                        } else {
                            Text(verbatim: L10n.tr(s.labelKey, lang: language))
                        }
                    }
                }
            }

            Section(L10n.tr("library.filterGroup", lang: language)) {
                // 虚拟分组「我的最爱」常驻首位（与真实分组并存）。
                Button {
                    favoritesOnly = true
                    statusFilter = nil
                    groupFilter = nil
                    platformFilter = nil
                } label: {
                    if favoritesOnly && statusFilter == nil && groupFilter == nil && platformFilter == nil {
                        Label(L10n.tr("game.favorites", lang: language), systemImage: "checkmark")
                    } else {
                        Text(verbatim: L10n.tr("game.favorites", lang: language))
                    }
                }
                ForEach(liveGroups) { group in
                    Button {
                        groupFilter = group
                        statusFilter = nil
                        platformFilter = nil
                        favoritesOnly = false
                    } label: {
                        if groupFilter?.persistentModelID == group.persistentModelID && statusFilter == nil && platformFilter == nil && !favoritesOnly {
                            Label(group.name, systemImage: "checkmark")
                        } else {
                            Text(verbatim: group.name)
                        }
                    }
                }
            }

            Section(L10n.tr("library.filterPlatform", lang: language)) {
                ForEach(platformsInUse, id: \.self) { platform in
                    Button {
                        platformFilter = platform
                        statusFilter = nil
                        groupFilter = nil
                        favoritesOnly = false
                    } label: {
                        HStack(spacing: 8) {
                            PlatformIcon(platform: platform, size: 16)
                            Text(verbatim: Presets.display(platform, category: .platform, language: language))
                            Spacer()
                            if platformFilter == platform && statusFilter == nil && groupFilter == nil && !favoritesOnly {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Divider()
            Button {
                showingGroupManager = true
            } label: {
                Label(L10n.tr("group.manage", lang: language), systemImage: "slider.horizontal.3")
            }
        } label: {
            Label(L10n.tr("library.filter", lang: language), systemImage: "line.3.horizontal.decrease")
        }
    }
}

/// iOS 分组管理页：列出全部分组，提供改名 / 选择游戏 / 删除。
struct iOSGroupManagerSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \GameGroup.name) private var groups: [GameGroup]
    @State private var renaming: GameGroup?
    @State private var pickingGames: GameGroup?
    @State private var deleting: GameGroup?
    @State private var showingNewGroup = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups.filter(\.isLive)) { group in
                    HStack(spacing: 16) {
                        Text(verbatim: group.name)
                            .lineLimit(1)
                        Spacer()
                        // 行内图标按钮补足 44×44 触控目标（HIG），视觉不变。
                        Button { renaming = group } label: {
                            Image(systemName: "pencil")
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        Button { pickingGames = group } label: {
                            Image(systemName: "checkmark.square")
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        Button(role: .destructive) { deleting = group } label: {
                            Image(systemName: "trash")
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .navigationTitle(L10n.tr("group.manage", lang: language))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.tr("common.done", lang: language)) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewGroup = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help(L10n.tr("group.newGroup", lang: language))
                }
            }
        }
        .sheet(isPresented: $showingNewGroup) { NewGroupSheet() }
        // 两个 item 绑定都过一道 `isLive`（判据见 `Game.isLive`，勿用 `isDeleted`）：
        // 分组可能已被别处删掉（整库替换 / 本页自己的删除），那时 sheet 里读它即 fatal。
        // `GroupGamePickerView` / `RenameGroupSheet` 自己也在 body 挡一道，这里是第一道。
        .sheet(item: Binding(
            get: { renaming?.isLive == true ? renaming : nil },
            set: { renaming = $0 }
        )) { RenameGroupSheet(group: $0) }
        .sheet(item: Binding(
            get: { pickingGames?.isLive == true ? pickingGames : nil },
            set: { pickingGames = $0 }
        )) { GroupGamePickerView(group: $0) }
        .platformConfirmDialog(
            L10n.tr("group.deleteTitle", lang: language),
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            message: deleting.flatMap { group in
                group.isLive ? L10n.tr("group.deleteConfirm", [group.name], lang: language) : nil
            },
            cancelTitle: L10n.tr("common.cancel", lang: language),
            actions: [
                ConfirmAction(
                    title: L10n.tr("common.delete", lang: language),
                    isDestructive: true
                ) {
                    if let group = deleting, group.isLive {
                        context.delete(group)
                        try? context.save()
                    }
                    deleting = nil
                }
            ]
        )
    }
}
#endif
