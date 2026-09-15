import Foundation

/// 需要落盘的完整应用状态。
public struct AppState: Codable, Equatable, Sendable {
    public var settings: Settings
    public var ledger: WorkTimeLedger
    /// 节假日缓存，键为 `国家代码-年份`，例如 `CN-2026`。
    public var holidays: [String: [HolidayDay]]
    /// 各年份节假日的最后更新时间。
    public var lastHolidayRefresh: [String: Date]
    public var createdAt: Date

    public init(
        settings: Settings = Settings(),
        ledger: WorkTimeLedger = WorkTimeLedger(),
        holidays: [String: [HolidayDay]] = [:],
        lastHolidayRefresh: [String: Date] = [:],
        createdAt: Date = Date()
    ) {
        self.settings = settings
        self.ledger = ledger
        self.holidays = holidays
        self.lastHolidayRefresh = lastHolidayRefresh
        self.createdAt = createdAt
    }

    public func holidays(countryCode: String, year: Int) -> [HolidayDay] {
        holidays[HolidayDay.cacheKey(countryCode: countryCode, year: year)] ?? []
    }

    /// 拉取某年节假日时使用的按日期索引表。
    public func holidayIndex(countryCode: String, years: [Int]) -> [String: HolidayDay] {
        var index: [String: HolidayDay] = [:]
        for year in years {
            for day in holidays(countryCode: countryCode, year: year) {
                index[day.date] = day
            }
        }
        return index
    }

    private enum CodingKeys: String, CodingKey {
        case settings
        case ledger
        case holidays
        case lastHolidayRefresh
        case createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        settings = (try? container.decode(Settings.self, forKey: .settings)) ?? Settings()
        ledger = (try? container.decode(WorkTimeLedger.self, forKey: .ledger)) ?? WorkTimeLedger()
        holidays = (try? container.decode([String: [HolidayDay]].self, forKey: .holidays)) ?? [:]
        lastHolidayRefresh = (try? container.decode([String: Date].self, forKey: .lastHolidayRefresh)) ?? [:]
        createdAt = (try? container.decode(Date.self, forKey: .createdAt)) ?? Date()
    }
}

/// 状态文件读写：默认存放在 `~/Library/Application Support/WorkTimeRecorder/state.json`。
public final class StateFileStore {
    public let directoryURL: URL
    public let fileURL: URL

    public init(directoryURL: URL? = nil) {
        let directory = directoryURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("WorkTimeRecorder", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("WorkTimeRecorder", isDirectory: true)
        self.directoryURL = directory
        self.fileURL = directory.appendingPathComponent("state.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public func load() -> AppState {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            return AppState()
        }
        do {
            var state = try Self.makeDecoder().decode(AppState.self, from: data)
            state.settings.normalize()
            return state
        } catch {
            // 数据损坏时先备份，再以全新状态启动，避免用户数据被静默覆盖。
            let backup = directoryURL.appendingPathComponent("state-corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: fileURL, to: backup)
            return AppState()
        }
    }

    public func save(_ state: AppState) throws {
        let data = try Self.makeEncoder().encode(state)
        try data.write(to: fileURL, options: .atomic)
    }
}
