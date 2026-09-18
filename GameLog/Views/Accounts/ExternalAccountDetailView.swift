import SwiftUI
import SwiftData

/// 一个账号的详情：同步状态、标题语言、游玩记录、绑定/解绑、清空导入数据。
///
/// ⚠️ 本页同样**不展示任何凭证**。凭证坏了只用「需要重新登录」表达，
/// 修法是重新绑定一次（`AddExternalAccountView`），不是让用户去看 token。
struct ExternalAccountDetailView: View {
    let account: LinkedAccount

    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    @Environment(\.dismiss) private var dismiss

    /// 记录一律**全量取回再内存过滤**，不读 `account.records` 这个 inverse 数组 ——
    /// 与 `ImportCoordinator` 同一条纪律（inverse 在某些写入路径上要等 save 之后才一致）。
    /// 记录本身只有几十字节，全量取回的代价可以忽略。
    ///
    /// ⚠️ 取回后**必须先滤掉已销毁的**（`.isLive`）：`purge` 一次删几百条，而 `@Query`
    /// 结果数组会滞后一帧，读死记录的 `account` / `titleName` 就是 SwiftData fatal。
    /// 本页所有派生列表（`mineRecords` / `visibleRecords` / 记录面板的反查）都从
    /// `liveRecords` 出发，不要在别处直接消费 `allRecords`。
    @Query(sort: \ExternalGameRecord.titleName) private var allRecords: [ExternalGameRecord]
    @State private var filter: Filter = .unmatched
    /// 记录列表的搜索词。几百条记录一路拉到底不现实（用户 2026-09-17 的原话：
    /// 「我不想拉几百条」）。**纯内存筛选、不做防抖** —— 这一档最多几百条，筛选是一次
    /// `filter` 调用，比防抖引入的延迟还便宜。
    @State private var search = ""
    @State private var syncing = false
    @State private var summary: String?
    @State private var errorKey: String?
    @State private var showingUnbindConfirm = false
    @State private var showingPurgeConfirm = false
    @State private var purgeReceipt: String?
    @State private var showingRelink = false
    /// 要处置的那条记录，**存 ID 不存引用**（项目硬规矩：`@State` 永不持有 `@Model`）。
    /// 这张面板可能开在同步正删记录、或用户点「清空该账号导入数据」的同一刻 ——
    /// 存引用就会拿旧对象再渲染一帧，读 `titleName` 即 SwiftData fatal。
    @State private var recordToLinkID: PersistentIdentifier?
    /// 解绑后本页必须立刻停止访问 `account`（它已经被删掉了）。
    @State private var isUnbinding = false

    enum Filter: String, CaseIterable, Identifiable {
        case unmatched
        case ignored
        case all
        var id: String { rawValue }
    }

    var body: some View {
        Group {
            // 解绑是主动路径（`unbind()` 先置位再删）；`isLive` 是纵深守卫 ——
            // 账号也可能被别处删掉（整库替换 / 另一条路径的解绑），那时本页还挂在栈上。
            if isUnbinding || !account.isLive {
                Color.clear
            } else {
                content
            }
        }
    }

    private var content: some View {
        Form {
            statusSection
            languageSection
            recordsSection
            dangerSection
        }
        .formStyle(.grouped)
        .navigationTitle(account.displayName)
        .sheet(isPresented: $showingRelink) {
            AddExternalAccountView(initialProvider: account.provider) { _ in
                showingRelink = false
            }
        }
        .sheet(item: $recordToLinkID) { id in
            // 每帧反查：这条记录可能在面板开着时被同步删掉（`purge` / 上一轮同步的清理），
            // 查不到就画空 —— 传引用则会在那一帧读已销毁模型（见 `recordToLinkID`）。
            if let record = liveRecords.first(where: { $0.persistentModelID == id }) {
                ExternalRecordLinkSheet(record: record)
            } else {
                Color.clear
            }
        }
        .platformConfirmDialog(
            L10n.tr("account.detail.unbindTitle", lang: language),
            isPresented: $showingUnbindConfirm,
            message: L10n.tr("account.detail.unbindConfirm", lang: language),
            cancelTitle: L10n.tr("common.cancel", lang: language),
            actions: [
                ConfirmAction(title: L10n.tr("account.detail.unbind", lang: language),
                              isDestructive: true) { unbind() }
            ]
        )
        .platformConfirmDialog(
            L10n.tr("account.purge.confirmTitle", lang: language),
            isPresented: $showingPurgeConfirm,
            message: L10n.tr("account.purge.confirm", lang: language),
            cancelTitle: L10n.tr("common.cancel", lang: language),
            actions: [
                ConfirmAction(title: L10n.tr("account.purge.action", lang: language),
                              isDestructive: true) { purge() }
            ]
        )
    }

