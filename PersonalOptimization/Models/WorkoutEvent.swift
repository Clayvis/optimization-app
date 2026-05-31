import Foundation
import SwiftData

enum WorkoutEventSource: String, Codable, CaseIterable, Sendable {
    case lift
    case basketball
    case swim
    case custom            // M3.7+: user-defined activity (running, HIIT, walk, yoga, ...)
    case manualSkip = "manual_skip"
    case sickDay = "sick_day"
    case travel
    case freeze
}

@Model
final class WorkoutEvent {
    var date: Date = Date.distantPast        // start of day in user TZ
    var completed: Bool = false
    var source: String = WorkoutEventSource.lift.rawValue
    var sourceID: UUID?

    /// HealthKit workout sample UUID when this event was imported by observing
    /// HKWorkout (Apple Watch or a third-party app); nil for in-app logs. Used
    /// to dedupe imports so the same workout is never counted twice. Optional
    /// with a nil default, so it lands as a lightweight in-place SwiftData
    /// migration on the current schema (same pattern as DailyLog.supersededAt).
    var hkWorkoutUUID: UUID?

    init(date: Date,
         completed: Bool,
         source: WorkoutEventSource,
         sourceID: UUID? = nil,
         hkWorkoutUUID: UUID? = nil) {
        self.date = date
        self.completed = completed
        self.source = source.rawValue
        self.sourceID = sourceID
        self.hkWorkoutUUID = hkWorkoutUUID
    }
}
