import SwiftUI
import SwiftData

/// 侧边栏条目：全部游戏 / 某状态 / 某个平台 / 某个分组 / 统计。
enum SidebarItem: Hashable {
    case all
    case status(GameStatus)
    case platform(String)
    case group(GameGroup)
    case stats
}

/// 侧边栏状态行图标。
private extension GameStatus {
    var sidebarIcon: String {
        switch self {
        case .backlog: "bookmark"
        case .playing: "play.circle"
        case .paused: "pause.circle"
        case .dropped: "xmark.circle"
        case .longRunning: "infinity"
        case .completed: "checkmark.circle"
        }
    }
}

/// 可折叠 section 的 header：系统小字样式 + 前置折叠 chevron（展开朝下、收起朝右，Finder 惯例），
/// 整行可点切换。原生 `Section(isExpanded:)` 在 macOS 27 beta 侧边栏上不出 chevron，故自绘。
private struct SidebarSectionHeader: View {
    let title: String
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                Text(title)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    @Query(sort: \GameGroup.name) private var groups: [GameGroup]
    @Query(sort: \Game.createdAt) private var games: [Game]
    @AppStorage(UserCustomization.avatarFileKey) private var avatarFile = ""
    @AppStorage(UserCustomization.usernameKey) private var username = ""
    // 侧边栏三区展开状态（默认 true=展开；直接喂给 Section(isExpanded:)，跨会话记忆）。
    @AppStorage(UserCustomization.sidebarStatusExpandedKey) private var statusExpanded = true
    @AppStorage(UserCustomization.sidebarPlatformsExpandedKey) private var platformsExpanded = true
    @AppStorage(UserCustomization.sidebarGroupsExpandedKey) private var groupsExpanded = true
    @State private var selection: SidebarItem? = .all
    @State private var showingNewGroup = false
    @State private var renameGroup: GameGroup?
    @State private var deleteGroup: GameGroup?
    @State private var pickingGamesGroup: GameGroup?

    /// 平台 → 去重游戏数 / 在用平台：唯一归属 LibraryStats。
    private var platformCounts: [String: Int] { LibraryStats.platformCounts(games) }
    private var platformsInUse: [String] { LibraryStats.platformsInUse(games) }

    /// 分组行「选择游戏」的 popover 绑定：只在该行分组被选中时弹出，锚定到该行。
    private func popoverBinding(for group: GameGroup) -> Binding<GameGroup?> {
        Binding(
            get: { pickingGamesGroup?.persistentModelID == group.persistentModelID ? group : nil },
            set: { if $0 == nil { pickingGamesGroup = nil } }
        )
    }

    var body: some View {
        mainRoot
    }

