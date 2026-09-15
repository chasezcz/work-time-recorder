import Foundation
import Testing
@testable import WorkTimeCore

@Suite struct WorkTimeLedgerTests {
    private let calendar = AppCalendar.calendar(timeZone: TimeZone(identifier: "Asia/Shanghai")!)

    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    @Test func clockInCreatesSessionAndDayKey() throws {
        var ledger = WorkTimeLedger()
        try ledger.clockIn(at: date("2026-09-15 09:12"), source: .manual, calendar: calendar)

        #expect(ledger.orderedDayKeys == ["2026-09-15"])
        let day = ledger.day("2026-09-15")
        #expect(day.sessions.count == 1)
        #expect(day.sessions[0].startSource == .manual)
        #expect(day.isWorking)
        #expect(ledger.isWorking)
    }

    @Test func clockInTwiceWhileWorkingIsRejected() throws {
        var ledger = WorkTimeLedger()
        try ledger.clockIn(at: date("2026-09-15 09:00"), source: .manual, calendar: calendar)
        TestHelper.expectError(WorkTimeError.alreadyWorking) {
            try ledger.clockIn(at: date("2026-09-15 10:00"), source: .manual, calendar: calendar)
        }
    }

    @Test func clockOutRecordsEndAndSource() throws {
        var ledger = WorkTimeLedger()
        try ledger.clockIn(at: date("2026-09-15 09:00"), source: .autoUnlock, calendar: calendar)
        try ledger.clockOut(at: date("2026-09-15 18:30"), source: .autoLock, calendar: calendar)

        let session = ledger.day("2026-09-15").sessions[0]
        #expect(session.endSource == .autoLock)
        #expect(!ledger.isWorking)
        let worked = ledger.workedSeconds(forDayKey: "2026-09-15", now: date("2026-09-15 20:00"), calendar: calendar)
        #expect(abs(worked - 9.5 * 3600) < 1)
    }

    @Test func clockOutWithoutActiveSessionThrows() throws {
        var ledger = WorkTimeLedger()
        TestHelper.expectError(WorkTimeError.notWorking) {
            try ledger.clockOut(at: date("2026-09-15 18:00"), source: .manual, calendar: calendar)
        }
    }

    @Test func undoClockOutReopensLatestSession() throws {
        var ledger = WorkTimeLedger()
        try ledger.clockIn(at: date("2026-09-15 09:00"), source: .autoUnlock, calendar: calendar)
        try ledger.clockOut(at: date("2026-09-15 18:00"), source: .autoLock, calendar: calendar)
        #expect(ledger.canUndoClockOut())

        try ledger.undoLastClockOut()
        let session = ledger.day("2026-09-15").sessions[0]
        #expect(session.end == nil)
        #expect(session.endSource == nil)
        #expect(ledger.isWorking)
        #expect(!ledger.canUndoClockOut())
    }

    @Test func undoAfterNewClockInReopensLatestSessionOnly() throws {
        var ledger = WorkTimeLedger()
        try ledger.clockIn(at: date("2026-09-15 09:00"), source: .manual, calendar: calendar)
        try ledger.clockOut(at: date("2026-09-15 12:00"), source: .manual, calendar: calendar)
        try ledger.clockIn(at: date("2026-09-15 13:00"), source: .manual, calendar: calendar)
        try ledger.clockOut(at: date("2026-09-15 18:00"), source: .manual, calendar: calendar)

        try ledger.undoLastClockOut()
        let sessions = ledger.day("2026-09-15").orderedSessions
        #expect(sessions[0].end != nil)
        #expect(sessions[1].end == nil)
    }

    @Test func undoWithoutClockOutThrows() {
        var ledger = WorkTimeLedger()
        TestHelper.expectError(WorkTimeError.nothingToUndo) {
            try ledger.undoLastClockOut()
        }
    }

    @Test func undoWhileWorkingThrows() throws {
        var ledger = WorkTimeLedger()
        try ledger.clockIn(at: date("2026-09-15 09:00"), source: .manual, calendar: calendar)
        TestHelper.expectError(WorkTimeError.alreadyWorking) {
            try ledger.undoLastClockOut()
        }
    }

    @Test func ongoingSessionCountsUntilNow() throws {
        var ledger = WorkTimeLedger()
        try ledger.clockIn(at: date("2026-09-15 09:00"), source: .manual, calendar: calendar)
        let worked = ledger.workedSeconds(forDayKey: "2026-09-15", now: date("2026-09-15 11:30"), calendar: calendar)
        #expect(abs(worked - 2.5 * 3600) < 1)
    }

    @Test func crossMidnightSessionIsClippedToEachDay() throws {
        var ledger = WorkTimeLedger()
        try ledger.clockIn(at: date("2026-09-14 22:00"), source: .manual, calendar: calendar)
        try ledger.clockOut(at: date("2026-09-15 02:00"), source: .manual, calendar: calendar)

        let firstDay = ledger.workedSeconds(forDayKey: "2026-09-14", now: date("2026-09-15 09:00"), calendar: calendar)
        let secondDay = ledger.workedSeconds(forDayKey: "2026-09-15", now: date("2026-09-15 09:00"), calendar: calendar)
        #expect(abs(firstDay - 2 * 3600) < 1)
        #expect(abs(secondDay - 2 * 3600) < 1)
    }

    @Test func activeEntrySurvivesAcrossDays() throws {
        var ledger = WorkTimeLedger()
        try ledger.clockIn(at: date("2026-09-14 22:00"), source: .manual, calendar: calendar)
        #expect(ledger.activeEntry()?.dateKey == "2026-09-14")
        #expect(ledger.isWorking)

        try ledger.clockOut(at: date("2026-09-15 01:00"), source: .autoLock, calendar: calendar)
        #expect(!ledger.isWorking)
    }

    @Test func targetOverrideTakesPrecedence() throws {
        var ledger = WorkTimeLedger()
        try ledger.clockIn(at: date("2026-09-15 09:00"), source: .manual, calendar: calendar)
        ledger.setTargetOverride(6 * 3600, dayKey: "2026-09-15")
        #expect(ledger.targetSeconds(forDayKey: "2026-09-15", settings: Settings()) == 6 * 3600)
        ledger.setTargetOverride(nil, dayKey: "2026-09-15")
        #expect(ledger.targetSeconds(forDayKey: "2026-09-15", settings: Settings()) == Settings.defaultDailyTargetSeconds)
    }

    @Test func markTargetNotified() {
        var ledger = WorkTimeLedger()
        ledger.markTargetNotified(dayKey: "2026-09-15")
        #expect(ledger.day("2026-09-15").targetNotified)
        ledger.clearTargetNotified(dayKey: "2026-09-15")
        #expect(!ledger.day("2026-09-15").targetNotified)
    }
}
