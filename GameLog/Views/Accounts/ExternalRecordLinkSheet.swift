import SwiftUI
import SwiftData

/// 一条外部记录的处置面板：关联 / 解除关联 / 合并 / 忽略。
///
/// **两个动作、两个状态位**（2026-09-16 重做，见 HANDOVER §54）：
/// - **关联**（`record.game`）—— 「这条记录算到哪个游戏头上」。解除关联是**可逆**的：
///   下次同步若又匹配上，会重新自动关联 —— 那正是「解除」的字面含义。
/// - **忽略**（`record.isIgnored`）—— 「以后别再自动导入这条」。独立、可撤销、可筛选。
///   与关联**正交**：忽略一条已关联的记录不会把它从库里摘掉，只是解除关联之后不再自动接上。
///
/// 旧版把两者压进同一个判据（`hasBeenLinked && game == nil` 当墓碑），于是「解除关联」与
/// 「删掉了那个游戏」在库里长得一模一样，而前者本该可逆；「已忽略」一旦被关联就再也撤不掉。
///
/// 手动绑定与自动匹配是两套纪律，这里走的是**手动**那套：用户点了就算数，不做二次猜测，
/// 绑定结果也不会被下一次同步改写。所以候选列表**可以用弱键**（模糊匹配）——
/// 它只产出一个列表，挑错也不改任何数据。
struct ExternalRecordLinkSheet: View {
    let record: ExternalGameRecord

    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Game.createdAt) private var games: [Game]

    /// 还活着的游戏。批量删除 / 整库替换之后 `@Query` 结果数组会滞后一帧，而候选列表要读
    /// `game.allNames` / `displayName` —— 读已销毁模型就是 SwiftData fatal（见 `Game.isLive`）。
    private var liveGames: [Game] { games.filter(\.isLive) }

    @State private var search = ""
    @State private var showingMerge = false

    var body: some View {
        // 纵深守卫：这条记录可能已被同步清理 / 「清空该账号导入数据」删掉，
        // 而本 sheet 的持有者在反查失败时才会换成空视图 —— 这里再挡一道，
        // 免得 header 段一读 `record.titleName` 就是 SwiftData fatal。
        if record.isLive {
            content
        } else {
            Color.clear.onAppear { dismiss() }
        }
    }

    private var content: some View {
        // macOS 上 sheet 自带窗口工具栏，再包 `NavigationStack` 会多出一条空导航栏
        //（与 `GameEditView` / `BannerSearchSheet` / 库页各 sheet 同一口径）。
        #if os(macOS)
        form
            // 表单型 sheet 用 min 尺寸：窗口可拉大看长候选列表，而固定 width/height 会把它锁死。
            .frame(minWidth: 520, minHeight: 600)
        #else
        NavigationStack { form }
        #endif
    }

    private var form: some View {
        Form {
            headerSection
            if record.game != nil { currentLinkSection }
            suggestionsSection
            browseSection
            ignoreSection
        }
        .formStyle(.grouped)
        .navigationTitle(L10n.tr("account.link.title", lang: language))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.tr("common.cancel", lang: language)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .sheet(isPresented: $showingMerge) {
            // 只传 ID：合并面板里的 source 可能在同步/清空时被删（见 GameMergeSheet 的说明）。
            if let source = record.game {
                GameMergeSheet(sourceID: source.persistentModelID)
            }
        }
    }

    // MARK: - 分区

    /// 记录的全部来源事实都摆在这里 —— 列表行上省略掉的「首次游玩 / 时长」来这里看。
    private var headerSection: some View {
        Section {
            LabeledContent(L10n.tr("account.link.record", lang: language)) {
                Text(verbatim: record.titleName)
            }
            LabeledContent(L10n.tr("account.link.platform", lang: language)) {
                Text(verbatim: Presets.display(record.platform, category: .platform, language: language))
            }
            if let first = record.firstPlayedAt {
                LabeledContent(L10n.tr("account.link.firstPlayed", lang: language)) {
                    Text(verbatim: first.formatted(date: .abbreviated, time: .omitted))
                }
            }
            if let last = record.lastPlayedAt {
                LabeledContent(L10n.tr("account.link.lastPlayed", lang: language)) {
                    Text(verbatim: last.formatted(date: .abbreviated, time: .omitted))
                }
            }
            if let hours = record.displayHours {
                LabeledContent(L10n.tr("account.link.hours", lang: language)) {
                    Text(verbatim: L10n.tr("account.detail.hours", [hours], lang: language))
                }
            }
            if record.versionType == .demo || record.versionType == .trial {
                LabeledContent(L10n.tr("account.link.version", lang: language)) {
                    Text(verbatim: L10n.tr(record.versionType.labelKey, lang: language))
                }
            }
        }
    }

    private var currentLinkSection: some View {
        Section {
            LabeledContent(L10n.tr("account.link.current", lang: language)) {
                Text(verbatim: record.game?.displayName(for: language) ?? "")
            }
            Button { unbind() } label: {
                // 不是 `link.badge.plus`（那是「建立关联」的语义，写在「解除关联」上是反的）。
                // SF Symbols 没有 `link.badge.minus`，用 `minus.circle` 表意。
                Label(L10n.tr("account.link.unbind", lang: language), systemImage: "minus.circle")
            }
            .appStandardButton()
            Button { showingMerge = true } label: {
                Label(L10n.tr("account.link.merge", lang: language), systemImage: "arrow.triangle.merge")
            }
            .appStandardButton()
        } footer: {
            LText("account.link.unbindHint")
        }
    }

    @ViewBuilder
    private var suggestionsSection: some View {
        if !suggestions.isEmpty {
            // 带 footer 的分区只能用 header 闭包写标题：SwiftUI 的 `Section(_ title:, content:, footer:)`
            // 只接受 LocalizedStringKey，我们的标题是运行时查出来的 String。
            // 与 SettingsView / GameEditView 里同一种写法。
            Section {
                ForEach(suggestions) { game in
                    Button { bind(to: game) } label: {
                        GameChoiceRow(game: game)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text(verbatim: L10n.tr("account.link.suggestions", lang: language))
            } footer: {
                LText("account.link.suggestionsHint")
            }
        }
    }

    private var browseSection: some View {
        Section(L10n.tr("account.link.allGames", lang: language)) {
            TextField(L10n.tr("account.link.search", lang: language), text: $search)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            if searchResults.isEmpty {
                LText("account.link.noMatch")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(searchResults.prefix(50)) { game in
                    Button { bind(to: game) } label: {
                        GameChoiceRow(game: game)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// 忽略 / 恢复。**不再以 `record.game == nil` 为显示条件** —— 旧版那样写，
    /// 一条已忽略的记录只要被关联上就再也撤销不了（按钮整段消失）。
    ///
    /// 动作后**不关面板**：按钮当场翻转成「恢复导入」，用户看得见状态确实变了、也能立刻撤回。
    private var ignoreSection: some View {
        Section {
            if record.isIgnored {
                Button { setIgnored(false) } label: {
                    Label(L10n.tr("account.link.unignore", lang: language),
                          systemImage: "arrow.uturn.backward")
                }
                .appStandardButton()
            } else {
                Button { setIgnored(true) } label: {
                    Label(L10n.tr("account.link.ignore", lang: language),
                          systemImage: "hand.raised")
                }
                .appStandardButton()
            }
        } header: {
            Text(verbatim: L10n.tr("account.link.autoImport", lang: language))
        } footer: {
            LText("account.link.ignoreHint")
        }
    }

    // MARK: - 数据

    /// 建议候选：弱键模糊匹配，用户看着挑。
    ///
    /// 已关联的那个要剔掉 —— 它是最容易命中「完全同名」的一条，可点它等于什么都没做
    /// （只把面板关掉），而真正该看的是别的候选。当前关联已经单列在上面那一段了。
    private var suggestions: [Game] {
        let linked = record.game?.persistentModelID
        return GameMerger.suggestions(for: record, among: liveGames)
            .filter { $0.persistentModelID != linked }
    }

    /// 全部候选按搜索词过滤。匹配口径走 `GameLinker.matches`（**三个列表共用一处**，
    /// 见那里的说明）——空查询返回全部。
    private var searchResults: [Game] {
        liveGames.filter { GameLinker.matches(query: search, names: $0.allNames) }
    }

    // MARK: - 动作

    /// 绑定 + 存盘。`ImageDecodeCache.bump()` 是给封面用的：绑上之后详情页可能立刻要显示这张图。
    ///
    /// 绑定之后**顺带替导入收尾**：`GameMerger.bind` 只改 `record.game`，从不回头看旧条目，
    /// 旧条目若是导入自动建的就永远留成一个空壳（用户报的「合并了但库里还是两条」）。
    /// 清掉了就按整库替换那一套收尾 —— 用户可能正停在那个空壳的详情页上。
    private func bind(to game: Game) {
        let previous = record.game
        GameMerger.bind(record, to: game)
        try? context.save()
        pruneIfOrphaned(previous)
        ImageDecodeCache.bump()
        dismiss()
    }

    private func unbind() {
        let previous = record.game
        GameMerger.unbind(record)
        try? context.save()
        // 解绑同样会让旧条目失去最后一个指向它的记录。**不置 `isIgnored`**（那是另一个动作），
        // 所以下次同步若又匹配上，会被重新自动关联 —— 但那时自动匹配会**复用它**吗？
        // 不会：条目已经删了，同步会重新建一个。删掉一个「自动建、0 记录、0 用户数据」的
        // 空壳不损失任何东西，这正是本动作的边界。**用户自己建的条目一律不删**（硬门）。
        pruneIfOrphaned(previous)
        ImageDecodeCache.bump()
        dismiss()
    }

    /// 旧条目若已成空壳就删掉，并在真删到时广播整库替换。
    ///
    /// 收尾三件事照抄 `ExternalAccountDetailView.purge()`：清解码缓存 + 广播。这与「用户
    /// 正在看那个条目」的概率无关 —— 广播的代价是一次状态重置，不广播的代价是一次
    /// SwiftData fatal（§54.14）。
    private func pruneIfOrphaned(_ previous: Game?) {
        guard let previous else { return }
        guard (try? ExternalAccountBinder.pruneIfOrphaned(previous, in: context)) == true else { return }
        NotificationCenter.default.post(name: UserCustomization.libraryReplacedNotification,
                                        object: nil)
    }

    /// 忽略 / 恢复。**不 dismiss**：面板留着，用户能立刻看到按钮翻转并再次点击撤回。
    private func setIgnored(_ ignored: Bool) {
        GameMerger.setIgnored(ignored, on: record)
        try? context.save()
    }
}
