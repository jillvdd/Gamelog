import SwiftUI

#if os(macOS)
import AppKit

// MARK: - macOS 富文本（所见即所得）评价编辑器

/// 编辑器把 `Game.reviewBody`（Markdown 源码）渲染成富文本就地显示：
/// `# 标题` → 大字标题、`**加粗**` → 粗体、`*斜体*` → 斜体、`- 项` → 项目符号。
/// 工具条按钮直接改选中段落的样式；存盘时再转回 Markdown 写回 `reviewBody`，
/// 保证与详情页渲染同源（编辑器所见 == 详情页文章）。
///
/// 分段策略：
/// - 段落级样式用一个自定义 attribute 标记（body / headingN / list），与显示解耦，读回无歧义。
/// - 行内加粗 / 斜体用 NSFont 的 symbolic traits 表达。
/// - 列表的项目符号 `•` 作为文本前缀精确渲染（比 NSTextList 可靠），读回时剥掉。
/// - 标题默认粗体展示；读回时标题内的加粗视为「展示」不作文本标记，保证 `#` 精确重建。
enum ReviewRichEditor {

    /// 自定义段落级样式 attribute。
    static let kindKey = NSAttributedString.Key("gamelog.review.lineKind")
    enum Kind: String {
        case body, heading1, heading2, heading3, list
    }

    /// 列表项目符号前缀（显示的 bullet，不存入 markdown）。
    private static let bullet = "•\t"

    // 与 MarkdownReviewView 观感一致的基准字号
    static let bodyPt: CGFloat = 15
    static let h1Pt: CGFloat = 22
    static let h2Pt: CGFloat = 18
    static let h3Pt: CGFloat = 16

    // MARK: 展示

    static func displayFont(for kind: Kind, bold: Bool, italic: Bool) -> NSFont {
        let basePt: CGFloat
        switch kind {
        case .body: basePt = bodyPt
        case .heading1: basePt = h1Pt
        case .heading2: basePt = h2Pt
        case .heading3: basePt = h3Pt
        case .list: basePt = bodyPt
        }
        let wantsBold: Bool
        switch kind {
        case .heading1, .heading2, .heading3: wantsBold = true
        default: wantsBold = bold
        }
        let base = NSFont.systemFont(ofSize: basePt)
        if wantsBold || italic {
            var traits: NSFontDescriptor.SymbolicTraits = []
            if wantsBold { traits.insert(.bold) }
            if italic { traits.insert(.italic) }
            let d = base.fontDescriptor.withSymbolicTraits(traits)
            return NSFont(descriptor: d, size: basePt) ?? base
        }
        return base
    }

    /// 构建一行（Line）的富文本物（段落已含样式，不含段尾换行）。
    static func attributedLine(_ line: MarkdownRichModel.Line) -> NSAttributedString {
        let kind = kind(from: line.kind)
        let result = NSMutableAttributedString()
        // 列表：先放 bullet 前缀（body 字号、不加粗）
        if kind == .list {
            let bulletFont = NSFont.systemFont(ofSize: bodyPt)
            result.append(NSAttributedString(string: bullet, attributes: [.font: bulletFont]))
        }
        for run in line.inline {
            let font = displayFont(for: kind, bold: run.bold, italic: run.italic)
            result.append(NSAttributedString(string: run.text,
                                             attributes: [.font: font, .foregroundColor: NSColor.labelColor]))
        }
        // 动态标签色，保证加粗/斜体等附加样式后仍跟随系统深色模式。
        let fullRange = NSRange(location: 0, length: result.length)
        if fullRange.length > 0 {
            result.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
        }
        result.addAttribute(.paragraphStyle, value: paragraphStyle(for: kind), range: fullRange)
        result.addAttribute(kindKey, value: kind.rawValue, range: fullRange)
        return result
    }

