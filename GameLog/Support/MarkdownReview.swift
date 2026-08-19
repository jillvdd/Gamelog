import SwiftUI

// MARK: - 共享 Markdown 渲染层（macOS / iOS 双端编译）

/// 长评正文 `Game.reviewBody` 支持的 Markdown 子集：
/// `# / ## / ###` 标题、`**加粗**`、`*斜体*`、`- 列表`。
/// 解析为块后，每块内部用 `AttributedString(markdown:)` 提取粗/斜体，
/// 列表符号与缩进由本层在 view 里补齐（原生 `Text` 不自动渲染列表符号）。
enum MarkdownReview {

    /// 一个块级元素。
    enum Block {
        case heading(level: Int, text: String)
        case list(items: [String])
        case paragraph(String)
    }

    /// 把 markdown 源码切分为有序块序列。
    /// 空行分隔段落；`#` 开头为标题（按井号个数定级）；`- ` 开头为列表项，
    /// 连续的列表项聚集成一个 `.list` 块。
    static func parse(_ markdown: String) -> [Block] {
        var blocks: [Block] = []
        var paragraphs: [String] = []   // 当前段落累积的行
        var listItems: [String] = []    // 当前列表累积的项

        func flushParagraph() {
            if !paragraphs.isEmpty {
                blocks.append(.paragraph(paragraphs.joined(separator: "\n")))
                paragraphs = []
            }
        }
        func flushList() {
            if !listItems.isEmpty {
                let merged = listItems.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                blocks.append(.list(items: merged))
                listItems = []
            }
        }

        let lines = markdown.components(separatedBy: .newlines)
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                // 空行：结束当前段落或列表。
                flushParagraph()
                flushList()
                continue
            }

            // 标题：按井号个数定级。
            if line.hasPrefix("### ") {
                flushParagraph(); flushList()
                blocks.append(.heading(level: 3, text: String(line.dropFirst(4))))
                continue
            }
            if line.hasPrefix("## ") {
                flushParagraph(); flushList()
                blocks.append(.heading(level: 2, text: String(line.dropFirst(3))))
                continue
            }
            if line.hasPrefix("# ") {
                flushParagraph(); flushList()
                blocks.append(.heading(level: 1, text: String(line.dropFirst(2))))
                continue
            }

            // 列表项：连续项聚集成一个块。
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph()
                listItems.append(String(line.dropFirst(2)))
                continue
            }

            // 普通正文行：累积到段落。
            paragraphs.append(line)
        }
        flushParagraph()
        flushList()
        return blocks
    }
}

// MARK: - 渲染视图

/// 渲染 `Game.reviewBody` 的 markdown 长评正文。
/// 内部按块排版：标题大字号粗体、正文系统字号、列表『• 』+ 缩进。
/// 字号 / 行距 / 块间距集中在本文件，双端共享；字体各自用系统字体。
struct MarkdownReviewView: View {

    let markdown: String

    // MARK: 样式表（双端观感一致的基础）

    private static let bodyFontSize: CGFloat = 15
    private static let bodyLineSpacing: CGFloat = 5
    private static let blockSpacing: CGFloat = 10
    private static let headingTopSpacing: CGFloat = 6
    private static let listIndent: CGFloat = 8
    private static let bulletWidth: CGFloat = 22

    var body: some View {
        let blocks = MarkdownReview.parse(markdown)
        return VStack(alignment: .leading, spacing: Self.blockSpacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownReview.Block) -> some View {
        switch block {
        case .heading(let level, let text):
            headingView(level: level, text: text)
        case .list(let items):
            listView(items)
        case .paragraph(let text):
            paragraphView(text)
        }
    }

    @ViewBuilder
    private func headingView(level: Int, text: String) -> some View {
        let size: CGFloat = switch level {
        case 1: 22
        case 2: 18
        default: 16
        }
        inlineText(text)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(.primary)
            .padding(.top, Self.headingTopSpacing)
    }

    @ViewBuilder
    private func paragraphView(_ text: String) -> some View {
        inlineText(text)
            .font(.system(size: Self.bodyFontSize))
            .foregroundStyle(.primary)
            .lineSpacing(Self.bodyLineSpacing)
    }

    @ViewBuilder
    private func listView(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•")
                        .font(.system(size: Self.bodyFontSize))
                        .frame(width: Self.bulletWidth, alignment: .leading)
                    inlineText(item)
                        .font(.system(size: Self.bodyFontSize))
                        .lineSpacing(Self.bodyLineSpacing)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.leading, Self.listIndent)
    }

    /// 块内部的富文本：用 AttributedString 提取加粗/斜体，交回 `Text` 渲染。
    private func inlineText(_ text: String) -> Text {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let attr = try? AttributedString(markdown: trimmed, options: .init(interpretedSyntax: .full)) {
            return Text(attr)
        }
        return Text(verbatim: trimmed)
    }
}
