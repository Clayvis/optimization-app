import Foundation
import SwiftData

/// Where a food's nutrition facts came from. Stored on the model as the raw
/// string (WorkoutEvent convention) so CloudKit sees a plain attribute.
enum FoodSource: String, Codable, CaseIterable, Sendable {
    case userCreated = "user_created"
    case openFoodFacts = "open_food_facts"
    case fatSecret = "fat_secret"
    case nutritionix
    case photoEstimate = "photo_estimate"

    /// A photo guess must not become a permanent database entry by accident,
    /// so it stays out of the Frequent list until the user promotes it.
    var countsTowardFrequent: Bool { self != .photoEstimate }

    var displayName: String {
        switch self {
        case .userCreated: return "My food"
        case .openFoodFacts: return "Open Food Facts"
        case .fatSecret: return "FatSecret"
        case .nutritionix: return "Nutritionix"
        case .photoEstimate: return "Photo estimate"
        }
    }
}

/// A food the user can log: their own entries, cached database hits, and
/// photo estimates. Macros are per `servingSize` `servingUnit`.
///
/// `useCount` and `lastUsed` are maintained by NutritionService at log time.
/// They drive the Recent and Frequent lists directly; nothing recomputes them
/// from FoodEntry at query time.
///
/// All fields default-valued and no unique attributes (CloudKit-compatible).
@Model
final class FoodItem {
    var id: UUID = UUID()
    var name: String = ""
    var brand: String?
    var barcode: String?
    var source: String = FoodSource.userCreated.rawValue
    var externalID: String?
    var servingSize: Double = 1
    var servingUnit: String = "serving"
    var servingsPerContainer: Double?
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var fiber: Double?
    var sugar: Double?
    var isFavorite: Bool = false
    var lastUsed: Date?
    var useCount: Int = 0
    var createdAt: Date = Date.distantPast

    init(name: String,
         brand: String? = nil,
         barcode: String? = nil,
         source: FoodSource = .userCreated,
         externalID: String? = nil,
         servingSize: Double = 1,
         servingUnit: String = "serving",
         servingsPerContainer: Double? = nil,
         calories: Double,
         protein: Double,
         carbs: Double,
         fat: Double,
         fiber: Double? = nil,
         sugar: Double? = nil,
         createdAt: Date = Date()) {
        self.name = name
        self.brand = brand
        self.barcode = barcode
        self.source = source.rawValue
        self.externalID = externalID
        self.servingSize = servingSize
        self.servingUnit = servingUnit
        self.servingsPerContainer = servingsPerContainer
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.sugar = sugar
        self.createdAt = createdAt
    }

    var sourceValue: FoodSource { FoodSource(rawValue: source) ?? .userCreated }

    /// Per-serving macros as a value.
    var macros: MacroTotals {
        MacroTotals(calories: calories, protein: protein, carbs: carbs, fat: fat, fiber: fiber, sugar: sugar)
    }

    /// "100 g", "1 cup", "1 serving".
    var servingLabel: String {
        NutritionFormat.serving(size: servingSize, unit: servingUnit)
    }
}