    /// 把一行追加到容器并换行。
    static func appendLine(_ line: MarkdownRichModel.Line, to out: NSMutableAttributedString) {
        out.append(attributedLine(line))
        out.append(NSAttributedString(string: "\n"))
    }

    /// 段落相关的排版属性。
    static func paragraphStyle(for kind: Kind) -> NSParagraphStyle {
        let ps = NSMutableParagraphStyle()
        switch kind {
        case .list:
            ps.headIndent = 18
            ps.firstLineHeadIndent = 0
            ps.paragraphSpacing = 4
            ps.lineSpacing = 5
        case .heading1, .heading2, .heading3:
            ps.paragraphSpacingBefore = 6
            ps.paragraphSpacing = 4
        case .body:
            ps.lineSpacing = 5
            ps.paragraphSpacing = 4
        }
        return ps
    }

    /// 正文段落样式（供 typingAttributes 默认使用，让「直接输入」的段落
    /// 指标与「正文 / 列表」完全一致，避免看起来字号不同）。
    static var bodyParagraphStyle: NSParagraphStyle { paragraphStyle(for: .body) }

    static func kind(from kind: MarkdownRichModel.Line.Kind) -> Kind {
        switch kind {
        case .body: return .body
        case .heading(let level):
            switch level { case 1: return .heading1; case 2: return .heading2; default: return .heading3 }
        case .list: return .list
        }
    }

    static func modelKind(from kind: Kind) -> MarkdownRichModel.Line.Kind {
        switch kind {
        case .body: return .body
        case .heading1: return .heading(1)
        case .heading2: return .heading(2)
        case .heading3: return .heading(3)
        case .list: return .list
        }
    }

    /// 从一个富文本段落读取回模型 Line。
    static func line(from attributedString: NSAttributedString) -> MarkdownRichModel.Line {
        // 空段（如文档末尾的空行）：返回空正文行，避免 attribute(at:0) 越界。
        guard attributedString.length > 0 else {
            return MarkdownRichModel.Line(inline: [], kind: .body)
        }
        let text = attributedString.string

        var kind: MarkdownRichModel.Line.Kind = .body
        if let raw = attributedString.attribute(kindKey, at: 0, effectiveRange: nil) as? String {
            switch raw {
            case Kind.heading1.rawValue: kind = .heading(1)
            case Kind.heading2.rawValue: kind = .heading(2)
            case Kind.heading3.rawValue: kind = .heading(3)
            case Kind.list.rawValue: kind = .list
            default: kind = .body
            }
        }

        // 剥掉列表 bullet 前缀的文本范围
        var bodyRange = NSRange(location: 0, length: attributedString.length)
        if text.hasPrefix(bullet) {
            bodyRange.location += (bullet as NSString).length
            bodyRange.length -= (bullet as NSString).length
        }

        let inline = inlineRuns(from: attributedString, in: bodyRange, clearBoldOnHeading: headingLevel(kind) != nil)
        return MarkdownRichModel.Line(inline: inline, kind: kind)
    }

    private static func headingLevel(_ kind: MarkdownRichModel.Line.Kind) -> Int? {
        if case .heading(let l) = kind { return l }
        return nil
    }

