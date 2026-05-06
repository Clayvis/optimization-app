import Foundation
import SwiftData

/// One row per freeze applied. Required because `WorkoutEvent` only covers workouts
/// and freezes can apply to any domain (workout, fasting, hydration, learning, protocol).
@Model
final class FreezeApplication {
    var domain: String = StreakDomain.workout.rawValue
    var date: Date = Date.distantPast    // start of day in user TZ

    init(domain: StreakDomain, date: Date) {
        self.domain = domain.rawValue
        self.date = date
    }
}
