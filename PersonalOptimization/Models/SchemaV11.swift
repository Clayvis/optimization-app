import Foundation
import SwiftData

/// SchemaV11 (Nutrition module, Phase 1). Additive only.
///
/// New entities:
/// - FoodItem: a loggable food (user-created, cached database hit, photo estimate).
/// - FoodEntry: one logged food on one day (day-keyed, macro snapshot).
/// - SavedMeal / SavedMealItem: named groups of foods logged together.
/// - NutritionTargets: daily calorie and macro targets with history.
///
/// No changes to existing entities. All fields default-valued, no unique
/// attributes, one cascade relationship in the LiftSession pattern;
/// CloudKit-compatible. Historical Lift declarations are frozen below: changing
/// them changes the released schema checksum and prevents upgrades from opening.
enum SchemaV11: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(11, 0, 0) }

    static var models: [any PersistentModel.Type] {
        SchemaV10.models + [
            FoodItem.self,
            FoodEntry.self,
            SavedMeal.self,
            SavedMealItem.self,
            NutritionTargets.self
        ]
    }

    // Released before the InBody progression/RIR fields. Never add current fields
    // here. V1...V11 share this pre-InBody graph; V12 uses the live models.
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
