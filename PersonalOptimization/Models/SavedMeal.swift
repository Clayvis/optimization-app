import Foundation
import SwiftData

/// A named group of foods the user logs together ("Usual breakfast").
/// `useCount` / `lastUsed` drive the Saved Meals ordering directly.
///
/// Items use the LiftSession relationship pattern (cascade + inverse, optional
/// array with a default), the one relationship shape already proven against
/// CloudKit in this codebase.
@Model
final class SavedMeal {
    var id: UUID = UUID()
    var name: String = ""
    @Relationship(deleteRule: .cascade, inverse: \SavedMealItem.meal)
    var items: [SavedMealItem]? = []
    var lastUsed: Date?
    var useCount: Int = 0
    var createdAt: Date = Date.distantPast

    init(name: String, createdAt: Date = Date()) {
        self.name = name
        self.createdAt = createdAt
    }

    var orderedItems: [SavedMealItem] {
        (items ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }

    /// Sum of every item at its saved serving count.
    var totals: MacroTotals {
        MacroTotals.sum(orderedItems.map(\.totals))
    }
}

/// One food inside a SavedMeal. Snapshots the food like FoodEntry does and
/// keeps `foodID` so logging the meal can pick up the food's latest facts
/// when the FoodItem still exists.
@Model
final class SavedMealItem {
    var foodID: UUID?
    var servings: Double = 1
    var orderIndex: Int = 0
    var name: String = ""
    var brand: String?
    var servingSize: Double = 1
    var servingUnit: String = "serving"
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var fiber: Double?
    var sugar: Double?
    var meal: SavedMeal?

    init(food: FoodItem, servings: Double, orderIndex: Int) {
        self.foodID = food.id
        self.servings = servings
        self.orderIndex = orderIndex
        self.name = food.name
        self.brand = food.brand
        self.servingSize = food.servingSize
        self.servingUnit = food.servingUnit
        self.calories = food.calories
        self.protein = food.protein
        self.carbs = food.carbs
        self.fat = food.fat
        self.fiber = food.fiber
        self.sugar = food.sugar
    }

    var perServing: MacroTotals {
        MacroTotals(calories: calories, protein: protein, carbs: carbs, fat: fat, fiber: fiber, sugar: sugar)
    }

    var totals: MacroTotals { perServing.scaled(by: servings) }
}
