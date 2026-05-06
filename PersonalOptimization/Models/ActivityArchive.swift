import Foundation
import SwiftData

/// Rolled-up daily metrics. One row per day. Survives even if individual session
/// rows are corrupted or migrated. Source-of-truth sessions stay raw; this is
/// additive only. Populated by BGAppRefreshTask end-of-day or on-demand by
/// `TrendAnalyticsService.archiveDay(_:)` for backfill.
@Model
final class ActivityArchive {
    /// Midnight in user's local TZ. Logically unique per day; uniqueness enforced
    /// by ActivityArchiveService.upsertArchive (CloudKit doesn't support
    /// `@Attribute(.unique)` on entities seeded into the cloud database).
    var date: Date = Date.distantPast
    var workoutVolumeTotal: Double = 0           // sum of LiftSession.totalVolumeLbs that day
    var workoutCount: Int = 0                    // count of WorkoutEvent.completed that day
    var fastingHours: Double = 0                 // log.fastEnd - log.fastStart in hours
    var hydrationOz: Double = 0                  // DailyLog.waterOz
    var learningMinutes: Int = 0                 // log.japaneseMinutes + log.guitarMinutes + log.courseworkMinutes
    var dominantMascotState: String = "neutral"  // most-frequent CharacterStateLog of the day
    var masterMetric: Double = 0                 // 0.0-1.0: that day's protocol adherence ratio
    var stepsHK: Int?
    var activeCaloriesHK: Double?
    var exerciseMinutesHK: Int?
    var sleepMinutesHK: Int?
    var hrvAvgHK: Double?
    var restingHRHK: Int?

    init(date: Date) {
        self.date = date
    }
}
