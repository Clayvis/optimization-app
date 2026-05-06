import Foundation
import SwiftData
import os

enum DayType: String, Sendable, CaseIterable {
    case rest, lift, basketball, swim
}

@MainActor
final class HydrationService {
    private let modelContext: ModelContext
    private let timezone: TimeZone
    private let targets: HydrationTargetsOz
    private let logger = Logger.app

    init(modelContext: ModelContext, timezone: TimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current, targets: HydrationTargetsOz) {
        self.modelContext = modelContext
        self.timezone = timezone
        self.targets = targets
    }

    /// Resolves the day-type for `date`. Priority: basketball > swim > lift > rest.
    /// Falls back to .rest if no explicit appliesTo match.
    func dayType(for date: Date) -> DayType {
        let weekday = isoWeekday(for: date)
        if targets.basketball.appliesTo.contains(weekday) { return .basketball }
        if targets.swim.appliesTo.contains(weekday) { return .swim }
        if targets.lift.appliesTo.contains(weekday) { return .lift }
        if targets.rest.appliesTo.contains(weekday) { return .rest }
        return .rest
    }

    /// Returns the (min, max) target oz for this date's day-type.
    func targetRange(for date: Date) -> ClosedRange<Double> {
        switch dayType(for: date) {
        case .basketball: return targets.basketball.min...targets.basketball.max
        case .swim:       return targets.swim.min...targets.swim.max
        case .lift:       return targets.lift.min...targets.lift.max
        case .rest:       return targets.rest.min...targets.rest.max
        }
    }

    /// Adds `oz` to today's water intake. Upserts the DailyLog for the date's day.
    @discardableResult
    func logBottle(oz: Double, at date: Date = Date()) throws -> DailyLog {
        let log = upsertDailyLog(for: date)
        log.waterOz += oz
        try modelContext.save()
        logger.info("Logged \(oz, privacy: .public) oz, day total now \(log.waterOz, privacy: .public)")
        return log
    }

    /// Increments today's electrolyte session counter.
    @discardableResult
    func logElectrolyte(at date: Date = Date()) throws -> DailyLog {
        let log = upsertDailyLog(for: date)
        log.electrolyteSessions += 1
        try modelContext.save()
        return log
    }

    /// Total water oz logged for the day containing `date`.
    func intakeForDay(of date: Date) -> Double {
        return existingLog(for: date)?.waterOz ?? 0
    }

    /// Number of electrolyte sessions logged for the day containing `date`.
    func electrolyteCount(for date: Date) -> Int {
        return existingLog(for: date)?.electrolyteSessions ?? 0
    }

    private func existingLog(for date: Date) -> DailyLog? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        let day = cal.startOfDay(for: date)

        let descriptor = FetchDescriptor<DailyLog>(
            predicate: #Predicate<DailyLog> { $0.date == day }
        )
        return (try? modelContext.fetch(descriptor))?.first
    }

    // MARK: - Helpers

    private func upsertDailyLog(for date: Date) -> DailyLog {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        let day = cal.startOfDay(for: date)

        let descriptor = FetchDescriptor<DailyLog>(
            predicate: #Predicate<DailyLog> { $0.date == day }
        )
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            return existing
        }
        let log = DailyLog(date: day)
        modelContext.insert(log)
        return log
    }

    private func isoWeekday(for date: Date) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        let raw = cal.component(.weekday, from: date)
        return raw == 1 ? 7 : raw - 1
    }
}
