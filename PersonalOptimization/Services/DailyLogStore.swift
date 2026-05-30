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
            predicate: #Predicate<DailyLog> { $0.date == day && $0.supersededAt == nil }
        )
        if let existing = modelContext.fetchFirstOrNil(descriptor) {
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
    /// duplicates into a canonical row. Non-destructive: duplicates are NOT
    /// deleted (CLAUDE.md retention forbids deletes on this launch/background
    /// path). Each duplicate is marked `supersededAt` and neutralized so it
    /// contributes nothing to any aggregate while the row is retained.
    /// Idempotent: already-superseded rows are skipped, so re-running is a
    /// no-op. Caller gates this on a UserDefaults flag so it does not run on
    /// every launch.
    func dedupe() throws {
        let all = try modelContext
            .fetch(FetchDescriptor<DailyLog>(sortBy: [SortDescriptor(\.date, order: .forward)]))
            .filter { $0.supersededAt == nil }
        var byDay: [Date: [DailyLog]] = [:]
        for log in all {
            let day = calendar.startOfDay(for: log.date)
            byDay[day, default: []].append(log)
        }
        var mergeCount = 0
        for (day, logs) in byDay where logs.count > 1 {
            // Canonical row is the first one (oldest by date, typically the
            // most filled). Merge the rest into it, then supersede them.
            let canonical = logs[0]
            for dup in logs.dropFirst() {
                Self.merge(source: dup, into: canonical)
                // Non-destructive supersede: the duplicate's data now lives in
                // canonical. Neutralize the duplicate's fields so it adds zero
                // to any sum even for readers that do not filter superseded
                // rows, then stamp supersededAt. The row is retained.
                Self.neutralize(dup)
                dup.supersededAt = Date()
                mergeCount += 1
            }
            // Pin the canonical row's date to the user-calendar start-of-day
            // so future upsert() calls under the same calendar hit it.
            canonical.date = day
        }
        if mergeCount > 0 {
            logger.notice("DailyLogStore.dedupe superseded \(mergeCount, privacy: .public) duplicate rows (non-destructive).")
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

    /// Resets every measurement field on a superseded duplicate to its zero
    /// value so the retained tombstone contributes nothing to any aggregate.
    /// Must cover exactly the fields `merge` reads; keep the two in sync when a
    /// DailyLog field is added. `date` is left intact so the row does not break
    /// earliest-log scans; `supersededAt` is stamped by the caller.
    private static func neutralize(_ log: DailyLog) {
        log.fastStart = nil
        log.fastEnd = nil
        log.fastBrokeEarly = false
        log.fastBreakReason = nil
        log.waterOz = 0
        log.electrolyteSessions = 0
        log.japaneseMinutes = 0
        log.guitarMinutes = 0
        log.courseworkMinutes = 0
        log.musicMinutes = 0
        log.subjectiveEnergy = nil
        log.achillesPain = nil
        log.sleepHours = nil
        log.restingHR = nil
        log.hrvRmssd = nil
        log.weightLbs = nil
        log.notes = nil
        log.respiratoryRate = nil
        log.oxygenSaturationPercent = nil
        log.bodyFatPercentage = nil
        log.leanBodyMassLbs = nil
        log.heartRateRecovery1minBpm = nil
        log.appleExerciseMinutes = nil
        log.appleStandHours = nil
        log.distanceMeters = nil
        log.environmentalAudioDb = nil
        log.wristTemperatureCelsius = nil
        log.mindfulMinutes = nil
        log.dietaryKcal = nil
        log.dietaryProteinG = nil
        log.dietaryCarbsG = nil
        log.dietaryFatG = nil
        log.caffeineMg = nil
        log.timeInDaylightMinutes = nil
        log.stepCount = nil
        log.healthKitSyncedAt = nil
        log.metadataBlob = nil
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
