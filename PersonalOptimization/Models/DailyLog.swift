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

    /// Timestamp of the last HealthKitSyncService write. Used to throttle
    /// repeated pulls and surface "last refreshed" in the UI.
    var healthKitSyncedAt: Date?

    /// JSON-encoded bag of fields that aren't queried but need to evolve.
    /// Read with `metadata(_:as:)`, write with `setMetadata(_:value:)`.
    /// Pattern lets us add fields without bumping the SwiftData schema.
    var metadataBlob: Data?

    init(date: Date, calendar: Calendar = .current) {
        self.date = calendar.startOfDay(for: date)
    }

    func metadata<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        guard let blob = metadataBlob,
              let dict = try? JSONSerialization.jsonObject(with: blob) as? [String: Any],
              let raw = dict[key] else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: raw) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func setMetadata<T: Encodable>(_ key: String, value: T?) {
        var dict: [String: Any] = [:]
        if let blob = metadataBlob,
           let existing = try? JSONSerialization.jsonObject(with: blob) as? [String: Any] {
            dict = existing
        }
        if let value {
            guard let data = try? JSONEncoder().encode(value),
                  let any = try? JSONSerialization.jsonObject(with: data) else { return }
            dict[key] = any
        } else {
            dict.removeValue(forKey: key)
        }
        metadataBlob = try? JSONSerialization.data(withJSONObject: dict)
    }
}