    private var mainRoot: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    Label(L10n.tr("library.all", lang: language), systemImage: "books.vertical")
                        .tag(SidebarItem.all)
                }
                Section {
                    if statusExpanded {
                        ForEach(GameStatus.allCases) { status in
                            Label(L10n.tr(status.labelKey, lang: language), systemImage: status.sidebarIcon)
                                .tag(SidebarItem.status(status))
                        }
                    }
                } header: {
                    SidebarSectionHeader(title: L10n.tr("game.status", lang: language), isExpanded: statusExpanded) {
                        withAnimation(.easeInOut(duration: 0.2)) { statusExpanded.toggle() }
                    }
                }
                if !platformsInUse.isEmpty {
                    Section {
                        if platformsExpanded {
                            ForEach(platformsInUse, id: \.self) { platform in
                                // 统一图标槽位（等比 contain，品牌 logo 参差不再撑行）+ 名字单行:
                                // 此前放大图标 + ViewThatFits 两行退化让平台区行高错乱、宽字标溢出。
                                HStack(spacing: 8) {
                                    PlatformIcon(platform: platform, size: 16, slot: CGSize(width: 32, height: 20))
                                    Text(verbatim: Presets.display(platform, category: .platform, language: language))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .badge(platformCounts[platform] ?? 0)
                                .tag(SidebarItem.platform(platform))
                            }
                        }
                    } header: {
                        SidebarSectionHeader(title: L10n.tr("library.platforms", lang: language), isExpanded: platformsExpanded) {
                            withAnimation(.easeInOut(duration: 0.2)) { platformsExpanded.toggle() }
                        }
                    }
                }
                if !groups.isEmpty {
                    Section {
                        if groupsExpanded {
                            ForEach(groups) { group in
                                Label(group.name, systemImage: "folder")
                                    .tag(SidebarItem.group(group))
                                    .contextMenu {
                                        Button {
                                            pickingGamesGroup = group
                                        } label: {
                                            Label(L10n.tr("group.pickGames", lang: language), systemImage: "checkmark.square")
                                        }
                                        Button {
                                            renameGroup = group
                                        } label: {
                                            Label(L10n.tr("group.rename", lang: language), systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            deleteGroup = group
                                        } label: {
                                            Label(L10n.tr("common.delete", lang: language), systemImage: "trash")
                                        }
                                    }
                                    .popover(item: popoverBinding(for: group), arrowEdge: .trailing) { _ in
                                        GroupGamePickerView(group: group)
                                    }
                            }
                        }
                    } header: {
                        SidebarSectionHeader(title: L10n.tr("game.groups", lang: language), isExpanded: groupsExpanded) {
                            withAnimation(.easeInOut(duration: 0.2)) { groupsExpanded.toggle() }
                        }
                    }
                }
                Section {
                    Label(L10n.tr("library.stats", lang: language), systemImage: "chart.bar.fill")
                        .tag(SidebarItem.stats)
                }
            }
            .listStyle(.sidebar)
            // 常驻滚动条槽位：折叠/展开会让内容在「溢出↔适配」间翻转，滚动条随之出现/消失，
            // 行宽突跳（~18pt）造成抖动、header 内容横移。恒定保留槽位后宽度稳定不再抖。
            .scrollIndicators(.visible)
            // 三参数全给:此前 min/ideal 两参形式在实测中被忽略,侧边栏被压到 ~127pt,
            // 平台名单行放不下(平台区混乱的另一半根源)。
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
            .safeAreaInset(edge: .bottom) {
                // 底部条加毛玻璃背景：内容滚动到下方时被半透明遮罩模糊，避免与头像/按钮重叠突兀。
                // 头像右侧显示用户名（同 Apple Music 左下角形态）；未设置用户名时只显示头像。
                HStack(spacing: 8) {
                    if !avatarFile.isEmpty, let avatar = UserCustomization.avatarImage() {
                        Image(appImage: avatar)
                            .resizable()
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                    }
                    let name = username.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        Text(verbatim: name)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                    }
                    // 头像/用户名靠左，「新建分组」推到右端。
                    Spacer(minLength: 0)
                    Button {
                        showingNewGroup = true
                    } label: {
                        Label(L10n.tr("group.newGroup", lang: language), systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial)
                .overlay(alignment: .top) { Divider() }
            }
        } detail: {
            switch selection {
            case .all, .none:
                LibraryView(groupFilter: nil)
            case .status(let status):
                LibraryView(groupFilter: nil, statusFilter: status)
            case .platform(let platform):
                LibraryView(groupFilter: nil, platform: platform)
            case .group(let group):
                LibraryView(groupFilter: group)
            case .stats:
                StatsView()
            }
        }
        // 最小窗口 980×600：对齐本机 Music 手动可拉到的最小尺寸(2026-08-26 用户实测;
        // HIG 对 macOS 无数值标准)。此前 1150 过宽——缩窗后详情区低于宽头部阈值即自动
        // 回落紧凑布局,无需再用窗口宽度兜底。侧边栏 min 220 在 980 下仍有 ~700 详情区。
        .frame(minWidth: 980, minHeight: 600)
        // 导入备份 / 从自动备份恢复会整体删除重建分组（设置页入口），侧边栏若正选中
        // 被删分组，继续渲染会访问已删 SwiftData 模型——与 iOS 侧 iOSLibraryTab 的
        // onChange 兜底同款机制（§24.2#1）。
        .onChange(of: groups) { _, newGroups in
            if case .group(let selected) = selection,
               !newGroups.contains(where: { $0.persistentModelID == selected.persistentModelID }) {
                selection = .all
            }
            if let picking = pickingGamesGroup,
               !newGroups.contains(where: { $0.persistentModelID == picking.persistentModelID }) {
                pickingGamesGroup = nil
            }
        }
        .sheet(isPresented: $showingNewGroup) {
            NewGroupSheet()
        }
        .sheet(item: $renameGroup) { group in
            RenameGroupSheet(group: group)
        }
        .confirmationDialog(
            L10n.tr("group.deleteTitle", lang: language),
            isPresented: Binding(get: { deleteGroup != nil }, set: { if !$0 { deleteGroup = nil } }),
            titleVisibility: .visible
        ) {
            Button(L10n.tr("common.delete", lang: language), role: .destructive) {
                if let group = deleteGroup {
                    if case .group(let selected) = selection, selected.persistentModelID == group.persistentModelID {
                        selection = .all
                    }
                    if pickingGamesGroup?.persistentModelID == group.persistentModelID {
                        pickingGamesGroup = nil
                    }
                    context.delete(group)
                }
                deleteGroup = nil
            }
            Button(L10n.tr("common.cancel", lang: language), role: .cancel) {
                deleteGroup = nil
            }
        } message: {
            if let group = deleteGroup {
                Text(verbatim: L10n.tr("group.deleteConfirm", [group.name], lang: language))
            }
        }
    }
}

/// 重命名分组的弹窗。空名或与其它分组重名不允许保存（排除自身）。
struct RenameGroupSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \GameGroup.name) private var groups: [GameGroup]
    let group: GameGroup
    @State private var name: String

    init(group: GameGroup) {
        self.group = group
        _name = State(initialValue: group.name)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }
    private var isDuplicate: Bool {
        !trimmed.isEmpty && groups.contains {
            $0.persistentModelID != group.persistentModelID && $0.name == trimmed
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            LText("group.rename")
                .font(.headline)
            BorderedTextField(text: $name, placeholder: L10n.tr("group.name", lang: language))
                .frame(width: 280)
            // 固定高度占位，避免错误出现时窗口跳动
            Text(verbatim: isDuplicate ? L10n.tr("group.nameExists", lang: language) : " ")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(1)
            HStack {
                Button(L10n.tr("common.cancel", lang: language)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.tr("common.save", lang: language)) {
                    group.name = trimmed
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmed.isEmpty || isDuplicate)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}
