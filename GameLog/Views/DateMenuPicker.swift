import SwiftUI
import AppKit

/// 滚轮单行高度与可见行数（三列共用）。
private let wheelRowHeight: CGFloat = 26
private let wheelVisibleRows = 5

/// 年月日三段滚轮的日期选择器：替代系统 DatePicker 的图形日历。
/// 三列并排（年 / 月 / 日），每列 5 行高、选中项居中吸附，复刻 iOS 日期滚轮的手感：
/// 选中行加粗并放大、相邻行轻微缩小并淡出。日列随年月联动（大小月 / 闰年）。
/// 三语显示（zh「2023年 6月 15日」/ ja 同 / en「2023 Jun 15」）。
struct DateMenuPicker: View {
    let title: String
    @Binding var selection: Date
    /// 年份可选下界（覆盖 FC 时代之前的老游戏发售日）。
    var lowerBoundYear = 1960
    @Environment(\.appLanguageCode) private var language

    @State private var year: Int
    @State private var month: Int
    @State private var day: Int

    init(title: String, selection: Binding<Date>, lowerBoundYear: Int = 1960) {
        self.title = title
        _selection = selection
        self.lowerBoundYear = lowerBoundYear
        let c = Calendar.current.dateComponents([.year, .month, .day], from: selection.wrappedValue)
        _year = State(initialValue: c.year ?? 2000)
        _month = State(initialValue: c.month ?? 1)
        _day = State(initialValue: c.day ?? 1)
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 0) {
                WheelColumn(
                    items: years,
                    width: 80,
                    selection: Binding(get: { year }, set: { setYear($0) }),
                    label: yearLabel
                )
                .frame(width: 80, height: wheelRowHeight * CGFloat(wheelVisibleRows))
                separator
                WheelColumn(
                    items: Array(1...12),
                    width: 56,
                    selection: Binding(get: { month }, set: { setMonth($0) }),
                    label: monthLabel
                )
                .frame(width: 56, height: wheelRowHeight * CGFloat(wheelVisibleRows))
                separator
                WheelColumn(
                    items: Array(1...daysInMonth),
                    width: 56,
                    selection: Binding(get: { day }, set: { setDay($0) }),
                    label: dayLabel
                )
                .frame(width: 56, height: wheelRowHeight * CGFloat(wheelVisibleRows))
            }
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor))
            )
        }
        .onChange(of: selection) { _, newValue in sync(to: newValue) }
    }

    private var calendar: Calendar { .current }

    private var currentYear: Int { calendar.component(.year, from: Date()) }

    /// 年份可选上界：今年 +2（允许预约明年后年的发售日），并动态跟随系统年份，
    /// 2027 年运行时自动扩展到 2029。若当前选中年更晚（导入数据），以其为准。
    private var yearUpper: Int { max(currentYear + 2, year) }

    /// 年份下界：1960 与当前选中年之小者，保证导入的 1950 年老数据也能显示。
    private var yearLower: Int { min(lowerBoundYear, year) }

    /// 年份滚轮全部候选（线性，滚轮内自由滚选）。
    private var years: [Int] { Array(yearLower...yearUpper) }

    /// 段间细竖线分隔（贯穿整个控件高度）。
    private var separator: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .padding(.vertical, 8)
    }

    private func yearLabel(_ y: Int) -> String {
        "\(y)\(L10n.tr("date.year", lang: language))"
    }

    /// 本地化月份名：zh「6月」/ ja「6月」/ en「Jun」。
    private func monthLabel(_ m: Int) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: language)
        fmt.dateFormat = "MMM"
        let base = calendar.date(from: DateComponents(year: 2000, month: m, day: 1)) ?? Date()
        return fmt.string(from: base)
    }

    private func dayLabel(_ d: Int) -> String {
        "\(d)\(L10n.tr("date.day", lang: language))"
    }

    private func setYear(_ y: Int) {
        year = y
        clampDay()
        selection = makeDate()
    }

    private func setMonth(_ m: Int) {
        month = m
        clampDay()
        selection = makeDate()
    }

    private func setDay(_ d: Int) {
        day = d
        selection = makeDate()
    }

    /// 年月变化后若日号超界，钳位到当月最后一天（如 8/31 选到 6 月 → 6/30）。
    private func clampDay() {
        if day > daysInMonth { day = daysInMonth }
    }

    /// 当前选中年月的最大天数（处理大小月与闰年）。
    private var daysInMonth: Int {
        guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: start) else { return 30 }
        return range.count
    }

    /// 用当前年月日 + 原日期时分秒构造新日期。
    private func makeDate() -> Date {
        var comps = calendar.dateComponents([.hour, .minute, .second], from: selection)
        comps.year = year
        comps.month = month
        comps.day = day
        return calendar.date(from: comps) ?? selection
    }

    /// 外部（如编辑时 load()）写入 selection 后回同步三段状态。
    private func sync(to date: Date) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        if let y = c.year, let m = c.month, let d = c.day {
            year = y
            month = m
            day = d
        }
    }
}

/// 单列滚轮：5 行高、选中项居中，滚动吸附到最近一项，复刻 iOS 日期滚轮手感。
/// 基于原生 NSScrollView：
/// - 不创建滚动条（hasVerticalScroller = false），悬停不再出现白色滚动条；
/// - 吸附在滚动结束后（didEndLiveScroll）精确对齐到最近整行，不会跳偏 1–2 行；
/// - 滚到边界后滚动事件沿 AppKit 响应链交给外层页面（原生 scroll chaining）。
private struct WheelColumn: NSViewRepresentable {
    let items: [Int]
    let width: CGFloat
    @Binding var selection: Int
    let label: (Int) -> String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = WheelScrollView()
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.horizontalScrollElasticity = .none
        scroll.verticalScrollElasticity = .none
        scroll.postsBoundsChangedNotifications = true
        scroll.contentView.postsBoundsChangedNotifications = true
        scroll.frame = NSRect(x: 0, y: 0, width: width, height: wheelRowHeight * CGFloat(wheelVisibleRows))

