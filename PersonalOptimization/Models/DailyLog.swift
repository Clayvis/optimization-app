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

    init(date: Date) {
        self.date = Calendar.current.startOfDay(for: date)
    }
}