    /// 按字体 traits 把富文本的 bodyRange 拆成模型 runs。
    private static func inlineRuns(from attr: NSAttributedString, in range: NSRange,
                                   clearBoldOnHeading: Bool) -> [MarkdownRichModel.Inline] {
        var runs: [MarkdownRichModel.Inline] = []
        guard range.length > 0 else { return runs }
        attr.enumerateAttributes(in: range, options: []) { attrs, r, _ in
            let text = (attr.string as NSString).substring(with: r)
            if text.isEmpty { return }
            var bold = false, italic = false
            if let font = attrs[.font] as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits
                bold = traits.contains(.bold)
                italic = traits.contains(.italic)
            }
            if clearBoldOnHeading { bold = false }  // 标题的粗是展示，非文本标记
            runs.append(MarkdownRichModel.Inline(text: text, bold: bold, italic: italic))
        }
        return runs
    }

    /// 全文档富文本 → Markdown 源码。
    static func markdown(fromRich attr: NSAttributedString) -> String {
        let ns = attr.string as NSString
        var lines: [MarkdownRichModel.Line] = []
        var paraStart = 0
        var i = 0
        let length = ns.length
        while i < length {
            if ns.character(at: i) == 0x0A {
                let range = NSRange(location: paraStart, length: i - paraStart)
                lines.append(line(from: attr.attributedSubstring(from: range)))
                paraStart = i + 1
            }
            i += 1
        }
        if paraStart < length || length == 0 {
            let range = NSRange(location: paraStart, length: length - paraStart)
            lines.append(line(from: attr.attributedSubstring(from: range)))
        }
        return MarkdownRichModel.markdown(from: lines)
    }
}

// MARK: - 中文合成斜体（synthetic oblique）

/// 对 italic run 里的 CJK 字符在字形绘制层施加轻微 shear 的布局管理器。
///
/// 中文（苹方等）没有真正的斜体字形，靠字体 italic 标志不会让中文倾斜；
/// 这里只改写字形绘制：拉丁字母走 SF 的真正斜体、不动；CJK 字形单独
/// 斜切约 12°。由于只在 `showCGGlyphs` 绘制层倾斜单个字形，布局/换行/
/// 命中/光标/IME/复制全部不受影响（不改定位、不改 model）。
final class ObliqueReviewLayoutManager: NSLayoutManager {

    /// CJK 的剪切系数：x 偏移 = -c × y，≈ tan(12°)。
    private let shearC: CGFloat = 0.21

    /// 判断一个字符是否需要中文合成斜体（汉字/假名/谚文/全角）。
    private static func isCJK(_ c: unichar) -> Bool {
        switch c {
        case 0x3400...0x4DBF,   // CJK 扩展 A
             0x4E00...0x9FFF,   // CJK 统一表意
             0xF900...0xFAFF,   // 兼容表意
             0x3040...0x30FF,   // 日文假名
             0x31F0...0x31FF,   // 假名扩展
             0xAC00...0xD7AF,   // 谚文
             0xFF00...0xFFEF:   // 全角形式
            return true
        default:
            return false
        }
    }

    override func showCGGlyphs(
        _ glyphs: UnsafePointer<CGGlyph>,
        positions: UnsafePointer<NSPoint>,
        count glyphCount: Int,
        font: NSFont,
        matrix textMatrix: AffineTransform,
        attributes: [NSAttributedString.Key: Any] = [:],
        in graphicsContext: NSGraphicsContext
    ) {
        // 仅当该 run 是 italic 才做中文合成斜体。
        let runFont = (attributes[.font] as? NSFont) ?? font
        let isItalic = runFont.fontDescriptor.symbolicTraits.contains(.italic)
        guard isItalic, glyphCount > 0 else {
            super.showCGGlyphs(glyphs, positions: positions, count: glyphCount, font: font,
                               matrix: textMatrix, attributes: attributes, in: graphicsContext)
            return
        }

        let glyphRanges = splitCJKRanges(count: glyphCount)
        guard !glyphRanges.isEmpty else {
            super.showCGGlyphs(glyphs, positions: positions, count: glyphCount, font: font,
                               matrix: textMatrix, attributes: attributes, in: graphicsContext)
            return
        }

        let cg = graphicsContext.cgContext
        for seg in glyphRanges {
            let ptr = glyphs + seg.location
            let pos = positions + seg.location
            if seg.cjk {
                cg.saveGState()
                cg.translateBy(x: 0, y: 0)
                cg.concatenate(CGAffineTransform(a: 1, b: 0, c: -shearC, d: 1, tx: 0, ty: 0))
                super.showCGGlyphs(ptr, positions: pos, count: seg.length, font: font,
                                   matrix: textMatrix, attributes: attributes, in: graphicsContext)
                cg.restoreGState()
            } else {
                super.showCGGlyphs(ptr, positions: pos, count: seg.length, font: font,
                                   matrix: textMatrix, attributes: attributes, in: graphicsContext)
            }
        }
    }

