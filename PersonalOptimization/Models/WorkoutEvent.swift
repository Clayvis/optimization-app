import Foundation
import SwiftData

enum WorkoutEventSource: String, Codable, CaseIterable, Sendable {
    case lift
    case basketball
    case swim
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

    init(date: Date, completed: Bool, source: WorkoutEventSource, sourceID: UUID? = nil) {
        self.date = date
        self.completed = completed
        self.source = source.rawValue
        self.sourceID = sourceID
    }
}
