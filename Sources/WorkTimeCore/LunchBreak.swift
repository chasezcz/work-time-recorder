import Foundation

/// 午休时段设置。
///
/// 默认 12:00 – 13:30，可在设置里开关与自定义；午休时段不计入工时。
public struct LunchBreak: Codable, Equatable, Sendable {
    public static let defaultStartMinutes = 12 * 60
    public static let defaultEndMinutes = 13 * 60 + 30

    /// 是否启用午休。
    public var isEnabled: Bool
    /// 从当天 00:00 起算的分钟数。
    public var startMinutes: Int
    public var endMinutes: Int

    public init(
        isEnabled: Bool = true,
        startMinutes: Int = LunchBreak.defaultStartMinutes,
        endMinutes: Int = LunchBreak.defaultEndMinutes
    ) {
        self.isEnabled = isEnabled
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
    }

    public var durationMinutes: Int { max(0, endMinutes - startMinutes) }

    public var isValid: Bool {
        startMinutes >= 0 && endMinutes <= 24 * 60 && endMinutes > startMinutes
    }

    /// `12:00 – 13:30`
    public var displayText: String {
        "\(Self.timeText(startMinutes)) – \(Self.timeText(endMinutes))"
    }

    /// `1 小时 30 分`
    public var durationText: String {
        DurationFormat.text(TimeInterval(durationMinutes * 60))
    }

    public static func timeText(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    public mutating func normalize() {
        startMinutes = min(max(startMinutes, 0), 24 * 60)
        endMinutes = min(max(endMinutes, 0), 24 * 60)
        if !isValid {
            startMinutes = Self.defaultStartMinutes
            endMinutes = Self.defaultEndMinutes
        }
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case startMinutes
        case endMinutes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = LunchBreak()
        isEnabled = (try? container.decode(Bool.self, forKey: .isEnabled)) ?? defaults.isEnabled
        startMinutes = (try? container.decode(Int.self, forKey: .startMinutes)) ?? defaults.startMinutes
        endMinutes = (try? container.decode(Int.self, forKey: .endMinutes)) ?? defaults.endMinutes
        normalize()
    }
}

/// 工时口径计算：把午休时段从打卡时长里扣掉。
public enum WorkTimeCalculator {
    /// 某天的午休区间（未启用或设置无效时返回 nil）。
    public static func lunchInterval(
        forDayKey key: String,
        lunch: LunchBreak,
        calendar: Calendar = AppCalendar.calendar()
    ) -> DateInterval? {
        guard lunch.isEnabled, lunch.durationMinutes > 0 else { return nil }
        guard let day = AppCalendar.dayInterval(forDayKey: key, calendar: calendar) else { return nil }
        guard let start = calendar.date(
            bySettingHour: lunch.startMinutes / 60,
            minute: lunch.startMinutes % 60,
            second: 0,
            of: day.start
        ), let end = calendar.date(
            bySettingHour: lunch.endMinutes / 60,
            minute: lunch.endMinutes % 60,
            second: 0,
            of: day.start
        ) else { return nil }
        guard end > start else { return nil }
        return DateInterval(start: start, end: min(end, day.end))
    }

    /// 区间内被午休占用的时长（只统计与打卡时间重叠的部分）。
    public static func breakSeconds(
        ledger: WorkTimeLedger,
        in interval: DateInterval,
        now: Date,
        settings: Settings,
        calendar: Calendar = AppCalendar.calendar()
    ) -> TimeInterval {
        var total: TimeInterval = 0
        for dayStart in AppCalendar.days(in: interval, calendar: calendar) {
            let key = AppCalendar.dayKey(for: dayStart, calendar: calendar)
            guard let lunch = lunchInterval(forDayKey: key, lunch: settings.lunchBreak, calendar: calendar) else { continue }
            let start = max(lunch.start, interval.start)
            let end = min(lunch.end, interval.end)
            guard end > start else { continue }
            total += ledger.workedSeconds(in: DateInterval(start: start, end: end), now: now)
        }
        return total
    }

    /// 区间内的净工时 = 打卡时长 − 与午休重叠的时长。
    public static func workedSeconds(
        ledger: WorkTimeLedger,
        in interval: DateInterval,
        now: Date,
        settings: Settings,
        calendar: Calendar = AppCalendar.calendar()
    ) -> TimeInterval {
        let gross = ledger.workedSeconds(in: interval, now: now)
        guard settings.lunchBreak.isEnabled else { return gross }
        let deducted = breakSeconds(ledger: ledger, in: interval, now: now, settings: settings, calendar: calendar)
        return max(0, gross - deducted)
    }

    /// 某天的净工时。
    public static func workedSeconds(
        ledger: WorkTimeLedger,
        dayKey: String,
        now: Date,
        settings: Settings,
        calendar: Calendar = AppCalendar.calendar()
    ) -> TimeInterval {
        guard let interval = AppCalendar.dayInterval(forDayKey: dayKey, calendar: calendar) else { return 0 }
        return workedSeconds(ledger: ledger, in: interval, now: now, settings: settings, calendar: calendar)
    }
}
