import SwiftUI
import SwiftData

/// 分组右键「选择游戏…」的 Popover：从整库挑游戏加入分组。
/// 网格封面 + 标题，组内游戏封面右上角 ✓；支持搜索（英/中/日名+别名）与平台筛选（整库口径）；
/// 点封面/标题即切换加入/移出并即时保存。筛选不持久化，重开面板重置。
struct GroupGamePickerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    let group: GameGroup

    @Query(sort: \Game.createdAt) private var games: [Game]
    @State private var searchText = ""
    /// 平台筛选，nil = 全部平台。
    @State private var platformFilter: String?

    /// 整库出现过的平台：唯一归属 LibraryStats。
    ///
    /// 先滤掉已销毁的游戏：本页每个格子都读 `game.coverImage`（外置存储，必 fault 回
    /// store），而整库替换 / 「清空该账号导入数据」之后 `@Query` 会滞后一帧 ——
    /// 那就是 `Fatal error: This backing data was detached`（判据见 `Game.isLive`）。
    private var platforms: [String] { LibraryStats.platformsInUse(games.filter(\.isLive)) }

    private var visibleGames: [Game] {
        // 过滤+排序统一走 LibraryQuery（按名排序 + 稳定平级裁决——修复并列游戏重渲染换位）。
        let result = LibraryQuery.filter(
            games: games.filter(\.isLive), group: nil, platform: platformFilter, status: nil, search: searchText
        )
        return LibraryQuery.sorted(result, by: .name, language: language)
    }

    private func isInGroup(_ game: Game) -> Bool {
        guard group.isLive else { return false }
        return group.games.contains { $0.persistentModelID == game.persistentModelID }
    }

    private func toggle(_ game: Game) {
        // 纵深守卫：分组可能已被整库替换删掉，`group.games` 读一下就是 SwiftData fatal
        //（本页是 popover，不会随根视图的状态重置一起关掉）。
        guard group.isLive, game.isLive else { return }
        if let idx = group.games.firstIndex(where: { $0.persistentModelID == game.persistentModelID }) {
            group.games.remove(at: idx)
        } else {
            group.games.append(game)
        }
        try? context.save()
    }

    var body: some View {
        Group {
            if group.isLive {
                content
            } else {
                Color.clear
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: "\(group.name) · \(L10n.tr("group.memberCount", [group.games.count], lang: language))")
                .font(.headline)
                .lineLimit(1)

            HStack(spacing: 8) {
                BorderedTextField(text: $searchText, placeholder: L10n.tr("group.pickSearch", lang: language))
                    .textFieldStyle(.plain)
                platformMenu
            }

            if visibleGames.isEmpty {
                Spacer()
                LText("library.noResult")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 150), spacing: 10)], spacing: 12) {
                        ForEach(visibleGames) { game in
                            cell(for: game)
                        }
                    }
                    .padding(2)
                }
                #if os(macOS)
                .frame(maxHeight: 460)
                #else
                .frame(maxHeight: .infinity)
                #endif
            }
        }
        .padding(16)
        #if os(macOS)
        .frame(width: 460)
        #else
        .frame(maxWidth: .infinity)
        #endif
    }

    @ViewBuilder
    private func cell(for game: Game) -> some View {
        // 按钮化：按压反馈（原 onTapGesture 无视觉响应）。
        Button {
            toggle(game)
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    cover(for: game)
                    if isInGroup(game) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Color.accentColor, in: Circle())
                            .padding(4)
                    }
                }
                Text(verbatim: game.displayName(for: language))
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressFeedbackButtonStyle(pressedScale: 0.95))
    }

    /// 选择器格子的比例（3:4）。画图的判据与 `aspectRatio` **共用这一个数**，
    /// 见 `GameRowView.thumbSize` 那条说明。
    private static let coverAspect: CGFloat = 3.0 / 4.0

    @ViewBuilder
    private func cover(for game: Game) -> some View {
        Group {
            if let image = game.coverImage {
                Image(appImage: image)
                    .resizable()
                    // 比 3:4 这个框宽的图（1:1 图标、导入的横图）完整显示、上下留空；
                    // 竖版封面比它窄 → 照旧填满裁切。外层锚点不变，选择器网格不会错位。
                    // 见 `AppImage.letterboxes(inBoxAspect:)`（判据只有那一处）。
                    .aspectRatio(contentMode: image.letterboxes(inBoxAspect: Self.coverAspect) ? .fit : .fill)
            } else {
                ZStack {
                    Rectangle().fill(Color.semantic(.quaternarySystemFill))
                    Image(systemName: "gamecontroller")
                        .font(.system(size: 22))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .aspectRatio(Self.coverAspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var platformMenu: some View {
        Menu {
            Button {
                platformFilter = nil
            } label: {
                if platformFilter == nil {
                    Label(L10n.tr("library.allPlatforms", lang: language), systemImage: "checkmark")
                } else {
                    Text(verbatim: L10n.tr("library.allPlatforms", lang: language))
                }
            }
            ForEach(platforms, id: \.self) { p in
                Button {
                    platformFilter = p
                } label: {
                    HStack(spacing: 8) {
                        PlatformIcon(platform: p, size: 16)
                        Text(verbatim: Presets.display(p, category: .platform, language: language))
                        Spacer()
                        if platformFilter == p {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                if let platformFilter {
                    PlatformIcon(platform: platformFilter, size: 14)
                }
                Image(systemName: "line.3.horizontal.decrease")
                Text(verbatim: platformMenuLabel)
                    .lineLimit(1)
            }
        }
        #if os(macOS)
        .fixedSize()
        #else
        .frame(maxWidth: 140)
        #endif
        .help(L10n.tr("library.filterPlatform", lang: language))
    }

    private var platformMenuLabel: String {
        if let platformFilter {
            return Presets.display(platformFilter, category: .platform, language: language)
        }
        return L10n.tr("library.allPlatforms", lang: language)
    }
}
