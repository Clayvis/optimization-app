import Foundation
import SwiftData

@Model
final class StreakCounter {
    var domain: String = StreakDomain.workout.rawValue
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var lastCompletedDate: Date?
    var freezesAvailable: Int = 2
    var freezesUsedThisMonth: Int = 0
    var freezeMonthAnchor: Date = Date.distantPast

    init(domain: StreakDomain) {
        self.domain = domain.rawValue
    }
}
