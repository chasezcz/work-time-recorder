import Foundation

/// 导出区间预设。
public enum ExportPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case today
    case thisWeek
    case thisMonth
    case thisQuarter
    case thisYear
    case all

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .today: return "今日"
        case .thisWeek: return "本周"
        case .thisMonth: return "本月"
        case .thisQuarter: return "本季度"
        case .thisYear: return "今年"
        case .all: return "全部"
        }
    }

    public var granularity: PeriodGranularity {
        switch self {
        case .today: return .day
        case .thisWeek: return .week
        case .thisMonth: return .month
        case .thisQuarter: return .quarter
        case .thisYear, .all: return .year
        }
    }

    public func interval(
        ledger: WorkTimeLedger,
        now: Date = Date(),
        calendar: Calendar = AppCalendar.calendar()
    ) -> DateInterval {
        switch self {
        case .all:
            let keys = ledger.orderedDayKeys
            let start = keys.first.flatMap { AppCalendar.date(fromDayKey: $0, calendar: calendar) } ?? calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
                ?? now.addingTimeInterval(86400)
            return DateInterval(start: calendar.startOfDay(for: start), end: end)
        default:
            return AppCalendar.interval(for: granularity, containing: now, calendar: calendar)
        }
    }
}

/// CSV 导出。
public enum CSVExport {
    /// Excel 打开中文 CSV 需要 BOM。
    private static let bom = "\u{FEFF}"

    /// 打卡明细：一行一段打卡记录。
    public static func sessionsCSV(
        ledger: WorkTimeLedger,
        interval: DateInterval,
        now: Date = Date(),
        holidays: [String: HolidayDay] = [:],
        calendar: Calendar = AppCalendar.calendar()
    ) -> String {
        let timeFormatter = AppCalendar.formatter("HH:mm", calendar: calendar)
        let rows = ledger.sessions(in: interval, now: now).map { entry -> [String] in
            let session = entry.session
            let key = AppCalendar.dayKey(for: session.start, calendar: calendar)
            let crossesMidnight = AppCalendar.dayKey(for: max(entry.end, session.start), calendar: calendar) != key
            let endText = session.end == nil ? "进行中" : timeFormatter.string(from: entry.end)
            return [
                key,
                AppCalendar.weekdayName(session.start, calendar: calendar),
                holidayLabel(key, holidays: holidays),
                timeFormatter.string(from: session.start),
                endText,
                DurationFormat.decimalHours(entry.end.timeIntervalSince(entry.start), fractionDigits: 2),
                session.startSource.displayName,
                session.endSource?.displayName ?? (session.end == nil ? "进行中" : ""),
                crossesMidnight ? "是" : "否"
            ]
        }
        let header = ["日期", "星期", "节假日", "开始时间", "结束时间", "时长(小时)", "上班方式", "下班方式", "跨天"]
        return bom + table(header: header, rows: rows)
    }

    /// 每日汇总：一行一天。
    public static func dailySummaryCSV(
        ledger: WorkTimeLedger,
        settings: Settings,
        interval: DateInterval,
        now: Date = Date(),
        holidays: [String: HolidayDay] = [:],
        calendar: Calendar = AppCalendar.calendar()
    ) -> String {
        let timeFormatter = AppCalendar.formatter("HH:mm", calendar: calendar)
        var rows: [[String]] = []

        for dayStart in AppCalendar.days(in: interval, calendar: calendar) {
            let key = AppCalendar.dayKey(for: dayStart, calendar: calendar)
            guard let dayInterval = AppCalendar.dayInterval(forDayKey: key, calendar: calendar) else { continue }
            let entries = ledger.sessions(in: dayInterval, now: now)
            let worked = entries.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
            let holiday = holidays[key]
            let weekend = AppCalendar.isWeekend(dayStart, calendar: calendar)
            let isOffDay = holiday.map { $0.isOffDay } ?? weekend
            let override = ledger.day(key).targetSecondsOverride
            let target = override ?? (isOffDay ? 0 : settings.dailyTargetSeconds)
            let ratio = target > 0 ? min(1, worked / target) : (worked > 0 ? 1 : 0)
            let hasRecord = !entries.isEmpty
            let firstIn = entries.first.map { timeFormatter.string(from: $0.start) } ?? ""
            let lastOut = entries.last.map { entry -> String in
                let session = entry.session
                if session.end == nil { return "进行中" }
                return timeFormatter.string(from: entry.end)
            } ?? ""
            let status: String
            if !hasRecord {
                status = isOffDay ? "休息" : "无记录"
            } else if target > 0 && worked >= target {
                status = "已达标"
            } else if isOffDay {
                status = "休息日加班"
            } else {
                status = "未达标"
            }
            rows.append([
                key,
                AppCalendar.weekdayName(dayStart, calendar: calendar),
                isOffDay ? "休息日" : "工作日",
                holidayLabel(key, holidays: holidays),
                DurationFormat.decimalHours(target, fractionDigits: 2),
                DurationFormat.decimalHours(worked, fractionDigits: 2),
                DurationFormat.decimalHours(worked - target, fractionDigits: 2),
                String(format: "%.0f%%", ratio * 100),
                "\(entries.count)",
                firstIn,
                lastOut,
                status
            ])
        }

        let header = ["日期", "星期", "日期类型", "节假日", "目标(小时)", "实际(小时)", "差额(小时)", "完成度", "打卡段数", "首次上班", "最后下班", "状态"]
        return bom + table(header: header, rows: rows)
    }

    private static func holidayLabel(_ key: String, holidays: [String: HolidayDay]) -> String {
        guard let holiday = holidays[key] else { return "" }
        return holiday.isOffDay ? holiday.name : "\(holiday.name)(补班)"
    }

    private static func table(header: [String], rows: [[String]]) -> String {
        var lines = [header.map(escape).joined(separator: ",")]
        lines.append(contentsOf: rows.map { $0.map(escape).joined(separator: ",") })
        return lines.joined(separator: "\n") + "\n"
    }

    private static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
