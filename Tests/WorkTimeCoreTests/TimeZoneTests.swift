import Foundation
import Testing
@testable import WorkTimeCore

@Suite struct TimeZoneTests {
    private let beijing = AppCalendar.calendar(timeZone: AppTimeZone.beijing)

    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = AppTimeZone.beijing
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    @Test func defaultCalendarUsesBeijing() {
        // 2026-09-15 17:30 UTC == 2026-09-16 01:30 北京时间
        let instant = Date(timeIntervalSince1970: 1_789_566_600)
        #expect(AppCalendar.dayKey(for: instant) == "2026-09-16")
        #expect(AppCalendar.dayKey(for: instant, calendar: beijing) == "2026-09-16")
    }

    @Test func settingsDefaultToBeijingAndNormalizeInvalidIdentifiers() {
        #expect(Settings().timeZoneIdentifier == AppTimeZone.beijingIdentifier)
        #expect(Settings().timeZone.secondsFromGMT() == 8 * 3600)
        #expect(Settings().timeZoneDisplayName == "北京时间（UTC+8）")

        var settings = Settings()
        settings.timeZoneIdentifier = "Not/AZone"
        settings.normalize()
        #expect(settings.timeZoneIdentifier == AppTimeZone.beijingIdentifier)
    }

    @Test func settingsDecodingFallsBackToBeijingForLegacyFiles() throws {
        let json = #"{"dailyTargetSeconds": 28800}"#
        let settings = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        #expect(settings.timeZoneIdentifier == AppTimeZone.beijingIdentifier)
        #expect(settings.showDockIcon)
    }

    @Test func systemTimeZoneOptionResolvesToCurrent() {
        var settings = Settings()
        settings.timeZoneIdentifier = AppTimeZone.systemIdentifier
        #expect(settings.timeZone.identifier == TimeZone.current.identifier)
        #expect(settings.timeZoneDisplayName.hasPrefix("跟随系统（"))
    }

    @Test func stateFileWritesBeijingOffsetTimestamps() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("work-time-recorder-tz-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = StateFileStore(directoryURL: directory)
        var state = AppState()
        let start = date("2026-09-15 09:28")
        try state.ledger.clockIn(at: start, source: .manual, calendar: beijing)
        try store.save(state)

        let raw = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(raw.contains("2026-09-15T09:28:00+08:00"))
        #expect(!raw.contains("2026-09-15T01:28:00Z"))

        let loaded = store.load()
        let loadedStart = loaded.ledger.day("2026-09-15").sessions.first?.start
        #expect(loadedStart != nil)
        #expect(abs((loadedStart ?? .distantPast).timeIntervalSince(start)) < 1)
    }

    @Test func legacyUTCStateFilesStillDecode() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("work-time-recorder-legacy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("state.json")
        let legacy = """
        {
          "createdAt": "2026-09-15T08:00:05Z",
          "ledger": {
            "days": {
              "2026-09-15": {
                "dateKey": "2026-09-15",
                "sessions": [
                  {
                    "id": "6F50B53D-42DC-4AA8-91FB-5A5547A2DCB3",
                    "start": "2026-09-15T01:12:00Z",
                    "startSource": "autoUnlock"
                  }
                ],
                "targetNotified": false
              }
            }
          },
          "settings": {"dailyTargetSeconds": 28800}
        }
        """
        try Data(legacy.utf8).write(to: fileURL)

        let loaded = StateFileStore(directoryURL: directory).load()
        let start = loaded.ledger.day("2026-09-15").sessions.first?.start
        #expect(start != nil)
        // 01:12 UTC == 09:12 北京时间
        #expect(AppCalendar.formatter("HH:mm", calendar: beijing).string(from: start!) == "09:12")
        #expect(loaded.settings.timeZoneIdentifier == AppTimeZone.beijingIdentifier)
    }

    @Test func correctFirstClockInMovesEarliestSession() throws {
        var ledger = WorkTimeLedger()
        try ledger.clockIn(at: date("2026-09-15 16:27"), source: .manual, calendar: beijing)
        let corrected = ledger.correctFirstClockInStart(ofDayKey: "2026-09-15", to: date("2026-09-15 09:28"), calendar: beijing)
        #expect(corrected)
        #expect(AppCalendar.formatter("HH:mm", calendar: beijing).string(from: ledger.day("2026-09-15").sessions[0].start) == "09:28")
    }

    @Test func correctFirstClockInRejectsInvalidTargets() throws {
        var ledger = WorkTimeLedger()
        try ledger.clockIn(at: date("2026-09-15 09:00"), source: .manual, calendar: beijing)
        try ledger.clockOut(at: date("2026-09-15 18:00"), source: .manual, calendar: beijing)
        // 晚于下班时间
        let tooLate = ledger.correctFirstClockInStart(ofDayKey: "2026-09-15", to: date("2026-09-15 19:00"), calendar: beijing)
        #expect(!tooLate)
        // 跨到别的一天
        let otherDay = ledger.correctFirstClockInStart(ofDayKey: "2026-09-15", to: date("2026-09-14 09:00"), calendar: beijing)
        #expect(!otherDay)
        // 不存在的日期
        let missingDay = ledger.correctFirstClockInStart(ofDayKey: "2026-09-16", to: date("2026-09-16 09:00"), calendar: beijing)
        #expect(!missingDay)
    }
}