    private struct Segment {
        let location: Int
        let length: Int
        let cjk: Bool
    }

    /// 把 0..<glyphCount 的 glyph 按「对应字符是否为 CJK」切成连续段。
    private func splitCJKRanges(count glyphCount: Int) -> [Segment] {
        var segs: [Segment] = []
        guard glyphCount > 0 else { return segs }
        var i = 0
        while i < glyphCount {
            let glyphIndex = i
            let cjk = Self.isCJK(characterByGlyph(glyphIndex))
            var j = i + 1
            while j < glyphCount && Self.isCJK(characterByGlyph(j)) == cjk { j += 1 }
            segs.append(Segment(location: i, length: j - i, cjk: cjk))
            i = j
        }
        return segs
    }

    /// 取某个 glyph 对应的字符。
    private func characterByGlyph(_ glyphIndex: Int) -> unichar {
        let charIndex = characterIndexForGlyph(at: glyphIndex)
        let s = textStorage?.string as NSString? ?? ""
        guard charIndex >= 0, charIndex < s.length else { return 0 }
        return s.character(at: charIndex)
    }
}

// MARK: - 富文本 NSTextView 壳（NSViewRepresentable）

/// 富文本 NSTextView 的 SwiftUI 壳：占满给定区域、滚动、isRichText=on。
struct ReviewRichEditorRepresentable: NSViewRepresentable {
    /// 让外部控制器能拿到 textView 引用。
    var onTextViewReady: (NSTextView) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()

        // 标准私有文本栈：NSTextStorage → NSLayoutManager → NSTextContainer → NSTextView。
        // 必须显式创建并挂接 NSTextStorage，否则 textView 没有后备存储、无法输入/渲染。
        // 自定义布局管理器负责中文合成斜体（见 ObliqueReviewLayoutManager）。
        let textStorage = NSTextStorage()
        let layoutManager = ObliqueReviewLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 0, height: 0), textContainer: textContainer)
        textView.isRichText = true
        textView.allowsUndo = true
        // 统一默认正文字号 = bodyPt（15）。注意：富文本模式（isRichText）下
        // `textView.font` setter 不会更新 typingAttributes，直接打字仍用旧默认字号，
        // 所以必须显式写 typingAttributes，让「直接输入 / 正文 / 列表」三者字号一致。
        textView.font = NSFont.systemFont(ofSize: ReviewRichEditor.bodyPt)
        let defaultFont = NSFont.systemFont(ofSize: ReviewRichEditor.bodyPt)
        textView.typingAttributes[.font] = defaultFont
        textView.typingAttributes[.foregroundColor] = NSColor.labelColor
        // 直接输入的段落样式与「正文」一致（行距/段距），否则空文档直打看起来偏小。
        textView.typingAttributes[.paragraphStyle] = ReviewRichEditor.bodyParagraphStyle
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.hasHorizontalScroller = false

        onTextViewReady(textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}

    final class Coordinator: NSObject {}
}

// MARK: - 控制器：持富文本、给工具条提供操作

/// 富文本编辑器的逻辑控制器：持有 NSTextView 弱引用，暴露工具条所需操作。
/// 作为 textView 的 delegate，在真实键盘输入前兜底校准 typingAttributes，避免直打字号异常。
@MainActor
final class ReviewRichTextController: NSObject, ObservableObject, NSTextViewDelegate {
    weak var textView: NSTextView?
    @Published var isEmpty = true

    var isRegistered: Bool = false

    /// 防止 normalizeFonts 触发 didChange 后递归。
    private var isNormalizing = false

