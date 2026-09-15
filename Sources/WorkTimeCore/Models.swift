import Foundation

/// 打卡来源：手动、解锁自动上班、锁屏自动下班。
public enum ClockSource: String, Codable, CaseIterable, Sendable {
    case manual
    case autoUnlock
    case autoLock

    public var displayName: String {
        switch self {
        case .manual: return "手动打卡"
        case .autoUnlock: return "解锁自动上班"
        case .autoLock: return "锁屏自动下班"
        }
    }

    public var shortName: String {
        switch self {
        case .manual: return "手动"
        case .autoUnlock: return "自动·解锁"
        case .autoLock: return "自动·锁屏"
        }
    }

    public var symbolName: String {
        switch self {
        case .manual: return "hand.tap"
        case .autoUnlock: return "lock.open"
        case .autoLock: return "lock"
        }
    }
}

/// 一段连续的上班记录。`end == nil` 表示仍在上班中。
public struct WorkSession: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var start: Date
    public var end: Date?
    public var startSource: ClockSource
    public var endSource: ClockSource?

    public init(
        id: UUID = UUID(),
        start: Date,
        end: Date? = nil,
        startSource: ClockSource,
        endSource: ClockSource? = nil
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.startSource = startSource
        self.endSource = endSource
    }

    public var isActive: Bool { end == nil }

    public func duration(until now: Date) -> TimeInterval {
        max(0, (end ?? now).timeIntervalSince(start))
    }
}

/// 一天的工时数据：日期键为 `yyyy-MM-dd`，包含当天所有打卡片段。
public struct WorkDay: Codable, Equatable, Sendable {
    public var dateKey: String
    public var sessions: [WorkSession]
    /// 当天单独设置的目标工时；为空表示沿用全局目标。
    public var targetSecondsOverride: TimeInterval?
    /// 当天是否已经发过“目标达成，可以下班”的提醒。
    public var targetNotified: Bool

    public init(
        dateKey: String,
        sessions: [WorkSession] = [],
        targetSecondsOverride: TimeInterval? = nil,
        targetNotified: Bool = false
    ) {
        self.dateKey = dateKey
        self.sessions = sessions
        self.targetSecondsOverride = targetSecondsOverride
        self.targetNotified = targetNotified
    }

    public var isWorking: Bool { sessions.contains { $0.isActive } }

    /// 按开始时间排序后的打卡片段。
    public var orderedSessions: [WorkSession] {
        sessions.sorted { $0.start < $1.start }
    }
}

/// 应用设置。
public struct Settings: Codable, Equatable, Sendable {
    public static let defaultDailyTargetSeconds: TimeInterval = 8 * 3600

    /// 每日目标工时（秒）。
    public var dailyTargetSeconds: TimeInterval
    /// 是否开启“解锁后自动上班”。
    public var automaticClockInEnabled: Bool
    /// 自动上班的时间门槛（24 小时制的小时与分钟）。
    public var autoClockInHour: Int
    public var autoClockInMinute: Int
    /// 是否开启“工时达标后锁屏自动下班”。
    public var automaticClockOutEnabled: Bool
    /// 工时达标时是否发系统通知。
    public var notifyWhenTargetReached: Bool
    /// 节假日 API 的国家/地区代码，例如 `CN`。
    public var holidayCountryCode: String
    /// 状态栏是否显示实时工时文字。
    public var showTimeInMenuBar: Bool
    /// 是否在 Dock 中显示图标（常规应用形态，同时可以使用台前调度）。
    public var showDockIcon: Bool
    /// 时区标识：默认北京时间 `Asia/Shanghai`，也可以是 `system` 表示跟随系统。
    public var timeZoneIdentifier: String

