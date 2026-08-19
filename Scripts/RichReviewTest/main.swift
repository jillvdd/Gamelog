// 富文本评价编辑器核心不变式回归测试（可重复运行，编译进产物但不编进 app）。
//
// 覆盖：Markdown → 富文本（NSAttributedString）→ Markdown 往返，必须逐字精确。
// 这是 WYSIWYG 编辑器「所见即所得但存的是 Markdown」的核心保证：
// 若往返不再守恒，说明编辑器读回（保存）与详情页渲染（载入）脱节。
//
// 编译运行（Xcode 工具链，勿用 CLT swiftc）：
//   xcrun swiftc -o /tmp/gamelog_richtext \
//     Scripts/RichReviewTest/main.swift \
//     GameLog/Support/MarkdownReview.swift \
//     GameLog/Support/MarkdownRichModel.swift \
//     GameLog/Support/MarkdownRichEditor.swift
//   /tmp/gamelog_richtext
import Foundation
import AppKit

var failures = 0

func check(_ name: String, _ cond: Bool, detail: String = "") {
    if cond {
        print("PASS \(name)")
    } else {
        failures += 1
        print("FAIL \(name)\(detail.isEmpty ? "" : " — \(detail)")")
    }
}

// 通过真实编辑器路径：markdown -> lines -> NSAttributedString -> markdown。
// 期望因 MarkdownReview.parse 会归一化空行为「无」，故测试输入不含多余空行。
let markdownCases: [(input: String, expected: String)] = [
    // 标题各级
    ("# 大标题", "# 大标题"),
    ("## 小节", "## 小节"),
    ("### 三级", "### 三级"),
    // 行内：全粗 / 全斜 / 混合 / 嵌套
    ("**全粗**", "**全粗**"),
    ("*全斜*", "*全斜*"),
    ("plain **bold** and *italic* plain", "plain **bold** and *italic* plain"),
    ("**粗*斜*粗**", "**粗*斜*粗**"),
    // 列表
    ("- 第一项\n- 第二项", "- 第一项\n- 第二项"),
    // 多行正文
    ("多行\n段落\n文本", "多行\n段落\n文本"),
    // 段落 + 标题 + 列表混排
    ("引言段落\n\n# 标题\n\n- a\n- b\n\n结尾", "引言段落\n# 标题\n- a\n- b\n结尾"),
    // 空输入
    ("", ""),
]

for c in markdownCases {
    let tv = NSTextView(frame: .zero)
    let lines = MarkdownRichModel.lines(from: c.input)
    let attr = NSMutableAttributedString()
    for line in lines { ReviewRichEditor.appendLine(line, to: attr) }
    tv.textStorage?.setAttributedString(attr)
    let back = ReviewRichEditor.markdown(fromRich: tv.attributedString())
    check("round-trip \(c.input.debugDescription)",
          back == c.expected,
          detail: "got \(back.debugDescription), expected \(c.expected.debugDescription)")
}

// 样式探测：确认载入后富文本真的带上了粗 / 斜 / 标题字号 / 列表缩进（所见即所得）。
let styleProbe = MarkdownRichModel.lines(from: "# 标题行\n\n这是**粗**和*斜*。\n\n- 项")
// 第 0 行应是 heading1 且字号放大
if let h1 = styleProbe.first, case .heading(let lvl) = h1.kind {
    let attr = ReviewRichEditor.attributedLine(h1)
    let font = attr.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    check("style h1 level=1 & large font",
          lvl == 1 && (font?.pointSize ?? 0) > 15,
          detail: "lvl=\(lvl) size=\(font?.pointSize ?? -1)")
} else {
    check("style h1 detected", false)
}
// 行内粗体 run 应带 bold trait
let boldRun = styleProbe[1].inline.first { $0.text == "粗" }
check("style bold run carries bold", boldRun?.bold == true)
let italicRun = styleProbe[1].inline.first { $0.text == "斜" }
check("style italic run carries italic", italicRun?.italic == true)
// 列表行应带缩进
if let listLine = styleProbe.last, case .list = listLine.kind {
    let attr = ReviewRichEditor.attributedLine(listLine)
    let style = attr.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
    check("style list wrapped with bullet prefix & indent",
          attr.string.hasPrefix("•") && (style?.headIndent ?? 0) > 0)
} else {
    check("style list detected", false)
}

print(failures == 0 ? "RICH REVIEW TEST PASSED" : "RICH REVIEW TEST FAILED (\(failures))")
exit(failures == 0 ? 0 : 1)