    /// 归属判定：是否允许「编辑已打开的另一游戏」时重建，交给外部处理。

    func register(_ textView: NSTextView) {
        self.textView = textView
        textView.delegate = self
        NotificationCenter.default.addObserver(
            self, selector: #selector(textChanged),
            name: NSText.didChangeNotification, object: textView)
        isRegistered = true
        updateIsEmpty()
    }

    @objc private func textChanged() {
        updateIsEmpty()
        normalizeFonts()
        #if DEBUG
        if let tv = textView {
            let a = tv.attributedString()
            let n = a.length
            let sel = tv.selectedRange()
            let at = min(max(sel.location - 1, 0), max(n - 1, 0))
            if n > 0 {
                let f = a.attribute(.font, at: at, effectiveRange: nil) as? NSFont
                Self.debug("changed len=\(n) sel=\(sel) docFont@\(at)=\(f?.pointSize ?? -1) typing=\((tv.typingAttributes[.font] as? NSFont)?.pointSize ?? -1)")
            }
        }
        #endif
    }

    /// 真实键盘输入落库后，NSTextView 用的是它内部固定默认字号（诊断显示 12pt），
    /// 无论 typingAttributes 设成多少都被忽略。这里在文本已落库后整篇扫描，
    /// 把非规范字号（非 15/16/18/22）的 run 按所在段落样式纠正回正确字号。
    private func normalizeFonts() {
        guard let textView, !isNormalizing else { return }
        let storage = textView.textStorage
        let attr = textView.attributedString()
        let n = attr.length
        guard n > 0 else { return }

        isNormalizing = true
        defer { isNormalizing = false }

        var rewrites: [(NSRange, NSFont, NSParagraphStyle)] = []
        attr.enumerateAttributes(in: NSRange(location: 0, length: n), options: []) { attrs, r, _ in
            let f = attrs[.font] as? NSFont
            guard let f, !Self.isKnownSize(f.pointSize) else { return }
            // 该 run 归属的段落样式（kindKey 段落级 attribute）
            let (kind, paraStyle) = Self.paragraphInfo(for: attr, at: r.location)
            let target = Self.font(for: kind, base: f)
            rewrites.append((r, target, paraStyle))
        }
        guard !rewrites.isEmpty else { return }

        storage?.beginEditing()
        for (r, font, paraStyle) in rewrites {
            storage?.addAttribute(.font, value: font, range: r)
            storage?.addAttribute(.paragraphStyle, value: paraStyle, range: r)
        }
        storage?.endEditing()
        textView.typingAttributes[.font] = NSFont.systemFont(ofSize: ReviewRichEditor.bodyPt)
        textView.typingAttributes[.paragraphStyle] = ReviewRichEditor.bodyParagraphStyle
    }

    /// 该字号是否为编辑器规范字号（正文/列表 15、副标题 16、标题2 18、标题1 22）。
    private static func isKnownSize(_ s: CGFloat) -> Bool { s == 15 || s == 16 || s == 18 || s == 22 }

    /// 读取某 run 所在段落的 kind 与段落样式。
    private static func paragraphInfo(for attr: NSAttributedString, at loc: Int)
        -> (ReviewRichEditor.Kind, NSParagraphStyle) {
        if let raw = attr.attribute(ReviewRichEditor.kindKey, at: loc, longestEffectiveRange: nil,
                                    in: NSRange(location: 0, length: attr.length)) as? String,
           let kind = ReviewRichEditor.Kind(rawValue: raw) {
            return (kind, ReviewRichEditor.paragraphStyle(for: kind))
        }
        return (.body, ReviewRichEditor.bodyParagraphStyle)
    }

    /// 根据段落 kind 决定该 run 的目标字体（保留原字体的粗/斜 trait）。
    private static func font(for kind: ReviewRichEditor.Kind, base: NSFont) -> NSFont {
        let traits = base.fontDescriptor.symbolicTraits
        let bold = traits.contains(.bold)
        let italic = traits.contains(.italic)
        return ReviewRichEditor.displayFont(for: kind, bold: bold, italic: italic)
    }

