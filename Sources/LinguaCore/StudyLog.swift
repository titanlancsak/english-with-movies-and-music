import Foundation

/// Study time per day, for the daily goal and the streak ("5 dias seguidos").
/// Time is kept per device so it can be added up across the computer and the phone (see Sync.swift).
public struct StudyLog: Codable, Hashable, Sendable {
    /// Device id -> day ("2026-10-12") -> seconds.
    public internal(set) var devices: [String: [String: Double]] = [:]
    public var goalMinutes = 10

    public init() {}

    /// Watching counts as it happens; each reviewed card and each pronunciation attempt adds a little.
    public static let secondsPerReview: Double = 10
    public static let secondsPerPractice: Double = 30

    public mutating func add(_ seconds: Double, device: String, on date: Date = Date()) {
        guard seconds > 0 else { return }
        devices[device, default: [:]][Self.day(date), default: 0] += seconds
    }

    public func seconds(on date: Date) -> Double {
        let day = Self.day(date)
        return devices.values.reduce(0) { $0 + ($1[day] ?? 0) }
    }

    /// 0...1 of today's goal.
    public func todayProgress(now: Date = Date()) -> Double {
        min(1, seconds(on: now) / Double(max(goalMinutes, 1) * 60))
    }

    /// Days in a row that reached the goal. Today counts once reached; until then the streak
    /// from yesterday is still alive.
    public func streak(now: Date = Date()) -> Int {
        let calendar = Calendar.current
        let goal = Double(max(goalMinutes, 1) * 60)
        var date = now
        if seconds(on: date) < goal { date = calendar.date(byAdding: .day, value: -1, to: date)! }
        var count = 0
        while seconds(on: date) >= goal {
            count += 1
            date = calendar.date(byAdding: .day, value: -1, to: date)!
        }
        return count
    }

    /// Keeps the larger value of each device and day.
    public mutating func merge(_ other: StudyLog) {
        for (device, days) in other.devices {
            for (day, seconds) in days {
                devices[device, default: [:]][day] = max(devices[device]?[day] ?? 0, seconds)
            }
        }
    }

    /// "2026-10-12" in the local time zone.
    public static func day(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
}