    // MARK: - 状态

    private var statusSection: some View {
        Section(L10n.tr("account.detail.status", lang: language)) {
            LabeledContent(L10n.tr("account.detail.platform", lang: language)) {
                Text(verbatim: account.provider.brandName)
            }
            LabeledContent(L10n.tr("account.detail.credential", lang: language)) {
                CredentialBadge(state: account.credentialState)
            }
            LabeledContent(L10n.tr("account.detail.lastSync", lang: language)) {
                Text(verbatim: lastSyncText)
            }
            if let error = account.lastSyncError {
                LText(error.labelKey)
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            Button { sync() } label: {
                Label(L10n.tr("account.detail.sync", lang: language),
                      systemImage: AccountUI.syncIcon)
            }
            .appStandardButton()
            .disabled(syncing)

            // 凭证失效/丢失时的唯一正解是重新绑一次 —— 那会刷新 Keychain 里的凭证。
            if account.credentialState == .expired || account.credentialState == .missing {
                Button { showingRelink = true } label: {
                    Label(L10n.tr("account.detail.relink", lang: language), systemImage: "person.badge.key")
                }
                .appStandardButton()
                LText("account.detail.relinkHint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if syncing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    LText("account.syncing")
                        .foregroundStyle(.secondary)
                }
            } else if let summary {
                Text(verbatim: summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let errorKey {
                LText(errorKey)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
    }

    private var lastSyncText: String {
        guard let last = account.lastSyncAt else {
            return L10n.tr("account.neverSynced", lang: language)
        }
        return L10n.tr("account.lastSyncAt",
                       [last.formatted(date: .abbreviated, time: .shortened), account.lastSyncRecordCount],
                       lang: language)
    }

    // MARK: - 标题与封面语言

    /// 两家 provider 都有这一段。机制相同（某个账号级选择 → 逐请求的语言头），
    /// 但两个头的**失败形状完全不同**，界面上必须分开说：
    /// - Nintendo `Gentry-Locale`：取值不被接受会 **400**，客户端退到 `en-GB` 并明确告知
    ///   （`localeFallbackFrom` → `localeFooter` 的第一句）。
    /// - PSN `Accept-Language`：标准头，取值不被接受只会被**忽略**，服务端也不回报实际用了哪个语言
    ///   —— 所以那条「已回退到 X」的提示**只在 Nintendo 显示**（PSN 显示不了，显示了就是编）。
    @ViewBuilder
    private var languageSection: some View {
        Section {
            Picker(L10n.tr("account.titleLocale.title", lang: language), selection: titleLocaleBinding) {
                ForEach(ExternalTitleLocale.allCases) { locale in
                    Text(verbatim: L10n.tr(locale.labelKey, lang: language))
                        .tag(locale)
                }
            }
            // 标题语言是**逐次请求**的，改了它只影响下一次同步 —— 所以必须给一个
            // 明确的「用新语言重来一遍」，而不是让用户以为改完就生效了。
            if localeNeedsFreshSync {
                Button { sync(refreshArtwork: true) } label: {
                    Label(L10n.tr("account.titleLocale.refresh", lang: language),
                          systemImage: AccountUI.syncIcon)
                }
                .appStandardButton()
                .disabled(syncing)
            }
        } header: {
            Text(verbatim: L10n.tr("account.titleLocale.header", lang: language))
        } footer: {
            localeFooter
        }
    }

    private var titleLocaleBinding: Binding<ExternalTitleLocale> {
        Binding(
            get: { account.titleLocale },
            set: { newValue in
                account.titleLocale = newValue
                try? context.save()
                // 换了语言，上一次的回退提示就过期了（它是针对上一次那个取值的）。
                account.localeFallbackFrom = nil
            }
        )
    }

    /// 「用户选的语言」与「上次同步实际用的语言」不一致 → 需要重新同步一次才会生效。
    /// 从没同步过时不显示（那时本来就要点「立即同步」）。
    private var localeNeedsFreshSync: Bool {
        guard account.lastSyncAt != nil else { return false }
        let requested = ExternalSyncDriver.requestedLocale(
            account: account, language: AppLanguage(localeCode: language))
        return requested != account.sourceLocale
    }

    @ViewBuilder
    private var localeFooter: some View {
        // 「被接口拒了、回退到 X」只对 Nintendo 说 —— PSN 的 `Accept-Language` 被忽略时
        // 服务端不回报，我们**检测不到**回退。这里若跟着显示就是编一个不存在的事实。
        if let requested = account.localeFallbackFrom, account.provider == .nintendo {
            // 语言被接口拒了就说清楚，不再静默降级 —— 用户选了繁體中文却拿回英文标题，
            // 看到的必须是「zh-TW 不被接受，本次回退到 en-GB」，而不是「功能坏了」。
            Text(verbatim: L10n.tr("account.titleLocale.fallback",
                                   [requested, account.sourceLocale], lang: language))
        } else if account.lastSyncAt != nil, !mineRecords.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                LText("account.titleLocale.hint")
                // 「只有一部分拿到中文」是**来源侧的事实**，不是我们的 bug，也不是用户选错了。
                // 不给数字的话，用户只能对着库里的混合标题自己猜（2026-09-16 的反馈就是这么来的）。
                // 这个数字**不落库**：直接从记录里的 `titleName` 现算，所以它永远与库一致，
                // 也不会因为「上次同步时报的那个数」过期而说谎。
                Text(verbatim: L10n.tr("account.titleLocale.coverage",
                                       [localizedTitleCount, mineRecords.count,
                                        account.sourceLocale.isEmpty ? "—" : account.sourceLocale],
                                       lang: language))
                    .foregroundStyle(.secondary)
            }
        } else {
            LText("account.titleLocale.hint")
        }
    }

    /// 来源侧返回的标题里，真正落在**这次实际使用的语言**上的条数。
    ///
    /// 判据是标题自己的文字种类（`TitleScript`），不是「我们请求了什么」—— 服务端在没有
    /// 目标语言的名称时会逐条回落到别的语言（实测 151 条里只有 62 条真的是繁體中文），
    /// 而请求本身是成功的，响应里也没有任何字段说明回落发生了。
    private var localizedTitleCount: Int {
        let locale = account.sourceLocale
        guard !locale.isEmpty else { return 0 }
        return mineRecords.filter {
            TitleScript.of($0.titleName).matches(localeCode: locale)
        }.count
    }

    // MARK: - 记录

    private var recordsSection: some View {
        Section {
            Picker(L10n.tr("account.detail.filter", lang: language), selection: $filter) {
                LText("account.detail.filter.unmatched", args: [unmatchedRecords.count])
                    .tag(Filter.unmatched)
                LText("account.detail.filter.ignored", args: [ignoredRecords.count])
                    .tag(Filter.ignored)
                LText("account.detail.filter.all", args: [mineRecords.count])
                    .tag(Filter.all)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // 搜索框放在分段控件**之下**：先选档再筛词，与用户的动作顺序一致。
            // 显示条件是「这一档有记录」——一条都没有时摆一个注定搜不到东西的框是噪音，
            // 而「搜了但没搜到」是另一回事（见下面的空态），那时这一档仍有记录、框还在。
            if !visibleRecords.isEmpty {
                BorderedTextField(text: $search,
                                  placeholder: L10n.tr("account.detail.search", lang: language))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }

            if visibleRecords.isEmpty {
                LText("account.detail.noRecords")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if searchFilteredRecords.isEmpty {
                // 与「这里还没有记录」分开说：混用会让用户以为记录丢了，
                // 而其实只是搜索词没命中（清掉词就回来了）。
                LText("account.detail.noSearchMatch")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(searchFilteredRecords) { record in
                    Button { recordToLinkID = record.persistentModelID } label: {
                        ExternalRecordRow(record: record)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text(verbatim: L10n.tr("account.detail.records", lang: language))
        } footer: {
            LText("account.detail.recordsHint")
        }
    }

    /// 还活着的记录（见 `allRecords` 上那段）。本页的**唯一入口**。
    private var liveRecords: [ExternalGameRecord] { allRecords.filter(\.isLive) }

    private var mineRecords: [ExternalGameRecord] {
        liveRecords.filter { $0.account?.localId == account.localId }
    }

    /// 待关联 = 还没挂到任何游戏上、也没被跳过。被跳过（用户点的「忽略」，或规则判定 ——
    /// 见 `isShownAsIgnored`）的单独一档，否则它们会永远混在「待关联」里、
    /// 看起来像是没人处理（旧版就是这样）。
    private var unmatchedRecords: [ExternalGameRecord] {
        mineRecords.filter { $0.game == nil && !$0.isShownAsIgnored }
    }

    /// 已忽略（无论有没有关联）：这一档存在的唯一目的就是**让忽略可撤销**，而 2026-09-18 起
    /// 它同时收**规则判掉**的记录（体验版那一档本来就在里面 —— 用户要求「所有跳过的都算已忽略，
    /// 这样如果出错还能手动绑定」）。口径的唯一归属是 `ExternalGameRecord.isShownAsIgnored`，
    /// 那些不对称之处（规则跳过的一旦绑上就不再算）在那里写明了。
    private var ignoredRecords: [ExternalGameRecord] {
        mineRecords.filter { $0.isShownAsIgnored }
    }

    /// 最近游玩优先（没有时间的排最后），同序按标题名字定序 —— 结果稳定，便于定位。
    private var visibleRecords: [ExternalGameRecord] {
        let base: [ExternalGameRecord]
        switch filter {
        case .unmatched: base = unmatchedRecords
        case .ignored: base = ignoredRecords
        case .all: base = mineRecords
        }
        return base.sorted { lhs, rhs in
            let l = lhs.lastPlayedAt ?? .distantPast
            let r = rhs.lastPlayedAt ?? .distantPast
            if l != r { return l > r }
            return lhs.titleName < rhs.titleName
        }
    }

    /// 在当前分段之内再筛一层搜索词 —— **先 filter 再 search**：三个 base 数组不变，
    /// 分段控件上的计数（「待关联 234」）因此始终是这一档的真实条数，不会被搜索词改小。
    ///
    /// 匹配口径走 `GameLinker.matches`（与关联面板 / 合并面板**共用一处**）。除记录自己的
    /// 标题 / 平台 / 编号，还收**已关联条目的名字**：用户会按「我库里叫 Yakuza 2」去找一条
    /// titleName 是 `龍が如く２` 的记录 —— 那正是这条记录已经被绑上的证据。
    ///
    /// ⚠️ 那份「平台 / 编号」清单走 `record.searchExtras`（**在模型上**）而不是在这里现拼：
    /// 现拼过一次，就漏了 Xbox 的平台列表（对等审计 GAP 1）。视图里写的东西 DataSmoke 看不见。
    private var searchFilteredRecords: [ExternalGameRecord] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return visibleRecords }
        return visibleRecords.filter { record in
            var extras = record.searchExtras
            // ⚠️ 已关联条目的名字要**先判 `isLive` 再读**：批量删除 / 整库替换之后
            // `record.game` 可能已经是一个销毁的模型，读它的 `allNames` 是 SwiftData fatal
            //（见 `Game.isLive`）。`allNames` 已含 `primaryName`，不必再单独塞一个。
            if let game = record.game, game.isLive {
                extras.append(contentsOf: game.allNames)
            }
            return GameLinker.matches(query: query, title: record.titleName, extras: extras)
        }
    }

    // MARK: - 危险区

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) { showingPurgeConfirm = true } label: {
                Text(verbatim: L10n.tr("account.purge.action", lang: language))
            }
            .disabled(syncing)
            Button(role: .destructive) { showingUnbindConfirm = true } label: {
                Text(verbatim: L10n.tr("account.detail.unbind", lang: language))
            }
            .disabled(syncing)
            if let purgeReceipt {
                Text(verbatim: purgeReceipt)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button { sync() } label: {
                    Label(L10n.tr("account.detail.sync", lang: language),
                          systemImage: AccountUI.syncIcon)
                }
                .appStandardButton()
                .disabled(syncing)
            }
        } footer: {
            LText("account.detail.unbindFooter")
        }
    }

    // MARK: - 动作

    private func sync(refreshArtwork: Bool = false) {
        guard !syncing else { return }
        syncing = true
        summary = nil
        errorKey = nil
        // 一并清空清空回执：否则一轮同步跑完，屏幕上会同时挂着「已清空 N 条」与
        // 「本次同步新增 N 条」两条互相矛盾的当前结果（清空回执属于上一次操作）。
        purgeReceipt = nil
        Task { @MainActor in
            let result = await ExternalSyncDriver.sync(account, container: context.container,
                                                       language: AppLanguage(localeCode: language),
                                                       refreshArtwork: refreshArtwork)
            syncing = false
            if let error = result.error {
                errorKey = error.messageKey
            } else if result.skippedBecauseInFlight {
                // 同账号已有一轮导入在跑（闸门挡住），不是失败。
                errorKey = "account.syncBusy"
            } else {
                var text = L10n.tr("account.detail.syncSummary",
                                   [result.summary.createdRecords, result.summary.updatedRecords,
                                    result.summary.autoLinked, result.summary.createdGames],
                                   lang: language)
                if result.summary.artworkRefreshed > 0 {
                    text += "\n" + L10n.tr("account.detail.artworkRefreshed",
                                           [result.summary.artworkRefreshed], lang: language)
                }
                // 奖杯/PS3·Vita 那一路没取到要如实说。整次同步是成功的（游玩记录都在），
                // 但不说的话，用户看到的就只是「PS3 游戏还是没进来」—— 看起来像功能没做。
                if result.trophyUnavailable {
                    text += "\n" + L10n.tr("account.detail.trophyUnavailable", lang: language)
                }
                // 游玩时长同理（只有 Xbox 会为非：时长在另一个端点上，只能批量 POST，
                // 免费档有配额）。不说的话用户看到满屏「—」，会以为这家来源根本不提供时长。
                if result.playtimeUnavailable {
                    text += "\n" + L10n.tr("account.detail.playtimeUnavailable", lang: language)
                }
                // 同步收尾顺手清掉的空壳条目。文案按**全库口径**写（见 `prunedGames` 的说明），
                // 不做成「该账号清了 N 条」——那样说会漏掉另一半真相。仅在真删到时出现。
                if result.prunedGames > 0 {
                    text += "\n" + L10n.tr("account.detail.pruned", [result.prunedGames], lang: language)
                }
                // 收走的「已经被游玩记录覆盖」的奖杯记录（本账号口径）。**必须说出来** ——
                // 这个动作会删掉用户手工绑过的记录（见 `removeSupersededRecords`），
                // 不声不响地删是这里最不该有的行为。
                if result.supersededRecords > 0 {
                    text += "\n" + L10n.tr("account.detail.superseded",
                                           [result.supersededRecords], lang: language)
                }
                summary = text
            }
        }
    }

    /// 清空这个账号导入进来的东西（记录 + 同步替我建、我没碰过的库条目）。
    ///
    /// beta 3.1 的幂等 bug 在真账号上留下了成对的重复数据，这是用户选定的修复路径：
    /// **先清空再重新同步**，而不是让程序去猜哪一份是脏的。有用户数据的条目一律保留
    /// （见 `ExternalAccountBinder.purgeImportedData`），回执里会说保留了几条。
    private func purge() {
        errorKey = nil
        do {
            let report = try ExternalAccountBinder.purgeImportedData(account, in: context)
            // 收尾三件事，一件都不能少（见 `purgeImportedData` 的说明）：
            // 清解码缓存；广播整库替换，让导航栈/弹窗里那些指向已删条目的引用立刻作废
            // （不广播的话，关掉设置回到库页就是一次 SwiftData fatal）；
            // 库页的卡片自带 `isLive` 守卫，兜住 SwiftUI 已排队的那一帧旧数组渲染
            //（判据是 `isLive` 不是 `isDeleted` —— 后者在 `save()` 之后会翻回 false）。
            ImageDecodeCache.bump()
            NotificationCenter.default.post(name: UserCustomization.libraryReplacedNotification,
                                            object: nil)
            purgeReceipt = L10n.tr("account.purge.done",
                                   [report.deletedRecords, report.deletedGames, report.keptGames],
                                   lang: language)
            summary = nil
        } catch {
            errorKey = "account.syncError.unknown"
        }
    }

    /// 解绑。**顺序与状态两条都不能省**（见 `ExternalAccountBinder.unbind`）：
    /// 先把本页切到「不再碰 account」的空态，再删（凭证 → 账号行），最后弹回列表。
    private func unbind() {
        isUnbinding = true
        do {
            try ExternalAccountBinder.unbind(account, in: context)
        } catch {
            errorKey = "account.syncError.unknown"
            isUnbinding = false
            return
        }
        ImageDecodeCache.bump()
        dismiss()
    }
}
