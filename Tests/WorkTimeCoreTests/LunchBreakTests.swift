import Foundation
import Testing
@testable import WorkTimeCore

@Suite struct LunchBreakTests {
    private let calendar = AppCalendar.calendar(timeZone: TimeZone(identifier: "Asia/Shanghai")!)

    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    private func makeLedger(start: String, end: String?) throws -> WorkTimeLedger {
        var ledger = WorkTimeLedger()
        try ledger.clockIn(at: date(start), source: .manual, calendar: calendar)
        if let end {
            try ledger.clockOut(at: date(end), source: .manual, calendar: calendar)
        }
        return ledger
    }

    @Test func defaultLunchSettings() {
        let lunch = Settings().lunchBreak
        #expect(lunch.isEnabled)
        #expect(lunch.startMinutes == 12 * 60)
        #expect(lunch.endMinutes == 13 * 60 + 30)
        #expect(lunch.durationMinutes == 90)
        #expect(lunch.displayText == "12:00 – 13:30")
        #expect(lunch.durationText == "1 小时 30 分")
    }

    @Test func fullDayDeductsDefaultLunch() throws {
        let ledger = try makeLedger(start: "2026-09-15 09:00", end: "2026-09-15 18:00")
        let worked = WorkTimeCalculator.workedSeconds(
            ledger: ledger,
            dayKey: "2026-09-15",
            now: date("2026-09-15 23:00"),
            settings: Settings(),
            calendar: calendar
        )
        #expect(abs(worked - 7.5 * 3600) < 1)
    }

    @Test func sessionsOutsideLunchAreUntouched() throws {
        let morning = try makeLedger(start: "2026-09-15 09:00", end: "2026-09-15 12:00")
        #expect(abs(
            WorkTimeCalculator.workedSeconds(
                ledger: morning, dayKey: "2026-09-15",
                now: date("2026-09-15 12:00"), settings: Settings(), calendar: calendar
            ) - 3 * 3600
        ) < 1)

        let afternoon = try makeLedger(start: "2026-09-15 13:30", end: "2026-09-15 18:00")
        #expect(abs(
            WorkTimeCalculator.workedSeconds(
                ledger: afternoon, dayKey: "2026-09-15",
                now: date("2026-09-15 18:00"), settings: Settings(), calendar: calendar
            ) - 4.5 * 3600
        ) < 1)
    }

    @Test func lunchOnlySessionCountsZero() throws {
        let ledger = try makeLedger(start: "2026-09-15 12:00", end: "2026-09-15 13:00")
        let worked = WorkTimeCalculator.workedSeconds(
            ledger: ledger,
            dayKey: "2026-09-15",
            now: date("2026-09-15 13:00"),
            settings: Settings(),
            calendar: calendar
        )
        #expect(abs(worked) < 1)
    }

    @Test func sessionSpanningLunchKeepsOnlyOutsidePart() throws {
        let ledger = try makeLedger(start: "2026-09-15 11:30", end: "2026-09-15 13:00")
        let worked = WorkTimeCalculator.workedSeconds(
            ledger: ledger,
            dayKey: "2026-09-15",
            now: date("2026-09-15 13:00"),
            settings: Settings(),
            calendar: calendar
        )
        // 11:30–12:00 属于工作时间，12:00–13:00 被午休扣掉
        #expect(abs(worked - 0.5 * 3600) < 1)
    }

    @Test func customLunchWindow() throws {
        let ledger = try makeLedger(start: "2026-09-15 09:00", end: "2026-09-15 18:00")
        var settings = Settings()
        settings.lunchBreak.startMinutes = 12 * 60
        settings.lunchBreak.endMinutes = 13 * 60
        let worked = WorkTimeCalculator.workedSeconds(
            ledger: ledger,
            dayKey: "2026-09-15",
            now: date("2026-09-15 18:00"),
            settings: settings,
            calendar: calendar
        )
        #expect(abs(worked - 8 * 3600) < 1)
    }

    @Test func partialLunchElapsedForOngoingSession() throws {
        let ledger = try makeLedger(start: "2026-09-15 11:30", end: nil)
        // 当前 12:30：只过了 30 分钟午休，扣 0.5 小时
        let worked = WorkTimeCalculator.workedSeconds(
            ledger: ledger,
            dayKey: "2026-09-15",
            now: date("2026-09-15 12:30"),
            settings: Settings(),
            calendar: calendar
        )
        #expect(abs(worked - 0.5 * 3600) < 1)
    }

    @Test func disabledLunchKeepsGross() throws {
        let ledger = try makeLedger(start: "2026-09-15 09:00", end: "2026-09-15 18:00")
        var settings = Settings()
        settings.lunchBreak.isEnabled = false
        let worked = WorkTimeCalculator.workedSeconds(
            ledger: ledger,
            dayKey: "2026-09-15",
            now: date("2026-09-15 18:00"),
            settings: settings,
            calendar: calendar
        )
        #expect(abs(worked - 9 * 3600) < 1)
    }

    @Test func normalizeResetsInvalidWindows() {
        var lunch = LunchBreak(startMinutes: 14 * 60, endMinutes: 12 * 60)
        lunch.normalize()
        #expect(lunch.startMinutes == LunchBreak.defaultStartMinutes)
        #expect(lunch.endMinutes == LunchBreak.defaultEndMinutes)
    }

    @Test func legacySettingsDecodeToDefaultLunch() throws {
        let json = #"{"dailyTargetSeconds": 28800}"#
        let settings = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        #expect(settings.lunchBreak.isEnabled)
        #expect(settings.lunchBreak.endMinutes == 13 * 60 + 30)
    }
}
