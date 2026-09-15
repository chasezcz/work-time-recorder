import Foundation
import Testing
@testable import WorkTimeCore

@Suite struct CalendarTests {
    private let calendar = AppCalendar.calendar(timeZone: TimeZone(identifier: "Asia/Shanghai")!)

    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    @Test func dayKeyRoundTrip() {
        let day = date("2026-09-15 10:00")
        #expect(AppCalendar.dayKey(for: day, calendar: calendar) == "2026-09-15")
        let back = AppCalendar.date(fromDayKey: "2026-09-15", calendar: calendar)
        #expect(back != nil)
        #expect(AppCalendar.dayKey(for: back!, calendar: calendar) == "2026-09-15")
        #expect(AppCalendar.date(fromDayKey: "bad-key", calendar: calendar) == nil)
    }

    @Test func weekStartsOnMonday() {
        let interval = AppCalendar.interval(for: .week, containing: date("2026-09-15 12:00"), calendar: calendar)
        #expect(AppCalendar.dayKey(for: interval.start, calendar: calendar) == "2026-09-14")
        #expect(AppCalendar.dayKey(for: interval.end, calendar: calendar) == "2026-09-21")
    }

    @Test func monthInterval() {
        let interval = AppCalendar.interval(for: .month, containing: date("2026-09-15 12:00"), calendar: calendar)
        #expect(AppCalendar.dayKey(for: interval.start, calendar: calendar) == "2026-09-01")
        #expect(AppCalendar.dayKey(for: interval.end, calendar: calendar) == "2026-10-01")
    }

    @Test func quarterInterval() {
        let interval = AppCalendar.interval(for: .quarter, containing: date("2026-09-15 12:00"), calendar: calendar)
        #expect(AppCalendar.dayKey(for: interval.start, calendar: calendar) == "2026-07-01")
        #expect(AppCalendar.dayKey(for: interval.end, calendar: calendar) == "2026-10-01")
    }

    @Test func yearInterval() {
        let interval = AppCalendar.interval(for: .year, containing: date("2026-09-15 12:00"), calendar: calendar)
        #expect(AppCalendar.dayKey(for: interval.start, calendar: calendar) == "2026-01-01")
        #expect(AppCalendar.dayKey(for: interval.end, calendar: calendar) == "2027-01-01")
    }

    @Test func shiftedIntervals() {
        let thisMonth = AppCalendar.interval(for: .month, containing: date("2026-09-15 12:00"), calendar: calendar)
        let lastMonth = AppCalendar.interval(thisMonth, shiftedBy: .month, offset: -1, calendar: calendar)
        #expect(AppCalendar.dayKey(for: lastMonth.start, calendar: calendar) == "2026-08-01")

        let thisQuarter = AppCalendar.interval(for: .quarter, containing: date("2026-09-15 12:00"), calendar: calendar)
        let nextQuarter = AppCalendar.interval(thisQuarter, shiftedBy: .quarter, offset: 1, calendar: calendar)
        #expect(AppCalendar.dayKey(for: nextQuarter.start, calendar: calendar) == "2026-10-01")
        #expect(AppCalendar.dayKey(for: nextQuarter.end, calendar: calendar) == "2027-01-01")

        let thisYear = AppCalendar.interval(for: .year, containing: date("2026-09-15 12:00"), calendar: calendar)
        let lastYear = AppCalendar.interval(thisYear, shiftedBy: .year, offset: -1, calendar: calendar)
        #expect(AppCalendar.dayKey(for: lastYear.start, calendar: calendar) == "2025-01-01")

        let nextWeek = AppCalendar.interval(
            AppCalendar.interval(for: .week, containing: date("2026-09-15 12:00"), calendar: calendar),
            shiftedBy: .week,
            offset: 1,
            calendar: calendar
        )
        #expect(AppCalendar.dayKey(for: nextWeek.start, calendar: calendar) == "2026-09-21")
    }

    @Test func daysInInterval() {
        let interval = AppCalendar.interval(for: .week, containing: date("2026-09-15 12:00"), calendar: calendar)
        let days = AppCalendar.days(in: interval, calendar: calendar)
        #expect(days.count == 7)
        #expect(AppCalendar.dayKey(for: days.first!, calendar: calendar) == "2026-09-14")
        #expect(AppCalendar.dayKey(for: days.last!, calendar: calendar) == "2026-09-20")
    }

    @Test func weekdayHelpers() {
        #expect(AppCalendar.weekdayName(date("2026-09-14 12:00"), calendar: calendar) == "周一")
        #expect(AppCalendar.weekdayName(date("2026-09-20 12:00"), calendar: calendar) == "周日")
        #expect(AppCalendar.isWeekend(date("2026-09-19 12:00"), calendar: calendar))
        #expect(!AppCalendar.isWeekend(date("2026-09-15 12:00"), calendar: calendar))
    }

    @Test func intervalDescription() {
        let month = AppCalendar.interval(for: .month, containing: date("2026-09-15 12:00"), calendar: calendar)
        #expect(AppCalendar.describe(month, granularity: .month, calendar: calendar) == "2026年9月")
        let quarter = AppCalendar.interval(for: .quarter, containing: date("2026-09-15 12:00"), calendar: calendar)
        #expect(AppCalendar.describe(quarter, granularity: .quarter, calendar: calendar) == "2026年 Q3")
        let day = AppCalendar.interval(for: .day, containing: date("2026-09-15 12:00"), calendar: calendar)
        #expect(AppCalendar.describe(day, granularity: .day, calendar: calendar) == "9月15日 周二")
    }

    @Test func durationFormatting() {
        #expect(DurationFormat.text(8 * 3600) == "8 小时")
        #expect(DurationFormat.text(8 * 3600 + 30 * 60) == "8 小时 30 分")
        #expect(DurationFormat.compact(4 * 3600 + 5 * 60) == "4h5m")
        #expect(DurationFormat.decimalHours(9.5 * 3600) == "9.5")
        #expect(DurationFormat.clock(8 * 3600 + 5 * 60) == "08:05")
    }
}
