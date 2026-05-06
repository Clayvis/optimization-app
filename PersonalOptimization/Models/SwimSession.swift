import Foundation
import SwiftData

@Model
final class SwimSession {
    var date: Date = Date.distantPast
    var poolLengthMeters: Double = 25
    var laps: Int = 0
    var totalMeters: Double = 0
    var durationMinutes: Int = 0
    var avgHR: Int?
    var location: String?

    init(date: Date, poolLengthMeters: Double = 25) {
        self.date = date
        self.poolLengthMeters = poolLengthMeters
    }
}
