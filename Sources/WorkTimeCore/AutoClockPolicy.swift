import Foundation

/// 自动打卡判定规则（纯函数，便于单测覆盖）。
public enum AutoClockPolicy {
    /// 自动上班：开启了自动上班、当前不在上班状态、已过时间门槛、且当天还没有任何打卡记录。
    ///
    /// “当天没有任何记录”保证手动打过卡（或已经下班）之后不会被自动打卡打扰。
    public static func shouldAutoClockIn(
        settings: Settings,
        ledger: WorkTimeLedger,
        now: Date,
        calendar: Calendar = AppCalendar.calendar()
    ) -> Bool {
        guard settings.automaticClockInEnabled else { return false }
        guard ledger.activeEntry() == nil else { return false }
        guard hasPassedClockInThreshold(now: now, settings: settings, calendar: calendar) else { return false }
        let key = AppCalendar.dayKey(for: now, calendar: calendar)
        return ledger.day(key).sessions.isEmpty
    }

    /// 自动下班：开启了自动下班、正在上班、且当天累计工时已达标。
    public static func shouldAutoClockOut(
        settings: Settings,
        ledger: WorkTimeLedger,
        now: Date,
        calendar: Calendar = AppCalendar.calendar()
    ) -> Bool {
        guard settings.automaticClockOutEnabled else { return false }
        guard ledger.activeEntry() != nil else { return false }
        let key = AppCalendar.dayKey(for: now, calendar: calendar)
        let target = ledger.targetSeconds(forDayKey: key, settings: settings)
        guard target > 0 else { return false }
        return workedSecondsToday(ledger: ledger, now: now, calendar: calendar) >= target
    }

    /// 是否已过“自动上班时间门槛”（默认凌晨 4:00）。
    public static func hasPassedClockInThreshold(
        now: Date,
        settings: Settings,
        calendar: Calendar = AppCalendar.calendar()
    ) -> Bool {
        let startOfDay = calendar.startOfDay(for: now)
        guard let threshold = calendar.date(
            bySettingHour: settings.autoClockInHour,
            minute: settings.autoClockInMinute,
            second: 0,
            of: startOfDay
        ) else { return true }
        return now >= threshold
    }

    /// 当天（0 点起）累计工时，进行中的片段算到 `now`。
    public static func workedSecondsToday(
        ledger: WorkTimeLedger,
        now: Date,
        calendar: Calendar = AppCalendar.calendar()
    ) -> TimeInterval {
        let key = AppCalendar.dayKey(for: now, calendar: calendar)
        guard let interval = AppCalendar.dayInterval(forDayKey: key, calendar: calendar) else { return 0 }
        return ledger.workedSeconds(in: interval, now: now)
    }

    /// 是否需要发出“可以下班了”的提醒。
    public static func shouldNotifyTargetReached(
        settings: Settings,
        ledger: WorkTimeLedger,
        now: Date,
        calendar: Calendar = AppCalendar.calendar()
    ) -> Bool {
        guard settings.notifyWhenTargetReached else { return false }
        guard ledger.activeEntry() != nil else { return false }
        let key = AppCalendar.dayKey(for: now, calendar: calendar)
        guard !ledger.day(key).targetNotified else { return false }
        let target = ledger.targetSeconds(forDayKey: key, settings: settings)
        guard target > 0 else { return false }
        return workedSecondsToday(ledger: ledger, now: now, calendar: calendar) >= target
    }
}
