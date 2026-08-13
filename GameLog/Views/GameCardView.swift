import SwiftUI
import SwiftData
import AppKit

extension Game {
    var coverImage: NSImage? {
        guard let data = coverData else { return nil }
        return NSImage(data: data)
    }
}

/// 网格视图中的游戏卡片：封面 + 库显示分徽章 + 名称 + 平台/日期。
struct GameCardView: View {
    @Environment(\.appLanguageCode) private var language
    let game: Game

    private var cover: some View {
        Group {
            if let image = game.coverImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle()
                        .fill(Color(nsColor: .quaternarySystemFill))
                    Image(systemName: "gamecontroller")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var platformText: String {
        let list = game.platformList
        guard !list.isEmpty else { return "" }
        let shown = list.prefix(2).map { Presets.display($0, category: .platform, language: language) }
            .joined(separator: " · ")
        if list.count > 2 {
            return "\(shown) · +\(list.count - 2)"
        }
        return shown
    }

    /// 最近一次通关日期，单独一行；无日期返回空串（不显示）。
    private var dateText: String {
        guard let latest = game.sortedCompletions.last, let date = latest.date else { return "" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                cover
                if let score = game.libraryScore {
                    Text(verbatim: Self.formatScore(score))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.72), in: Capsule())
                        .padding(6)
                }
            }
            Text(verbatim: game.displayName(for: language))
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if !platformText.isEmpty {
                Text(verbatim: platformText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !dateText.isEmpty {
                Text(verbatim: dateText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func formatScore(_ score: Double) -> String {
        String(format: "%.1f", score)
    }
}

/// 列表视图中的游戏行。
struct GameRowView: View {
    @Environment(\.appLanguageCode) private var language
    let game: Game

    private var subtitle: String {
        game.platformList
            .map { Presets.display($0, category: .platform, language: language) }
            .joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let image = game.coverImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Rectangle().fill(Color(nsColor: .quaternarySystemFill))
                        Image(systemName: "gamecontroller").foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(width: 40, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: game.displayName(for: language))
                    .font(.system(size: 13, weight: .medium))
                if !subtitle.isEmpty {
                    Text(verbatim: subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let score = game.libraryScore {
                Text(verbatim: GameCardView.formatScore(score))
                    .font(.system(size: 15, weight: .bold))
                    .monospacedDigit()
            } else {
                LText("score.unrated")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// 新建分组的弹窗。空名或重名不允许保存。
struct NewGroupSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \GameGroup.name) private var groups: [GameGroup]
    @State private var name = ""

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }
    private var isDuplicate: Bool {
        !trimmed.isEmpty && groups.contains { $0.name == trimmed }
    }

    var body: some View {
        VStack(spacing: 16) {
            LText("group.newGroup")
                .font(.headline)
            BorderedTextField(text: $name, placeholder: L10n.tr("group.name", lang: language))
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
                    context.insert(GameGroup(name: trimmed))
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
