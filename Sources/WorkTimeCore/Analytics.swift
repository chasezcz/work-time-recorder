import Foundation

/// 单日统计。
public struct DayStat: Identifiable, Equatable, Sendable {
    public var id: String { dateKey }
    public let dateKey: String
    public let date: Date
    public let workedSeconds: TimeInterval
    public let targetSeconds: TimeInterval
    public let sessionCount: Int
    public let firstClockIn: Date?
    public let lastActivity: Date?
    public let holidayName: String?
    public let isOffDay: Bool
    public let isFuture: Bool

    public init(
        dateKey: String,
        date: Date,
        workedSeconds: TimeInterval,
        targetSeconds: TimeInterval,
        sessionCount: Int,
        firstClockIn: Date?,
        lastActivity: Date?,
        holidayName: String?,
        isOffDay: Bool,
        isFuture: Bool
    ) {
        self.dateKey = dateKey
        self.date = date
        self.workedSeconds = workedSeconds
        self.targetSeconds = targetSeconds
        self.sessionCount = sessionCount
        self.firstClockIn = firstClockIn
        self.lastActivity = lastActivity
        self.holidayName = holidayName
        self.isOffDay = isOffDay
        self.isFuture = isFuture
    }

    public var completionRatio: Double {
        guard targetSeconds > 0 else { return workedSeconds > 0 ? 1 : 0 }
        return min(1, workedSeconds / targetSeconds)
    }

    /// 超过目标的部分；休息日工作则全部算加班。
    public var overtimeSeconds: TimeInterval {
        max(0, workedSeconds - targetSeconds)
    }

    public var hasRecords: Bool { sessionCount > 0 || workedSeconds > 0 }
}

/// 图表中的一根柱子（周/月视图里是一天，季度/年视图里是一个月）。
public struct BucketStat: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let interval: DateInterval
    public let workedSeconds: TimeInterval
    public let targetSeconds: TimeInterval
    public let isCurrent: Bool
    public let isOffDay: Bool

    public init(
        id: String,
        title: String,
        interval: DateInterval,
        workedSeconds: TimeInterval,
        targetSeconds: TimeInterval,
        isCurrent: Bool,
        isOffDay: Bool
    ) {
        self.id = id
        self.title = title
        self.interval = interval
        self.workedSeconds = workedSeconds
        self.targetSeconds = targetSeconds
        self.isCurrent = isCurrent
        self.isOffDay = isOffDay
    }

    public var hours: Double { workedSeconds / 3600 }
    public var targetHours: Double { targetSeconds / 3600 }
}

/// 一个统计周期的完整结果。
public struct PeriodStats: Equatable, Sendable {
    public let granularity: PeriodGranularity
    public let interval: DateInterval
    public let totalWorkedSeconds: TimeInterval
    public let totalTargetSeconds: TimeInterval
    /// 有打卡记录的天数。
    public let activeDayCount: Int
    /// 需要达标的上班日数量（扣除周末与节假日，含调休补班）。
    public let requiredDayCount: Int
    public let overtimeSeconds: TimeInterval
    public let buckets: [BucketStat]
    public let days: [DayStat]

    public var averageSecondsPerActiveDay: TimeInterval {
        activeDayCount > 0 ? totalWorkedSeconds / Double(activeDayCount) : 0
    }

    public var completionRatio: Double {
        guard totalTargetSeconds > 0 else { return totalWorkedSeconds > 0 ? 1 : 0 }
        return min(1, totalWorkedSeconds / totalTargetSeconds)
    }

    public var isTargetReached: Bool {
        totalTargetSeconds > 0 && totalWorkedSeconds >= totalTargetSeconds
    }
}