    private func updateIsEmpty() {
        isEmpty = (textView?.string ?? "").isEmpty
    }

    // MARK: 输入前兜底（真键盘路径）

    /// 富文本模式下 NSTextView 有时会把直接输入的字体重置回系统默认（约 13pt），
    /// 导致「什么都不点直打」看起来比「正文 / 列表」小。这里在每次真实输入前，
    /// 根据插入点前一字符的字号把 typingAttributes 校准回规范：
    /// 正文/列表/空档 → 正文（15pt）；标题段 → 继承该标题字号，保证任何位置直打都一致。
    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                  replacementString: String?) -> Bool {
        // 删除 / 非输入回调不干扰。
        guard replacementString != nil else { return true }
        guard !textView.isRichText || affectedCharRange.length == 0 else { return true }

        let ns = textView.attributedString() as NSAttributedString
        let loc = affectedCharRange.location
        let previousPointSize = (loc > 0 && loc <= ns.length)
            ? (ns.attribute(.font, at: loc - 1, effectiveRange: nil) as? NSFont)?.pointSize
            : nil

        switch previousPointSize {
        case 22, 18, 16:
            // 在标题段落里继续打：继承该标题字号并保持粗体。
            let size = previousPointSize!
            textView.typingAttributes[.font] = NSFont.boldSystemFont(ofSize: size)
        case 15:
            // 在正文 / 列表里继续打：已是规范字号，显式重设以防被重置。
            textView.typingAttributes[.font] = NSFont.systemFont(ofSize: ReviewRichEditor.bodyPt)
        default:
            // 文档开头 / 空档 / 意外默认字号：统一回正文。
            textView.typingAttributes[.font] = NSFont.systemFont(ofSize: ReviewRichEditor.bodyPt)
        }
        textView.typingAttributes[.paragraphStyle] = ReviewRichEditor.bodyParagraphStyle
        textView.typingAttributes[.foregroundColor] = NSColor.labelColor
        #if DEBUG
        Self.debug("shouldChange loc=\(loc) prev=\(String(describing: previousPointSize)) setTyping=\((textView.typingAttributes[.font] as? NSFont)?.pointSize ?? -1)")
        #endif
        return true
    }

    /// 临时诊断（DEBUG 构建）：把真实输入路径的字号情况写到 /tmp/gamelog_editor_diag.log。
    private static func debug(_ msg: String) {
        let line = "[\(Date())] \(msg)\n"
        if let h = FileHandle(forWritingAtPath: "/tmp/gamelog_editor_diag.log") {
            h.seekToEndOfFile()
            h.write(line.data(using: .utf8)!)
        } else {
            try? line.data(using: .utf8)?.write(to: URL(fileURLWithPath: "/tmp/gamelog_editor_diag.log"))
        }
    }

    // MARK: 载入 / 读回

    /// 用 Markdown 源码整体重建富文本（打开编辑器时调用）。
    func load(markdown: String) {
        guard let textView else { return }
        let lines = MarkdownRichModel.lines(from: markdown)
        let attr = NSMutableAttributedString()
        for line in lines { ReviewRichEditor.appendLine(line, to: attr) }
        textView.textStorage?.setAttributedString(attr)
        updateIsEmpty()
    }

    /// 当前富文本 → Markdown 源码（保存时调用）。
    var markdown: String {
        guard let textView else { return "" }
        if textView.string.isEmpty { return "" }
        return ReviewRichEditor.markdown(fromRich: textView.attributedString())
    }

    // MARK: 行内样式（加粗 / 斜体）

    func toggleBold() { toggleTrait(.bold) }
    func toggleItalic() { toggleTrait(.italic) }

    private enum Trait: Hashable { case bold, italic
        var symbol: NSFontDescriptor.SymbolicTraits {
            switch self { case .bold: return .bold; case .italic: return .italic }
        }
    }

    private func toggleTrait(_ trait: Trait) {
        guard let textView else { return }
        let selected = textView.selectedRange()
        guard selected.length > 0 else {
            toggleTypingAttributes(trait)
            return
        }
        let storage = textView.textStorage!
        // 是否当前已全为「关」→ 翻成开；否则关
        var anyOn = false
        storage.enumerateAttribute(.font, in: selected, options: []) { value, _, stop in
            if let f = value as? NSFont, f.fontDescriptor.symbolicTraits.contains(trait.symbol) {
                anyOn = true
                stop.pointee = true
            }
        }
        let desired = !anyOn
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: selected, options: []) { value, r, _ in
            let font = value as? NSFont ?? .systemFont(ofSize: ReviewRichEditor.bodyPt)
            let traits = font.fontDescriptor.symbolicTraits
            var nt = traits
            if desired { nt.insert(trait.symbol) } else { nt.remove(trait.symbol) }
            let desc = font.fontDescriptor.withSymbolicTraits(nt)
            let nf = NSFont(descriptor: desc, size: font.pointSize) ?? font
            storage.addAttribute(.font, value: nf, range: r)
        }
        storage.endEditing()
        textView.textStorage?.fixAttributes(in: selected)
    }

    private func toggleTypingAttributes(_ trait: Trait) {
        guard let textView else { return }
        let current = textView.typingAttributes[.font] as? NSFont
        let size = current?.pointSize ?? ReviewRichEditor.bodyPt
        var traits = current?.fontDescriptor.symbolicTraits ?? []
        if traits.contains(trait.symbol) { traits.remove(trait.symbol) } else { traits.insert(trait.symbol) }
        let base = NSFont.systemFont(ofSize: size)
        let desc = base.fontDescriptor.withSymbolicTraits(traits)
        textView.typingAttributes[.font] = NSFont(descriptor: desc, size: size) ?? base
    }

    // MARK: 段落级样式（正文 / 大标题 / 副标题 / 列表）

    func setBody() { setParagraphKind(.body) }
    func setHeading1() { setParagraphKind(.heading1) }
    func setHeading2() { setParagraphKind(.heading2) }
    func setHeading3() { setParagraphKind(.heading3) }
    func toggleList() { setParagraphKind(.list) }

    private func setParagraphKind(_ kind: ReviewRichEditor.Kind) {
        guard let textView else { return }
        let attr = textView.attributedString()
        let ranges = paragraphRanges(in: attr, around: textView.selectedRange())

        let storage = textView.textStorage!
        storage.beginEditing()
        // 从后往前替换，避免 range 位移
        for range in ranges.reversed() {
            let para = attr.attributedSubstring(from: range)
            let line = ReviewRichEditor.line(from: para)
            let rebuilt = ReviewRichEditor.attributedLine(
                MarkdownRichModel.Line(inline: line.inline, kind: ReviewRichEditor.modelKind(from: kind)))
            storage.replaceCharacters(in: range, with: rebuilt)
        }
        storage.endEditing()
        updateIsEmpty()
    }

    /// 找出选区涉及的完整段落 range（含段尾换行）。
    private func paragraphRanges(in attr: NSAttributedString, around sel: NSRange) -> [NSRange] {
        let ns = attr.string as NSString
        var start = sel.location
        while start > 0 && ns.character(at: start - 1) != 0x0A { start -= 1 }
        // 选区末尾：若落在行中部则扩到行尾（不含换行）
        var end = NSMaxRange(sel)
        if end < ns.length && ns.character(at: end) != 0x0A {
            while end < ns.length && ns.character(at: end) != 0x0A { end += 1 }
        }
        return [NSRange(location: start, length: end - start)]
    }
}
#endif
