import Foundation
import Testing
@testable import WorkTimeCore

@Suite struct AnalyticsTests {
    private let calendar = AppCalendar.calendar(timeZone: TimeZone(identifier: "Asia/Shanghai")!)

    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    private func makeLedger(_ entries: [(String, String)]) -> WorkTimeLedger {
        var ledger = WorkTimeLedger()
        for (start, end) in entries {
            try? ledger.clockIn(at: date(start), source: .manual, calendar: calendar)
            try? ledger.clockOut(at: date(end), source: .manual, calendar: calendar)
        }
        return ledger
    }

    @Test func weekStatsBucketsAndTotals() {
        // 2026-09-15 是周二，所在周为 9/14 – 9/20。
        let ledger = makeLedger([
            ("2026-09-15 09:00", "2026-09-15 18:00"),
            ("2026-09-16 09:30", "2026-09-16 19:00")
        ])
        let stats = Analytics.periodStats(
            ledger: ledger,
            settings: Settings(),
            granularity: .week,
            containing: date("2026-09-15 20:00"),
            now: date("2026-09-16 20:00"),
            calendar: calendar
        )

        #expect(stats.buckets.count == 7)
        #expect(stats.activeDayCount == 2)
        #expect(abs(stats.totalWorkedSeconds - (9 * 3600 + 9.5 * 3600)) < 1)
        // 目标只累计到今天为止的工作日：周一、周二、周三 = 3 天 × 8h。
        #expect(stats.requiredDayCount == 3)
        #expect(abs(stats.totalTargetSeconds - 24 * 3600) < 1)
        #expect(!stats.isTargetReached)
    }

    @Test func weekendHasNoTargetWithoutOverride() {
        let ledger = makeLedger([("2026-09-19 10:00", "2026-09-19 15:00")])
        let stats = Analytics.periodStats(
            ledger: ledger,
            settings: Settings(),
            granularity: .week,
            containing: date("2026-09-19 20:00"),
            now: date("2026-09-19 20:00"),
            calendar: calendar
        )
        let saturday = stats.days.first { $0.dateKey == "2026-09-19" }!
        #expect(saturday.targetSeconds == 0)
        #expect(saturday.isOffDay)
        #expect(abs(saturday.overtimeSeconds - 5 * 3600) < 1)
    }

    @Test func holidayMakesWorkdayOffAndMakeupDayWorking() {
        let ledger = makeLedger([("2026-10-01 09:00", "2026-10-01 18:00")])
        let holidays: [String: HolidayDay] = [
            "2026-10-01": HolidayDay(date: "2026-10-01", name: "国庆节", isOffDay: true, source: "test"),
            "2026-10-10": HolidayDay(date: "2026-10-10", name: "国庆节", isOffDay: false, source: "test")
        ]
        let stats = Analytics.periodStats(
            ledger: ledger,
            settings: Settings(),
            granularity: .month,
            containing: date("2026-10-10 12:00"),
            now: date("2026-10-10 23:00"),
            holidays: holidays,
            calendar: calendar
        )
        let nationalDay = stats.days.first { $0.dateKey == "2026-10-01" }!
        #expect(nationalDay.isOffDay)
        #expect(nationalDay.targetSeconds == 0)
        #expect(nationalDay.holidayName == "国庆节")

        // 10/10 是周六，但属于调休补班，需要有目标。
        let makeup = stats.days.first { $0.dateKey == "2026-10-10" }!
        #expect(!makeup.isOffDay)
        #expect(makeup.targetSeconds == Settings.defaultDailyTargetSeconds)
    }

    @Test func futureDaysHaveNoTarget() {
        let stats = Analytics.periodStats(
            ledger: WorkTimeLedger(),
            settings: Settings(),
            granularity: .month,
            containing: date("2026-09-15 12:00"),
            now: date("2026-09-15 12:00"),
            calendar: calendar
        )
        let future = stats.days.filter { $0.isFuture }
        #expect(!future.isEmpty)
        #expect(future.allSatisfy { $0.targetSeconds == 0 })
    }

    @Test func quarterAndYearBucketsGroupByMonth() {
        let ledger = makeLedger([("2026-09-15 09:00", "2026-09-15 18:00")])
        let quarter = Analytics.periodStats(
            ledger: ledger, settings: Settings(), granularity: .quarter,
            containing: date("2026-09-15 12:00"), now: date("2026-09-30 23:00"), calendar: calendar
        )
        #expect(quarter.buckets.count == 3)
        #expect(quarter.buckets.map(\.title) == ["7月", "8月", "9月"])
        #expect(abs(quarter.buckets[2].workedSeconds - 9 * 3600) < 1)

        let year = Analytics.periodStats(
            ledger: ledger, settings: Settings(), granularity: .year,
            containing: date("2026-09-15 12:00"), now: date("2026-12-31 23:00"), calendar: calendar
        )
        #expect(year.buckets.count == 12)
        #expect(year.buckets[8].title == "9月")
    }

    @Test func ongoingSessionCountsTowardsStats() throws {
        var ledger = WorkTimeLedger()
        try ledger.clockIn(at: date("2026-09-15 09:00"), source: .manual, calendar: calendar)
        let stats = Analytics.periodStats(
            ledger: ledger, settings: Settings(), granularity: .day,
            containing: date("2026-09-15 12:00"), now: date("2026-09-15 12:00"), calendar: calendar
        )
        #expect(abs(stats.totalWorkedSeconds - 3 * 3600) < 1)
        #expect(!stats.isTargetReached)
    }

    @Test func overtimeIsReportedWhenTargetExceeded() {
        let ledger = makeLedger([("2026-09-15 08:00", "2026-09-15 20:00")])
        let stats = Analytics.periodStats(
            ledger: ledger, settings: Settings(), granularity: .day,
            containing: date("2026-09-15 21:00"), now: date("2026-09-15 21:00"), calendar: calendar
        )
        #expect(stats.isTargetReached)
        #expect(abs(stats.overtimeSeconds - 4 * 3600) < 1)
        #expect(stats.completionRatio == 1)
    }
}
