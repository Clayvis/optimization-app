import Foundation
import SwiftData

@Model
final class DailyLog {
    var date: Date = Date.distantPast
    var fastStart: Date?
    var fastEnd: Date?
    var fastBrokeEarly: Bool = false
    var fastBreakReason: String?
    var waterOz: Double = 0
    var electrolyteSessions: Int = 0
    var japaneseMinutes: Int = 0
    var guitarMinutes: Int = 0
    var courseworkMinutes: Int = 0
    var musicMinutes: Int = 0    // M4.2 followup: generic instrument / vocal practice
    var subjectiveEnergy: Int?
    var achillesPain: Int?
    var sleepHours: Double?
    var restingHR: Int?
    var hrvRmssd: Double?
    var weightLbs: Double?
    var notes: String?

    // M4.2 — HealthKit-derived fields. All optional; defaults to nil; populated
    // by HealthKitSyncService.syncToday. The Coach and TrendAnalytics surface
    // these when present and ignore them when nil — no fallback synthesis.
    var respiratoryRate: Double?
    var oxygenSaturationPercent: Double?
    var bodyFatPercentage: Double?
    var leanBodyMassLbs: Double?
    var heartRateRecovery1minBpm: Int?
    var appleExerciseMinutes: Int?
    var appleStandHours: Int?
    var distanceMeters: Double?
    var environmentalAudioDb: Double?
    var wristTemperatureCelsius: Double?
    var mindfulMinutes: Int?
    var dietaryKcal: Double?
    var dietaryProteinG: Double?
    var dietaryCarbsG: Double?
    var dietaryFatG: Double?
    var caffeineMg: Double?
    var timeInDaylightMinutes: Int?
    var stepCount: Int?

    /// Total active energy burned today from HealthKit (the Apple Watch /
    /// Fitness "Move" number). Lets the Move track reflect a workout the watch
    /// tracked even when no session was logged in the app. Additive optional;
    /// rides SchemaV10 via lightweight migration like the other M4.2 HK fields.
    var activeEnergyBurnedKcal: Double?

    /// Timestamp of the last HealthKitSyncService write. Used to throttle
    /// repeated pulls and surface "last refreshed" in the UI.
    var healthKitSyncedAt: Date?

    /// JSON-encoded bag of fields that aren't queried but need to evolve.
    /// Read with `metadata(_:as:)`, write with `setMetadata(_:value:)`.
    /// Pattern lets us add fields without bumping the SwiftData schema.
    var metadataBlob: Data?

    /// Non-nil when this row was a duplicate of another calendar-day row and
    /// has been merged into the canonical one by `DailyLogStore.dedupe`. Its
    /// measurement fields are neutralized (zeroed/niled) so it contributes
    /// nothing to any aggregate. The row is retained (never deleted) per the
    /// CLAUDE.md permanent-retention rule. `DailyLogStore.upsert` filters these
    /// out so the writer never returns a tombstone. Optional with a nil default
    /// so it lands as a lightweight in-place migration on the current schema.
    var supersededAt: Date?

    init(date: Date, calendar: Calendar = .current) {
        self.date = calendar.startOfDay(for: date)
    }

    /// Metadata helpers - every `try?` below is best-effort JSON round-trip
    /// against a Data blob. nil means the blob is missing or corrupt; the
    /// caller treats nil as "no value" and skips the write. There is no
    /// recoverable error to surface inline. The MARK line in front of each
    /// try? satisfies CLAUDE.md's per-call justification rule.
    func metadata<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        // MARK: try? justified - corrupt blob means "no value"; see helper note.
        guard let blob = metadataBlob,
              let dict = try? JSONSerialization.jsonObject(with: blob) as? [String: Any], // MARK: try? justified - see prior line.
              let raw = dict[key] else { return nil }
        // MARK: try? justified - see helper note.
        guard let data = try? JSONSerialization.data(withJSONObject: raw, options: [.fragmentsAllowed]) else { return nil }
        // MARK: try? justified - see helper note.
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func setMetadata<T: Encodable>(_ key: String, value: T?) {
        var dict: [String: Any] = [:]
        // MARK: try? justified - see helper note on `metadata(_:as:)`.
        if let blob = metadataBlob,
           let existing = try? JSONSerialization.jsonObject(with: blob) as? [String: Any] { // MARK: try? justified - see prior line.
            dict = existing
        }
        if let value {
            // MARK: try? justified - see helper note on `metadata(_:as:)`.
            guard let data = try? JSONEncoder().encode(value),
                  let any = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return } // MARK: try? justified - see prior line.
            dict[key] = any
        } else {
            dict.removeValue(forKey: key)
        }
        // MARK: try? justified - see helper note on `metadata(_:as:)`.
        metadataBlob = try? JSONSerialization.data(withJSONObject: dict)
    }
}
