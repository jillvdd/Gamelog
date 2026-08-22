import SwiftUI
import SwiftData

#if os(macOS)
import AppKit
import UniformTypeIdentifiers
import Quartz
#else
import PhotosUI
import QuickLook
#endif

#if os(macOS)
/// Quick Look 预览协调器：把收藏照片写入临时文件，交给系统 Quick Look 面板显示（原生缩放/平移/旋转/全屏）。
/// 持有强引用直到面板用完；deinit 清理临时文件。
final class QuickLookCoordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private let url: URL

    init(url: URL) {
        self.url = url
        super.init()
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        url as NSURL
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
}
#endif

/// 持有记录内联内容（收藏家模式，详情页「持有」滑块下内联铺在信息下方）：
/// 藏品档案：网格 / 列表双视图、顶部总览、单份实体档案（介质 / 版本区分 / 品相 / 来源 / 价格 / 估值 / 购买日 / 备注）。
/// 不再自带 ScrollView（由详情页统一滚动承载），避免嵌套滚动 + §29.9 的 hover 布局递归。
struct HoldingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    let game: Game

    /// 网格 / 列表双视图（跨会话记忆，同 Library）。
    @AppStorage(UserCustomization.useHoldingsGridViewKey) private var useGridView = true
    /// 网格/列表滑块当前列（内部状态驱动，点击即时动画，不依赖父视图重算）。
    @State private var gridSliderIndex: Int = 0

    @State private var showingAddVersion = false
    @State private var editingCopy: PhysicalCopy?
    @State private var pendingDeleteCopy: PhysicalCopy?
    #if os(macOS)
    /// 持有 Quick Look 协调器强引用（防止面板使用期间被释放），换图/视图消失时自动释放并清理临时文件。
    @State private var quickLook: QuickLookCoordinator?
    #else
    /// iOS 照片预览（QLPreviewController sheet）用的临时文件 URL。
    @State private var previewItem: PhotoPreviewItem?
    #endif

    /// 按添加先后排序。
    private var sortedCopies: [PhysicalCopy] {
        game.copies.sorted { $0.createdAt < $1.createdAt }
    }

    /// 版本数（去重版本名）。
    private var editionCount: Int { sortedCopies.count }
    /// 总数量。
    private var totalQuantity: Int { sortedCopies.reduce(0) { $0 + $1.count } }
    /// 总花费（按当前语言，缺值忽略）。
    private var totalSpent: Double? {
        let vals = sortedCopies.compactMap { $0.price(for: language) }
        return vals.isEmpty ? nil : vals.reduce(0, +)
    }
    /// 总估值（按当前语言，缺值忽略）。
    private var totalEstimate: Double? {
        let vals = sortedCopies.compactMap { $0.estValue(for: language) }
        return vals.isEmpty ? nil : vals.reduce(0, +)
    }

    /// 用系统 Quick Look 查看一张收藏照片（原生缩放/平移/旋转/全屏）。
    private func showQuickLook(_ data: Data) {
        #if os(macOS)
        let url = Self.writeTempImage(data)
        let coordinator = QuickLookCoordinator(url: url)
        quickLook = coordinator
        let panel = QLPreviewPanel.shared()
        panel?.dataSource = coordinator
        panel?.delegate = coordinator
        panel?.reloadData()
        panel?.makeKeyAndOrderFront(nil)
        #else
        // iOS：用 QLPreviewController 全屏查看。
        previewItem = PhotoPreviewItem(url: Self.writeTempImage(data))
        #endif
    }

    /// 图片数据 → 临时文件（按 PNG magic 判断扩展名，其余按 JPEG）。
    private static func writeTempImage(_ data: Data) -> URL {
        let ext: String
        if data.starts(with: Data([0x89, 0x50, 0x4E, 0x47])) { ext = "png" } else { ext = "jpg" }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gamelog_preview_\(UUID().uuidString).\(ext)")
        try? data.write(to: url)
        return url
    }

    var body: some View {
        // 内联内容（详情页统一 ScrollView 承载）：标题 + 视图切换 + 总览 + 网格/列表。
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                LText("detail.holdings")
                    .font(.title3.bold())
                Text(verbatim: "(\(game.copies.count))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                // 网格/列表液态玻璃滑块（与详情|持有滑块同视觉：.thinMaterial 底 + accent 滑块 + spring 动画）。
                GeometryReader { geo in
                    let isGrid = useGridView
                    let cellWidth = geo.size.width / 2
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(Color.accentColor.opacity(0.18))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9)
                                    .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1)
                            )
                            .frame(width: cellWidth, height: geo.size.height)
                            .offset(x: CGFloat(gridSliderIndex) * cellWidth)
                            .animation(.spring(response: 0.3, dampingFraction: 0.78), value: gridSliderIndex)
                        HStack(spacing: 0) {
                            Button {
                                guard !useGridView else { return }
                                gridSliderIndex = 0
                                useGridView = true
                            } label: {
                                Image(systemName: "square.grid.2x2")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(useGridView ? Color.accentColor : Color.secondary)
                                    .frame(width: cellWidth, height: geo.size.height)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Button {
                                guard useGridView else { return }
                                gridSliderIndex = 1
                                useGridView = false
                            } label: {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(!useGridView ? Color.accentColor : Color.secondary)
                                    .frame(width: cellWidth, height: geo.size.height)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(width: 90, height: 44)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.thinMaterial)
                }
                Button {
                    showingAddVersion = true
                } label: {
                    Label(L10n.tr("copy.addShort", lang: language), systemImage: "plus.circle")
                }
            }

            overviewBar

            if sortedCopies.isEmpty {
                LText("copy.noArchive")
                    .foregroundStyle(.secondary)
            } else if useGridView {
                gridModeContent
            } else {
                listModeContent
            }
        }
        .onAppear { gridSliderIndex = useGridView ? 0 : 1 }
        .sheet(isPresented: $showingAddVersion) {
            CopyEditSheet(game: game, copy: nil)
        }
        .sheet(item: $editingCopy) { copy in
            CopyEditSheet(game: game, copy: copy)
        }
        #if !os(macOS)
        .sheet(item: $previewItem) { item in
            PhotoPreviewController(url: item.url)
                .ignoresSafeArea()
                .onDisappear {
                    try? FileManager.default.removeItem(at: item.url)
                }
        }
        #endif
        .platformConfirmDialog(
            L10n.tr("common.confirmDelete", lang: language),
            isPresented: Binding(
                get: { pendingDeleteCopy != nil },
                set: { if !$0 { pendingDeleteCopy = nil } }
            ),
            message: pendingDeleteCopy.map {
                L10n.tr("copy.deleteConfirm", [$0.version], lang: language)
            },
            cancelTitle: L10n.tr("common.cancel", lang: language),
            actions: [
                ConfirmAction(
                    title: L10n.tr("common.delete", lang: language),
                    isDestructive: true
                ) {
                    if let copy = pendingDeleteCopy {
                        context.delete(copy)
                        try? context.save()
                    }
                    pendingDeleteCopy = nil
                }
            ]
        )
    }

    /// 顶部总览条：版本数 / 总数量 / 总花费 / 总估值四格。
    private var overviewBar: some View {
        // 四项统计用 spacing 区隔，不画分割条。
        HStack(spacing: 24) {
            overviewCell(value: "\(editionCount)", label: L10n.tr("copy.overviewEditions", lang: language))
            overviewCell(value: "\(totalQuantity)", label: L10n.tr("copy.overviewQuantity", lang: language))
            overviewCell(value: PriceFormat.string(totalSpent, language: language) ?? "—", label: L10n.tr("copy.overviewSpent", lang: language))
            overviewCell(value: PriceFormat.string(totalEstimate, language: language) ?? "—", label: L10n.tr("copy.overviewEstimate", lang: language))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.semantic(.controlBackground)))
    }

    private func overviewCell(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: value)
                .font(.system(size: 22, weight: .bold))
                .monospacedDigit()
            Text(verbatim: label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 网格视图：首图当主视觉 + 余下 +N 角标。
    private var gridModeContent: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 16)], spacing: 16) {
            ForEach(sortedCopies) { copy in
                CopyGridCellView(
                    copy: copy,
                    onEdit: { editingCopy = copy },
                    onDelete: { pendingDeleteCopy = copy },
                    onEnlarge: showQuickLook
                )
            }
        }
    }

    /// 列表视图：档案列表。
    private var listModeContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(sortedCopies) { copy in
                CopyCardView(
                    copy: copy,
                    onEdit: { editingCopy = copy },
                    onDelete: { pendingDeleteCopy = copy },
                    onEnlarge: showQuickLook
                )
            }
        }
    }
}

