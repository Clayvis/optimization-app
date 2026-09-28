import Foundation
import SwiftData

@Model
final class LiftSession {
    /// Stable identity for linking a suggestion to the workout actually logged
    /// (SchemaV13). Nil for sessions created before V13. Deliberately not named
    /// `id`: an optional `id` would replace the persistentModelID-based
    /// Identifiable conformance, so every pre-V13 row would share the nil
    /// identity in any `ForEach(sessions)`.
    var sessionID: UUID? = nil
    var date: Date = Date.distantPast
    var template: String = "Lift A"
    @Relationship(deleteRule: .cascade, inverse: \LiftExercise.session)
    var exercises: [LiftExercise]? = []
    var totalVolumeLbs: Double = 0
    var durationMinutes: Int = 0
    var avgHR: Int?
    var notes: String?

    init(date: Date, template: String) {
        self.sessionID = UUID()
        self.date = date
        self.template = template
    }
}

@Model
final class LiftExercise {
    var name: String = ""
    var orderIndex: Int = 0
    @Relationship(deleteRule: .cascade, inverse: \LiftSet.exercise)
    var sets: [LiftSet]? = []
    var rpe: Int?
    var progressionSets: Int = 3
    var progressionLowerReps: Int = 10
    var progressionUpperReps: Int = 15
    var session: LiftSession?
    var isCustom: Bool = false

    init(name: String, orderIndex: Int, isCustom: Bool = false) {
        self.name = name
        self.orderIndex = orderIndex
        self.isCustom = isCustom
    }
}

@Model
final class LiftSet {
    var weightLbs: Double = 0
    var reps: Int = 0
    var repsInReserve: Int?
    var restSeconds: Int?
    var orderIndex: Int = 0
    var exercise: LiftExercise?

    init(weightLbs: Double, reps: Int, orderIndex: Int) {
        self.weightLbs = weightLbs
        self.reps = reps
        self.orderIndex = orderIndex
    }
}
