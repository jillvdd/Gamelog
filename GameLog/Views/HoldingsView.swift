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

    @State private var showingAddVersion = false
    /// 正在编辑 / 待删除的那份持有，**存 ID 不存引用**（项目硬规矩：`@State` 永不持有
    /// `@Model`；判据与理由见 `Game.isLive`）。本页所在详情页背后的整库替换 / 「清空该
    /// 账号导入数据」会**级联删掉** `game.copies`，而这两个 sheet 与确认弹窗可能正开着。
    @State private var editingCopyID: PersistentIdentifier?
    @State private var pendingDeleteCopyID: PersistentIdentifier?
    #if os(macOS)
    /// 持有 Quick Look 协调器强引用（防止面板使用期间被释放），换图/视图消失时自动释放并清理临时文件。
    @State private var quickLook: QuickLookCoordinator?
    #else
    /// iOS 照片预览（QLPreviewController sheet）用的临时文件 URL。
    @State private var previewItem: PhotoPreviewItem?
    #endif

    /// 按添加先后排序。
    ///
    /// 先滤掉已销毁的：整库替换 / 清空导入数据会级联删掉 `game.copies`，而 SwiftUI 可能
    /// 拿旧数组再渲染一帧 —— 本页的每个格子都会读 `copy.version` / `copy.images`，
    /// 那是 `Fatal error: This backing data was detached`（判据见 `Game.isLive`）。
    private var sortedCopies: [PhysicalCopy] {
        game.copies.filter(\.isLive).sorted { $0.createdAt < $1.createdAt }
    }

    /// 待删除的那份（按 ID 反查，找不到 = 已经不在了）。
    private var pendingDeleteCopy: PhysicalCopy? {
        guard let id = pendingDeleteCopyID else { return nil }
        return sortedCopies.first { $0.persistentModelID == id }
    }

    /// 四格汇总：唯一归属 LibraryStats（全库/按游戏同一份口径）。
    private var collectorTotals: LibraryStats.CollectorTotals {
        LibraryStats.collectorTotals(sortedCopies, language: language)
    }
    private var editionCount: Int { collectorTotals.editionCount }
    private var totalQuantity: Int { collectorTotals.totalQuantity }
    private var totalSpent: Double? { collectorTotals.totalSpent }
    private var totalEstimate: Double? { collectorTotals.totalEstimate }

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
                //
                // 选中列**派生自 `useGridView`**，不另存独立状态 —— 照 `DetailStatusPicker`
                // 那条口径（GameDetailView 里写明了「不另存独立状态」）。旧版另存了一份
                // `gridSliderIndex` 且只在 onAppear 同步一次：任何绕过这两个按钮的写入
                // （同步恢复、其他端改同一键、@AppStorage 外部变更）都会让高亮停在错误一侧。
                GeometryReader { geo in
                    let sliderIndex = useGridView ? 0 : 1
                    let cellWidth = geo.size.width / 2
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(SurfaceStyle.segmentHighlight)
                            .overlay(
                                RoundedRectangle(cornerRadius: 9)
                                    .strokeBorder(SurfaceStyle.segmentTrack, lineWidth: 1)
                            )
                            .frame(width: cellWidth, height: geo.size.height)
                            .offset(x: CGFloat(sliderIndex) * cellWidth)
                            .animation(SurfaceStyle.segmentSpring, value: sliderIndex)
                        HStack(spacing: 0) {
                            Button {
                                useGridView = true
                            } label: {
                                Image(systemName: "square.grid.2x2")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(useGridView ? Color.accentColor : Color.secondary)
                                    .frame(width: cellWidth, height: geo.size.height)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PressFeedbackButtonStyle(pressedScale: 0.9, pressedOpacity: 0.55))
                            Button {
                                useGridView = false
                            } label: {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(!useGridView ? Color.accentColor : Color.secondary)
                                    .frame(width: cellWidth, height: geo.size.height)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PressFeedbackButtonStyle(pressedScale: 0.9, pressedOpacity: 0.55))
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
        .sheet(isPresented: $showingAddVersion) {
            CopyEditSheet(game: game, copy: nil)
        }
        .sheet(item: $editingCopyID) { id in
            // 每帧反查（判据同 `editingCopyID`）：找不到就画空，不碰已销毁对象。
            if let copy = sortedCopies.first(where: { $0.persistentModelID == id }) {
                CopyEditSheet(game: game, copy: copy)
            } else {
                Color.clear
            }
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
        // 整库替换（备份导入 / 自动备份恢复 / 「清空该账号导入数据」）后，`game.copies`
        // 会被级联删掉，而本页可能还开着编辑/删除确认。清掉这两个持有旧对象的 state，
        // 与同族消费页（LibraryView / StatsView / RootView）同一条纪律。
        .onReceive(NotificationCenter.default.publisher(for: UserCustomization.libraryReplacedNotification)) { _ in
            editingCopyID = nil
            pendingDeleteCopyID = nil
        }
        .platformConfirmDialog(
            L10n.tr("common.confirmDelete", lang: language),
            isPresented: Binding(
                get: { pendingDeleteCopyID != nil },
                set: { if !$0 { pendingDeleteCopyID = nil } }
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
                    // 用 ID 反查而不是直接删 `pendingDeleteCopy`：确认弹窗可能在整库替换
                    // 之后才被点掉，那一刻旧对象已经是死模型（见 `pendingDeleteCopyID`）。
                    if let id = pendingDeleteCopyID,
                       let copy = sortedCopies.first(where: { $0.persistentModelID == id }) {
                        context.delete(copy)
                        try? context.save()
                    }
                    pendingDeleteCopyID = nil
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
        .appCardSurface()
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
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 16, alignment: .top)], spacing: 16) {
            ForEach(sortedCopies) { copy in
                CopyGridCellView(
                    copy: copy,
                    onEdit: { editingCopyID = copy.persistentModelID },
                    onDelete: { pendingDeleteCopyID = copy.persistentModelID },
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
                    onEdit: { editingCopyID = copy.persistentModelID },
                    onDelete: { pendingDeleteCopyID = copy.persistentModelID },
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
    /// macOS 照片图库选择器开关（photoLibraryPicker 在 iOS 为 no-op，状态无害）。
    @State private var showPhotoLibrary = false

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
        .appCardSurface()
        .overlay(RoundedRectangle(cornerRadius: SurfaceStyle.cardRadius).stroke(Color.semantic(.separator)))
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
        .photoLibraryPicker(
            isPresented: $showPhotoLibrary,
            maxSelectionCount: max(1, 6 - copy.images.count),
            onImages: processImages
        )
    }

    /// 首图方格（固定 1:1，用 §4.22 的安全图案：Color.clear 占位确定尺寸 + overlay Image 覆盖裁剪，
    /// 避免 Image 自带比例撑高单元格导致与相邻卡片重叠）。
    private var thumbnailGrid: some View {
        Color.clear
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay {
                if let data = firstImage, let image = AppImage(data: data) {
                    // 按钮化：按压反馈（原 onTapGesture 无视觉响应）。
                    Button {
                        onEnlarge(data)
                    } label: {
                        Image(appImage: image)
                            .resizable()
                            .scaledToFill()
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressFeedbackButtonStyle(pressedScale: 0.96))
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
        // 加图来源二选一菜单：照片图库 / 文件（与 iOS 底部菜单同思路，macOS 用下拉 Menu 呈现）。
        // menuStyle(.button) 呈现为原 bordered 小按钮观感（Menu 不吃 .buttonStyle，此前漏挂会退回裸文字）。
        Menu {
            Button(L10n.tr("image.photoLibrary", lang: language)) { showPhotoLibrary = true }
            Button(L10n.tr("image.fromFiles", lang: language)) { pickImages() }
        } label: {
            Label(L10n.tr("copy.addImage", lang: language), systemImage: "plus")
                .font(.system(size: 12))
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .menuIndicator(.hidden)
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
        ImageImport.importCollectionPhotos(into: copy, keepOriginal: keepOriginal, context: context)
    }

    private func removeImage(at index: Int) {
        guard index < copy.images.count else { return }
        var images = copy.images
        images.remove(at: index)
        copy.images = images
        ImageDecodeCache.bump()
        try? context.save()
    }

    private func processImages(_ datas: [Data]) {
        ImageImport.appendCollectionPhotos(datas: datas, into: copy, keepOriginal: keepOriginal, context: context)
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
    /// macOS 照片图库选择器开关（photoLibraryPicker 在 iOS 为 no-op，状态无害）。
    @State private var showPhotoLibrary = false

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
                // 身份用**数据本身**（`Data` 本来就 Hashable），不用下标 —— 用下标时删掉
                // 第一张，后面所有格子的身份都会平移，`ThumbnailView` 的 `@State hovering`
                // 于是落到错误的格子上（悬停高亮显示在隔壁照片上）。
                ForEach(copy.images, id: \.self) { data in
                    ThumbnailView(
                        data: data,
                        onDelete: { pendingDeleteImage = copy.images.firstIndex(of: data) },
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
        .appCardSurface()
        .overlay(RoundedRectangle(cornerRadius: SurfaceStyle.cardRadius).stroke(Color.semantic(.separator)))
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
        .photoLibraryPicker(
            isPresented: $showPhotoLibrary,
            maxSelectionCount: max(1, 6 - copy.images.count),
            onImages: processImages
        )
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
                    // 用户自由备注按原样显示；走 LText 会把备注内容当本地化 key 查表，
                    // 备注恰好命中某个 key（如 common.cancel）时会显示翻译文案而非原文。
                    Text(verbatim: copy.notes)
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
        // 加图来源二选一菜单：照片图库 / 文件。borderlessButton 菜单样式让 label（虚线方格）外观不变。
        Menu {
            Button(L10n.tr("image.photoLibrary", lang: language)) { showPhotoLibrary = true }
            Button(L10n.tr("image.fromFiles", lang: language)) { pickImages() }
        } label: {
            addImageLabel
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(copy.images.count >= 6)
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
        ImageImport.importCollectionPhotos(into: copy, keepOriginal: keepOriginal, context: context)
    }

    private func removeImage(at index: Int) {
        guard index < copy.images.count else { return }
        var images = copy.images
        images.remove(at: index)
        copy.images = images
        ImageDecodeCache.bump()
        try? context.save()
    }

    private func processImages(_ datas: [Data]) {
        ImageImport.appendCollectionPhotos(datas: datas, into: copy, keepOriginal: keepOriginal, context: context)
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
        // 按钮化：按压反馈（原 onTapGesture 无视觉响应）；× 删除角标是嵌套按钮，点按以内层为准。
        Button {
            onEnlarge()
        } label: {
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
            .contentShape(Rectangle())
        }
        .buttonStyle(PressFeedbackButtonStyle(pressedScale: 0.96))
        #if os(macOS)
        .onHover { hovering = $0 }
        #endif
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
        // 回填保留原值精度（%.0f 会把 199.5 四舍五入成 "200"，直接点保存就无声改了库里的价格）。
        _priceText = State(initialValue: copy?.price(for: lang).map(Self.priceText) ?? "")
        _estValueText = State(initialValue: copy?.estValue(for: lang).map(Self.priceText) ?? "")
        _hasPurchaseDate = State(initialValue: copy?.purchaseDate != nil)
        _purchaseDate = State(initialValue: copy?.purchaseDate ?? Date())
        _notes = State(initialValue: copy?.notes ?? "")
    }

    /// 价格回填文本：整数不带小数点，小数保留原值（价格来自用户输入解析，无二进制噪声）。
    private static func priceText(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
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
