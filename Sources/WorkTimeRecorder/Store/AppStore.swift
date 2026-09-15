import AppKit
import Combine
import Foundation
import WorkTimeCore

/// 应用状态中心：负责持久化、自动打卡调度、节假日缓存和统计数据组装。
@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()

    enum HolidayState: Equatable {
        case idle
        case loading
        case updated(Date)
        case failed(String)
    }

    /// 最近一次自动/手动动作，用于界面上的轻量反馈。
    struct LastEvent: Equatable {
        var message: String
        var date: Date
    }

    @Published private(set) var state: AppState
    @Published private(set) var now: Date = Date()
    @Published private(set) var holidayState: HolidayState = .idle
    @Published private(set) var lastEvent: LastEvent?

    let fileStore: StateFileStore
    private let holidayService: HolidayService
    private let screenMonitor: ScreenLockMonitor
    private var tickTimer: Timer?
    private var isStarted = false
    /// 演示模式下禁止写盘，避免演示数据污染真实记录。
    private(set) var isDemoMode = false

    /// 时区口径：默认北京时间，可在设置里切换为跟随系统。
    var timeZone: TimeZone { state.settings.timeZone }

    var calendar: Calendar { AppCalendar.calendar(timeZone: timeZone) }

    init(
        fileStore: StateFileStore = StateFileStore(),
        holidayService: HolidayService = HolidayService(),
        screenMonitor: ScreenLockMonitor = ScreenLockMonitor()
    ) {
        self.fileStore = fileStore
        self.holidayService = holidayService
        self.screenMonitor = screenMonitor
        self.state = fileStore.load()
    }

    // MARK: - 生命周期

    func start() {
        guard !isStarted else { return }
        isStarted = true

        applyActivationPolicy()
        NotificationService.shared.requestAuthorizationIfNeeded()

        screenMonitor.onUnlock = { [weak self] in
            Task { @MainActor in self?.handleBecameActive() }
        }
        screenMonitor.onLock = { [weak self] in
            Task { @MainActor in self?.handleScreenLocked() }
        }
        screenMonitor.start()

        startTicking()
        tick()

        // 每次启动都尝试刷新节假日，失败时继续使用本地缓存。
        let year = calendar.component(.year, from: now)
        Task { await refreshHolidays(years: [year, year + 1]) }
    }

    private func startTicking() {
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    func tick() {
        now = Date()
        checkTargetReminder()
    }

    // MARK: - 派生状态

    var settings: Settings { state.settings }
    var ledger: WorkTimeLedger { state.ledger }

    var todayKey: String { AppCalendar.dayKey(for: now, calendar: calendar) }

    var activeEntry: (dateKey: String, session: WorkSession)? { state.ledger.activeEntry() }

    var isWorking: Bool { state.ledger.isWorking }

    var canUndoClockOut: Bool { state.ledger.canUndoClockOut() }

    var todayWorkedSeconds: TimeInterval {
        AutoClockPolicy.workedSecondsToday(ledger: state.ledger, now: now, calendar: calendar)
    }

    var todayTargetSeconds: TimeInterval {
        state.ledger.targetSeconds(forDayKey: todayKey, settings: state.settings)
    }

    var todayProgress: Double {
        guard todayTargetSeconds > 0 else { return todayWorkedSeconds > 0 ? 1 : 0 }
        return min(1, todayWorkedSeconds / todayTargetSeconds)
    }

    var remainingSeconds: TimeInterval { max(0, todayTargetSeconds - todayWorkedSeconds) }

    var todayDay: WorkDay { state.ledger.day(todayKey) }

    var todaySessions: [WorkSession] { todayDay.orderedSessions }

    var hasTodayRecords: Bool { !todayDay.sessions.isEmpty }

    var todayHoliday: HolidayDay? { currentHolidayIndex[todayKey] }

    var todayIsOffDay: Bool {
        if let holiday = todayHoliday { return holiday.isOffDay }
        return AppCalendar.isWeekend(now, calendar: calendar)
    }

    var todayHasCustomTarget: Bool { todayDay.targetSecondsOverride != nil }

    var statusTitle: String {
        if isWorking {
            return activeEntry?.dateKey == todayKey ? "上班中" : "上班中 · 跨天"
        }
        if hasTodayRecords {
            if todayTargetSeconds > 0 && todayWorkedSeconds >= todayTargetSeconds { return "已达标" }
            return "已下班"
        }
        if todayIsOffDay { return "休息日" }
        return "未打卡"
    }

    var statusSubtitle: String {
        if isWorking {
            return todayTargetSeconds > 0 && remainingSeconds > 0
                ? "距离目标还差 \(DurationFormat.text(remainingSeconds))"
                : "今日目标已完成"
        }
        if hasTodayRecords {
            return "今日累计 \(DurationFormat.text(todayWorkedSeconds))"
        }
        if todayIsOffDay {
            return "今天休息，也可以手动打卡"
        }
        return "等待上班打卡"
    }

    var dayTitle: String {
        let day = AppCalendar.dayLabel(now, calendar: calendar)
        let weekday = AppCalendar.weekdayName(now, calendar: calendar)
        return "\(day) \(weekday)"
    }

    var menuBarText: String {
        guard settings.showTimeInMenuBar, hasTodayRecords || isWorking else { return "" }
        return DurationFormat.compact(todayWorkedSeconds)
    }

    var dataFileURL: URL { fileStore.fileURL }

    private var currentHolidayIndex: [String: HolidayDay] {
        let year = calendar.component(.year, from: now)
        return state.holidayIndex(countryCode: state.settings.holidayCountryCode, years: [year - 1, year, year + 1])
    }

    // MARK: - 打卡动作

    func clockIn(source: ClockSource = .manual) {
        let date = Date()
        var ledger = state.ledger
        do {
            try ledger.clockIn(at: date, source: source, calendar: calendar)
            state.ledger = ledger
            setLastEvent(source == .manual ? "已打上班卡 \(Self.timeText(date))" : "已自动记录上班 \(Self.timeText(date))")
            persist()
            tick()
        } catch {
            setLastEvent("上班打卡失败：\(error.localizedDescription)")
        }
    }

    func clockOut(source: ClockSource = .manual) {
        let date = Date()
        var ledger = state.ledger
        do {
            try ledger.clockOut(at: date, source: source, calendar: calendar)
            state.ledger = ledger
            setLastEvent(source == .manual ? "已打下班卡 \(Self.timeText(date))" : "已自动记录下班 \(Self.timeText(date))")
            persist()
            tick()
        } catch {
            setLastEvent("下班打卡失败：\(error.localizedDescription)")
        }
    }

    /// 撤回最近一次下班打卡，用于“回来加班”。
    func undoLastClockOut() {
        var ledger = state.ledger
        do {
            try ledger.undoLastClockOut()
            state.ledger = ledger
            setLastEvent("已撤销下班，恢复上班中")
            persist()
            tick()
        } catch {
            setLastEvent("撤销失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 自动打卡

    /// 解锁或唤醒后：当天还没打过卡、且已过时间门槛，则自动开始上班。
    private func handleBecameActive() {
        let date = Date()
        now = date

        guard AutoClockPolicy.shouldAutoClockIn(
            settings: state.settings,
            ledger: state.ledger,
            now: date,
            calendar: calendar
        ) else { return }

        var ledger = state.ledger
        do {
            try ledger.clockIn(at: date, source: .autoUnlock, calendar: calendar)
            state.ledger = ledger
            setLastEvent("已自动记录上班 \(Self.timeText(date))（首次解锁）")
            persist()
        } catch {
            NSLog("[WorkTimeRecorder] 自动上班失败：%@", String(describing: error))
        }
    }

    /// 锁屏或休眠后：工时已达标则自动记录下班。
    private func handleScreenLocked() {
        let date = Date()
        now = date

        guard AutoClockPolicy.shouldAutoClockOut(
            settings: state.settings,
            ledger: state.ledger,
            now: date,
            calendar: calendar
        ) else { return }

        var ledger = state.ledger
        do {
            try ledger.clockOut(at: date, source: .autoLock, calendar: calendar)
            state.ledger = ledger
            setLastEvent("工时已达标，锁屏自动记录下班 \(Self.timeText(date))")
            persist()
            NotificationService.shared.notify(
                title: "已自动记录下班",
                body: "今天已工作 \(DurationFormat.text(todayWorkedSeconds))，锁屏时间已记为下班。回来加班可以在菜单里点“撤销下班”。",
                identifier: "auto-clock-out-\(todayKey)"
            )
        } catch {
            NSLog("[WorkTimeRecorder] 自动下班失败：%@", String(describing: error))
        }
    }

    /// 工时达标时发一次系统通知。
    private func checkTargetReminder() {
        guard AutoClockPolicy.shouldNotifyTargetReached(
            settings: state.settings,
            ledger: state.ledger,
            now: now,
            calendar: calendar
        ) else { return }

        var ledger = state.ledger
        ledger.markTargetNotified(dayKey: todayKey)
        state.ledger = ledger
        persist()

        NotificationService.shared.notify(
            title: "工时目标已完成 🎉",
            body: "今天已工作 \(DurationFormat.text(todayWorkedSeconds))，可以下班啦。锁屏后会自动记录下班时间。",
            identifier: "target-reached-\(todayKey)"
        )
    }

    // MARK: - 设置

    func updateSettings(_ mutate: (inout Settings) -> Void) {
        var settings = state.settings
        mutate(&settings)
        settings.normalize()
        state.settings = settings
        applyActivationPolicy()
        persist()
        tick()
    }

    /// 根据设置切换“常规应用（有 Dock 图标、可参与台前调度）”与“仅状态栏”形态。
    func applyActivationPolicy() {
        let policy: NSApplication.ActivationPolicy = state.settings.showDockIcon ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
    }

    /// 修正某天首次打卡时间，用于补录/纠正上班时间。
    @discardableResult
    func correctFirstClockIn(ofDayKey key: String, to date: Date) -> Bool {
        var ledger = state.ledger
        guard ledger.correctFirstClockInStart(ofDayKey: key, to: date, calendar: calendar) else {
            setLastEvent("修正失败：新的时间需要早于下班时间，且在同一天内")
            return false
        }
        state.ledger = ledger
        let label = AppCalendar.formatter("HH:mm", calendar: calendar).string(from: date)
        setLastEvent("已把 \(AppCalendar.dayLabel(date, calendar: calendar)) 的首次打卡修正为 \(label)")
        persist()
        tick()
        return true
    }

    func setDailyTarget(hours: Double) {
        updateSettings { $0.dailyTargetSeconds = max(60, min(hours, 24) * 3600) }
    }

    func setTodayTarget(hours: Double?) {
        var ledger = state.ledger
        ledger.setTargetOverride(hours.map { max(0.5, min($0, 24)) * 3600 }, dayKey: todayKey)
        state.ledger = ledger
        persist()
        tick()
    }

    func resetAllData() {
        var ledger = WorkTimeLedger()
        ledger.removeAll()
        state.ledger = ledger
        persist()
        setLastEvent("已清空全部打卡数据")
        tick()
    }

    /// 仅用于 `--demo` 与截图：替换内存状态，不写入磁盘。
    func applyDemoState(_ newState: AppState) {
        isDemoMode = true
        state = newState
        tick()
    }

    func revealDataFileInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([fileStore.fileURL])
    }

    // MARK: - 节假日

    func holidays(countryCode: String? = nil, year: Int) -> [HolidayDay] {
        state.holidays(countryCode: countryCode ?? settings.holidayCountryCode, year: year)
    }

    func lastHolidayRefresh(year: Int) -> Date? {
        state.lastHolidayRefresh[HolidayDay.cacheKey(countryCode: settings.holidayCountryCode, year: year)]
    }

    /// 拉取指定年份的节假日并写入缓存；不传年份时刷新今年与明年。
    func refreshHolidays(years: [Int]? = nil) async {
        let countryCode = settings.holidayCountryCode
        let currentYear = calendar.component(.year, from: Date())
        let targetYears = (years ?? [currentYear, currentYear + 1]).sorted()
        holidayState = .loading

        var successCount = 0
        var errors: [String] = []

        for year in targetYears {
            let key = HolidayDay.cacheKey(countryCode: countryCode, year: year)
            do {
                let days = try await holidayService.fetch(year: year, countryCode: countryCode)
                var newState = state
                newState.holidays[key] = days
                newState.lastHolidayRefresh[key] = Date()
                state = newState
                successCount += 1
            } catch {
                errors.append("\(year) 年：\(error.localizedDescription)")
            }
        }

        if successCount > 0 {
            persist()
            holidayState = .updated(Date())
        } else {
            holidayState = .failed(errors.joined(separator: "；"))
        }
    }

    /// 缓存缺失时才拉取（供分析窗口按年份懒加载）。
    func ensureHolidaysLoaded(forInterval interval: DateInterval) {
        let years = yearsSpanned(by: interval)
        let missing = years.filter { holidays(year: $0).isEmpty }
        guard !missing.isEmpty else { return }
        Task { await refreshHolidays(years: missing) }
    }

    func yearsSpanned(by interval: DateInterval) -> [Int] {
        let startYear = calendar.component(.year, from: interval.start)
        let lastMoment = calendar.date(byAdding: .second, value: -1, to: interval.end) ?? interval.end
        let endYear = calendar.component(.year, from: lastMoment)
        return Array(Set([startYear, endYear])).sorted()
    }

    func holidayIndex(for interval: DateInterval) -> [String: HolidayDay] {
        state.holidayIndex(countryCode: settings.holidayCountryCode, years: yearsSpanned(by: interval))
    }

    // MARK: - 统计与导出

    /// `offset` 为相对当前周期的偏移，0 表示当前周期。
    func periodStats(granularity: PeriodGranularity, offset: Int = 0) -> PeriodStats {
        let current = AppCalendar.interval(for: granularity, containing: now, calendar: calendar)
        let interval = AppCalendar.interval(current, shiftedBy: granularity, offset: offset, calendar: calendar)
        return Analytics.periodStats(
            ledger: state.ledger,
            settings: state.settings,
            granularity: granularity,
            containing: interval.start,
            now: now,
            holidays: holidayIndex(for: interval),
            calendar: calendar
        )
    }

    func exportInterval(for preset: ExportPreset) -> DateInterval {
        preset.interval(ledger: state.ledger, now: now, calendar: calendar)
    }

    func sessionsCSV(preset: ExportPreset) -> String {
        let interval = exportInterval(for: preset)
        return CSVExport.sessionsCSV(
            ledger: state.ledger,
            interval: interval,
            now: now,
            holidays: holidayIndex(for: interval),
            calendar: calendar
        )
    }

    func summaryCSV(preset: ExportPreset) -> String {
        let interval = exportInterval(for: preset)
        return CSVExport.dailySummaryCSV(
            ledger: state.ledger,
            settings: state.settings,
            interval: interval,
            now: now,
            holidays: holidayIndex(for: interval),
            calendar: calendar
        )
    }

    func exportPreview(preset: ExportPreset) -> (days: Int, sessions: Int, workedSeconds: TimeInterval) {
        let interval = exportInterval(for: preset)
        let sessions = state.ledger.sessions(in: interval, now: now)
        let worked = sessions.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        let dayKeys = Set(sessions.map { AppCalendar.dayKey(for: $0.start, calendar: calendar) })
        return (dayKeys.count, sessions.count, worked)
    }

    // MARK: - 内部工具

    private func setLastEvent(_ message: String) {
        lastEvent = LastEvent(message: message, date: Date())
    }

    /// 订阅状态变化（界面层使用，回调在主线程下一次循环触发）。
    func observe(_ handler: @escaping () -> Void) -> AnyCancellable {
        objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { _ in handler() }
    }

    private func persist() {
        guard !isDemoMode else { return }
        do {
            try fileStore.save(state)
        } catch {
            NSLog("[WorkTimeRecorder] 保存失败：%@", String(describing: error))
        }
    }

    private static func timeText(_ date: Date) -> String {
        let formatter = AppCalendar.formatter("HH:mm")
        return formatter.string(from: date)
    }
}
