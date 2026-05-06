import Foundation
import SwiftData

@Model
final class LearningStreak {
    var module: String = ""
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var lastCompletedDate: Date?
    var totalMinutesAllTime: Int = 0

    init(module: String) {
        self.module = module
    }
}
