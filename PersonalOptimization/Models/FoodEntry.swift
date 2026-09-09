import Foundation
import SwiftData

/// The meal a logged food belongs to. Stored as the raw string.
enum MealSlot: String, Codable, CaseIterable, Sendable, Identifiable {
    case breakfast, lunch, dinner, snack

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .dinner: return "Dinner"
        case .snack: return "Snacks"
        }
    }

    var systemImage: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        case .snack: return "leaf.fill"
        }
    }

    /// The slot a new entry most likely belongs to at a local hour, so the
    /// add sheet opens pre-filtered and the user rarely has to change it.
    static func suggested(forHour hour: Int) -> MealSlot {
        switch hour {
        case 4..<11: return .breakfast
        case 11..<15: return .lunch
        case 15..<17: return .snack
        case 17..<22: return .dinner
        default: return .snack
        }
    }
}

/// One logged food on one day.
///
/// Day-keyed (`date` is the user-calendar start of day, like WorkoutEvent and
/// HydrationEntry) rather than a DailyLog relationship: DailyLog duplicates are
/// merged and superseded, which would strand child rows. The per-serving
/// macros are snapshotted from the FoodItem at log time so history never
/// changes when a food is edited or removed, day sums are a single-table
/// fetch, and an entry that syncs ahead of its FoodItem still renders.
/// `foodID` is a soft link back to the FoodItem for "log again".
///
/// HealthKit sample UUIDs are kept as CSV (the codebase's CloudKit-safe list
/// convention, see UserProfile.hydrationQuickPicksOzCSV) so an edit or delete
/// can remove the old samples before rewriting.
@Model
final class FoodEntry {
    var id: UUID = UUID()
    var date: Date = Date.distantPast        // start of day in the user's calendar
    var loggedAt: Date = Date.distantPast
    var meal: String = MealSlot.snack.rawValue
    var foodID: UUID?
    var servings: Double = 1

    // Snapshot of the food at log time (per serving).
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

    var healthKitSampleIDsCSV: String = ""
    /// Set when the HealthKit write landed; nil while pending or after a
    /// failed write (the failure itself is a HealthKitWriteFailure row).
    var healthKitSyncedAt: Date?

    init(date: Date, loggedAt: Date, meal: MealSlot, food: FoodItem, servings: Double) {
        self.date = date
        self.loggedAt = loggedAt
        self.meal = meal.rawValue
        self.foodID = food.id
        self.servings = servings
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

    var mealSlot: MealSlot {
        get { MealSlot(rawValue: meal) ?? .snack }
        set { meal = newValue.rawValue }
    }

    /// Per-serving macros as a value.
    var perServing: MacroTotals {
        MacroTotals(calories: calories, protein: protein, carbs: carbs, fat: fat, fiber: fiber, sugar: sugar)
    }

    /// What this entry contributes to the day.
    var totals: MacroTotals { perServing.scaled(by: servings) }

    var healthKitSampleIDs: [UUID] {
        get { healthKitSampleIDsCSV.split(separator: ",").compactMap { UUID(uuidString: String($0)) } }
        set { healthKitSampleIDsCSV = newValue.map(\.uuidString).joined(separator: ",") }
    }

    /// "2 × 100 g", "1 × 1 cup".
    var portionLabel: String {
        "\(NutritionFormat.number(servings)) × \(NutritionFormat.serving(size: servingSize, unit: servingUnit))"
    }
}
