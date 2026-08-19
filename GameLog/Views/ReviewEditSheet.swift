import SwiftUI
import SwiftData

#if os(iOS)

/// iOS 评价编辑 sheet：顶部一句话（tagline）+ 底部长评（Markdown）。
/// 长评是基础可用的纯文本 Markdown 输入（用户习惯在备忘录写好复制进来）。
/// 不做预览（要预览直接看详情页渲染，双端用同一个 `MarkdownReviewView`）。
/// 保存才写回，取消 / 关闭不写回。
struct ReviewEditSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguageCode) private var language

    let game: Game

    @State private var reviewTitle = ""
    @State private var reviewBody = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                // 一句话评价（tagline）
                TextField(L10n.tr("game.reviewTitlePlaceholder", lang: language), text: $reviewTitle)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                Divider()

                // 长评正文（Markdown 纯文本输入）
                TextEditor(text: $reviewBody)
                    .font(.body)
                    .padding(4)
            }
            .navigationTitle(L10n.tr("review.edit", lang: language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("common.cancel", lang: language)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.tr("review.save", lang: language)) { save() }
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            reviewTitle = game.reviewTitle
            reviewBody = game.reviewBody
        }
    }

    private func save() {
        game.reviewTitle = reviewTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        game.reviewBody = reviewBody
        try? context.save()
        dismiss()
    }
}

#endif
