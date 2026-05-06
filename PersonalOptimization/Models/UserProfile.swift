import Foundation
import SwiftData

@Model
final class UserProfile {
    var name: String = ""
    var dob: Date = Date.distantPast
    var sex: String = "male"
    var heightInches: Double = 74
    var weightLbs: Double = 205
    var timezone: String = "Asia/Tokyo"
    var fastWindowStartHour: Int = 22
    var fastWindowEndHour: Int = 10
    var bottleSizeOz: Double = 32
    var anthropicModel: String = "claude-sonnet-4-6"
    var rolloutPhase: Int = 1
    var notificationBundling: Bool = false
    var mascotEnabled: Bool = true
    var reducedMotion: Bool = false

    init(name: String = "", dob: Date = .distantPast, sex: String = "male") {
        self.name = name
        self.dob = dob
        self.sex = sex
    }
}
