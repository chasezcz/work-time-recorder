import AppKit
import WorkTimeCore

/// `--demo`：注入内存演示数据并打开窗口，方便截图与视觉检查（不会写入磁盘）。
@MainActor
enum DemoMode {
    static func apply(to store: AppStore) {
        store.applyDemoState(makeState(calendar: store.calendar))
    }

    static func makeState(calendar: Calendar = AppCalendar.calendar()) -> AppState {
        var state = AppState()
        var ledger = WorkTimeLedger()
        let now = Date()

        func at(_ daysAgo: Int, _ hour: Int, _ minute: Int) -> Date? {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now)) else { return nil }
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
        }

        // 今天：09:12 自动解锁上班，仍在进行中
        if let start = at(0, 9, 12) {
            try? ledger.clockIn(at: start, source: .autoUnlock, calendar: calendar)
        }

        // 最近几天：不同长度的完整打卡记录，用于周/月图表
        let history: [(daysAgo: Int, start: (Int, Int), end: (Int, Int))] = [
            (1, (9, 5), (18, 35)),
            (2, (9, 30), (19, 10)),
            (3, (8, 50), (17, 40)),
            (4, (9, 15), (20, 5)),
            (5, (9, 0), (17, 30))
        ]
        for item in history {
            guard let start = at(item.daysAgo, item.start.0, item.start.1),
                  let end = at(item.daysAgo, item.end.0, item.end.1) else { continue }
            try? ledger.clockIn(at: start, source: .autoUnlock, calendar: calendar)
            try? ledger.clockOut(at: end, source: .autoLock, calendar: calendar)
        }

        state.ledger = ledger
        state.settings.dailyTargetSeconds = 8 * 3600
        state.settings.automaticClockInEnabled = true
        state.settings.automaticClockOutEnabled = true
        state.settings.autoClockInHour = 4

        let year = calendar.component(.year, from: now)
        if state.holidays(countryCode: "CN", year: year).isEmpty {
            state.holidays[HolidayDay.cacheKey(countryCode: "CN", year: year)] = [
                HolidayDay(date: "\(year)-01-01", name: "元旦", isOffDay: true, source: "holiday-cn"),
                HolidayDay(date: "\(year)-02-17", name: "春节", isOffDay: true, source: "holiday-cn"),
                HolidayDay(date: "\(year)-02-14", name: "春节", isOffDay: false, source: "holiday-cn"),
                HolidayDay(date: "\(year)-05-01", name: "劳动节", isOffDay: true, source: "holiday-cn"),
                HolidayDay(date: "\(year)-06-19", name: "端午节", isOffDay: true, source: "holiday-cn"),
                HolidayDay(date: "\(year)-09-25", name: "中秋节", isOffDay: true, source: "holiday-cn"),
                HolidayDay(date: "\(year)-10-01", name: "国庆节", isOffDay: true, source: "holiday-cn")
            ]
            state.lastHolidayRefresh[HolidayDay.cacheKey(countryCode: "CN", year: year)] = now
        }
        return state
    }
}
