import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers
import Quartz

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

/// 持有记录视图（收藏家模式，详情页「持有」页签）：
/// 版本卡片列表（版本名 + 数量步进器 + 最多 6 张缩略图），新增/改名/删除版本，添加/删除/放大照片。
struct HoldingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    let game: Game

    @State private var showingAddVersion = false
    @State private var renamingCopy: PhysicalCopy?
    @State private var pendingDeleteCopy: PhysicalCopy?
    /// 持有 Quick Look 协调器强引用（防止面板使用期间被释放），换图/视图消失时自动释放并清理临时文件。
    @State private var quickLook: QuickLookCoordinator?

    /// 按添加先后排序。
    private var sortedCopies: [PhysicalCopy] {
        game.copies.sorted { $0.createdAt < $1.createdAt }
    }

    /// 用系统 Quick Look 查看一张收藏照片（原生缩放/平移/旋转/全屏）。
    private func showQuickLook(_ data: Data) {
        let url = Self.writeTempImage(data)
        let coordinator = QuickLookCoordinator(url: url)
        quickLook = coordinator
        let panel = QLPreviewPanel.shared()
        panel?.dataSource = coordinator
        panel?.delegate = coordinator
        panel?.reloadData()
        panel?.makeKeyAndOrderFront(nil)
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                LText("detail.holdings")
                    .font(.title3.bold())
                Text(verbatim: "(\(game.copies.count))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showingAddVersion = true
                } label: {
                    Label(L10n.tr("copy.addVersion", lang: language), systemImage: "plus.circle")
                }
            }

            if sortedCopies.isEmpty {
                LText("copy.noCopies")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedCopies) { copy in
                    CopyCardView(
                        copy: copy,
                        onRename: { renamingCopy = copy },
                        onDelete: { pendingDeleteCopy = copy },
                        onEnlarge: showQuickLook
                    )
                }
            }
        }
        .frame(maxWidth: 1500, alignment: .leading)
        .sheet(isPresented: $showingAddVersion) {
            AddCopySheet(game: game)
        }
        .sheet(item: $renamingCopy) { copy in
            RenameCopySheet(copy: copy)
        }
        .confirmationDialog(
            L10n.tr("common.confirmDelete", lang: language),
            isPresented: Binding(
                get: { pendingDeleteCopy != nil },
                set: { if !$0 { pendingDeleteCopy = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.tr("common.delete", lang: language), role: .destructive) {
                if let copy = pendingDeleteCopy {
                    context.delete(copy)
                    try? context.save()
                }
                pendingDeleteCopy = nil
            }
            Button(L10n.tr("common.cancel", lang: language), role: .cancel) {
                pendingDeleteCopy = nil
            }
        } message: {
            if let copy = pendingDeleteCopy {
                Text(verbatim: L10n.tr("copy.deleteConfirm", [copy.version], lang: language))
            }
        }
    }
}

/// 单个版本卡片：版本名 + 数量步进器 + 3 列缩略图网格（含删除/放大）+「添加图片」。
private struct CopyCardView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    @AppStorage(UserCustomization.keepOriginalImagesKey) private var keepOriginal = false
    let copy: PhysicalCopy
    var onRename: () -> Void = {}
    var onDelete: () -> Void = {}
    var onEnlarge: (Data) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(verbatim: copy.version)
                    .font(.headline)
                    .lineLimit(1)
                quantityControl
                Spacer()
                Button(action: onRename) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help(L10n.tr("common.edit", lang: language))
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .help(L10n.tr("common.delete", lang: language))
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                ForEach(Array(copy.images.enumerated()), id: \.offset) { index, data in
                    ThumbnailView(
                        data: data,
                        onDelete: { removeImage(at: index) },
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
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor))
        )
    }

    /// 数量控件：− ×N +（数字清晰可见，最少 1 份）。
    private var quantityControl: some View {
        HStack(spacing: 4) {
            Button {
                copy.count = max(1, copy.count - 1)
                try? context.save()
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(copy.count <= 1)
            .foregroundStyle(copy.count <= 1 ? .tertiary : .primary)

            Text(verbatim: "×\(copy.count)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.primary)
                .frame(minWidth: 30, alignment: .center)

            Button {
                copy.count += 1
                try? context.save()
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color(nsColor: .quaternarySystemFill)))
        .help(L10n.tr("copy.count", lang: language))
    }

    @ViewBuilder
    private var addImageButton: some View {
        Button {
            pickImages()
        } label: {
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
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .quaternarySystemFill))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                        .foregroundStyle(.tertiary)
                )
        }
        .buttonStyle(.plain)
        .help(L10n.tr("copy.addImage", lang: language))
    }

    private func pickImages() {
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
    }

    private func removeImage(at index: Int) {
        guard index < copy.images.count else { return }
        var images = copy.images
        images.remove(at: index)
        copy.images = images
        try? context.save()
    }
}

/// 单张缩略图：悬停显示 × 可删，点击放大。
/// 用 `Color.clear` 先占 1:1 方格、图片 `scaledToFill` 裁剪填充，避免按原图尺寸溢出网格。
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
                    if let image = NSImage(data: data) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle().fill(Color(nsColor: .quaternarySystemFill))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))

            if hovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white, .red)
                }
                .buttonStyle(.plain)
                .padding(4)
                .transition(.opacity)
            }
        }
        .onHover { hovering = $0 }
        .onTapGesture(perform: onEnlarge)
        .help(L10n.tr("copy.viewImage", lang: language))
    }
}

/// 新增版本弹窗：版本名（必填，预填「版本 N」可改）+ 数量（默认 1）。
private struct AddCopySheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    @Environment(\.dismiss) private var dismiss
    let game: Game
    @State private var version: String
    @State private var count = 1

    init(game: Game) {
        self.game = game
        let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.chinese.localeCode
        _version = State(initialValue: L10n.tr("copy.versionAuto", [game.copies.count + 1], lang: lang))
    }

    private var trimmed: String { version.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 16) {
            LText("copy.addVersion")
                .font(.headline)
            BorderedTextField(text: $version, placeholder: L10n.tr("copy.versionPlaceholder", lang: language))
                .frame(width: 280)
            Stepper(value: $count, in: 1...999) {
                HStack {
                    LText("copy.count")
                    Spacer()
                    Text(verbatim: "\(count)")
                        .monospacedDigit()
                }
            }
            .frame(width: 280)
            HStack {
                Button(L10n.tr("common.cancel", lang: language)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.tr("common.save", lang: language)) {
                    let copy = PhysicalCopy(version: trimmed, count: max(1, count))
                    copy.game = game
                    context.insert(copy)
                    try? context.save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmed.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}

/// 改名弹窗（版本名必填）。
private struct RenameCopySheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    @Environment(\.dismiss) private var dismiss
    let copy: PhysicalCopy
    @State private var version: String

    init(copy: PhysicalCopy) {
        self.copy = copy
        _version = State(initialValue: copy.version)
    }

    private var trimmed: String { version.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 16) {
            LText("copy.rename")
                .font(.headline)
            BorderedTextField(text: $version, placeholder: L10n.tr("copy.version", lang: language))
                .frame(width: 280)
            HStack {
                Button(L10n.tr("common.cancel", lang: language)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.tr("common.save", lang: language)) {
                    copy.version = trimmed
                    try? context.save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmed.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}

