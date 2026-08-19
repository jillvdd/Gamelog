import Foundation

// MARK: - 富文本编辑器逻辑核心（纯逻辑，跨端编译）

/// 评价长评的「行版富文本」模型，供 macOS 所见即所得编辑器使用。
///
/// 数据模型 `Game.reviewBody` 存的仍是 Markdown 源码；编辑器把每行拆成
/// `Line`（段落级样式 kind + 行内 runs），工具条直接改 `Line`，存盘时再
/// 转回 Markdown。行 / 段落的语义与 `MarkdownReview.parse` 保持一致，
/// 保证「编辑器所见 == 详情页渲染」。
enum MarkdownRichModel {

    /// 行内的一段 run：一段连续、样式相同的文字。
    struct Inline {
        var text: String
        var bold: Bool = false
        var italic: Bool = false
    }

    /// 编辑器的一行文字。
    struct Line {
        var inline: [Inline]
        /// 段落级样式。
        enum Kind: Equatable {
            case body
            case heading(Int)   // 1 / 2 / 3
            case list
        }
        var kind: Kind = .body

        /// 当前行纯文本（runs 拼接，供保存/显示用）。
        var plainText: String { inline.map { $0.text }.joined() }
    }

    // MARK: Markdown → Lines

    /// 把 Markdown 源码解析为行序列。
    ///
    /// 复用 `MarkdownReview.parse` 的块结构，保证与详情页渲染同源：
    /// - 标题 → 单独一行（kind = heading(级)）
    /// - 列表 → 每项一行（kind = list）
    /// - 段落 → 按换行拆开（kind = body）
    static func lines(from markdown: String) -> [Line] {
        var out: [Line] = []
        for block in MarkdownReview.parse(markdown) {
            switch block {
            case .heading(let level, let text):
                out.append(Line(inline: parseInline(text), kind: .heading(level)))
            case .list(let items):
                for item in items {
                    out.append(Line(inline: parseInline(item), kind: .list))
                }
            case .paragraph(let text):
                // 段落可能跨多行：拆成多行 body，保留行内样式。
                for rawLine in text.components(separatedBy: .newlines) {
                    out.append(Line(inline: parseInline(rawLine), kind: .body))
                }
            }
        }
        return out
    }

    // MARK: Lines → Markdown

    /// 把行序列转回 Markdown 源码。
    /// 行内 **加粗** / *斜体*，段落级 # 标题 / - 列表。
    static func markdown(from lines: [Line]) -> String {
        var out: [String] = []
        for line in lines {
            let body = inlineMarkdown(line.inline)
            switch line.kind {
            case .heading(let level):
                out.append(String(repeating: "#", count: level) + " " + body)
            case .list:
                out.append("- " + body)
            case .body:
                out.append(body)
            }
        }
        return out.joined(separator: "\n")
    }

    // MARK: 行内转换（runs ↔ 带标记源码）

    /// 把带 **粗** *斜* 标记的一行解析为 runs。
    /// 支持的子集与 `MarkdownReview` 一致：`**bold**`、`*italic*`。
    private static func parseInline(_ source: String) -> [Inline] {
        let chars = Array(source)
        var runs: [Inline] = []
        var i = 0

        func pushPlain(_ text: String) {
            if text.isEmpty { return }
            if var last = runs.last, !last.bold, !last.italic {
                last.text += text
                runs[runs.count - 1] = last
            } else {
                runs.append(Inline(text: text))
            }
        }

        while i < chars.count {
            // ** 加粗
            if chars[i] == "*", i + 1 < chars.count, chars[i + 1] == "*" {
                var j = i + 2
                var body = ""
                while j < chars.count {
                    if chars[j] == "*", j + 1 < chars.count, chars[j + 1] == "*" { break }
                    body.append(chars[j])
                    j += 1
                }
                if j < chars.count { // 找到了闭合的 **
                    runs.append(Inline(text: body, bold: true))
                    i = j + 2
                    continue
                }
                // 未闭合：按普通字符处理
                pushPlain("**")
                i += 2
                continue
            }
            // * 斜体
            if chars[i] == "*" {
                var j = i + 1
                var body = ""
                while j < chars.count, chars[j] != "*" {
                    body.append(chars[j])
                    j += 1
                }
                if j < chars.count { // 找到了闭合的 *
                    runs.append(Inline(text: body, italic: true))
                    i = j + 1
                    continue
                }
                pushPlain("*")
                i += 1
                continue
            }
            // 普通字符：累计（若是连续的普通文本合并成单个 run）
            var j = i
            var plain = ""
            while j < chars.count, chars[j] != "*" {
                plain.append(chars[j])
                j += 1
            }
            pushPlain(plain)
            i = j
        }
        return runs
    }

    /// 把 runs 转回带标记源码。
    private static func inlineMarkdown(_ inline: [Inline]) -> String {
        var out = ""
        for run in inline {
            if run.bold {
                out += "**" + run.text + "**"
            } else if run.italic {
                out += "*" + run.text + "*"
            } else {
                out += run.text
            }
        }
        return out
    }
}
