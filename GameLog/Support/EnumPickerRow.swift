import SwiftUI

/// 拥有本地化标签 key 的枚举（labelKey 指向 Localizable.strings）。
protocol LabelKeyed {
    var labelKey: String { get }
}

/// 通用枚举选择行（CaseIterable + Identifiable + RawRepresentable<String> + LabelKeyed）。
/// 标签走 `L10n.tr(e.labelKey, lang:)`；菜单在 macOS/iOS 均为 `.menu`。
struct EnumPickerRow<E>: View where E: CaseIterable & Identifiable & Hashable & LabelKeyed,
    E: RawRepresentable, E.RawValue == String {
    let title: String
    let cases: [E]
    @Binding var selection: E
    let language: String

    var body: some View {
        LabeledContent(title) {
            Picker("", selection: $selection) {
                ForEach(cases) { e in
                    Text(verbatim: L10n.tr(e.labelKey, lang: language)).tag(e)
                }
            }
            .labelsHidden()
            #if os(macOS)
            .pickerStyle(.menu)
            .frame(width: 200)
            #else
            .pickerStyle(.menu)
            #endif
        }
    }
}
