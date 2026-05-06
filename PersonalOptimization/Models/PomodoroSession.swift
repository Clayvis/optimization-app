import Foundation
import SwiftData

@Model
final class PomodoroSession {
    var date: Date = Date.distantPast
    var courseTag: String = ""
    var workMinutes: Int = 50
    var breakMinutes: Int = 10
    var completedCycles: Int = 0
    var notes: String?

    init(date: Date, courseTag: String, workMinutes: Int = 50, breakMinutes: Int = 10) {
        self.date = date
        self.courseTag = courseTag
        self.workMinutes = workMinutes
        self.breakMinutes = breakMinutes
    }
}