/// 统计计算入口。
public enum Analytics {
    /// 计算某个周期的工时统计。
    ///
    /// - Parameters:
    ///   - holidays: 以 `yyyy-MM-dd` 为键的节假日表，用于区分休息日与调休补班。
    ///   - now: 当前时间，用于裁剪进行中的打卡片段、排除尚未到来的工作日。
    public static func periodStats(
        ledger: WorkTimeLedger,
        settings: Settings,
        granularity: PeriodGranularity,
        containing date: Date,
        now: Date = Date(),
        holidays: [String: HolidayDay] = [:],
        calendar: Calendar = AppCalendar.calendar()
    ) -> PeriodStats {
        let interval = AppCalendar.interval(for: granularity, containing: date, calendar: calendar)
        let dayStarts = AppCalendar.days(in: interval, calendar: calendar)
        var days: [DayStat] = []

        for dayStart in dayStarts {
            let key = AppCalendar.dayKey(for: dayStart, calendar: calendar)
            guard let dayInterval = AppCalendar.dayInterval(forDayKey: key, calendar: calendar) else { continue }
            let isFuture = dayStart > now
            let worked = ledger.workedSeconds(in: dayInterval, now: now)
            let entries = ledger.sessions(in: dayInterval, now: now)
            let day = ledger.day(key)
            let holiday = holidays[key]
            let weekend = AppCalendar.isWeekend(dayStart, calendar: calendar)
            let isOffDay = holiday.map { $0.isOffDay } ?? weekend

            var target = settings.dailyTargetSeconds
            if let override = day.targetSecondsOverride {
                target = override
            } else if isOffDay {
                target = 0
            }
            if isFuture { target = 0 }

            days.append(
                DayStat(
                    dateKey: key,
                    date: dayStart,
                    workedSeconds: worked,
                    targetSeconds: target,
                    sessionCount: entries.count,
                    firstClockIn: entries.first?.start,
                    lastActivity: entries.last?.end,
                    holidayName: holiday?.name,
                    isOffDay: isOffDay,
                    isFuture: isFuture
                )
            )
        }

        let totalWorked = days.reduce(0) { $0 + $1.workedSeconds }
        let totalTarget = days.reduce(0) { $0 + $1.targetSeconds }
        let activeDays = days.filter { $0.hasRecords }.count
        let requiredDays = days.filter { $0.targetSeconds > 0 }.count
        let overtime = days.reduce(0) { $0 + $1.overtimeSeconds }

        return PeriodStats(
            granularity: granularity,
            interval: interval,
            totalWorkedSeconds: totalWorked,
            totalTargetSeconds: totalTarget,
            activeDayCount: activeDays,
            requiredDayCount: requiredDays,
            overtimeSeconds: overtime,
            buckets: buckets(for: granularity, days: days, now: now, calendar: calendar),
            days: days
        )
    }

    /// 生成图表用的分桶数据。
    public static func buckets(
        for granularity: PeriodGranularity,
        days: [DayStat],
        now: Date,
        calendar: Calendar = AppCalendar.calendar()
    ) -> [BucketStat] {
        switch granularity {
        case .day:
            return days.map { day in
                BucketStat(
                    id: day.dateKey,
                    title: AppCalendar.weekdayName(day.date, calendar: calendar),
                    interval: AppCalendar.interval(for: .day, containing: day.date, calendar: calendar),
                    workedSeconds: day.workedSeconds,
                    targetSeconds: day.targetSeconds,
                    isCurrent: true,
                    isOffDay: day.isOffDay
                )
            }
        case .week, .month:
            return days.map { day in
                BucketStat(
                    id: day.dateKey,
                    title: granularity == .week
                        ? AppCalendar.weekdayName(day.date, calendar: calendar)
                        : "\(calendar.component(.day, from: day.date))",
                    interval: AppCalendar.interval(for: .day, containing: day.date, calendar: calendar),
                    workedSeconds: day.workedSeconds,
                    targetSeconds: day.targetSeconds,
                    isCurrent: calendar.isDate(day.date, inSameDayAs: now),
                    isOffDay: day.isOffDay
                )
            }
        case .quarter, .year:
            var grouped: [String: [DayStat]] = [:]
            var order: [String] = []
            for day in days {
                let components = calendar.dateComponents([.year, .month], from: day.date)
                let key = String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
                if grouped[key] == nil {
                    grouped[key] = []
                    order.append(key)
                }
                grouped[key]?.append(day)
            }
            return order.compactMap { key in
                guard let monthDays = grouped[key], let first = monthDays.first else { return nil }
                let month = calendar.component(.month, from: first.date)
                let start = AppCalendar.interval(for: .month, containing: first.date, calendar: calendar).start
                let end = AppCalendar.interval(for: .month, containing: first.date, calendar: calendar).end
                return BucketStat(
                    id: key,
                    title: "\(month)月",
                    interval: DateInterval(start: start, end: end),
                    workedSeconds: monthDays.reduce(0) { $0 + $1.workedSeconds },
                    targetSeconds: monthDays.reduce(0) { $0 + $1.targetSeconds },
                    isCurrent: calendar.isDate(first.date, equalTo: now, toGranularity: .month),
                    isOffDay: false
                )
            }
        }
    }
}
