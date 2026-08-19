import SwiftUI

/// 单行输入框：macOS 用 NSTextField 封装（规避 SwiftUI TextField 在 macOS 丢尾随空格 bug），
/// iOS 用系统 TextField。圆角描边由系统控件提供。
struct BorderedTextField: View {
    @Binding var text: String
    var placeholder: String = ""
    var isEnabled: Bool = true
    /// 回车提交回调（macOS 为 NSTextField 的 action；iOS 为键盘提交）。
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        #if os(macOS)
        BorderedTextFieldMac(text: $text, placeholder: placeholder, isEnabled: isEnabled, onSubmit: onSubmit)
        #else
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .disabled(!isEnabled)
            .onSubmit { onSubmit?() }
        #endif
    }
}

/// 带圆角边框的文本编辑框：macOS 用 NSTextView 封装（高度随内容增长、封顶约 20 行后内部滚动），
/// iOS 用系统 TextEditor。圆角背景与描边都在 SwiftUI 层。
struct BorderedTextEditor: View {
    @Binding var text: String
    var minHeight: CGFloat
    var maxHeight: CGFloat
    /// NSTextView 就绪钩子（仅 macOS 有效）。入参需在 macOS 分支 cast 成 NSTextView。
    var onTextViewReady: ((Any) -> Void)?

    init(text: Binding<String>, minHeight: CGFloat, maxHeight: CGFloat? = nil,
         onTextViewReady: ((Any) -> Void)? = nil) {
        self._text = text
        self.minHeight = minHeight
        self.maxHeight = maxHeight ?? Self.defaultMaxHeight
        self.onTextViewReady = onTextViewReady
    }

    /// 约 20 行的最大高度：系统正文字号行高 × 20 + 上下内边距。
    static var defaultMaxHeight: CGFloat {
        #if os(macOS)
        let lineHeight = NSLayoutManager().defaultLineHeight(for: NSFont.systemFont(ofSize: NSFont.systemFontSize))
        return lineHeight * 20 + 12
        #else
        return 320
        #endif
    }

    var body: some View {
        #if os(macOS)
        TextEditorNSView(text: $text, minHeight: minHeight, maxHeight: maxHeight,
                         onTextViewReady: onTextViewReady)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.semantic(.textBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.semantic(.separator))
            )
        #else
        TextEditor(text: $text)
            .frame(minHeight: minHeight, maxHeight: maxHeight)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.semantic(.textBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.semantic(.separator))
            )
        #endif
    }
}

#if os(macOS)
import AppKit

/// 单行输入框（NSTextField 封装）。
/// 规避 macOS SwiftUI TextField 在父视图重渲染时丢失尾随空格的 bug（空格输入不显示、直到下一字符才出现）：
/// 只在外部绑定值真正变化时才回写字段文本，用户输入过程中（绑定已同步、值相同）不重置字段。
struct BorderedTextFieldMac: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var isEnabled: Bool = true
    /// 回车提交回调（NSTextField 的 action，替代可能对 representable 失效的 `.onSubmit`）。
    var onSubmit: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.placeholderString = placeholder
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.usesSingleLineMode = true
        field.isEnabled = isEnabled
        if onSubmit != nil {
            field.target = context.coordinator
            field.action = #selector(Coordinator.commit(_:))
        }
        // 让字段在 Form 行/父级提案下横向撑满（与 SwiftUI TextField 行为一致）。
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        nsView.isEnabled = isEnabled
        // 关键：仅外部值变化才回写，避免输入途中被重置。
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: BorderedTextFieldMac

        init(_ parent: BorderedTextFieldMac) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        @objc func commit(_ sender: NSTextField) {
            parent.text = sender.stringValue
            parent.onSubmit?()
        }
    }
}

/// 透明的 NSTextView 滚动容器，背景由外层 BorderedTextEditor 提供。
private struct TextEditorNSView: NSViewRepresentable {
    @Binding var text: String
    var minHeight: CGFloat
    var maxHeight: CGFloat
    /// 通用钩子：NSTextView 就绪后暴露引用，供外部（如格式工具条）执行插入/选区操作。
    var onTextViewReady: ((NSTextView) -> Void)?

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TextEditorNSView
        weak var textView: NSTextView?
        var frameObservation: NSKeyValueObservation?

        init(_ parent: TextEditorNSView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = AutoGrowScrollView(minHeight: minHeight, maxHeight: maxHeight)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 0, height: 0))
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: minHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.drawsBackground = false
        textView.delegate = context.coordinator

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.hasHorizontalScroller = false

        context.coordinator.textView = textView
        context.coordinator.frameObservation = textView.observe(\.frame, options: [.new]) { [weak scrollView] _, _ in
            scrollView?.invalidateIntrinsicContentSize()
        }
        textView.string = text
        onTextViewReady?(textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        if let scroll = nsView as? AutoGrowScrollView {
            scroll.minHeight = minHeight
            scroll.maxHeight = maxHeight
        }
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            textView.string = text
        }
    }
}

/// 高度随文档内容自适应、封顶 maxHeight 的 NSScrollView。
private final class AutoGrowScrollView: NSScrollView {
    var minHeight: CGFloat
    var maxHeight: CGFloat

    init(minHeight: CGFloat, maxHeight: CGFloat) {
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        let docHeight = documentView?.frame.height ?? 0
        let h = min(maxHeight, max(minHeight, docHeight))
        return NSSize(width: NSView.noIntrinsicMetric, height: h)
    }
}
#endif
