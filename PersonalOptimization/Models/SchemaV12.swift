import Foundation
import SwiftData

/// Body-composition scans and workout progression/RIR fields.
/// Frozen released InBody schema. Do not add fields here: V13 uses the live
/// workout types and historical stores must keep their released checksum.
enum SchemaV12: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(12, 0, 0) }
    static var models: [any PersistentModel.Type] {
        let historicalLiftModels = [
            ObjectIdentifier(SchemaV11.LiftSession.self),
            ObjectIdentifier(SchemaV11.LiftExercise.self),
            ObjectIdentifier(SchemaV11.LiftSet.self)
        ]
        return SchemaV11.models.filter { !historicalLiftModels.contains(ObjectIdentifier($0)) } + [
            LiftSession.self,
            LiftExercise.self,
            LiftSet.self,
            InBodyScan.self
        ]
    }

    // Frozen released InBody workout graph. V13 adds a stable session ID.
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
}
