import Foundation

/// 应用的时区口径。
///
/// 默认固定为北京时间（`Asia/Shanghai`，UTC+8）：无论是“一天”的边界、
/// 界面显示，还是数据文件里的时间戳偏移量，都以它为准，避免跨设备/跨时区看数据时产生歧义。
public enum AppTimeZone {
    /// 北京时间（东八区）。
    public static let beijingIdentifier = "Asia/Shanghai"
    /// 特殊取值：跟随当前系统时区。
    public static let systemIdentifier = "system"

    public static var beijing: TimeZone {
        TimeZone(identifier: beijingIdentifier)
            ?? TimeZone(secondsFromGMT: 8 * 3600)
            ?? TimeZone(identifier: "UTC")!
    }

    public static func timeZone(identifier: String) -> TimeZone {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == systemIdentifier { return .current }
        return TimeZone(identifier: trimmed) ?? beijing
    }

    public static func isValid(identifier: String) -> Bool {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == systemIdentifier { return true }
        return TimeZone(identifier: trimmed) != nil
    }

    /// `北京时间（UTC+8）` / `跟随系统（UTC+8）`
    public static func displayName(identifier: String) -> String {
        let timeZone = timeZone(identifier: identifier)
        let offset = offsetLabel(for: timeZone)
        if identifier == systemIdentifier {
            return "跟随系统（\(offset)）"
        }
        if timeZone.identifier == beijingIdentifier {
            return "北京时间（UTC+8）"
        }
        return "\(timeZone.identifier)（\(offset)）"
    }

    public static func offsetLabel(for timeZone: TimeZone) -> String {
        let seconds = timeZone.secondsFromGMT()
        let sign = seconds < 0 ? "-" : "+"
        let hours = abs(seconds) / 3600
        let minutes = (abs(seconds) % 3600) / 60
        return minutes == 0 ? "UTC\(sign)\(hours)" : String(format: "UTC%@%d:%02d", sign, hours, minutes)
    }
}
