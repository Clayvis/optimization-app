import Foundation

struct DailyMinutes: Sendable, Equatable {
    let date: Date
    let minutes: Int
}

enum LearningStreakCalculator {

    /// Computes the current consecutive-day streak ending at `asOf` (inclusive of today
    /// only if today already meets `threshold`; today's miss is treated as in-progress).
    static func currentStreak(history: [DailyMinutes], threshold: Int, asOf: Date, timezone: TimeZone) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        let byDay = Self.indexByDay(history, calendar: cal)

        let today = cal.startOfDay(for: asOf)
        var streak = 0

        // Today counts only if already met; otherwise skip without breaking.
        if let m = byDay[today], m >= threshold {
            streak = 1
        }

        var cursor = cal.date(byAdding: .day, value: -1, to: today) ?? today
        while let m = byDay[cursor], m >= threshold {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    /// Returns the longest run of consecutive days at or above `threshold` anywhere in
    /// the history.
    static func longestStreak(history: [DailyMinutes], threshold: Int, timezone: TimeZone) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        let byDay = Self.indexByDay(history, calendar: cal)
        let qualifyingDays = byDay.filter { $0.value >= threshold }.keys.sorted()
        guard !qualifyingDays.isEmpty else { return 0 }

        var longest = 1
        var current = 1
        for i in 1..<qualifyingDays.count {
            let prev = qualifyingDays[i - 1]
            let cur = qualifyingDays[i]
            if let next = cal.date(byAdding: .day, value: 1, to: prev), cal.isDate(next, inSameDayAs: cur) {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }
        return longest
    }

    private static func indexByDay(_ history: [DailyMinutes], calendar: Calendar) -> [Date: Int] {
        var result: [Date: Int] = [:]
        for entry in history {
            let key = calendar.startOfDay(for: entry.date)
            result[key, default: 0] += entry.minutes
        }
        return result
    }
}
