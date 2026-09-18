import SwiftUI
import SwiftData

/// 右键菜单里打开的分组勾选面板：勾选即加入/移出分组，实时刷新。
///
/// 勾选**即时落库**（无「保存」），所以这里不提供「取消」—— 一个不撤销任何东西的取消按钮
/// 只会误导。单一出口「完成」承担 defaultAction，macOS 的 Esc 由 `onExitCommand` 接管
///（面板靠在库页上，整库替换随时可能在它开着的时候删掉 `game` / 某个分组）。
struct GroupPickerSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    @Environment(\.dismiss) private var dismiss
    let game: Game

    @Query(sort: \GameGroup.name) private var groups: [GameGroup]

    /// 还活着的分组。批量删除 / 整库替换之后 SwiftUI 会拿旧 `@Query` 数组再渲染一帧，
    /// 那时读已销毁分组就是 SwiftData fatal（判据见 `Game.isLive`）。
    private var liveGroups: [GameGroup] { groups.filter(\.isLive) }

    var body: some View {
        // 纵深守卫：game 可能已被「清空该账号导入数据」/整库替换删掉，
        // 而本 sheet 挂在库页的 `libraryReplacing` 门内、不随根视图状态重置一起关。
        if game.isLive {
            content
        } else {
            Color.clear.onAppear { dismiss() }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: game.displayName(for: language))
                .font(.headline)

            LText("game.groups")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if liveGroups.isEmpty {
                LText("library.noResult")
                    .foregroundStyle(.secondary)
            } else {
                // 分组多于一屏时可滚（此前固定宽 320 的 VStack 会把多出来的分组直接裁掉）。
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(liveGroups) { group in
                            Toggle(isOn: binding(for: group)) {
                                // 面板固定宽 320，长分组名原本直接截断；缩到 0.7 再截，
                                // 与 `RootView` 侧边栏平台名同一口径（全项目 11 处用 0.7）。
                                Text(verbatim: group.name)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)
            }

            HStack {
                Spacer()
                Button(L10n.tr("common.done", lang: language)) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
        #if os(macOS)
        // Esc 关面板：即时落库的面板没有 cancelAction 按钮，不接管的话 Esc 完全没反应。
        .onExitCommand { dismiss() }
        #endif
    }

    /// 某分组的勾选绑定：读写都带 `isLive` 守卫 —— 分组可能在面板开着时被整库替换删掉。
    private func binding(for group: GameGroup) -> Binding<Bool> {
        Binding(
            get: { game.groups.contains { $0.persistentModelID == group.persistentModelID } },
            set: { on in
                guard game.isLive, group.isLive else { return }
                if on {
                    if !game.groups.contains(where: { $0.persistentModelID == group.persistentModelID }) {
                        game.groups.append(group)
                    }
                } else {
                    game.groups.removeAll { $0.persistentModelID == group.persistentModelID }
                }
                try? context.save()
            }
        )
    }
}
