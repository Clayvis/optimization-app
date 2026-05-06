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
    var subjectiveEnergy: Int?
    var achillesPain: Int?
    var sleepHours: Double?
    var restingHR: Int?
    var hrvRmssd: Double?
    var weightLbs: Double?
    var notes: String?

    init(date: Date) {
        self.date = Calendar.current.startOfDay(for: date)
    }
}
