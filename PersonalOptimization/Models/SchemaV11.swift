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
/// CloudKit-compatible. AppSchema.current points here so phone, watch, and
/// complications agree.
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
}
