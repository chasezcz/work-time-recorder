import Foundation

/// 统计粒度。
public enum PeriodGranularity: String, CaseIterable, Codable, Identifiable, Sendable {
    case day
    case week
    case month
    case quarter
    case year

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .day: return "日"
        case .week: return "周"
        case .month: return "月"
        case .quarter: return "季度"
        case .year: return "年"
        }
    }

    public var chartTitle: String {
        switch self {
        case .day: return "当天时间轴"
        case .week: return "本周每日工时"
        case .month: return "本月每日工时"
        case .quarter: return "本季度每月工时"
        case .year: return "本年每月工时"
        }
    }
}

/// 统一使用的日历与日期边界工具。
///
/// 所有"一天"的边界都按本地时区计算，周以周一为一周开始。
public enum AppCalendar {
    /// 默认使用北京时间；需要其他时区时显式传入。
    public static func calendar(timeZone: TimeZone = AppTimeZone.beijing) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    public static func dayKey(for date: Date, calendar: Calendar = AppCalendar.calendar()) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return "1970-01-01"
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func date(fromDayKey key: String, calendar: Calendar = AppCalendar.calendar()) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    public static func startOfDay(_ date: Date, calendar: Calendar = AppCalendar.calendar()) -> Date {
        calendar.startOfDay(for: date)
    }

    public static func dayInterval(forDayKey key: String, calendar: Calendar = AppCalendar.calendar()) -> DateInterval? {
        guard let start = date(fromDayKey: key, calendar: calendar) else { return nil }
        let startOfDay = calendar.startOfDay(for: start)
        guard let end = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return nil }
        return DateInterval(start: startOfDay, end: end)
    }

    public static func startOfWeek(_ date: Date, calendar: Calendar = AppCalendar.calendar()) -> Date {
        let start = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: start)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -offset, to: start) ?? start
    }

    /// 指定粒度下包含 `date` 的自然区间（含起点，不含终点）。
    public static func interval(
        for granularity: PeriodGranularity,
        containing date: Date,
        calendar: Calendar = AppCalendar.calendar()
    ) -> DateInterval {
        switch granularity {
        case .day:
            let start = calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
            return DateInterval(start: start, end: end)
        case .week:
            let start = startOfWeek(date, calendar: calendar)
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 86400)
            return DateInterval(start: start, end: end)
        case .month:
            let components = calendar.dateComponents([.year, .month], from: date)
            let start = calendar.date(from: components) ?? calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start.addingTimeInterval(31 * 86400)
            return DateInterval(start: start, end: end)
        case .quarter:
            let components = calendar.dateComponents([.year, .month], from: date)
            let year = components.year ?? 1970
            let month = components.month ?? 1
            let quarterIndex = (month - 1) / 3
            let start = calendar.date(from: DateComponents(year: year, month: quarterIndex * 3 + 1, day: 1))
                ?? calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .month, value: 3, to: start) ?? start.addingTimeInterval(92 * 86400)
            return DateInterval(start: start, end: end)
        case .year:
            let year = calendar.component(.year, from: date)
            let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .year, value: 1, to: start) ?? start.addingTimeInterval(366 * 86400)
            return DateInterval(start: start, end: end)
        }
    }

    /// 按粒度平移区间，`offset` 为 0 表示当前区间。
    public static func interval(
        _ interval: DateInterval,
        shiftedBy granularity: PeriodGranularity,
        offset: Int,
        calendar: Calendar = AppCalendar.calendar()
    ) -> DateInterval {
        guard offset != 0 else { return interval }
        switch granularity {
        case .day:
            return shifted(interval, component: .day, value: offset, calendar: calendar)
        case .week:
            return shifted(interval, component: .day, value: offset * 7, calendar: calendar)
        case .month:
            return shifted(interval, component: .month, value: offset, calendar: calendar)
        case .quarter:
            return shifted(interval, component: .month, value: offset * 3, calendar: calendar)
        case .year:
            return shifted(interval, component: .year, value: offset, calendar: calendar)
        }
    }

    private static func shifted(
        _ interval: DateInterval,
        component: Calendar.Component,
        value: Int,
        calendar: Calendar
    ) -> DateInterval {
        guard let start = calendar.date(byAdding: component, value: value, to: interval.start),
              let end = calendar.date(byAdding: component, value: value, to: interval.end) else {
            return interval
        }
        return DateInterval(start: start, end: end)
    }

    /// 区间内的每一天（取每天 00:00）。
    public static func days(in interval: DateInterval, calendar: Calendar = AppCalendar.calendar()) -> [Date] {
        var result: [Date] = []
        var cursor = calendar.startOfDay(for: interval.start)
        var guardCount = 0
        while cursor < interval.end && guardCount < 1000 {
            result.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
            guardCount += 1
        }
        return result
    }

    public static func isWeekend(_ date: Date, calendar: Calendar = AppCalendar.calendar()) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    public static let weekdayNames = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

    public static func weekdayName(_ date: Date, calendar: Calendar = AppCalendar.calendar()) -> String {
        let weekday = calendar.component(.weekday, from: date)
        return weekdayNames[(weekday - 1 + 7) % 7]
    }

    public static func monthLabel(_ date: Date, calendar: Calendar = AppCalendar.calendar()) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return "\(components.year ?? 0)年\(components.month ?? 0)月"
    }

    public static func dayLabel(_ date: Date, calendar: Calendar = AppCalendar.calendar()) -> String {
        let components = calendar.dateComponents([.month, .day], from: date)
        return "\(components.month ?? 0)月\(components.day ?? 0)日"
    }

    /// 人类可读的区间描述，例如 `2026年9月14日 – 9月20日`。
    public static func describe(_ interval: DateInterval, granularity: PeriodGranularity, calendar: Calendar = AppCalendar.calendar()) -> String {
        let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        switch granularity {
        case .day:
            return "\(dayLabel(interval.start, calendar: calendar)) \(weekdayName(interval.start, calendar: calendar))"
        case .week:
            let startText = dayLabel(interval.start, calendar: calendar)
            let endText = dayLabel(lastDay, calendar: calendar)
            let week = calendar.component(.weekOfYear, from: interval.start)
            return "\(calendar.component(.year, from: interval.start))年第\(week)周 · \(startText) – \(endText)"
        case .month:
            return monthLabel(interval.start, calendar: calendar)
        case .quarter:
            let month = calendar.component(.month, from: interval.start)
            return "\(calendar.component(.year, from: interval.start))年 Q\((month - 1) / 3 + 1)"
        case .year:
            return "\(calendar.component(.year, from: interval.start))年"
        }
    }

    /// 时间戳格式化（导出与界面共用）。
    public static func formatter(_ format: String, calendar: Calendar = AppCalendar.calendar()) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter
    }
}
