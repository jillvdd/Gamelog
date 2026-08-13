import SwiftUI
import SwiftData

/// 右键菜单里打开的分组勾选面板：勾选即加入/移出分组，实时刷新。
struct GroupPickerSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    @Environment(\.dismiss) private var dismiss
    let game: Game

    @Query(sort: \GameGroup.name) private var groups: [GameGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: game.displayName(for: language))
                .font(.headline)

            LText("game.groups")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if groups.isEmpty {
                LText("library.noResult")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(groups) { group in
                        Toggle(isOn: Binding(
                            get: { game.groups.contains { $0.persistentModelID == group.persistentModelID } },
                            set: { on in
                                if on {
                                    if !game.groups.contains(where: { $0.persistentModelID == group.persistentModelID }) {
                                        game.groups.append(group)
                                    }
                                } else {
                                    game.groups.removeAll { $0.persistentModelID == group.persistentModelID }
                                }
                                try? context.save()
                            }
                        )) {
                            Text(verbatim: group.name)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button(L10n.tr("common.done", lang: language)) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
