import Foundation
import SwiftData

/// One row per ISO-week the user reflects on. Generated each Sunday from
/// `ActivityArchive` (M3.7). Identity-framed message and free-text user note
/// captured here so the trend is reviewable across months.
@Model
final class WeeklyReflection {
    var weekStartDate: Date = Date.distantPast     // Monday 00:00 in user's TZ; logically unique per user
    var generatedAt: Date = Date.distantPast
    var adherencePercent: Double = 0               // 0.0-1.0 mean across the seven days
    var bestDomain: String = "workout"             // "workout" | "fasting" | "hydration" | "learning"
    var weakestDomain: String = "hydration"
    var bestDayOfWeek: Int = 1                     // ISO weekday 1-7
    var workoutCount: Int = 0
    var hydrationDaysMet: Int = 0
    var fastingDaysCompleted: Int = 0
    var learningMinutesTotal: Int = 0
    var dominantMascotState: String = "neutral"
    var coachMessage: String = ""                  // identity-framed sentence the mascot delivers
    var userNote: String?

    init(weekStartDate: Date,
         generatedAt: Date = Date(),
         adherencePercent: Double = 0,
         bestDomain: String = "workout",
         weakestDomain: String = "hydration",
         bestDayOfWeek: Int = 1,
         workoutCount: Int = 0,
         hydrationDaysMet: Int = 0,
         fastingDaysCompleted: Int = 0,
         learningMinutesTotal: Int = 0,
         dominantMascotState: String = "neutral",
         coachMessage: String = "",
         userNote: String? = nil) {
        self.weekStartDate = weekStartDate
        self.generatedAt = generatedAt
        self.adherencePercent = adherencePercent
        self.bestDomain = bestDomain
        self.weakestDomain = weakestDomain
        self.bestDayOfWeek = bestDayOfWeek
        self.workoutCount = workoutCount
        self.hydrationDaysMet = hydrationDaysMet
        self.fastingDaysCompleted = fastingDaysCompleted
        self.learningMinutesTotal = learningMinutesTotal
        self.dominantMascotState = dominantMascotState
        self.coachMessage = coachMessage
        self.userNote = userNote
    }
}
