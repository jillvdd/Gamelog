import SwiftUI

/// 「游戏账号」这一批界面共用的行组件。
///
/// 放在一处是因为它们表达的是同一件事、必须长得一样：
/// 候选游戏行（绑定面板 / 合并面板）、账号行（关联设置页）与外部记录行（账号详情）。
///
/// 三行的标题都 `lineLimit(1)`：一条外部记录 / 游戏名 / 账号名可以很长
/// （「Ghost of Tsushima Director's Cut」），而同一行还挂着状态标签或按钮，
/// 不截断就会把右侧的东西挤出屏幕。

// MARK: - 候选游戏行

/// 候选游戏行（绑定面板 / 合并面板共用）。
///
/// 两处要表达的是同一件事「这是哪个游戏」，只是次要信息不同：绑定看平台与中文名，
/// 合并看搬过去多少条数据。所以次要行做成一个可选补充，而不是两个近乎相同的视图。
struct GameChoiceRow: View {
    let game: Game
    /// 次要行里跟在平台后面的补充信息（合并面板传条数摘要，绑定面板传 nil）。
    var trailing: String?

    @Environment(\.appLanguageCode) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: game.displayName(for: language))
                .foregroundStyle(.primary)
                .lineLimit(1)
                // 名字可能很长（「Ghost of Tsushima Director's Cut」的中日文名更甚），
                // 缩一点再截，比直接砍掉尾字强（与 `RootView` 侧边栏平台名同口径）。
                .minimumScaleFactor(0.7)
            HStack(spacing: 8) {
                // 与全项目另外 29 处同口径读平台名：裸 `game.platform` 存的是 canonical 值，
                // 非中文用户会看到「其他」（英文 canonical 是 "Other"），旧数据还会露出改名前的老值。
                Text(verbatim: Presets.display(game.platform, category: .platform, language: language))
                if let trailing {
                    Text(verbatim: trailing)
                } else if let zh = game.nameZh, zh != game.displayName(for: language) {
                    Text(verbatim: zh)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: - 账号行

/// 账号行：展示名 + 品牌 + 上次同步状态 + 凭证状态徽章 + 行内同步按钮。
///
/// 原先是 `ExternalAccountsView` 里的 `private` 行。「关联设置」页把账号列表**直接铺在页面上**
/// （不再是一层 sheet 跳转）之后，它就跟上面两行住在同一个列表体系里，于是搬到这里 ——
/// 三行的字号与截断规矩从此一处可查。
///
/// ⚠️ 徽章与同步按钮/转圈**同时在**（2026-09-18）：此前的写法是「同步中转圈 **或** 徽章」，
/// 于是同步一开始徽章就消失——而那恰恰是用户最需要看它的时刻（凭证失效时更要盯着同步结果）。
/// 所以转圈改成与徽章并列，占的是同步按钮那一格。
struct ExternalAccountRow: View {
    let account: LinkedAccount
    let syncing: Bool
    /// 行内同步按钮的动作。由列表页给；结果照旧写回列表页那一行 banner（不做每行独立回执）。
    var onSync: () -> Void

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
            CredentialBadge(state: account.credentialState)
            if syncing {
                ProgressView().controlSize(.small)
            } else {
                // `.borderless` 让这次点击被按钮自己吃掉，而不是穿透给外层 `NavigationLink`
                // 把用户带进详情页 —— 行本身仍是「点进这个账号」的入口（用户拍板）。
                Button(action: onSync) {
                    Image(systemName: AccountUI.syncIcon)
                }
                .buttonStyle(.borderless)
                .help(L10n.tr("account.detail.sync", lang: language))
                .accessibilityLabel(L10n.tr("account.detail.sync", lang: language))
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

// MARK: - 外部记录行

/// 一条外部游玩记录（账号详情页的列表）。三行：标题 + 状态标签 / 平台·首次·最近·时长 / 关联结果，
/// 中间按来源插入一行摘要（PSN → 奖杯四色点，Xbox → 成就与游戏分数，两家都没有就不插）。
struct ExternalRecordRow: View {
    let record: ExternalGameRecord

    @Environment(\.appLanguageCode) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // 标题截断、标签靠右钉住：标签是这条记录唯一的状态说明，被长标题挤掉就白做了。
            HStack(spacing: 6) {
                Text(verbatim: record.titleName)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                statusTags
            }
            metaLine
            trophyLine
            achievementLine
            if let matchDescription {
                Text(verbatim: matchDescription)
                    .font(.caption2)
                    .foregroundStyle(record.game == nil ? Color.secondary : AccountUI.linkedTint)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    // MARK: - 第二行（平台 · 首次 · 最近 · 时长）

    /// 窄屏优先保住「平台 + 最近游玩」；`ViewThatFits` 挑第一条放得下的，而不是靠截断硬砍。
    ///
    /// 为什么不是一串 `Text` 拼 `HStack`：那样每条各自截断，出现「Nintendo Switc… · 2026…」
    /// 这种半截字符串；一个 `Text` 里的 `·` 连接则整行末尾截断，读起来清楚。
    private var metaLine: some View {
        ViewThatFits(in: .horizontal) {
            Text(verbatim: metaText(includingFirst: true))
            Text(verbatim: metaText(includingFirst: false))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    /// 第二行（平台 · 首次 · 最近 · 时长）与奖杯摘要之间。
    ///
    /// ⚠️ 这一行**只在这条记录真有奖杯数据时出现**（PSN 上没匹配到奖杯套的记录、
    /// 以及全部 Nintendo / Xbox 记录都是 `nil` —— 成就走下面那条 `achievementLine`，
    /// 两个体系不互相折算，见 `AchievementProgress`）。不要加一行「无奖杯数据」占位 ——
    /// 那是绝大多数行的状态，等于给每条记录都多添一行噪音。
    ///
    /// 用四色小圆点而不是 `TrophyIcon`：这一行只有 `caption2` 的高度，20pt 的图标会把行高
    /// 撑开、在长列表里连成一片彩色块。颜色仍从 `TrophyGrade.tint` 取（唯一归属）。
    @ViewBuilder
    private var trophyLine: some View {
        if let trophies = record.trophies {
            HStack(spacing: 8) {
                ForEach(TrophyGrade.allCases) { grade in
                    HStack(spacing: 3) {
                        Circle()
                            .fill(grade.tint)
                            .frame(width: 6, height: 6)
                        Text(verbatim: "\(trophies.earned(grade))/\(trophies.defined(grade))")
                            .monospacedDigit()
                    }
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            // 四个色点对读屏用户毫无意义，换成一句话（等级名与顺序由 `TrophyGrade.allCases` 定）。
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: L10n.tr(
                "game.trophies.summary",
                [trophies.earned(.platinum), trophies.earned(.gold),
                 trophies.earned(.silver), trophies.earned(.bronze)],
                lang: language)))
        }
    }

    /// Xbox 的成就摘要，与 `trophyLine` 同一个位置。
    ///
    /// 为什么要有它：这是**同一个界面上的两家 provider**。账号页的记录列表里 PSN 行行都带奖杯摘要、
    /// Xbox 行却什么都不显示的话，用户扫一眼只能得出「Xbox 的成就没导进来」这个结论 ——
    /// 而数据其实在（详情页那张成就卡上有），只是没在这一行露面（2026-09-18 对等审计 GAP 2）。
    ///
    /// 与 `trophyLine` 的**唯一形状差别**：不画色点。成就**没有分级**（`AchievementProgress`
    /// 就是四个计数），画四个点出来等于凭空造一个来源里不存在的分级。
    ///
    /// 判据是**数据**不是 provider（与 `trophyLine` 对位）：成就不论谁写的都只有 Xbox 一家。
    /// 入场判据用 `hasDisplayableValue` 而不是 `!= nil` —— `totalAchievements = 0` 的条目
    /// 有 `achievement` 对象、两格却都印 `—`（同 `showsXboxAchievementCard` 那条纪律）。
    @ViewBuilder
    private var achievementLine: some View {
        if let achievements = record.achievements, achievements.hasDisplayableValue {
            // 窄屏优先保住没有标签的那版；与 `metaLine` 同一套办法，不靠截断硬砍。
            ViewThatFits(in: .horizontal) {
                Text(verbatim: achievementText(achievements, labeled: true))
                Text(verbatim: achievementText(achievements, labeled: false))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: achievementText(achievements, labeled: true)))
        }
    }

    /// `成就 25/52 · 游戏分数 1240/2000`；`labeled: false` 是窄屏那一版（只留数字）。
    ///
    /// 两格各自可能缺（总数 0 → 那格为 nil，见 `AchievementProgress`），缺的那格**整段不出现**
    /// 而不是印 `—`：这一行是**摘要**不是卡片，`—` 放在这里只是噪音（卡片上才需要它来占位对齐）。
    private func achievementText(_ achievements: AchievementProgress, labeled: Bool) -> String {
        var parts: [String] = []
        if let text = achievements.achievementsText {
            parts.append(labeled
                ? "\(L10n.tr("game.xbox.achievements", lang: language)) \(text)"
                : text)
        }
        if let text = achievements.gamerscoreText {
            parts.append(labeled
                ? "\(L10n.tr("game.xbox.gamerscore", lang: language)) \(text)"
                : text)
        }
        return parts.joined(separator: " · ")
    }

    private func metaText(includingFirst: Bool) -> String {
        var parts = [Presets.display(record.platform, category: .platform, language: language)]
        // 版本标签（体验版/试玩版）紧跟平台：它是「这条为什么没进库」的直接解释。
        if record.versionType == .demo || record.versionType == .trial {
            parts.append(L10n.tr(record.versionType.labelKey, lang: language))
        }
        if includingFirst, let first = record.firstPlayedAt {
            parts.append(L10n.tr("account.detail.firstPlayed",
                                 [first.formatted(date: .abbreviated, time: .omitted)], lang: language))
        }
        if let last = record.lastPlayedAt {
            parts.append(L10n.tr("account.detail.lastPlayed",
                                 [last.formatted(date: .abbreviated, time: .omitted)], lang: language))
        }
        if let hours = record.displayHours {
            parts.append(L10n.tr("account.detail.hours", [hours], lang: language))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - 状态标签

    /// 三个标签**并列**，不是 `else if`：一条记录可以同时「已忽略」且「来源已无」，
    /// 后者只说明来源侧没了，前者才是「以后别再自动导入」。
    ///
    /// 第三个是**跳过原因**（2026-09-18）：规则判掉的记录现在也进「已忽略」档，光说
    /// 「已忽略」用户没法判断这是规则判错了还是自己点过 —— 说清原因他才好决定要不要
    /// 手动绑回来（绑定入口就在这一行的处置面板里）。
    ///
    /// ⚠️ 体验版 / 试玩版**不走这个标签**：它们的原因已经印在上面那行
    /// （`metaText` 的版本文案）里了，同一句话在一行里印两遍是噪音。
    /// ⚠️ 已经绑到某个游戏上的记录也不印（`game == nil` 那道门）：它已经进库了，
    /// 「本条被跳过」不再是对当前状态的描述。
    @ViewBuilder
    private var statusTags: some View {
        let ruleReason = record.game == nil ? record.storedSkipReason : nil
        let tags = (
            absent: !record.presentInLastSync,
            ignored: record.isShownAsIgnored,
            rule: ruleReason
        )
        if tags.absent || tags.ignored || tags.rule != nil {
            HStack(spacing: 6) {
                if tags.absent {
                    TagLabel(text: L10n.tr("account.detail.absent", lang: language), tint: .orange)
                }
                if tags.ignored {
                    TagLabel(text: L10n.tr("account.detail.ignored", lang: language), tint: .secondary)
                }
                if let rule = tags.rule {
                    TagLabel(text: L10n.tr(rule.labelKey, lang: language), tint: .secondary)
                }
            }
            .fixedSize()
        }
    }

    /// 第三行：只讲「关联到了哪」。已忽略（含规则跳过）且未关联的记录**不重复说一遍**
    /// —— 标签已经写着了，而「待关联」那句会与「已忽略」自相矛盾。
    private var matchDescription: String? {
        if let game = record.game {
            return L10n.tr("account.detail.linkedTo", [game.displayName(for: language)], lang: language)
        }
        return record.isShownAsIgnored ? nil : L10n.tr("account.detail.unmatchedHint", lang: language)
    }
}
