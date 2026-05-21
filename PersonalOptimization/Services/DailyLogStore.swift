import Foundation
import SwiftData
import os

/// Single writer for DailyLog rows. Every caller that needs a DailyLog for a
/// given moment should funnel through here so the day boundary is computed
/// against the user's calendar (not the device's) and so duplicate rows for
/// the same calendar day can never appear from inconsistent timezone logic.
///
/// Why this is not implemented via @Attribute(.unique): SwiftData prohibits
/// unique attribute constraints on CloudKit-mirrored models. Instead we keep
/// uniqueness as an application invariant enforced by this store, with a
/// one-shot dedupe migration that runs at launch to repair any historical
/// duplicates that may have crept in.
@MainActor
final class DailyLogStore {
    private let modelContext: ModelContext
    private let calendar: Calendar
    private let logger = Logger.persistence

    init(modelContext: ModelContext, calendar: Calendar) {
        self.modelContext = modelContext
        self.calendar = calendar
    }

    /// Convenience: build the store using the user's calendar from UserProfile.
    static func forUser(modelContext: ModelContext) -> DailyLogStore {
        DailyLogStore(modelContext: modelContext, calendar: UserCalendar.current(modelContext: modelContext))
    }

    /// Returns the unique DailyLog row for the calendar day containing `date`.
    /// Creates it if needed. Safe to call from any number of writers; the
    /// returned row is the canonical one.
    @discardableResult
    func upsert(for date: Date) -> DailyLog {
        let day = calendar.startOfDay(for: date)
        let descriptor = FetchDescriptor<DailyLog>(
            predicate: #Predicate<DailyLog> { $0.date == day }
        )
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            return existing
        }
        let log = DailyLog(date: day, calendar: calendar)
        modelContext.insert(log)
        return log
    }

    /// Convenience for the very common "today" case. Avoids a Date() call at
    /// each site so timezone math stays consistent.
    @discardableResult
    func upsertToday(reference: Date = Date()) -> DailyLog {
        upsert(for: reference)
    }

    /// One-shot dedupe pass. Scans for DailyLog rows whose date keys collapse
    /// to the same calendar day under the store's calendar; merges the
    /// duplicates and deletes them. Idempotent: re-running on a clean store
    /// is a no-op. Caller is responsible for gating this on a UserDefaults
    /// flag so it does not run on every launch.
    func dedupe() throws {
        let all = try modelContext.fetch(FetchDescriptor<DailyLog>(sortBy: [SortDescriptor(\.date, order: .forward)]))
        var byDay: [Date: [DailyLog]] = [:]
        for log in all {
            let day = calendar.startOfDay(for: log.date)
            byDay[day, default: []].append(log)
        }
        var mergeCount = 0
        for (day, logs) in byDay where logs.count > 1 {
            // Sort: canonical row is the first one (oldest by date, which is
            // typically the one with the most filled fields). Merge the rest
            // into it then delete them.
            let canonical = logs[0]
            for dup in logs.dropFirst() {
                Self.merge(source: dup, into: canonical)
                modelContext.delete(dup)
                mergeCount += 1
            }
            // Pin the canonical row's date to the user-calendar start-of-day
            // so future upsert() calls under the same calendar hit it.
            canonical.date = day
        }
        if mergeCount > 0 {
            logger.notice("DailyLogStore.dedupe merged \(mergeCount, privacy: .public) duplicate rows.")
            try modelContext.save()
        }
    }

    /// Field-by-field merge favoring non-nil values, summing counters, and
    /// taking the max of streak-like measurements. Covers all DailyLog
    /// fields including the M4.2 HealthKit-derived attributes.
    private static func merge(source: DailyLog, into target: DailyLog) {
        if target.fastStart == nil { target.fastStart = source.fastStart }
        if target.fastEnd == nil { target.fastEnd = source.fastEnd }
        if source.fastBrokeEarly { target.fastBrokeEarly = true }
        if target.fastBreakReason == nil { target.fastBreakReason = source.fastBreakReason }
        target.waterOz += source.waterOz
        target.electrolyteSessions += source.electrolyteSessions
        target.japaneseMinutes += source.japaneseMinutes
        target.guitarMinutes += source.guitarMinutes
        target.courseworkMinutes += source.courseworkMinutes
        target.musicMinutes += source.musicMinutes
        if target.subjectiveEnergy == nil { target.subjectiveEnergy = source.subjectiveEnergy }
        if target.achillesPain == nil { target.achillesPain = source.achillesPain }
        if let sourceSleep = source.sleepHours {
            target.sleepHours = max(target.sleepHours ?? 0, sourceSleep)
        }
        if target.restingHR == nil { target.restingHR = source.restingHR }
        if target.hrvRmssd == nil { target.hrvRmssd = source.hrvRmssd }
        if target.weightLbs == nil { target.weightLbs = source.weightLbs }
        if let sourceNotes = source.notes, !sourceNotes.isEmpty {
            target.notes = [target.notes, sourceNotes].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " | ")
        }
        // M4.2 HealthKit fields: prefer the source value when target is nil.
        if target.respiratoryRate == nil { target.respiratoryRate = source.respiratoryRate }
        if target.oxygenSaturationPercent == nil { target.oxygenSaturationPercent = source.oxygenSaturationPercent }
        if target.bodyFatPercentage == nil { target.bodyFatPercentage = source.bodyFatPercentage }
        if target.leanBodyMassLbs == nil { target.leanBodyMassLbs = source.leanBodyMassLbs }
        if target.heartRateRecovery1minBpm == nil { target.heartRateRecovery1minBpm = source.heartRateRecovery1minBpm }
        if target.appleExerciseMinutes == nil { target.appleExerciseMinutes = source.appleExerciseMinutes }
        if target.appleStandHours == nil { target.appleStandHours = source.appleStandHours }
        if target.distanceMeters == nil { target.distanceMeters = source.distanceMeters }
        if target.environmentalAudioDb == nil { target.environmentalAudioDb = source.environmentalAudioDb }
        if target.wristTemperatureCelsius == nil { target.wristTemperatureCelsius = source.wristTemperatureCelsius }
        if target.mindfulMinutes == nil { target.mindfulMinutes = source.mindfulMinutes }
        if target.dietaryKcal == nil { target.dietaryKcal = source.dietaryKcal }
        if target.dietaryProteinG == nil { target.dietaryProteinG = source.dietaryProteinG }
        if target.dietaryCarbsG == nil { target.dietaryCarbsG = source.dietaryCarbsG }
        if target.dietaryFatG == nil { target.dietaryFatG = source.dietaryFatG }
        if target.caffeineMg == nil { target.caffeineMg = source.caffeineMg }
        if target.timeInDaylightMinutes == nil { target.timeInDaylightMinutes = source.timeInDaylightMinutes }
        if target.stepCount == nil { target.stepCount = source.stepCount }
        if target.healthKitSyncedAt == nil { target.healthKitSyncedAt = source.healthKitSyncedAt }
    }
}

/// One-shot dedupe runner gated by a UserDefaults flag so callers can wire
/// it into app launch without re-running every cold start.
@MainActor
enum DailyLogDedupeOnce {
    private static let key = "DailyLogDedupe.v1.completed"

    static func runIfNeeded(modelContext: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        do {
            try DailyLogStore.forUser(modelContext: modelContext).dedupe()
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            Logger.persistence.error("DailyLogDedupeOnce failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
