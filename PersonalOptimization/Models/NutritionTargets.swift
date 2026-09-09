import Foundation
import SwiftData

/// Daily calorie and macro targets, in grams. History is kept: the row in
/// force for a day is the latest `effectiveFrom` at or before that day, so
/// past days are always judged against the targets that applied then.
/// NutritionService.setTargets is the only writer.
@Model
final class NutritionTargets {
    var id: UUID = UUID()
    var effectiveFrom: Date = Date.distantPast   // start of day in the user's calendar
    var calories: Double = 2000
    var proteinGrams: Double = 140
    var carbsGrams: Double = 200
    var fatGrams: Double = 65
    var eatBackExerciseCalories: Bool = false
    var exerciseEatBackPercent: Double = 0.5     // 0...1, applies only when eatBack is on
    var createdAt: Date = Date.distantPast

    init(effectiveFrom: Date, values: NutritionTargetValues, createdAt: Date = Date()) {
        self.effectiveFrom = effectiveFrom
        self.createdAt = createdAt
        apply(values)
    }

    func apply(_ values: NutritionTargetValues) {
        calories = values.calories
        proteinGrams = values.proteinGrams
        carbsGrams = values.carbsGrams
        fatGrams = values.fatGrams
        eatBackExerciseCalories = values.eatBackExerciseCalories
        exerciseEatBackPercent = values.exerciseEatBackPercent
    }

    var values: NutritionTargetValues {
        NutritionTargetValues(calories: calories,
                              proteinGrams: proteinGrams,
                              carbsGrams: carbsGrams,
                              fatGrams: fatGrams,
                              eatBackExerciseCalories: eatBackExerciseCalories,
                              exerciseEatBackPercent: exerciseEatBackPercent)
    }
}
