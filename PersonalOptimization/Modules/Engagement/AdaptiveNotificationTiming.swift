import Foundation
import SwiftData

/// Pure computation of preferred notification time per domain based on the user's
/// own completion history. Activates only when ≥14 distinct days are present;
/// otherwise returns nil so callers fall back to scheduled block time.
enum AdaptiveNotificationTiming {

    static let activationThresholdDays: Int = 14

    /// Returns the preferred notification time for `domain` projected onto today's date,
    /// or nil if not enough history exists yet.
    /// - Parameters:
    ///   - domain: streak/notification domain.
    ///   - history: all CompletionHistory rows for this domain (and others; they will be filtered).
    ///   - asOf: anchor "now" used to project the time onto today's calendar date.
    ///   - timezone: timezone for day-of-year bucketing and time-of-day extraction.
    static func estimatePreferredTime(
        domain: StreakDomain,
        history: [CompletionHistory],
        asOf: Date,
        timezone: TimeZone = TimeZone.current
    ) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone

        let domainHistory = history.filter { $0.domain == domain.rawValue }
        let bucketedByDay: [Date: Date] = Dictionary(grouping: domainHistory,
                                                     by: { cal.startOfDay(for: $0.timestamp) })
            .compactMapValues { entries in entries.min(by: { $0.timestamp < $1.timestamp })?.timestamp }

        guard bucketedByDay.count >= activationThresholdDays else { return nil }

        let minutesOfDay = bucketedByDay.values.map { ts -> Int in
            let comps = cal.dateComponents([.hour, .minute], from: ts)
            return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        }
        let medianMinutes = median(minutesOfDay)
        return projectMinutesOntoDay(medianMinutes, asOf: asOf, calendar: cal)
    }

    /// Decision helper: should we suppress today's notification because the behavior
    /// already happened today?
    static func shouldSuppressIfAlreadyLogged(
        domain: StreakDomain,
        history: [CompletionHistory],
        asOf: Date,
        timezone: TimeZone = TimeZone.current
    ) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        let today = cal.startOfDay(for: asOf)
        return history.contains { $0.domain == domain.rawValue && cal.isDate($0.timestamp, inSameDayAs: today) }
    }

    // MARK: - Private

    private static func median(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        } else {
            return sorted[mid]
        }
    }

    private static func projectMinutesOntoDay(_ minutes: Int, asOf: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: asOf)
        var comps = DateComponents()
        comps.hour = minutes / 60
        comps.minute = minutes % 60
        return calendar.date(byAdding: comps, to: day) ?? day
    }
}

/// Convenience for callers that have a ModelContext on hand (NotificationService, etc).
@MainActor
enum CompletionHistoryWriter {
    static func record(domain: StreakDomain, at time: Date = Date(), modelContext: ModelContext) {
        let entry = CompletionHistory(domain: domain, timestamp: time)
        modelContext.insert(entry)
        try? modelContext.save()
    }
}
