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

    init(modelContext: ModelContext, timezone: TimeZone = TimeZone.current, targets: HydrationTargetsOz) {
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

    /// Adds `oz` of plain water to today's intake. Wraps the more general `logBeverage`.
    @discardableResult
    func logBottle(oz: Double, at date: Date = Date()) throws -> DailyLog {
        try logBeverage(amountOz: oz, beverageType: .water, at: date, note: nil)
    }

    /// Logs an arbitrary beverage. Persists a HydrationEntry and updates DailyLog.waterOz
    /// using the beverage's hydration coefficient.
    @discardableResult
    func logBeverage(amountOz: Double,
                     beverageType: BeverageType,
                     at date: Date = Date(),
                     note: String? = nil) throws -> DailyLog {
        guard amountOz > 0 else { return upsertDailyLog(for: date) }
        let entry = HydrationEntry(date: date, amountOz: amountOz, beverageType: beverageType, note: note)
        modelContext.insert(entry)
        let log = upsertDailyLog(for: date)
        log.waterOz += entry.effectiveOz
        try modelContext.save()
        CompletionHistoryWriter.record(domain: .hydration, at: date, modelContext: modelContext)
        logger.info("Logged \(amountOz, privacy: .public) oz \(beverageType.rawValue, privacy: .public) effective=\(entry.effectiveOz, privacy: .public) day total=\(log.waterOz, privacy: .public)")
        return log
    }

    /// Convenience: log millilitres. Converted to ounces internally (1 oz = 29.5735 mL).
    @discardableResult
    func logBeverage(amountML: Double,
                     beverageType: BeverageType,
                     at date: Date = Date(),
                     note: String? = nil) throws -> DailyLog {
        let oz = amountML / 29.5735
        return try logBeverage(amountOz: oz, beverageType: beverageType, at: date, note: note)
    }

    /// Increments today's electrolyte session counter. Also writes a HydrationEntry
    /// with the configured electrolyte serving size for granular history.
    @discardableResult
    func logElectrolyte(at date: Date = Date(), servingOz: Double = 16) throws -> DailyLog {
        let log = upsertDailyLog(for: date)
        log.electrolyteSessions += 1

        let entry = HydrationEntry(date: date, amountOz: servingOz, beverageType: .electrolyte, note: nil)
        modelContext.insert(entry)
        log.waterOz += entry.effectiveOz

        try modelContext.save()
        CompletionHistoryWriter.record(domain: .hydration, at: date, modelContext: modelContext)
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

    /// Updates an existing entry's amount and beverage type. Recomputes the
    /// day's `DailyLog.waterOz` by deducting the previous effectiveOz and
    /// adding the new one. Recomputes the hydration streak so a corrected
    /// entry that drops the day below target rolls the streak back honestly.
    func updateEntry(_ entry: HydrationEntry,
                     newAmountOz: Double,
                     newBeverageType: BeverageType) throws {
        guard newAmountOz > 0 else { return }
        let log = upsertDailyLog(for: entry.date)
        let previousEffective = entry.effectiveOz
        entry.amountOz = newAmountOz
        entry.beverageTypeRaw = newBeverageType.rawValue
        let newEffective = entry.effectiveOz
        log.waterOz = max(0, log.waterOz - previousEffective + newEffective)
        try modelContext.save()
        recomputeHydrationStreak(asOf: entry.date)
    }

    /// Deletes an entry and rolls back its contribution to today's
    /// `DailyLog.waterOz`. Electrolyte session count adjusts when the deleted
    /// entry was an electrolyte log. Recomputes the hydration streak so a
    /// removed entry that drops the day below target rolls the streak back
    /// honestly (no silent inflation).
    func deleteEntry(_ entry: HydrationEntry) throws {
        let day = entry.date
        let log = upsertDailyLog(for: day)
        log.waterOz = max(0, log.waterOz - entry.effectiveOz)
        if entry.beverageType == .electrolyte {
            log.electrolyteSessions = max(0, log.electrolyteSessions - 1)
        }
        modelContext.delete(entry)
        try modelContext.save()
        recomputeHydrationStreak(asOf: day)
    }

    /// Best-effort streak recompute after a destructive hydration edit.
    /// Failures here just leave the streak slightly stale until the next
    /// natural recompute; we never want a delete to throw on the user.
    /// StreakService lives in the iOS-only Engagement module, so the Watch
    /// build skips this entirely.
    private func recomputeHydrationStreak(asOf date: Date) {
        #if !os(watchOS)
        let streakService = StreakService(
            modelContext: modelContext,
            timezone: timezone,
            hydrationTargets: targets
        )
        _ = try? streakService.recompute(domain: .hydration, asOf: date)  // MARK: try? justified - best-effort; failure logged inside the called function.
        #endif
    }

    /// All HydrationEntry rows logged within the day containing `date`, newest first.
    func entriesForDay(of date: Date) -> [HydrationEntry] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        let day = cal.startOfDay(for: date)
        let next = cal.date(byAdding: .day, value: 1, to: day) ?? day
        let descriptor = FetchDescriptor<HydrationEntry>(
            predicate: #Predicate<HydrationEntry> { $0.date >= day && $0.date < next },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return modelContext.fetchOrEmpty(descriptor)
    }

    private func existingLog(for date: Date) -> DailyLog? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        let day = cal.startOfDay(for: date)

        let descriptor = FetchDescriptor<DailyLog>(
            predicate: #Predicate<DailyLog> { $0.date == day }
        )
        return modelContext.fetchFirstOrNil(descriptor)
    }

    // MARK: - Helpers

    private func upsertDailyLog(for date: Date) -> DailyLog {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        return DailyLogStore(modelContext: modelContext, calendar: cal).upsert(for: date)
    }

    private func isoWeekday(for date: Date) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        let raw = cal.component(.weekday, from: date)
        return raw == 1 ? 7 : raw - 1
    }
}

extension HydrationService {
    /// Parses a CSV string of integer ounces into a sorted, de-duplicated list.
    /// Falls back to the M3.6 default presets if parsing yields no usable values.
    static func parseQuickPicksCSV(_ csv: String) -> [Double] {
        let parts = csv.split(separator: ",")
        let parsed: [Double] = parts.compactMap {
            let trimmed = $0.trimmingCharacters(in: .whitespaces)
            return Double(trimmed)
        }
        let cleaned = Array(Set(parsed.filter { $0 > 0 })).sorted()
        return cleaned.isEmpty ? [4, 8, 12, 16, 20, 24, 32] : cleaned
    }
}
