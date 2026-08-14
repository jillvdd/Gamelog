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

    /// 整库出现过的平台（预设世代倒序 + 自定义排最后）。
    private var platforms: [String] {
        Presets.ordered(games.flatMap { $0.completions.map(\.platform) })
    }

    private var visibleGames: [Game] {
        var result = games
        if let platformFilter {
            result = result.filter { game in
                game.completions.contains { $0.platform == platformFilter }
            }
        }
        if !searchText.isEmpty {
            result = result.filter { $0.matches(search: searchText) }
        }
        return result.sorted {
            $0.displayName(for: language).localizedCaseInsensitiveCompare($1.displayName(for: language)) == .orderedAscending
        }
    }

    private func isInGroup(_ game: Game) -> Bool {
        group.games.contains { $0.persistentModelID == game.persistentModelID }
    }

    private func toggle(_ game: Game) {
        if let idx = group.games.firstIndex(where: { $0.persistentModelID == game.persistentModelID }) {
            group.games.remove(at: idx)
        } else {
            group.games.append(game)
        }
        try? context.save()
    }

    var body: some View {
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
        .onTapGesture { toggle(game) }
    }

    @ViewBuilder
    private func cover(for game: Game) -> some View {
        Group {
            if let image = game.coverImage {
                Image(appImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(Color.semantic(.quaternarySystemFill))
                    Image(systemName: "gamecontroller")
                        .font(.system(size: 22))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
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
