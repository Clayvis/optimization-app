import Foundation
import SwiftData

@Model
final class BasketballSession {
    var date: Date = Date.distantPast
    var startTime: Date = Date.distantPast
    var endTime: Date = Date.distantPast
    var avgHR: Int?
    var maxHR: Int?
    var hrZoneMinutes: [String: Int] = [:]
    var hydrationOz: Double = 0
    var achillesPostScore: Int?
    var notes: String?

    init(date: Date, startTime: Date, endTime: Date) {
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
    }
}
