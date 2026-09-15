import Foundation
import Testing
@testable import WorkTimeCore

@Suite struct ExportAndPersistenceTests {
    private let calendar = AppCalendar.calendar(timeZone: TimeZone(identifier: "Asia/Shanghai")!)

    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    private func temporaryDirectory(_ name: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("work-time-recorder-tests-\(name)-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func sessionsCSVContainsHeaderAndRow() throws {
        var ledger = WorkTimeLedger()
        try ledger.clockIn(at: date("2026-09-15 09:05"), source: .autoUnlock, calendar: calendar)
        try ledger.clockOut(at: date("2026-09-15 18:35"), source: .manual, calendar: calendar)
        let interval = AppCalendar.interval(for: .day, containing: date("2026-09-15 12:00"), calendar: calendar)

        let csv = CSVExport.sessionsCSV(
            ledger: ledger,
            settings: Settings(),
            interval: interval,
            now: date("2026-09-15 20:00"),
            calendar: calendar
        )
        #expect(csv.hasPrefix("\u{FEFF}"))
        let lines = csv.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].contains("日期,星期,节假日,开始时间"))
        #expect(lines[1].contains("2026-09-15,周二"))
        #expect(lines[0].contains("午休扣除"))
        #expect(lines[1].contains("09:05,18:35,9.50,1.50,8.00"))
        #expect(lines[1].contains("解锁自动上班"))
    }

    @Test func sessionsCSVMarksOngoingSession() throws {
        var ledger = WorkTimeLedger()
        try ledger.clockIn(at: date("2026-09-15 09:00"), source: .manual, calendar: calendar)
        let interval = AppCalendar.interval(for: .day, containing: date("2026-09-15 12:00"), calendar: calendar)
        let csv = CSVExport.sessionsCSV(
            ledger: ledger,
            settings: Settings(),
            interval: interval,
            now: date("2026-09-15 12:00"),
            calendar: calendar
        )
        #expect(csv.contains("进行中"))
    }

    @Test func dailySummaryCSVHasOneRowPerDay() throws {
        var ledger = WorkTimeLedger()
        try ledger.clockIn(at: date("2026-09-15 09:00"), source: .manual, calendar: calendar)
        try ledger.clockOut(at: date("2026-09-15 18:00"), source: .manual, calendar: calendar)
        let interval = AppCalendar.interval(for: .week, containing: date("2026-09-15 12:00"), calendar: calendar)
        let csv = CSVExport.dailySummaryCSV(
            ledger: ledger,
            settings: Settings(),
            interval: interval,
            now: date("2026-09-20 23:00"),
            calendar: calendar
        )
        let lines = csv.split(separator: "\n")
        #expect(lines.count == 8) // 表头 + 7 天
        #expect(csv.contains("2026-09-15,周二,工作日"))
        // 09:00–18:00 毛 9 小时，扣除默认午休 1.5 小时后净 7.5 小时，未达标
        #expect(csv.contains("8.00,1.50,7.50"))
        #expect(csv.contains("未达标"))
        #expect(csv.contains("2026-09-19,周六,休息日"))
    }

    @Test func csvEscapesSpecialCharacters() throws {
        let json = """
        {"year": 2026, "days": [{"name": "测试,含逗号", "date": "2026-01-01", "isOffDay": true}]}
        """
        let holiday = try HolidayService.decodeChinaHoliday(Data(json.utf8))[0]
        var ledger = WorkTimeLedger()
        try ledger.clockIn(at: date("2026-01-01 10:00"), source: .manual, calendar: calendar)
        let interval = AppCalendar.interval(for: .day, containing: date("2026-01-01 12:00"), calendar: calendar)
        let csv = CSVExport.sessionsCSV(
            ledger: ledger,
            settings: Settings(),
            interval: interval,
            now: date("2026-01-01 12:00"),
            holidays: ["2026-01-01": holiday],
            calendar: calendar
        )
        #expect(csv.contains("\"测试,含逗号\""))
    }

    @Test func exportPresetAllSpansRecordedDays() throws {
        var ledger = WorkTimeLedger()
        try ledger.clockIn(at: date("2026-08-01 09:00"), source: .manual, calendar: calendar)
        try ledger.clockOut(at: date("2026-08-01 18:00"), source: .manual, calendar: calendar)
        let interval = ExportPreset.all.interval(ledger: ledger, now: date("2026-09-15 12:00"), calendar: calendar)
        #expect(AppCalendar.dayKey(for: interval.start, calendar: calendar) == "2026-08-01")
        #expect(AppCalendar.dayKey(for: interval.end, calendar: calendar) == "2026-09-16")
    }

    @Test func stateRoundTripThroughDisk() throws {
        let directory = temporaryDirectory("roundtrip")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = StateFileStore(directoryURL: directory)
        var state = AppState()
        try state.ledger.clockIn(at: date("2026-09-15 09:00"), source: .manual, calendar: calendar)
        state.settings.dailyTargetSeconds = 7.5 * 3600
        state.holidays["CN-2026"] = [HolidayDay(date: "2026-01-01", name: "元旦", isOffDay: true, source: "test")]
        try store.save(state)

        let loaded = store.load()
        #expect(loaded.settings.dailyTargetSeconds == 7.5 * 3600)
        #expect(loaded.ledger.day("2026-09-15").sessions.count == 1)
        #expect(loaded.holidays(countryCode: "CN", year: 2026).count == 1)
    }

    @Test func corruptStateIsBackedUpInsteadOfCrashing() throws {
        let directory = temporaryDirectory("corrupt")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = StateFileStore(directoryURL: directory)
        try Data("{ not json".utf8).write(to: store.fileURL)
        let loaded = store.load()
        #expect(loaded.ledger.days.isEmpty)
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("state-corrupt-") }
        #expect(backups.count == 1)
    }

    @Test func settingsDecodingToleratesMissingFields() throws {
        let json = #"{"dailyTargetSeconds": 21600}"#
        let settings = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        #expect(settings.dailyTargetSeconds == 21600)
        #expect(settings.autoClockInHour == 4)
        #expect(settings.notifyWhenTargetReached)
    }

    @Test func settingsNormalizeClampsValues() {
        var settings = Settings()
        settings.autoClockInHour = 99
        settings.autoClockInMinute = -5
        settings.holidayCountryCode = "  "
        settings.normalize()
        #expect(settings.autoClockInHour == 23)
        #expect(settings.autoClockInMinute == 0)
        #expect(settings.holidayCountryCode == "CN")
    }
}
