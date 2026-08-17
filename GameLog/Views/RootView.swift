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

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    @Query(sort: \GameGroup.name) private var groups: [GameGroup]
    @Query(sort: \Game.createdAt) private var games: [Game]
    @AppStorage(UserCustomization.avatarFileKey) private var avatarFile = ""
    @State private var selection: SidebarItem? = .all
    @State private var showingNewGroup = false
    @State private var renameGroup: GameGroup?
    @State private var deleteGroup: GameGroup?
    @State private var pickingGamesGroup: GameGroup?

    /// 平台 → 去重游戏数（含游戏级平台，未通关游戏计入；一款游戏在多个平台各计一次）。
    private var platformCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for game in games {
            for platform in game.platformList {
                counts[platform, default: 0] += 1
            }
        }
        return counts
    }

    /// 库里出现过的平台，按预设世代倒序 + 自定义按字母排最后。
    private var platformsInUse: [String] {
        Presets.ordered(Array(platformCounts.keys))
    }

    /// 分组行「选择游戏」的 popover 绑定：只在该行分组被选中时弹出，锚定到该行。
    private func popoverBinding(for group: GameGroup) -> Binding<GameGroup?> {
        Binding(
            get: { pickingGamesGroup?.persistentModelID == group.persistentModelID ? group : nil },
            set: { if $0 == nil { pickingGamesGroup = nil } }
        )
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    Label(L10n.tr("library.all", lang: language), systemImage: "books.vertical")
                        .tag(SidebarItem.all)
                }
                Section(L10n.tr("game.status", lang: language)) {
                    ForEach(GameStatus.allCases) { status in
                        Label(L10n.tr(status.labelKey, lang: language), systemImage: status.sidebarIcon)
                            .tag(SidebarItem.status(status))
                    }
                }
                if !platformsInUse.isEmpty {
                    Section(L10n.tr("library.platforms", lang: language)) {
                        ForEach(platformsInUse, id: \.self) { platform in
                            // 图标 + 名字：一行放得下就并排；侧边栏窄时图标换到名字上方，名字不被截断。
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 6) {
                                    PlatformIcon(platform: platform, size: 16)
                                    Text(verbatim: Presets.display(platform, category: .platform, language: language))
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    PlatformIcon(platform: platform, size: 16)
                                    Text(verbatim: Presets.display(platform, category: .platform, language: language))
                                        .lineLimit(2)
                                }
                            }
                            .badge(platformCounts[platform] ?? 0)
                            .tag(SidebarItem.platform(platform))
                        }
                    }
                }
                if !groups.isEmpty {
                    Section(L10n.tr("game.groups", lang: language)) {
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
                }
                Section {
                    Label(L10n.tr("library.stats", lang: language), systemImage: "chart.bar.fill")
                        .tag(SidebarItem.stats)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
            .safeAreaInset(edge: .bottom) {
                // 底部条加毛玻璃背景：内容滚动到下方时被半透明遮罩模糊，避免与头像/按钮重叠突兀。
                HStack(spacing: 8) {
                    if !avatarFile.isEmpty, let avatar = UserCustomization.avatarImage() {
                        Image(appImage: avatar)
                            .resizable()
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                    }
                    Button {
                        showingNewGroup = true
                    } label: {
                        Label(L10n.tr("group.newGroup", lang: language), systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
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
        .frame(minWidth: 900, minHeight: 600)
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
