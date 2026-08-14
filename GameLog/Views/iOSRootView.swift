import SwiftUI
import SwiftData

#if os(iOS)

/// iOS 入口：底部 TabBar（库 / 统计 / 设置）。
/// macOS 保持 NavigationSplitView 侧边栏（RootView）；iOS 用 TabBar 三个页签。
struct iOSRootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    @State private var tab = Tab.library
    /// AirDrop / 打开方式 收到的备份文件 URL（确认后导入）。
    @State private var incomingBackupURL: URL?
    @State private var showingIncomingImport = false

    private enum Tab: Hashable { case library, stats, settings }

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

    /// 导入 AirDrop 收到的备份：替换整个库。
    private func importIncomingBackup() {
        guard let url = incomingBackupURL else { return }
        incomingBackupURL = nil
        // 「文件」App 打开方式发来的 URL 是 security-scoped，直接读会无权限；AirDrop 路径系统已拷入沙盒可读。
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            try BackupManager.decodeAndReplace(data, into: context)
            try context.save()
        } catch {
            // 导入失败静默：保留现有数据。
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
    @State private var showingGroupManager = false

    /// 库里出现过的平台（预设世代倒序 + 自定义排最后）。
    private var platformsInUse: [String] {
        var seen: Set<String> = []
        for game in games {
            for completion in game.completions where !completion.platform.isEmpty {
                seen.insert(completion.platform)
            }
        }
        return Presets.ordered(Array(seen))
    }

    var body: some View {
        NavigationStack {
            LibraryView(groupFilter: groupFilter, platform: platformFilter)
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

    /// 整合的筛选菜单：分组 / 平台 / 全部游戏互斥单选（与 macOS 侧边栏的导航一致）。
    /// 选中分组会清掉平台筛选、选中平台会清掉分组筛选，不会同时生效，始终只有一个勾选。
    private var filterMenu: some View {
        Menu {
            Button {
                groupFilter = nil
                platformFilter = nil
            } label: {
                if groupFilter == nil && platformFilter == nil {
                    Label(L10n.tr("library.all", lang: language), systemImage: "checkmark")
                } else {
                    Text(verbatim: L10n.tr("library.all", lang: language))
                }
            }

            Section(L10n.tr("library.filterGroup", lang: language)) {
                ForEach(groups) { group in
                    Button {
                        groupFilter = group
                        platformFilter = nil
                    } label: {
                        if groupFilter?.persistentModelID == group.persistentModelID && platformFilter == nil {
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
                        groupFilter = nil
                    } label: {
                        HStack(spacing: 8) {
                            PlatformIcon(platform: platform, size: 16)
                            Text(verbatim: Presets.display(platform, category: .platform, language: language))
                            Spacer()
                            if platformFilter == platform && groupFilter == nil {
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
                ForEach(groups) { group in
                    HStack(spacing: 16) {
                        Text(verbatim: group.name)
                            .lineLimit(1)
                        Spacer()
                        Button { renaming = group } label: { Image(systemName: "pencil") }
                            .buttonStyle(.borderless)
                        Button { pickingGames = group } label: { Image(systemName: "checkmark.square") }
                            .buttonStyle(.borderless)
                        Button(role: .destructive) { deleting = group } label: { Image(systemName: "trash") }
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
        .sheet(item: $renaming) { RenameGroupSheet(group: $0) }
        .sheet(item: $pickingGames) { GroupGamePickerView(group: $0) }
        .platformConfirmDialog(
            L10n.tr("group.deleteTitle", lang: language),
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            message: deleting.map {
                L10n.tr("group.deleteConfirm", [$0.name], lang: language)
            },
            cancelTitle: L10n.tr("common.cancel", lang: language),
            actions: [
                ConfirmAction(
                    title: L10n.tr("common.delete", lang: language),
                    isDestructive: true
                ) {
                    if let group = deleting {
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
