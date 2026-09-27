import Foundation
import SwiftData
@testable import PersonalOptimization

/// Frozen model declarations copied verbatim from released commit dbb4644.
/// Do not substitute current Lift classes: that hides the real upgrade failure.
enum ReleasedNutritionSchema: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(11, 0, 0) }
    static var models: [any PersistentModel.Type] {
        let excluded = [ObjectIdentifier(SchemaV11.LiftSession.self),
                        ObjectIdentifier(SchemaV11.LiftExercise.self),
                        ObjectIdentifier(SchemaV11.LiftSet.self)]
        return SchemaV10.models.filter { !excluded.contains(ObjectIdentifier($0)) } + [
            LiftSession.self, LiftExercise.self, LiftSet.self,
            FoodItem.self, FoodEntry.self, SavedMeal.self, SavedMealItem.self, NutritionTargets.self
        ]
    }

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

/// V10 shipped the same workout graph, before nutrition entities were added.
enum ReleasedPreNutritionSchema: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(10, 0, 0) }
    static var models: [any PersistentModel.Type] {
        let nutrition = [ObjectIdentifier(FoodItem.self), ObjectIdentifier(FoodEntry.self),
                         ObjectIdentifier(SavedMeal.self), ObjectIdentifier(SavedMealItem.self),
                         ObjectIdentifier(NutritionTargets.self)]
        return ReleasedNutritionSchema.models.filter { !nutrition.contains(ObjectIdentifier($0)) }
    }
}

/// Frozen workout declarations from 1184d54. Proves the repair still recognizes
/// databases created by the already-shipped InBody/Phase 2 build.
enum ReleasedInBodySchema: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(12, 0, 0) }
    static var models: [any PersistentModel.Type] {
        let old = [ObjectIdentifier(ReleasedNutritionSchema.LiftSession.self),
                   ObjectIdentifier(ReleasedNutritionSchema.LiftExercise.self),
                   ObjectIdentifier(ReleasedNutritionSchema.LiftSet.self)]
        return ReleasedNutritionSchema.models.filter { !old.contains(ObjectIdentifier($0)) } + [
            LiftSession.self, LiftExercise.self, LiftSet.self, InBodyScan.self
        ]
    }

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
