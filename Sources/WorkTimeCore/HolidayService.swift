import Foundation

/// 一天是节假日还是调休补班。
public struct HolidayDay: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(date)|\(name)|\(isOffDay)" }
    public let date: String // yyyy-MM-dd
    public let name: String
    /// `false` 表示“调休补班”（节假日安排里要上班）。
    public let isOffDay: Bool
    public let source: String

    public init(date: String, name: String, isOffDay: Bool, source: String) {
        self.date = date
        self.name = name
        self.isOffDay = isOffDay
        self.source = source
    }

    /// 缓存键：`CN-2026`
    public static func cacheKey(countryCode: String, year: Int) -> String {
        "\(countryCode.uppercased())-\(year)"
    }
}

public enum HolidayError: Error, LocalizedError {
    case emptyResponse(source: String)
    case allSourcesFailed(detail: String)

    public var errorDescription: String? {
        switch self {
        case .emptyResponse(let source):
            return "\(source) 返回了空数据"
        case .allSourcesFailed(let detail):
            return "所有节假日数据源都拉取失败：\(detail)"
        }
    }
}

/// 公开节假日 API 服务。
///
/// - 中国（`CN`）：优先使用 holiday-cn（包含完整放假区间与调休补班日），
///   失败时回退到 Nager.Date（官方节假日单日数据）。
/// - 其他国家和地区：使用 Nager.Date。
public struct HolidayService: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetch(year: Int, countryCode: String) async throws -> [HolidayDay] {
        guard year >= 2000 && year <= 2100 else {
            throw HolidayError.emptyResponse(source: "年份")
        }
        let code = countryCode.uppercased()
        var errors: [String] = []

        if code == "CN" {
            do {
                let url = URL(string: "https://cdn.jsdelivr.net/gh/NateScarlet/holiday-cn@master/\(year).json")!
                let data = try await request(url)
                let days = try Self.decodeChinaHoliday(data)
                if !days.isEmpty {
                    return days
                }
                errors.append("holiday-cn 空数据")
            } catch {
                errors.append("holiday-cn: \(error.localizedDescription)")
            }
        }

        do {
            let url = URL(string: "https://date.nager.at/api/v3/PublicHolidays/\(year)/\(code)")!
            let data = try await request(url)
            let days = try Self.decodeNager(data)
            if !days.isEmpty {
                return days
            }
            errors.append("Nager.Date 空数据")
        } catch {
            errors.append("Nager.Date: \(error.localizedDescription)")
        }

        throw HolidayError.allSourcesFailed(detail: errors.joined(separator: "；"))
    }

    private func request(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("WorkTimeRecorder/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    // MARK: - 解析

    static func decodeChinaHoliday(_ data: Data) throws -> [HolidayDay] {
        struct File: Decodable {
            let year: Int
            let days: [RawDay]
        }
        struct RawDay: Decodable {
            let name: String
            let date: String
            let isOffDay: Bool
        }
        let file = try JSONDecoder().decode(File.self, from: data)
        let days = try file.days.map { raw -> HolidayDay in
            guard raw.date.count == 10 else { throw HolidayError.emptyResponse(source: "holiday-cn 日期格式") }
            return HolidayDay(date: raw.date, name: raw.name, isOffDay: raw.isOffDay, source: "holiday-cn")
        }
        return sortAndDedupe(days)
    }

    static func decodeNager(_ data: Data) throws -> [HolidayDay] {
        struct RawDay: Decodable {
            let date: String
            let localName: String
            let name: String
            let global: Bool
        }
        let rawDays = try JSONDecoder().decode([RawDay].self, from: data)
        let days = rawDays.compactMap { raw -> HolidayDay? in
            guard raw.date.count == 10 else { return nil }
            return HolidayDay(
                date: raw.date,
                name: raw.localName.isEmpty ? raw.name : raw.localName,
                isOffDay: true,
                source: "nager"
            )
        }
        return sortAndDedupe(days)
    }

    private static func sortAndDedupe(_ days: [HolidayDay]) -> [HolidayDay] {
        var seen = Set<String>()
        let filtered = days.filter { seen.insert($0.date).inserted }
        return filtered.sorted { $0.date < $1.date }
    }
}
