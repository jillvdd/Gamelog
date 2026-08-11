import SwiftUI
import SwiftData

/// 侧边栏条目：全部游戏 / 某个分组 / 统计。
enum SidebarItem: Hashable {
    case all
    case group(GameGroup)
    case stats
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    @Query(sort: \GameGroup.name) private var groups: [GameGroup]
    @AppStorage(UserCustomization.avatarFileKey) private var avatarFile = ""
    @State private var selection: SidebarItem? = .all
    @State private var showingNewGroup = false
    @State private var renameGroup: GameGroup?
    @State private var deleteGroup: GameGroup?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    Label(L10n.tr("library.all", lang: language), systemImage: "books.vertical")
                        .tag(SidebarItem.all)
                }
                if !groups.isEmpty {
                    Section(L10n.tr("game.groups", lang: language)) {
                        ForEach(groups) { group in
                            Label(group.name, systemImage: "folder")
                                .tag(SidebarItem.group(group))
                                .contextMenu {
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
                HStack(spacing: 8) {
                    if !avatarFile.isEmpty, let avatar = UserCustomization.avatarImage() {
                        Image(nsImage: avatar)
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
                    .padding()
                }
            }
        } detail: {
            switch selection {
            case .all, .none:
                LibraryView(groupFilter: nil)
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
            TextField(L10n.tr("group.name", lang: language), text: $name)
                .textFieldStyle(.roundedBorder)
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
