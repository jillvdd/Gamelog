import Foundation

/// 容错的 RFC3339 解析 —— **PSN 与 Xbox 共用这一处**。
///
/// 两家的时间戳是同一种东西（服务端序列化的 ISO-8601），失败形状也完全一样：
/// `ISO8601DateFormatter` 的 `.withFractionalSeconds` **只吃固定 3 位**小数秒，而实测
/// - PSN 给过 `2024-08-03T19:28:27.12Z`（**两位**，见 `PSNAPI` 的注释）；
/// - Xbox 给的是 `2026-09-15T01:20:50.0474465Z`（**七位** —— .NET 的 ticks 写法，见 §63）。
///
/// 两家都解不出来。所以**先把小数部分整段抹掉**再解：秒以下的信息对本功能没有意义
/// （我们要的是「哪天玩的」），解析得出来比解析得精确重要。
///
/// ⚠️ Nintendo 的 `NintendoAPI.parseTimestamp` 是**另一个东西**，不要合并：它还要吃
/// 纯日期（`2024-01-02`）那种形状，规则本就不同。
///
/// **解析不出返回 nil**：时间缺失是正常情况（`firstPlayedAt` 本就可空），
/// 不能让它变成一次同步失败。
enum ExternalTimestamp {
    /// 抹掉小数秒后解析。`nil` / 空串 / 认不出的形状一律返回 nil。
    static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        for formatter in iso8601Formatters {
            if let date = formatter.date(from: trimmed) { return date }
        }

        // 抹掉小数秒：`.` 之后连续的**数字**删掉，保留其后的 `Z` / `+08:00`。
        if let dot = trimmed.firstIndex(of: ".") {
            let tail = trimmed[dot...].dropFirst().drop { $0.isNumber }
            let stripped = String(trimmed[..<dot]) + tail
            for formatter in iso8601Formatters {
                if let date = formatter.date(from: stripped) { return date }
            }
        }
        return nil
    }

    /// 带时区的 ISO-8601（含/不含毫秒两种）。
    private static let iso8601Formatters: [ISO8601DateFormatter] = {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return [withFraction, plain]
    }()
}
