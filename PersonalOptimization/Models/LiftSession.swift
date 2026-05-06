import Foundation
import SwiftData

@Model
final class LiftSession {
    var date: Date = Date.distantPast
    var template: String = "Lift A"
    @Relationship(deleteRule: .cascade, inverse: \LiftExercise.session)
    var exercises: [LiftExercise]? = []
    var totalVolumeLbs: Double = 0
    var durationMinutes: Int = 0
    var avgHR: Int?
    var notes: String?

    init(date: Date, template: String) {
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
    var session: LiftSession?

    init(name: String, orderIndex: Int) {
        self.name = name
        self.orderIndex = orderIndex
    }
}

@Model
final class LiftSet {
    var weightLbs: Double = 0
    var reps: Int = 0
    var restSeconds: Int?
    var orderIndex: Int = 0
    var exercise: LiftExercise?

    init(weightLbs: Double, reps: Int, orderIndex: Int) {
        self.weightLbs = weightLbs
        self.reps = reps
        self.orderIndex = orderIndex
    }
}