        let doc = WheelDocumentView()
        context.coordinator.attach(scroll: scroll, document: doc)
        scroll.documentView = doc
        updateDocument(doc, in: scroll)
        return scroll
    }

    private func updateDocument(_ doc: WheelDocumentView, in scroll: NSScrollView) {
        doc.label = label
        doc.rowHeight = wheelRowHeight
        doc.items = items
        doc.frame = NSRect(
            x: 0, y: 0,
            width: width,
            height: wheelRowHeight * CGFloat(items.count) + wheelRowHeight * 4
        )
        doc.needsDisplay = true
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let doc = scroll.documentView as? WheelDocumentView else { return }
        if doc.items != items {
            updateDocument(doc, in: scroll)
        } else {
            doc.label = label
        }
        // 外部 selection 变化（clampDay / sync / load）→ 滚动到对应项。
        if let idx = items.firstIndex(of: selection) {
            let target = CGFloat(idx) * wheelRowHeight
            if abs(scroll.contentView.bounds.origin.y - target) > 0.5 {
                scroll.contentView.setBoundsOrigin(NSPoint(x: 0, y: target))
                doc.centerIndex = idx
                doc.needsDisplay = true
            }
        }
    }

    final class Coordinator: NSObject {
        var parent: WheelColumn
        private var scroll: NSScrollView?
        private var document: WheelDocumentView?
        private var boundsObserver: NSObjectProtocol?
        private var liveScrollObserver: NSObjectProtocol?

        init(_ parent: WheelColumn) { self.parent = parent }

        func attach(scroll: NSScrollView, document: WheelDocumentView) {
            self.scroll = scroll
            self.document = document
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scroll.contentView,
                queue: .main
            ) { [weak self] _ in self?.onBoundsChanged() }
            liveScrollObserver = NotificationCenter.default.addObserver(
                forName: NSScrollView.didEndLiveScrollNotification,
                object: scroll,
                queue: .main
            ) { [weak self] _ in self?.snap() }
        }

        /// 实时跟随滚动：更新选中项（视口中心行）并重绘。
        private func onBoundsChanged() {
            guard let scroll, let document else { return }
            let y = scroll.contentView.bounds.origin.y
            let idx = min(max(Int((y / wheelRowHeight).rounded()), 0), parent.items.count - 1)
            document.centerIndex = idx
            document.needsDisplay = true
            let value = parent.items[idx]
            if value != parent.selection {
                parent.selection = value
            }
        }

        /// 滚动结束后瞬时对齐到最近整行（目标偏移 = 行号 × 行高）。
        private func snap() {
            guard let scroll, let document else { return }
            let target = CGFloat(document.centerIndex) * wheelRowHeight
            let current = scroll.contentView.bounds.origin.y
            guard abs(target - current) > 0.5 else { return }
            scroll.contentView.setBoundsOrigin(NSPoint(x: 0, y: target))
        }
    }
}

/// 滚轮专用 NSScrollView：滚到边界后吞掉滚动事件，不传递给外层页面。
/// 用户明确不想要「滚到头自动变成滚页面」——滚轮区域应独占滚动，
/// 要滚动页面需把鼠标移出滚轮区域。
private final class WheelScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        let currentY = contentView.bounds.origin.y
        let maxY = max(0, (documentView?.frame.height ?? 0) - contentView.bounds.height)
        // 已到顶部还继续往上滚，或已到底部还继续往下滚：吞掉事件，不外传。
        if delta > 0 && currentY <= 0.5 { return }
        if delta < 0 && currentY >= maxY - 0.5 { return }
        super.scrollWheel(with: event)
    }
}

/// 滚轮列的行内容：自绘行列表，选中行加粗放大、相邻行缩小淡出。
private final class WheelDocumentView: NSView {
    var items: [Int] = []
    var label: ((Int) -> String)?
    var rowHeight: CGFloat = 26
    var centerIndex = 0

    /// 从上到下布局（配合文本顶部对齐绘制）。
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let label else { return }
        let pad = rowHeight * 2
        let regularFont = NSFont.systemFont(ofSize: 13, weight: .regular)
        let boldFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        for (i, v) in items.enumerated() {
            let distance = abs(i - centerIndex)
            let alpha: CGFloat = distance == 0 ? 1.0 : (distance == 1 ? 0.55 : 0.3)
            let scale: CGFloat = distance == 0 ? 1.0 : 0.9
            let font = distance == 0 ? boldFont : regularFont
            let color = NSColor.labelColor.withAlphaComponent(alpha)
            let str = label(v) as NSString
            let size = str.size(withAttributes: [.font: font])
            let centerX = bounds.width / 2
            let centerY = pad + CGFloat(i) * rowHeight + rowHeight / 2

            NSGraphicsContext.current?.saveGraphicsState()
            let cg = NSGraphicsContext.current!.cgContext
            cg.translateBy(x: centerX, y: centerY)
            cg.scaleBy(x: scale, y: scale)
            str.draw(
                at: NSPoint(x: -size.width / 2, y: -size.height / 2),
                withAttributes: [.font: font, .foregroundColor: color]
            )
            NSGraphicsContext.current?.restoreGraphicsState()
        }
    }
}