    public init(
        dailyTargetSeconds: TimeInterval = Settings.defaultDailyTargetSeconds,
        automaticClockInEnabled: Bool = true,
        autoClockInHour: Int = 4,
        autoClockInMinute: Int = 0,
        automaticClockOutEnabled: Bool = true,
        notifyWhenTargetReached: Bool = true,
        holidayCountryCode: String = "CN",
        showTimeInMenuBar: Bool = true,
        showDockIcon: Bool = true,
        timeZoneIdentifier: String = AppTimeZone.beijingIdentifier
    ) {
        self.dailyTargetSeconds = dailyTargetSeconds
        self.automaticClockInEnabled = automaticClockInEnabled
        self.autoClockInHour = autoClockInHour
        self.autoClockInMinute = autoClockInMinute
        self.automaticClockOutEnabled = automaticClockOutEnabled
        self.notifyWhenTargetReached = notifyWhenTargetReached
        self.holidayCountryCode = holidayCountryCode
        self.showTimeInMenuBar = showTimeInMenuBar
        self.showDockIcon = showDockIcon
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    public var autoClockInLabel: String {
        String(format: "%02d:%02d", autoClockInHour, autoClockInMinute)
    }

    public var dailyTargetLabel: String {
        DurationFormat.text(dailyTargetSeconds)
    }

    /// 当前设置对应的时区。
    public var timeZone: TimeZone {
        AppTimeZone.timeZone(identifier: timeZoneIdentifier)
    }

    public var timeZoneDisplayName: String {
        AppTimeZone.displayName(identifier: timeZoneIdentifier)
    }

    private enum CodingKeys: String, CodingKey {
        case dailyTargetSeconds
        case automaticClockInEnabled
        case autoClockInHour
        case autoClockInMinute
        case automaticClockOutEnabled
        case notifyWhenTargetReached
        case holidayCountryCode
        case showTimeInMenuBar
        case showDockIcon
        case timeZoneIdentifier
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Settings()
        dailyTargetSeconds = (try? container.decode(TimeInterval.self, forKey: .dailyTargetSeconds)) ?? defaults.dailyTargetSeconds
        automaticClockInEnabled = (try? container.decode(Bool.self, forKey: .automaticClockInEnabled)) ?? defaults.automaticClockInEnabled
        autoClockInHour = (try? container.decode(Int.self, forKey: .autoClockInHour)) ?? defaults.autoClockInHour
        autoClockInMinute = (try? container.decode(Int.self, forKey: .autoClockInMinute)) ?? defaults.autoClockInMinute
        automaticClockOutEnabled = (try? container.decode(Bool.self, forKey: .automaticClockOutEnabled)) ?? defaults.automaticClockOutEnabled
        notifyWhenTargetReached = (try? container.decode(Bool.self, forKey: .notifyWhenTargetReached)) ?? defaults.notifyWhenTargetReached
        holidayCountryCode = (try? container.decode(String.self, forKey: .holidayCountryCode)) ?? defaults.holidayCountryCode
        showTimeInMenuBar = (try? container.decode(Bool.self, forKey: .showTimeInMenuBar)) ?? defaults.showTimeInMenuBar
        showDockIcon = (try? container.decode(Bool.self, forKey: .showDockIcon)) ?? defaults.showDockIcon
        timeZoneIdentifier = (try? container.decode(String.self, forKey: .timeZoneIdentifier)) ?? defaults.timeZoneIdentifier
        normalize()
    }

    /// 修正非法取值，保证从磁盘读回的数据始终可用。
    public mutating func normalize() {
        if dailyTargetSeconds < 60 || dailyTargetSeconds > 24 * 3600 {
            dailyTargetSeconds = Settings.defaultDailyTargetSeconds
        }
        autoClockInHour = min(max(autoClockInHour, 0), 23)
        autoClockInMinute = min(max(autoClockInMinute, 0), 59)
        let code = holidayCountryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        holidayCountryCode = code.isEmpty ? "CN" : code
        if !AppTimeZone.isValid(identifier: timeZoneIdentifier) {
            timeZoneIdentifier = AppTimeZone.beijingIdentifier
        }
    }
}

/// 时长文案格式化。
public enum DurationFormat {
    /// `8 小时 30 分`
    public static func text(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours == 0 && minutes == 0 { return "0 分" }
        if hours == 0 { return "\(minutes) 分" }
        if minutes == 0 { return "\(hours) 小时" }
        return "\(hours) 小时 \(minutes) 分"
    }

    /// `8h30m`，用于状态栏等紧凑场景。
    public static func compact(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours == 0 { return "\(minutes)m" }
        if minutes == 0 { return "\(hours)h" }
        return "\(hours)h\(minutes)m"
    }

    /// `8.5`（小时，保留一位小数）
    public static func decimalHours(_ seconds: TimeInterval, fractionDigits: Int = 1) -> String {
        String(format: "%.\(fractionDigits)f", max(0, seconds) / 3600)
    }

    /// `08:30`
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", total / 3600, (total % 3600) / 60)
    }
}

public enum WorkTimeError: Error, Equatable, LocalizedError {
    case alreadyWorking
    case notWorking
    case nothingToUndo

    public var errorDescription: String? {
        switch self {
        case .alreadyWorking: return "当前已在上班状态"
        case .notWorking: return "当前没有进行中的上班记录"
        case .nothingToUndo: return "没有可以撤销的下班记录"
        }
    }
}
