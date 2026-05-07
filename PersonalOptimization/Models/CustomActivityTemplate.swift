import Foundation
import SwiftData

/// A user-defined activity type. Lets users (especially the wife test profile)
/// log activities the hardcoded Lift/Basketball/Swim flows don't cover —
/// running, walking, HIIT, yoga, hiking, classes, anything the user wants.
///
/// Templates are first-class persisted rows. The Settings → Training →
/// Activities surface lets users add/edit/delete. TrainingHubView surfaces
/// active templates as tap-to-start session entry points.
@Model
final class CustomActivityTemplate {
    var name: String = ""                              // "Running", "HIIT class", "Yoga"
    var systemImageName: String = "figure.run"         // SF Symbol used in the hub list
    var defaultDurationMinutes: Int = 30
    var trackDistance: Bool = false                    // running/walking/biking → true
    var notes: String?
    var createdAt: Date = Date.distantPast
    var archived: Bool = false                         // soft-delete; archived templates hide from the hub but preserve history

    init(name: String,
         systemImageName: String = "figure.run",
         defaultDurationMinutes: Int = 30,
         trackDistance: Bool = false,
         notes: String? = nil) {
        self.name = name
        self.systemImageName = systemImageName
        self.defaultDurationMinutes = defaultDurationMinutes
        self.trackDistance = trackDistance
        self.notes = notes
        self.createdAt = Date()
    }
}

/// One logged session of a CustomActivityTemplate. Mirrors the shape of
/// LiftSession / BasketballSession / SwimSession just generically: duration +
/// optional distance + optional intensity tag. Writes a `WorkoutEvent` with
/// `source = .custom` so streaks, master metric, and TrendAnalytics see it
/// the same as the typed sessions.
@Model
final class CustomActivitySession {
    var date: Date = Date.distantPast
    var templateName: String = ""                      // copied at log time; survives template archive/delete
    var durationMinutes: Int = 0
    var distanceMeters: Double?
    var intensity: String?                             // "easy" | "moderate" | "hard" | nil
    var avgHR: Int?
    var caloriesKcal: Double?
    var notes: String?
    var templateID: UUID?                              // weak link back to the template row when present

    init(date: Date,
         templateName: String,
         durationMinutes: Int,
         distanceMeters: Double? = nil,
         intensity: String? = nil,
         notes: String? = nil) {
        self.date = date
        self.templateName = templateName
        self.durationMinutes = durationMinutes
        self.distanceMeters = distanceMeters
        self.intensity = intensity
        self.notes = notes
    }
}
