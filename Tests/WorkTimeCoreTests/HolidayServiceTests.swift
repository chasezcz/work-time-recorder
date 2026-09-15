import Foundation
import Testing
@testable import WorkTimeCore

@Suite struct HolidayServiceTests {
    @Test func decodeChinaHoliday() throws {
        let json = """
        {
            "year": 2026,
            "days": [
                {"name": "元旦", "date": "2026-01-02", "isOffDay": true},
                {"name": "元旦", "date": "2026-01-01", "isOffDay": true},
                {"name": "元旦", "date": "2026-01-04", "isOffDay": false}
            ]
        }
        """
        let days = try HolidayService.decodeChinaHoliday(Data(json.utf8))
        #expect(days.count == 3)
        #expect(days.map(\.date) == ["2026-01-01", "2026-01-02", "2026-01-04"])
        #expect(days[0].isOffDay)
        #expect(days[0].name == "元旦")
        #expect(days[0].source == "holiday-cn")
        #expect(!days[2].isOffDay)
    }

    @Test func decodeNager() throws {
        let json = """
        [
            {"date": "2026-01-01", "localName": "元旦", "name": "New Year's Day", "countryCode": "CN", "global": true, "types": ["Public"]}
        ]
        """
        let days = try HolidayService.decodeNager(Data(json.utf8))
        #expect(days.count == 1)
        #expect(days[0].date == "2026-01-01")
        #expect(days[0].name == "元旦")
        #expect(days[0].isOffDay)
        #expect(days[0].source == "nager")
    }

    @Test func decodeNagerSkipsInvalidDates() throws {
        let json = """
        [
            {"date": "2026-1-1", "localName": "无效", "name": "Invalid", "global": true}
        ]
        """
        let days = try HolidayService.decodeNager(Data(json.utf8))
        #expect(days.isEmpty)
    }

    @Test func cacheKey() {
        #expect(HolidayDay.cacheKey(countryCode: "cn", year: 2026) == "CN-2026")
    }

    @Test func stateHolidayIndex() {
        var state = AppState()
        state.holidays["CN-2026"] = [
            HolidayDay(date: "2026-01-01", name: "元旦", isOffDay: true, source: "test")
        ]
        let index = state.holidayIndex(countryCode: "CN", years: [2026])
        #expect(index["2026-01-01"]?.name == "元旦")
        #expect(state.holidays(countryCode: "CN", year: 2027).isEmpty)
    }
}
