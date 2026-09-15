import Foundation

/// 工时账本：按天保存打卡片段，并提供打卡、撤销、工时统计等纯逻辑能力。
///
/// 这里是全部工时口径的唯一来源，界面层只负责展示与触发。
public struct WorkTimeLedger: Codable, Equatable, Sendable {
    public private(set) var days: [String: WorkDay]

    public init(days: [String: WorkDay] = [:]) {
        self.days = days
    }

    // MARK: - 读取

    public func day(_ key: String) -> WorkDay {
        days[key] ?? WorkDay(dateKey: key)
    }

    public func contains(_ key: String) -> Bool {
        days[key] != nil
    }

    /// 所有天数按日期键升序排列。
    public var orderedDayKeys: [String] {
        days.keys.sorted()
    }

    /// 进行中的打卡片段（可能属于昨天，用于跨天连续上班）。
    public func activeEntry() -> (dateKey: String, session: WorkSession)? {
        var result: (dateKey: String, session: WorkSession)?
        for (key, day) in days {
            for session in day.sessions where session.isActive {
                if result == nil || session.start > result!.session.start {
                    result = (key, session)
                }
            }
        }
        return result
    }

    /// 最近一次打卡片段（不论是否结束）。
    public func latestEntry() -> (dateKey: String, session: WorkSession)? {
        var result: (dateKey: String, session: WorkSession)?
        for (key, day) in days {
            for session in day.sessions {
                if result == nil || session.start > result!.session.start {
                    result = (key, session)
                }
            }
        }
        return result
    }

    public var isWorking: Bool { activeEntry() != nil }

    /// 是否可以把最近一次下班打卡撤回（当前不在上班状态，且存在已结束的打卡片段）。
    public func canUndoClockOut() -> Bool {
        guard activeEntry() == nil else { return false }
        return latestEntry()?.session.end != nil
    }

    /// 区间内累计工时（按片段与区间求交集，进行中的片段算到 `now`）。
    public func workedSeconds(in interval: DateInterval, now: Date) -> TimeInterval {
        var total: TimeInterval = 0
        for day in days.values {
            for session in day.sessions {
                let effectiveEnd = session.end ?? now
                let start = max(session.start, interval.start)
                let end = min(effectiveEnd, interval.end)
                if end > start {
                    total += end.timeIntervalSince(start)
                }
            }
        }
        return total
    }

    public func workedSeconds(forDayKey key: String, now: Date, calendar: Calendar = AppCalendar.calendar()) -> TimeInterval {
        guard let interval = AppCalendar.dayInterval(forDayKey: key, calendar: calendar) else { return 0 }
        return workedSeconds(in: interval, now: now)
    }

    /// 区间内与时间有交集的打卡片段（已裁剪到区间边界，进行中的片段以 `now` 结束）。
    public func sessions(in interval: DateInterval, now: Date) -> [(dateKey: String, session: WorkSession, start: Date, end: Date)] {
        var result: [(dateKey: String, session: WorkSession, start: Date, end: Date)] = []
        for (key, day) in days {
            for session in day.sessions {
                let effectiveEnd = session.end ?? now
                let start = max(session.start, interval.start)
                let end = min(effectiveEnd, interval.end)
                if end > start {
                    result.append((key, session, start, end))
                }
            }
        }
        return result.sorted { $0.start < $1.start }
    }

    public func sessionCount(in interval: DateInterval, now: Date) -> Int {
        sessions(in: interval, now: now).count
    }

    // MARK: - 写入

    /// 上班打卡。已有进行中的片段时抛出 `alreadyWorking`。
    @discardableResult
    public mutating func clockIn(
        at date: Date,
        source: ClockSource,
        calendar: Calendar = AppCalendar.calendar()
    ) throws -> WorkDay {
        if activeEntry() != nil {
            throw WorkTimeError.alreadyWorking
        }
        let key = AppCalendar.dayKey(for: date, calendar: calendar)
        var day = days[key] ?? WorkDay(dateKey: key)
        day.sessions.append(WorkSession(start: date, startSource: source))
        day.sessions.sort { $0.start < $1.start }
        days[key] = day
        return day
    }

    /// 下班打卡，结束当前进行中的片段。
    @discardableResult
    public mutating func clockOut(
        at date: Date,
        source: ClockSource,
        calendar: Calendar = AppCalendar.calendar()
    ) throws -> WorkDay {
        guard let active = activeEntry() else {
            throw WorkTimeError.notWorking
        }
        var day = days[active.dateKey] ?? WorkDay(dateKey: active.dateKey)
        if let index = day.sessions.firstIndex(where: { $0.id == active.session.id }) {
            day.sessions[index].end = max(date, day.sessions[index].start)
            day.sessions[index].endSource = source
        }
        days[active.dateKey] = day
        return day
    }

    /// 撤回最近一次下班打卡：把该片段恢复为"进行中"，用于"回来加班"。
    @discardableResult
    public mutating func undoLastClockOut() throws -> WorkDay {
        guard activeEntry() == nil else {
            throw WorkTimeError.alreadyWorking
        }
        guard let latest = latestEntry(), latest.session.end != nil else {
            throw WorkTimeError.nothingToUndo
        }
        var day = days[latest.dateKey] ?? WorkDay(dateKey: latest.dateKey)
        if let index = day.sessions.firstIndex(where: { $0.id == latest.session.id }) {
            day.sessions[index].end = nil
            day.sessions[index].endSource = nil
        }
        days[latest.dateKey] = day
        return day
    }

    /// 标记当天已经提醒过目标达成。
    public mutating func markTargetNotified(dayKey: String) {
        var day = days[dayKey] ?? WorkDay(dateKey: dayKey)
        guard !day.targetNotified else { return }
        day.targetNotified = true
        days[dayKey] = day
    }

    public mutating func clearTargetNotified(dayKey: String) {
        guard var day = days[dayKey], day.targetNotified else { return }
        day.targetNotified = false
        days[dayKey] = day
    }

    /// 设置某天的独立目标（`nil` 表示沿用全局目标）。
    public mutating func setTargetOverride(_ seconds: TimeInterval?, dayKey: String) {
        var day = days[dayKey] ?? WorkDay(dateKey: dayKey)
        day.targetSecondsOverride = seconds
        days[dayKey] = day
    }

    public mutating func removeDay(_ key: String) {
        days.removeValue(forKey: key)
    }

    public mutating func removeAll() {
        days.removeAll()
    }

    /// 某天的目标工时：优先使用当天覆盖值，否则使用全局值。
    public func targetSeconds(forDayKey key: String, settings: Settings) -> TimeInterval {
        days[key]?.targetSecondsOverride ?? settings.dailyTargetSeconds
    }
}
