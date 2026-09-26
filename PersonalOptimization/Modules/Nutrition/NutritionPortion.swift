import Foundation

/// Immutable copy boundary. A deleted or edited catalog food cannot alter a meal.
struct NutritionPortion: Codable {
    let foodID: UUID?
    let name: String
    let brand: String?
    let servingSize: Double
    let servingUnit: String
    let servings: Double
    let macros: MacroTotals

    init(_ entry: FoodEntry) {
        foodID = entry.foodID; name = entry.name; brand = entry.brand
        servingSize = entry.servingSize; servingUnit = entry.servingUnit
        servings = entry.servings; macros = entry.perServing
    }

    init(_ item: SavedMealItem) {
        foodID = item.foodID; name = item.name; brand = item.brand
        servingSize = item.servingSize; servingUnit = item.servingUnit
        servings = item.servings; macros = item.perServing
    }

    /// Uninserted adapter for the existing snapshot constructors.
    func foodSnapshot() -> FoodItem {
        FoodItem(name: name, brand: brand, servingSize: servingSize, servingUnit: servingUnit,
                 calories: macros.calories, protein: macros.protein, carbs: macros.carbs,
                 fat: macros.fat, fiber: macros.fiber, sugar: macros.sugar)
    }
}

struct RecentNutritionMeal: Identifiable {
    let id: String
    let date: Date
    let slot: MealSlot
    let entries: [FoodEntry]
    var totals: MacroTotals { MacroTotals.sum(entries.map(\.totals)) }
}

struct SavedNutritionMealDTO: Codable {
    let id: UUID
    let name: String
    let createdAt: Date
    let lastUsed: Date?
    let useCount: Int
    let items: [NutritionPortion]

    init(_ meal: SavedMeal) {
        id = meal.id; name = meal.name; createdAt = meal.createdAt
        lastUsed = meal.lastUsed; useCount = meal.useCount
        items = meal.orderedItems.map(NutritionPortion.init)
    }

    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !items.isEmpty, useCount >= 0 else { throw NutritionError.emptyMeal }
        for item in items {
            guard item.servings.isFinite, item.servings > 0,
                  item.servingSize.isFinite, item.servingSize > 0,
                  item.macros.scaled(by: item.servings).isFinite else { throw NutritionError.invalidNumber }
        }
    }

    func model() -> SavedMeal {
        let meal = SavedMeal(name: name, createdAt: createdAt)
        meal.id = id; meal.lastUsed = lastUsed; meal.useCount = useCount
        meal.items = items.enumerated().map { index, portion in
            let item = SavedMealItem(food: portion.foodSnapshot(), servings: portion.servings, orderIndex: index)
            item.foodID = portion.foodID; item.meal = meal
            return item
        }
        return meal
    }
}
