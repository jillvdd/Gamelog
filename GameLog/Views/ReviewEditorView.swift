import SwiftUI
import SwiftData

#if os(macOS)

/// 共享的评价编辑会话：详情页把当前编辑目标写入 `gameID`，独立窗口据此加载。
/// 独立窗口是单例场景，切换游戏编辑时靠 `.id(gameID)` 重建内部视图。
@MainActor
final class ReviewEditorSession: ObservableObject {
    static let shared = ReviewEditorSession()
    @Published var gameID: PersistentIdentifier?
    private init() {}
}

/// macOS 独立评价编辑窗口：一个仿系统备忘录入的全屏富文本编辑器（所见即所得）。
/// 顶栏只留「取消 / 保存」——「保存」才把富文本转回 Markdown 写回 `game` 并关闭；
/// 取消 / 直接关窗不写回。写作时看到的是富文本（加粗/标题/列表就在原地显示），
/// 详情页展示时 `MarkdownReviewView` 再把同一份 Markdown 渲染成文章（编辑 / 展示分离）。
struct ReviewEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.appLanguageCode) private var language
    @ObservedObject private var session = ReviewEditorSession.shared
    @StateObject private var controller = ReviewRichTextController()

    @State private var game: Game?
    @State private var reviewTitle = ""

    var body: some View {
        Group {
            if let game {
                editorContent(game)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .id(session.gameID) // 切换编辑目标时重建内部状态
        .task(id: session.gameID) { load() }
        .background(WindowSizer()) // 打开即放大到可用屏幕，营造备忘录式沉浸写作
    }

    private func load() {
        guard let id = session.gameID, let resolved = context.model(for: id) as? Game else {
            game = nil
            return
        }
        game = resolved
        reviewTitle = resolved.reviewTitle
        controller.load(markdown: resolved.reviewBody)
    }

    @ViewBuilder
    private func editorContent(_ game: Game) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶栏：当前游戏名 + 保存 / 取消
            HStack(alignment: .center, spacing: 12) {
                Text(verbatim: game.displayName(for: language))
                    .font(.title2.bold())
                    .lineLimit(1)
                    .truncationMode(.tail)
                // 一句话评价（tagline）轻量标注
                if !reviewTitle.isEmpty {
                    Text(verbatim: "·  \(reviewTitle)")
                        .font(.body)
                        .italic()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer()
                Button(L10n.tr("common.cancel", lang: language)) {
                    dismissWindow()
                }
                .keyboardShortcut(.cancelAction)
                Button(L10n.tr("review.save", lang: language)) {
                    save(game)
                }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            // 格式工具条：仿系统备忘录顶部，直接改选中文字样式（所见即所得）。
            formatToolbar
                .padding(.vertical, 4)

            Divider()

            // 大富文本书写区：占满剩余空间，像备忘录一样连续滚动。
            ReviewRichEditorRepresentable { textView in
                controller.register(textView)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 640, minHeight: 480)
    }

    /// 格式工具条：把选中文字直接改样式（所见即所得），仿系统备忘录顶部。
    /// 段落样式用文字标签（正文 / 大标题 / 副标题），比纯图标更直白；
    /// 行内样式沿用备忘录的 B / I 字母按钮。
    private var formatToolbar: some View {
        HStack(spacing: 8) {
            styleLabelButton(L10n.tr("review.main", lang: language)) { controller.setBody() }
            styleLabelButton(L10n.tr("review.title", lang: language)) { controller.setHeading1() }
            styleLabelButton(L10n.tr("review.subtitle", lang: language)) { controller.setHeading2() }
            Divider().frame(height: 16)
            toolbarLetterButton("B", L10n.tr("review.bold", lang: language)) { controller.toggleBold() }
            toolbarLetterButton("I", L10n.tr("review.italic", lang: language)) { controller.toggleItalic() }
            Divider().frame(height: 16)
            toolbarIconButton("list.bullet", L10n.tr("review.list", lang: language)) { controller.toggleList() }
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    /// 段落样式标签按钮：带字号的文字标签，直观表明「点了变多大」。
    private func styleLabelButton(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 8)
                .frame(height: 22)
        }
        .buttonStyle(.plain)
        .help(text)
    }

    private func toolbarIconButton(_ systemImage: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 22)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func toolbarLetterButton(_ text: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .italic()
                .frame(width: 26, height: 22)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func save(_ game: Game) {
        game.reviewTitle = reviewTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        game.reviewBody = controller.markdown
        try? context.save()
        dismissWindow()
    }
}

/// 窗口打开即放大到可用屏幕区域（仿备忘录沉浸写作）。
private struct WindowSizer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window?.sheetParent ?? view.window {
                window.setFrame(window.screen?.visibleFrame ?? window.frame, display: true)
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

#endif
