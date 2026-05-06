import Foundation
import SwiftData

/// Coach v2 weekly programming pass. Generated on Sundays. One row per
/// `weekStartDate` (Monday). Includes the seven-day plan as embedded JSON
/// plus a narrative explanation.
@Model
final class WeeklyProgram {
    /// Monday 00:00 in user's TZ. Logically unique per week; uniqueness enforced
    /// by service-layer upsert (CloudKit forbids `@Attribute(.unique)` on
    /// cloud-backed entities).
    var weekStartDate: Date = Date.distantPast
    var generatedAt: Date = Date.distantPast
    var programJSON: String = "{}"                  // 7-day plan; structure mirrors PrescribedWorkout per day
    var coachNarrative: String = ""                 // human-readable explanation for the week
    var statusRaw: String = WeeklyProgramStatus.active.rawValue
    var tokenUsage: Int = 0
    var modelUsed: String = "claude-sonnet-4-6"

    var status: WeeklyProgramStatus {
        get { WeeklyProgramStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    init(weekStartDate: Date,
         generatedAt: Date,
         programJSON: String = "{}",
         coachNarrative: String = "",
         tokenUsage: Int = 0,
         modelUsed: String = "claude-sonnet-4-6") {
        self.weekStartDate = weekStartDate
        self.generatedAt = generatedAt
        self.programJSON = programJSON
        self.coachNarrative = coachNarrative
        self.tokenUsage = tokenUsage
        self.modelUsed = modelUsed
    }
}

enum WeeklyProgramStatus: String, Codable, CaseIterable, Sendable {
    case active
    case superseded
    case completed
}
