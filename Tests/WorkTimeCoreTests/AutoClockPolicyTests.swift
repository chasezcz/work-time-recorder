import Foundation
import Testing
@testable import WorkTimeCore

@Suite struct AutoClockPolicyTests {
    private let calendar = AppCalendar.calendar(timeZone: TimeZone(identifier: "Asia/Shanghai")!)

    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    @Test func autoClockInFiresAfterThresholdOnEmptyDay() {
        let settings = Settings(automaticClockInEnabled: true, autoClockInHour: 4, autoClockInMinute: 0)
        #expect(
            AutoClockPolicy.shouldAutoClockIn(
                settings: settings,
                ledger: WorkTimeLedger(),
                now: date("2026-09-15 09:30"),
                calendar: calendar
            )
        )
    }

    @Test func autoClockInDoesNotFireBeforeThreshold() {
        let settings = Settings(automaticClockInEnabled: true, autoClockInHour: 4, autoClockInMinute: 0)
        #expect(
            !AutoClockPolicy.shouldAutoClockIn(
                settings: settings,
                ledger: WorkTimeLedger(),
                now: date("2026-09-15 03:59"),
                calendar: calendar
            )
        )
    }

    @Test func autoClockInDoesNotFireWhenDisabled() {
        let settings = Settings(automaticClockInEnabled: false, autoClockInHour: 4, autoClockInMinute: 0)
        #expect(
            !AutoClockPolicy.shouldAutoClockIn(
                settings: settings,
                ledger: WorkTimeLedger(),
                now: date("2026-09-15 09:30"),
                calendar: calendar
            )
        )
    }

    @Test func autoClockInDoesNotFireWhenAlreadyWorking() throws {
        var ledger = WorkTimeLedger()
        try ledger.clockIn(at: date("2026-09-15 09:00"), source: .manual, calendar: calendar)
        #expect(
            !AutoClockPolicy.shouldAutoClockIn(
                settings: Settings(),
                ledger: ledger,
                now: date("2026-09-15 10:00"),
                calendar: calendar
            )
        )
    }

    @Test func autoClockInDoesNotFireAfterManualClockOut() throws {
        var ledger = WorkTimeLedger()
        try ledger.clockIn(at: date("2026-09-15 08:00"), source: .manual, calendar: calendar)
        try ledger.clockOut(at: date("2026-09-15 12:00"), source: .manual, calendar: calendar)
        #expect(
            !AutoClockPolicy.shouldAutoClockIn(
                settings: Settings(),
                ledger: ledger,
                now: date("2026-09-15 14:00"),
                calendar: calendar
            )
        )
    }

    @Test func autoClockOutFiresWhenTargetReachedAndWorking() throws {
        var ledger = WorkTimeLedger()
        try ledger.clockIn(at: date("2026-09-15 09:00"), source: .manual, calendar: calendar)
        #expect(
            AutoClockPolicy.shouldAutoClockOut(
                settings: Settings(),
                ledger: ledger,
                now: date("2026-09-15 17:10"),
                calendar: calendar
            )
        )
    }

    @Test func autoClockOutDoesNotFireBeforeTarget() throws {
        var ledger = WorkTimeLedger()
        try ledger.clockIn(at: date("2026-09-15 09:00"), source: .manual, calendar: calendar)
        #expect(
            !AutoClockPolicy.shouldAutoClockOut(
                settings: Settings(),
                ledger: ledger,
                now: date("2026-09-15 12:00"),
                calendar: calendar
            )
        )
    }

    @Test func autoClockOutDoesNotFireWhenNotWorking() throws {
        var ledger = WorkTimeLedger()
        try ledger.clockIn(at: date("2026-09-15 09:00"), source: .manual, calendar: calendar)
        try ledger.clockOut(at: date("2026-09-15 18:00"), source: .manual, calendar: calendar)
        #expect(
            !AutoClockPolicy.shouldAutoClockOut(
                settings: Settings(),
                ledger: ledger,
                now: date("2026-09-15 20:00"),
                calendar: calendar
            )
        )
    }

    @Test func crossMidnightSessionCountsTowardsTodayTarget() throws {
        var ledger = WorkTimeLedger()
        try ledger.clockIn(at: date("2026-09-14 22:00"), source: .manual, calendar: calendar)
        #expect(
            AutoClockPolicy.shouldAutoClockOut(
                settings: Settings(),
                ledger: ledger,
                now: date("2026-09-15 10:00"),
                calendar: calendar
            )
        )
    }

    @Test func targetNotificationFiresOnce() throws {
        var ledger = WorkTimeLedger()
        try ledger.clockIn(at: date("2026-09-15 09:00"), source: .manual, calendar: calendar)
        let now = date("2026-09-15 17:10")
        #expect(
            AutoClockPolicy.shouldNotifyTargetReached(
                settings: Settings(),
                ledger: ledger,
                now: now,
                calendar: calendar
            )
        )
        ledger.markTargetNotified(dayKey: "2026-09-15")
        #expect(
            !AutoClockPolicy.shouldNotifyTargetReached(
                settings: Settings(),
                ledger: ledger,
                now: now,
                calendar: calendar
            )
        )
    }
}
