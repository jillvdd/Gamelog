import SwiftUI
import SwiftData

/// 「游戏账号」列表：已绑定的 Nintendo / PlayStation 账号。
///
/// ⚠️ 本文件（及它的全部子页）**绝不展示凭证** —— session token / NPSSO / refresh token
/// 一律不出现在 UI 上。接口地址同样不出现在 UI 上，唯一的例外是 PlayStation 那条提示里
/// 用户**必须亲自去打开**的 Sony 页面地址：没有它这一步就走不下去。
/// 凭证只该在 Keychain 与网络层之间流动；用户需要知道的只是「这个账号还能不能用」，
/// 那是 `AccountCredentialState` 的职责。
///
/// 版式与设置页同源（`Form` + `.formStyle(.grouped)`）：这一批界面本质就是设置页的子页，
/// 用同一套版式才能和「设置 → 数据备份」那些页长得一样。
struct ExternalAccountsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \LinkedAccount.linkedAt) private var accounts: [LinkedAccount]

    @State private var showingAdd = false
    @State private var syncing: Set<UUID> = []
    @State private var banner: String?

    /// 还活着的账号。解绑会 `context.delete(account)` + `save()`，而 `@Query` 结果数组
    /// 会滞后一帧 —— 读死账号的 `displayName` / `localId` 就是 SwiftData fatal
    ///（判据见 `Game.isLive`）。本页所有列表与反查都从这一个入口取。
    private var liveAccounts: [LinkedAccount] { accounts.filter(\.isLive) }

    var body: some View {
        // ⚠️ 与同批其余账号 sheet 不同，这里**必须**保留 `NavigationStack`（macOS 也是）：
        // 账号行是 `NavigationLink(value:)` + `navigationDestination` 的 push，没有栈就点不进详情页。
        // 其余 sheet 是纯表单、栈只带来一条空导航栏，才改成 macOS 不包。
        NavigationStack {
            Form {
                accountsSection
                if !liveAccounts.isEmpty { actionsSection }
                addSection
            }
            .formStyle(.grouped)
            .navigationTitle(L10n.tr("settings.accounts", lang: language))
            .navigationDestination(for: UUID.self) { id in
                // 按 localId 反查而不是把对象本身塞进导航值：解绑会把账号删掉，
                // 反查让「已经不存在」变成一个可表达的状态，而不是去碰一个已删除的对象。
                if let account = liveAccounts.first(where: { $0.localId == id }) {
                    ExternalAccountDetailView(account: account)
                } else {
                    Color.clear
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.tr("common.done", lang: language)) { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddExternalAccountView { account in
                showingAdd = false
                sync(account)
            }
        }
        #if os(macOS)
        // 用 min 而非固定：这一页要能装下详情子页（比它更长），也要能拉大看长账号列表。
        // 此前固定 560×620 比承载它的设置 sheet（520×720）还宽，打开时反而把父窗口撑变形。
        .frame(minWidth: 520, minHeight: 620)
        #endif
    }

    // MARK: - 分区

    private var accountsSection: some View {
        Section {
            if liveAccounts.isEmpty {
                LText("account.empty")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(liveAccounts) { account in
                    NavigationLink(value: account.localId) {
                        ExternalAccountRow(account: account,
                                           syncing: syncing.contains(account.localId))
                    }
                }
            }
        } footer: {
            LText("account.experimentalHint")
        }
    }

    private var actionsSection: some View {
        Section {
            Button { syncAll() } label: {
                Label(L10n.tr("account.syncAll", lang: language),
                      systemImage: AccountUI.syncIcon)
            }
            .appStandardButton()
            .disabled(!syncing.isEmpty)
            if let banner {
                Text(verbatim: banner)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var addSection: some View {
        Section {
            Button { showingAdd = true } label: {
                Label(L10n.tr("account.add", lang: language), systemImage: "plus")
            }
            .appStandardButton()
        }
    }

    // MARK: - 同步

    private func sync(_ account: LinkedAccount) {
        guard !syncing.contains(account.localId) else { return }
        // 记下 localId 再进 Task：await 期间用户完全可能解绑这个账号（对象被删），
        // await 之后**不能再碰 `account`**（读 `displayName` 即 SwiftData fatal）。
        // 本行自身仍要读一次，先在这里取好。
        let localId = account.localId
        let displayName = account.displayName
        syncing.insert(localId)
        banner = nil
        Task { @MainActor in
            let result = await ExternalSyncDriver.sync(account, container: context.container,
                                                       language: AppLanguage(localeCode: language))
            syncing.remove(localId)
            // 账号已不在库里（解绑了）：这轮结果无处可归属，直接丢弃。
            guard accounts.contains(where: { $0.localId == localId }) else { return }
            banner = result.isSuccess
                ? L10n.tr("account.syncDone", [displayName, result.summary.processed], lang: language)
                : L10n.tr("account.syncFailed", [displayName], lang: language)
        }
    }

    private func syncAll() {
        let targets = accounts.filter(\.isLive)
        guard !targets.isEmpty else { return }
        syncing = Set(targets.map(\.localId))
        banner = nil
        Task { @MainActor in
            let results = await ExternalSyncDriver.syncAll(targets, container: context.container,
                                                           language: AppLanguage(localeCode: language))
            syncing.removeAll()
            let succeeded = results.values.filter(\.isSuccess).count
            banner = L10n.tr("account.syncAllDone", [succeeded, results.count], lang: language)
        }
    }
}

// MARK: - 行

/// 账号行：展示名 + 品牌 + 上次同步状态 + 凭证状态徽章。
private struct ExternalAccountRow: View {
    let account: LinkedAccount
    let syncing: Bool

    @Environment(\.appLanguageCode) private var language

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: account.displayName)
                    .lineLimit(1)
                    // 账号名是用户自己的昵称，长度不可控；缩一点再截（同 `GameChoiceRow` 口径）。
                    .minimumScaleFactor(0.7)
                Text(verbatim: subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if syncing {
                ProgressView().controlSize(.small)
            } else {
                CredentialBadge(state: account.credentialState)
            }
        }
    }

    /// 副标题**一律以平台打头**：一个任天堂账号和一个 PSN 账号的账号名可能长得很像，
    /// 「上次同步是三天前」不说明问题，「凭证已失效」才说明问题，而平台决定了这条记录归谁。
    /// 所以三种情况下都带上品牌，只有中间那句话在换。
    ///
    /// 成功那一档**只放日期，不放时刻与条数**：iPhone 上「Nintendo Account · 15 Sep 2026
    /// at 11:12 PM · 12 条记录」一准被截断，而截掉的正是最后那段。行里给到「哪个平台、
    /// 哪天同步过」就够判断了；精确时刻与条数在详情页有完整的一份。
    private var subtitle: String {
        let brand = account.provider.brandName
        if let error = account.lastSyncError {
            return "\(brand) · \(L10n.tr(error.labelKey, lang: language))"
        }
        guard let last = account.lastSyncAt else {
            return "\(brand) · \(L10n.tr("account.neverSynced", lang: language))"
        }
        return "\(brand) · \(last.formatted(date: .abbreviated, time: .omitted))"
    }
}
