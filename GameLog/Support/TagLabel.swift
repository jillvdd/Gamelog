import SwiftUI

/// 行内小标签（「来源已无此记录」「实验性」这类状态说明）。
///
/// 尺寸口径与 `GameBadge.plain` 的小胶囊同一档：`caption2`、内边距 6×2、底色 = 主题色 15%。
/// 新调用点照用，别在调用处另起一套数值（同 `AppToolbar` / `PlatformIcon` 的集中口径）。
struct TagLabel: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(verbatim: text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }
}