/// 网格单元：首图当主视觉（固定方格，1:1），余下 +N 角标 + 版本名×数量 + 介质/版本区分/品相胶囊 + 价格 + 编辑/加图/删除。
private struct CopyGridCellView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    @AppStorage(UserCustomization.keepOriginalImagesKey) private var keepOriginal = false
    let copy: PhysicalCopy
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}
    var onEnlarge: (Data) -> Void = { _ in }
    /// 待删除照片的下标（非 nil 时弹确认，防止误触）。
    @State private var pendingDeleteImage: Int?
    #if !os(macOS)
    @State private var showImageSource = false
    #endif

    private var firstImage: Data? { copy.images.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 首图主视觉（固定 1:1 方格）。
            ZStack(alignment: .topTrailing) {
                thumbnailGrid
                HStack(spacing: 6) {
                    if copy.images.count > 1 {
                        Text(verbatim: "+\(copy.images.count - 1)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(.thinMaterial))
                    }
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundStyle(.red)
                            .padding(6)
                            .background(Capsule().fill(.thinMaterial))
                    }
                    .buttonStyle(.plain)
                    #if !os(macOS)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
                    #endif
                }
                .padding(8)
            }

            // 版本名 × 数量。
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: copy.version)
                    .font(.headline)
                    .lineLimit(1)
                Text(verbatim: "×\(copy.count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
            }

            // 介质 / 版本区分 / 品相 / 来源 横排胶囊。
            WrappingLayout(spacing: 8) {
                capsule(L10n.tr(copy.media.labelKey, lang: language))
                capsule(L10n.tr(copy.regional.labelKey, lang: language))
                if copy.hasCondition {
                    capsule(L10n.tr(copy.condition.labelKey, lang: language))
                }
                capsule(L10n.tr(copy.acquisition.labelKey, lang: language))
                if !copy.platform.isEmpty {
                    platformCapsule(copy.platform, language: language)
                }
            }
            .padding(.leading, -2)

            // 价格。
            if let price = copy.price(for: language) {
                Text(verbatim: PriceFormat.string(price, language: language) ?? "")
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
            }

            HStack(spacing: 8) {
                Button(L10n.tr("copy.editArchive", lang: language)) { onEdit() }
                    .font(.system(size: 12))
                #if os(macOS)
                .buttonStyle(.bordered)
                .controlSize(.small)
                #else
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                #endif
                addImageButton
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.semantic(.controlBackground)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.semantic(.separator)))
        .platformConfirmDialog(
            L10n.tr("common.confirmDelete", lang: language),
            isPresented: Binding(
                get: { pendingDeleteImage != nil },
                set: { if !$0 { pendingDeleteImage = nil } }
            ),
            message: L10n.tr("copy.deleteImageConfirm", lang: language),
            cancelTitle: L10n.tr("common.cancel", lang: language),
            actions: [
                ConfirmAction(
                    title: L10n.tr("common.delete", lang: language),
                    isDestructive: true
                ) {
                    if let index = pendingDeleteImage { removeImage(at: index) }
                    pendingDeleteImage = nil
                }
            ]
        )
        #if !os(macOS)
        .imageSourcePicker(
            isPresented: $showImageSource,
            maxSelectionCount: max(1, 6 - copy.images.count),
            onImages: processImages
        )
        #endif
    }

    /// 首图方格（固定 1:1，用 §4.22 的安全图案：Color.clear 占位确定尺寸 + overlay Image 覆盖裁剪，
    /// 避免 Image 自带比例撑高单元格导致与相邻卡片重叠）。
    private var thumbnailGrid: some View {
        Color.clear
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay {
                if let data = firstImage, let image = AppImage(data: data) {
                    Image(appImage: image)
                        .resizable()
                        .scaledToFill()
                        .onTapGesture { onEnlarge(data) }
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(Color.semantic(.quaternarySystemFill))
                        Image(systemName: "photo")
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var addImageButton: some View {
        #if os(macOS)
        Button { pickImages() } label: {
            Label(L10n.tr("copy.addImage", lang: language), systemImage: "plus")
                .font(.system(size: 12))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(copy.images.count >= 6)
        #else
        Button { showImageSource = true } label: {
            Label(L10n.tr("copy.addImage", lang: language), systemImage: "plus")
                .font(.system(size: 12))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(copy.images.count >= 6)
        #endif
    }

    private func pickImages() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.prompt = L10n.tr("copy.addImage", lang: language)
        guard panel.runModal() == .OK else { return }
        let remaining = 6 - copy.images.count
        guard remaining > 0 else { return }
        let datas = panel.urls.prefix(remaining).compactMap {
            UserCustomization.collectionImageData(from: $0, keepOriginal: keepOriginal)
        }
        guard !datas.isEmpty else { return }
        var images = copy.images
        images.append(contentsOf: datas)
        copy.images = images
        try? context.save()
        #endif
    }

    private func removeImage(at index: Int) {
        guard index < copy.images.count else { return }
        var images = copy.images
        images.remove(at: index)
        copy.images = images
        try? context.save()
    }

    private func processImages(_ datas: [Data]) {
        var images = copy.images
        for data in datas {
            guard images.count < 6 else { break }
            if let processed = UserCustomization.collectionImageData(from: data, keepOriginal: keepOriginal) {
                images.append(processed)
            }
        }
        copy.images = images
        try? context.save()
    }
}

/// 单个版本档案卡片（列表视图）：版本名×数量 + 档案信息区 + 照片网格。
private struct CopyCardView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    @AppStorage(UserCustomization.keepOriginalImagesKey) private var keepOriginal = false
    let copy: PhysicalCopy
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}
    var onEnlarge: (Data) -> Void = { _ in }
    @State private var pendingDeleteImage: Int?
    #if !os(macOS)
    @State private var showImageSource = false
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(verbatim: copy.version)
                    .font(.headline)
                    #if os(macOS)
                    .lineLimit(1)
                    #else
                    .lineLimit(2)
                    #endif
                Text(verbatim: "×\(copy.count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                #if !os(macOS)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
                #endif
                .help(L10n.tr("common.edit", lang: language))
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                #if !os(macOS)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
                #endif
                .foregroundStyle(.red)
                .help(L10n.tr("common.delete", lang: language))
            }

            // 档案信息区：标签字号刻意大于版本名标题（§29.10）。
            archiveInfoSection

            // 照片网格（含删除 / 放大 / 添加）。
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                ForEach(Array(copy.images.enumerated()), id: \.offset) { index, data in
                    ThumbnailView(
                        data: data,
                        onDelete: { pendingDeleteImage = index },
                        onEnlarge: { onEnlarge(data) }
                    )
                }
                if copy.images.count < 6 {
                    addImageButton
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.semantic(.controlBackground)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.semantic(.separator)))
        .platformConfirmDialog(
            L10n.tr("common.confirmDelete", lang: language),
            isPresented: Binding(
                get: { pendingDeleteImage != nil },
                set: { if !$0 { pendingDeleteImage = nil } }
            ),
            message: L10n.tr("copy.deleteImageConfirm", lang: language),
            cancelTitle: L10n.tr("common.cancel", lang: language),
            actions: [
                ConfirmAction(
                    title: L10n.tr("common.delete", lang: language),
                    isDestructive: true
                ) {
                    if let index = pendingDeleteImage { removeImage(at: index) }
                    pendingDeleteImage = nil
                }
            ]
        )
        #if !os(macOS)
        .imageSourcePicker(
            isPresented: $showImageSource,
            maxSelectionCount: max(1, 6 - copy.images.count),
            onImages: processImages
        )
        #endif
    }

    /// 档案信息区：介质 → 版本区分 → 品相（仅实体）→ 来源 → 购买日 + 备注。
    /// 标签字号 .title3.weight(.semibold)（约 20pt）> 版本名 .headline（约 17pt），弱化标题、突出档案。
    private var archiveInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 介质 / 版本区分 / 品相 / 来源 横排胶囊（与网格单元格同款）。
            WrappingLayout(spacing: 8) {
                capsule(L10n.tr(copy.media.labelKey, lang: language))
                capsule(L10n.tr(copy.regional.labelKey, lang: language))
                if copy.hasCondition {
                    capsule(L10n.tr(copy.condition.labelKey, lang: language))
                }
                capsule(L10n.tr(copy.acquisition.labelKey, lang: language))
                if !copy.platform.isEmpty {
                    platformCapsule(copy.platform, language: language)
                }
            }
            .padding(.leading, -2)
            if let date = copy.purchaseDate {
                archiveRow(label: L10n.tr("copy.purchaseDate", lang: language),
                            value: date.formatted(date: .abbreviated, time: .omitted))
            }
            // 价格 / 估值 横向左右并列（仅当至少一项存在时显示该行）。
            if copy.price(for: language) != nil || copy.estValue(for: language) != nil {
                HStack(alignment: .firstTextBaseline, spacing: 24) {
                    if let price = copy.price(for: language) {
                        archiveRow(label: L10n.tr("copy.price", lang: language),
                                    value: PriceFormat.string(price, language: language) ?? "")
                    }
                    if let est = copy.estValue(for: language) {
                        archiveRow(label: L10n.tr("copy.estValue", lang: language),
                                    value: PriceFormat.string(est, language: language) ?? "")
                    }
                    Spacer()
                }
            }
            if !copy.notes.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    LText(copy.notes)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func archiveRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: label)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 64, alignment: .leading)
            Text(verbatim: value)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var addImageButton: some View {
        #if os(macOS)
        Button { pickImages() } label: { addImageLabel }
            .buttonStyle(.plain)
            .help(L10n.tr("copy.addImage", lang: language))
        #else
        Button { showImageSource = true } label: { addImageLabel }
            .buttonStyle(.plain)
        #endif
    }

    private var addImageLabel: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .medium))
                    Text(verbatim: "\(copy.images.count)/6")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.semantic(.quaternarySystemFill)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4])).foregroundStyle(.tertiary))
    }

    private func pickImages() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.prompt = L10n.tr("copy.addImage", lang: language)
        guard panel.runModal() == .OK else { return }
        let remaining = 6 - copy.images.count
        guard remaining > 0 else { return }
        let datas = panel.urls.prefix(remaining).compactMap {
            UserCustomization.collectionImageData(from: $0, keepOriginal: keepOriginal)
        }
        guard !datas.isEmpty else { return }
        var images = copy.images
        images.append(contentsOf: datas)
        copy.images = images
        try? context.save()
        #endif
    }

    private func removeImage(at index: Int) {
        guard index < copy.images.count else { return }
        var images = copy.images
        images.remove(at: index)
        copy.images = images
        try? context.save()
    }

    private func processImages(_ datas: [Data]) {
        var images = copy.images
        for data in datas {
            guard images.count < 6 else { break }
            if let processed = UserCustomization.collectionImageData(from: data, keepOriginal: keepOriginal) {
                images.append(processed)
            }
        }
        copy.images = images
        try? context.save()
    }
}

