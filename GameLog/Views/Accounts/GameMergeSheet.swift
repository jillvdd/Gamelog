import SwiftUI
import SwiftData

/// 把两个游戏条目合并成一个：`source` 整个并进 `target`，然后删掉 `source`。
///
/// 出现的场景几乎全是导入带来的：用户库里早有「艾尔登法环」，同步 PSN 时又自动建了一个
/// 「ELDEN RING」——两条各有一半信息，用户想要的是「合成一条」。
///
/// 取舍只有一条：**target 优先，source 补空**（详见 `GameMerger.merge`）。
/// 界面上把这条讲清楚，是因为它决定了用户该选哪一边 —— 用户对两条的期待往往不一样。
struct GameMergeSheet: View {
    /// 要并入的条目的 ID，**不是引用**。
    ///
    /// 项目硬规矩（HANDOVER §「@State 永不持有 @Model」）：这张 sheet 可能开在
    /// 「清空该账号导入数据」正删游戏的同一刻，而 SwiftUI 会让它拿旧引用再渲染一帧 ——
    /// 读一个已销毁模型的 `displayName` 直接 SwiftData fatal。存 ID、每帧从 `@Query`
    /// 反查（照 `HomeCarousel.spotlightID` 的范式），查不到就当它不存在。
    let sourceID: PersistentIdentifier

    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Game.createdAt) private var games: [Game]

    @State private var search = ""
    /// 保留哪一个（同样只存 ID，理由见上）。nil = 用户还没选。
    @State private var targetID: PersistentIdentifier?
    @State private var isMerging = false
    @State private var showingConfirm = false

    var body: some View {
        Group {
            if let source = resolvedSource {
                if isMerging {
                    Color.clear
                } else {
                    content(source)
                }
            } else {
                // source 已经没了（清空导入数据 / 整库替换）：这张 sheet 没有意义了。
                // 不能在 body 里直接 dismiss（改状态会重入），交给 onAppear。
                Color.clear
                    .onAppear { dismiss() }
            }
        }
    }

    // MARK: - 解析

    /// 只认还活着的条目：`@Query` 在批量删除后可能仍含已销毁模型，
    /// 读它们的属性就是那条 fatal（见 `Game.isLive`）。
    private var liveGames: [Game] { games.filter(\.isLive) }

    private var resolvedSource: Game? {
        liveGames.first { $0.persistentModelID == sourceID }
    }

    private var target: Game? {
        guard let targetID else { return nil }
        return liveGames.first { $0.persistentModelID == targetID }
    }

    private func content(_ source: Game) -> some View {
        baseForm(source)
            // 二次确认：`GameMerger.merge` 结尾是 `context.delete(source)`，是本功能唯一的
            // 不可逆删除 —— 与「删除游戏」「清空账号数据」同一档，不能比它们少一道确认。
            .platformConfirmDialog(
                L10n.tr("account.merge.title", lang: language),
                isPresented: $showingConfirm,
                message: L10n.tr("account.merge.confirmHint", lang: language),
                cancelTitle: L10n.tr("common.cancel", lang: language),
                actions: [
                    ConfirmAction(
                        title: L10n.tr("account.merge.confirm", lang: language),
                        isDestructive: true
                    ) { merge(source) }
                ]
            )
    }

    /// macOS 上 sheet 自带窗口工具栏，再包 `NavigationStack` 会多出一条空导航栏
    ///（与 `GameEditView` / `BannerSearchSheet` / 库页各 sheet 同一口径）。
    /// 单独一个 `@ViewBuilder` 而不是把 `#if` 写在 `content` 里：`#if` 块后面接不了
    /// 尾随修饰符（`.platformConfirmDialog` 会挂不上去）。
    @ViewBuilder
    private func baseForm(_ source: Game) -> some View {
        #if os(macOS)
        // 表单型 sheet 用 min 尺寸：窗口可拉大看长列表，而固定 width/height 会把它锁死。
        form(source)
            .frame(minWidth: 520, minHeight: 600)
        #else
        NavigationStack { form(source) }
        #endif
    }

    private func form(_ source: Game) -> some View {
        Form {
            Section {
                LabeledContent(L10n.tr("account.merge.source", lang: language)) {
                    Text(verbatim: source.displayName(for: language))
                }
                if let target {
                    LabeledContent(L10n.tr("account.merge.target", lang: language)) {
                        Text(verbatim: target.displayName(for: language))
                    }
                }
            } footer: {
                LText("account.merge.explain")
            }

            Section(L10n.tr("account.merge.choose", lang: language)) {
                TextField(L10n.tr("account.merge.search", lang: language), text: $search)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                if candidates(source).isEmpty {
                    LText("account.link.noMatch")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(candidates(source).prefix(50)) { game in
                        Button { targetID = game.persistentModelID } label: {
                            HStack {
                                GameChoiceRow(game: game, trailing: counts(of: game))
                                Spacer(minLength: 8)
                                if targetID == game.persistentModelID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section {
                Button(role: .destructive) { showingConfirm = true } label: {
                    Text(verbatim: L10n.tr("account.merge.confirm", lang: language))
                }
                .appStandardButton()
                .disabled(target == nil)
            } footer: {
                LText("account.merge.confirmHint")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(L10n.tr("account.merge.title", lang: language))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.tr("common.cancel", lang: language)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    /// 候选行右侧的补充信息：这条游戏各有多少数据会跟着合并走。
    private func counts(of game: Game) -> String {
        L10n.tr("account.merge.counts",
                [game.completions.count, game.externalRecords.count],
                lang: language)
    }

    /// 候选 = 除自己以外的全部游戏，按搜索词过滤。
    /// 匹配口径走 `GameLinker.matches`（与关联面板、账号记录列表**共用一处**）。
    private func candidates(_ source: Game) -> [Game] {
        let others = liveGames.filter { $0.persistentModelID != source.persistentModelID }
        return others.filter { GameLinker.matches(query: search, names: $0.allNames) }
    }

    /// 合并。`merge` 会**删掉 source**，所以先把本页切到不碰它的空态，避免 SwiftUI
    /// 在同一个更新周期里再去读一个已删除对象。
    private func merge(_ source: Game) {
        guard let target else { return }
        isMerging = true
        GameMerger.merge(source, into: target, in: context)
        try? context.save()
        ImageDecodeCache.bump()
        dismiss()
    }
}