/// 单张缩略图：悬停显示 × 可删，点击放大。固定 1:1 方格。
private struct ThumbnailView: View {
    @Environment(\.appLanguageCode) private var language
    let data: Data
    var onDelete: () -> Void = {}
    var onEnlarge: () -> Void = {}
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let image = AppImage(data: data) {
                        Image(appImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle().fill(Color.semantic(.quaternarySystemFill))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Group {
                #if os(macOS)
                if hovering {
                    deleteBadge.transition(.opacity)
                }
                #else
                deleteBadge
                #endif
            }
        }
        #if os(macOS)
        .onHover { hovering = $0 }
        #endif
        .onTapGesture(perform: onEnlarge)
        .help(L10n.tr("copy.viewImage", lang: language))
    }

    private var deleteBadge: some View {
        Button(action: onDelete) {
            Image(systemName: "xmark.circle.fill")
                #if os(macOS)
                .font(.system(size: 16))
                #else
                .font(.system(size: 20))
                #endif
                .foregroundStyle(.white, .red)
        }
        .buttonStyle(.plain)
        .padding(4)
    }
}

/// 编辑藏品档案弹窗（取代原 RenameCopySheet）：完整档案 + 改名。
struct CopyEditSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    @Environment(\.dismiss) private var dismiss
    let game: Game
    /// nil = 新建，非 nil = 编辑。
    let copy: PhysicalCopy?

    @State private var version: String
    @State private var count = 1
    @State private var media: CopyMedia
    @State private var regional: CopyRegional
    @State private var condition: CopyCondition
    @State private var acquisition: CopyAcquisition
    @State private var platform: String
    @State private var priceText: String
    @State private var estValueText: String
    @State private var hasPurchaseDate = false
    @State private var purchaseDate = Date()
    @State private var notes: String

    init(game: Game, copy: PhysicalCopy?) {
        self.game = game
        self.copy = copy
        let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.chinese.localeCode
        _version = State(initialValue: copy?.version ?? L10n.tr("copy.versionAuto", [game.copies.count + 1], lang: lang))
        _count = State(initialValue: copy?.count ?? 1)
        _media = State(initialValue: copy?.media ?? .physicalStandard)
        _regional = State(initialValue: copy?.regional ?? .jp)
        _condition = State(initialValue: copy?.condition ?? .used)
        _acquisition = State(initialValue: copy?.acquisition ?? .officialChannelOverseas)
        _platform = State(initialValue: (copy?.platform.isEmpty ?? true) ? Presets.platforms[0] : copy!.platform)
        _priceText = State(initialValue: copy?.price(for: lang).map { String(format: "%.0f", $0) } ?? "")
        _estValueText = State(initialValue: copy?.estValue(for: lang).map { String(format: "%.0f", $0) } ?? "")
        _hasPurchaseDate = State(initialValue: copy?.purchaseDate != nil)
        _purchaseDate = State(initialValue: copy?.purchaseDate ?? Date())
        _notes = State(initialValue: copy?.notes ?? "")
    }

    private var trimmed: String { version.trimmingCharacters(in: .whitespaces) }
    private var parsedPrice: Double? {
        let t = priceText.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : Double(t)
    }
    private var parsedEst: Double? {
        let t = estValueText.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : Double(t)
    }

    var body: some View {
        VStack(spacing: 16) {
            LText(copy == nil ? "copy.addArchive" : "copy.editArchive")
                .font(.headline)
            Form {
                Section {
                    LabeledContent(L10n.tr("copy.version", lang: language)) {
                        BorderedTextField(text: $version, placeholder: L10n.tr("copy.versionPlaceholder", lang: language))
                            #if os(macOS)
                            .frame(width: 280)
                            #else
                            .frame(maxWidth: .infinity)
                            #endif
                    }
                    Stepper(value: $count, in: 1...999) {
                        HStack {
                            LText("copy.count")
                            Spacer()
                            Text(verbatim: "\(count)").monospacedDigit()
                        }
                    }
                }
                Section {
                    PresetOrCustomPicker(
                        title: L10n.tr("completion.platform", lang: language),
                        presets: Presets.platforms,
                        category: .platform,
                        collapsible: true,
                        value: $platform
                    )
                }
                Section {
                    EnumPickerRow(title: L10n.tr("copy.media", lang: language),
                                  cases: CopyMedia.allCases,
                                  selection: $media,
                                  language: language)
                    if media.isPhysical {
                        EnumPickerRow(title: L10n.tr("copy.condition", lang: language),
                                      cases: CopyCondition.allCases,
                                      selection: $condition,
                                      language: language)
                    }
                }
                Section {
                    EnumPickerRow(title: L10n.tr("copy.regional", lang: language),
                                  cases: CopyRegional.allCases,
                                  selection: $regional,
                                  language: language)
                }
                Section {
                    EnumPickerRow(title: L10n.tr("copy.acquisition", lang: language),
                                  cases: CopyAcquisition.allCases,
                                  selection: $acquisition,
                                  language: language)
                }
                Section {
                    LabeledContent(L10n.tr("copy.price", lang: language)) {
                        BorderedTextField(text: $priceText, placeholder: "0")
                            #if os(macOS)
                            .frame(width: 140)
                            #else
                            .frame(maxWidth: .infinity)
                            #endif
                    }
                    LabeledContent(L10n.tr("copy.estValue", lang: language)) {
                        BorderedTextField(text: $estValueText, placeholder: "0")
                            #if os(macOS)
                            .frame(width: 140)
                            #else
                            .frame(maxWidth: .infinity)
                            #endif
                    }
                }
                Section {
                    Toggle(L10n.tr("copy.purchaseDate", lang: language), isOn: $hasPurchaseDate)
                    if hasPurchaseDate {
                        DateMenuPicker(title: L10n.tr("copy.purchaseDate", lang: language), selection: $purchaseDate)
                    }
                    LabeledContent(L10n.tr("copy.notes", lang: language)) {
                        BorderedTextField(text: $notes, placeholder: L10n.tr("copy.notesPlaceholder", lang: language))
                            #if os(macOS)
                            .frame(width: 280)
                            #else
                            .frame(maxWidth: .infinity)
                            #endif
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Button(L10n.tr("common.cancel", lang: language)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.tr("common.save", lang: language)) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(24)
        #if os(macOS)
        .frame(width: 460)
        #else
        .frame(maxWidth: .infinity)
        #endif
    }

    private func save() {
        let target = copy ?? PhysicalCopy(version: trimmed, count: max(1, count))
        target.version = trimmed
        target.count = max(1, count)
        target.media = media
        target.regional = regional
        target.condition = condition
        target.acquisition = acquisition
        target.platform = platform
        target.setPrice(parsedPrice, for: language)
        target.setEstValue(parsedEst, for: language)
        target.purchaseDate = hasPurchaseDate ? purchaseDate : nil
        target.notes = notes
        if copy == nil {
            target.game = game
            context.insert(target)
        }
        try? context.save()
        dismiss()
    }
}

#if !os(macOS)
/// iOS 照片预览用的临时文件 URL（Identifiable 驱动 sheet）。
struct PhotoPreviewItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// iOS 收藏照片查看：QLPreviewController（原生缩放/分享/全屏）。
struct PhotoPreviewController: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
#endif

/// 档案属性胶囊（介质 / 版本区分 / 品相 / 来源）：统一横排样式，网格与列表视图共用。
fileprivate func capsule(_ text: String) -> some View {
    Text(verbatim: text)
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
        .fixedSize()
        .lineLimit(1)
}

/// 平台胶囊（带平台图标），仅当持有档案填了平台时展示。
fileprivate func platformCapsule(_ platform: String, language: String) -> some View {
    HStack(spacing: 4) {
        PlatformIcon(platform: platform, size: 12)
        Text(verbatim: Presets.display(platform, category: .platform, language: language))
    }
    .font(.system(size: 12))
    .padding(.horizontal, 12)
    .padding(.vertical, 5)
    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
    .fixedSize()
    .lineLimit(1)
}

// MARK: - 自写 WrappingLayout（按内容自适应宽度换行，不用 LazyVGrid(.adaptive) 以免截断长标签）

/// 内容自适应换行布局：子视图按各自固有宽度排布，放不下换到下一行。
/// 取代 `LazyVGrid(.adaptive)`——后者空间不足会压缩单格宽度并截断（`lineLimit(1)` 把「官方渠道海淘」截成「官方渠道…」）。
struct WrappingLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: width, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
