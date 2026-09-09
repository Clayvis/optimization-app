import Foundation

// Pure nutrition value types. This file rides the SharedModels glob so the
// phone, the watch app, and the complications extension all compute the same
// numbers from the same rows. No SwiftData, no UI.

/// Calories and macros as a value: per serving, per entry, or per day.
/// Fiber and sugar are the only sub-macros in v1 and stay optional so a food
/// without a fiber figure never reads as "0 g fiber".
struct MacroTotals: Equatable, Sendable {
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var fiber: Double?
    var sugar: Double?

    static let zero = MacroTotals()

    /// Reject non-numeric input and arithmetic overflow before persistence or
    /// HealthKit writes. Optional facts may be absent, but never NaN/infinity.
    var isFinite: Bool {
        [calories, protein, carbs, fat, caloriesFromMacros].allSatisfy(\.isFinite)
            && fiber?.isFinite != false && sugar?.isFinite != false
    }

    init(calories: Double = 0,
         protein: Double = 0,
         carbs: Double = 0,
         fat: Double = 0,
         fiber: Double? = nil,
         sugar: Double? = nil) {
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.sugar = sugar
    }

    func scaled(by factor: Double) -> MacroTotals {
        MacroTotals(calories: calories * factor,
                    protein: protein * factor,
                    carbs: carbs * factor,
                    fat: fat * factor,
                    fiber: fiber.map { $0 * factor },
                    sugar: sugar.map { $0 * factor })
    }

    static func + (lhs: MacroTotals, rhs: MacroTotals) -> MacroTotals {
        MacroTotals(calories: lhs.calories + rhs.calories,
                    protein: lhs.protein + rhs.protein,
                    carbs: lhs.carbs + rhs.carbs,
                    fat: lhs.fat + rhs.fat,
                    fiber: addOptional(lhs.fiber, rhs.fiber),
                    sugar: addOptional(lhs.sugar, rhs.sugar))
    }

    static func sum(_ items: [MacroTotals]) -> MacroTotals {
        items.reduce(.zero, +)
    }

    /// Calories implied by the macros (4 / 4 / 9). A manual entry whose
    /// stated calories drift far from this is probably a typo.
    var caloriesFromMacros: Double {
        protein * NutritionTargetValues.kcalPerGramProtein
            + carbs * NutritionTargetValues.kcalPerGramCarbs
            + fat * NutritionTargetValues.kcalPerGramFat
    }

    private static func addOptional(_ a: Double?, _ b: Double?) -> Double? {
        switch (a, b) {
        case (nil, nil): return nil
        case (let x?, nil): return x
        case (nil, let y?): return y
        case (let x?, let y?): return x + y
        }
    }
}

/// Daily targets in grams. Grams are what people actually hit; percent of
/// calories is derived for display only, because it drifts when calories
/// change.
struct NutritionTargetValues: Equatable, Sendable {
    static let kcalPerGramProtein = 4.0
    static let kcalPerGramCarbs = 4.0
    static let kcalPerGramFat = 9.0

    var calories: Double
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var eatBackExerciseCalories: Bool = false
    var exerciseEatBackPercent: Double = 0.5

    var isFinite: Bool {
        [calories, proteinGrams, carbsGrams, fatGrams, exerciseEatBackPercent, caloriesFromMacros]
            .allSatisfy(\.isFinite)
    }

    init(calories: Double,
         proteinGrams: Double,
         carbsGrams: Double,
         fatGrams: Double,
         eatBackExerciseCalories: Bool = false,
         exerciseEatBackPercent: Double = 0.5) {
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.eatBackExerciseCalories = eatBackExerciseCalories
        self.exerciseEatBackPercent = exerciseEatBackPercent
    }

    /// Calories the gram targets add up to. Shown next to the calorie target
    /// so a mismatch is visible while editing.
    var caloriesFromMacros: Double {
        proteinGrams * Self.kcalPerGramProtein
            + carbsGrams * Self.kcalPerGramCarbs
            + fatGrams * Self.kcalPerGramFat
    }

    var proteinPercent: Double { share(proteinGrams * Self.kcalPerGramProtein) }
    var carbsPercent: Double { share(carbsGrams * Self.kcalPerGramCarbs) }
    var fatPercent: Double { share(fatGrams * Self.kcalPerGramFat) }

    private func share(_ kcal: Double) -> Double {
        calories > 0 ? kcal / calories : 0
    }

    /// Starting point for a first-time setup: 2000 kcal, protein at 0.8 g per
    /// pound of body weight when the profile knows it (140 g otherwise), fat
    /// at 25 percent of calories, carbs fill the remainder. The user edits
    /// from here; nothing is saved until they do.
    static func prefill(weightLbs: Double?, calories: Double = 2000) -> NutritionTargetValues {
        let validWeight = weightLbs.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let protein = validWeight.map { max(50, ($0 * 0.8).rounded()) } ?? 140
        let fat = (calories * 0.25 / kcalPerGramFat).rounded()
        let carbs = max(0, ((calories - protein * kcalPerGramProtein - fat * kcalPerGramFat) / kcalPerGramCarbs).rounded())
        return NutritionTargetValues(calories: calories, proteinGrams: protein, carbsGrams: carbs, fatGrams: fat)
    }

    /// Non-negative grams and calories, percent clamped to 0...1.
    func sanitized() -> NutritionTargetValues {
        NutritionTargetValues(calories: max(0, calories),
                              proteinGrams: max(0, proteinGrams),
                              carbsGrams: max(0, carbsGrams),
                              fatGrams: max(0, fatGrams),
                              eatBackExerciseCalories: eatBackExerciseCalories,
                              exerciseEatBackPercent: min(1, max(0, exerciseEatBackPercent)))
    }

    var isUsable: Bool {
        isFinite && (calories > 0 || proteinGrams > 0 || carbsGrams > 0 || fatGrams > 0)
    }
}

/// The day's numbers for the Today card, the day view, and (Phase 8) the
/// complication. "Remaining" is target minus logged, plus the exercise
/// eat-back when the user opted in. Negative remaining means over.
struct NutritionDaySummary: Equatable, Sendable {
    let date: Date
    let consumed: MacroTotals
    let targets: NutritionTargetValues?
    /// Active energy burned that day from HealthKit (DailyLog). nil when unknown.
    let activeEnergyKcal: Double?
    let entryCount: Int

    init(date: Date,
         consumed: MacroTotals,
         targets: NutritionTargetValues?,
         activeEnergyKcal: Double?,
         entryCount: Int) {
        self.date = date
        self.consumed = consumed
        self.targets = targets
        self.activeEnergyKcal = activeEnergyKcal
        self.entryCount = entryCount
    }

    var hasTargets: Bool { targets != nil }

    /// Calories added back for exercise. Zero unless eat-back is on and
    /// HealthKit reported a burn. Watch and phone estimates run high, which
    /// is why the default percent is 50.
    var exerciseAdjustmentKcal: Double {
        guard let targets, targets.eatBackExerciseCalories,
              let burned = activeEnergyKcal, burned.isFinite, burned > 0 else { return 0 }
        return burned * min(1, max(0, targets.exerciseEatBackPercent))
    }

    /// The day's calorie budget after the exercise adjustment.
    var calorieBudget: Double? { targets.map { $0.calories + exerciseAdjustmentKcal } }

    var caloriesRemaining: Double? { calorieBudget.map { $0 - consumed.calories } }
    var proteinRemaining: Double? { targets.map { $0.proteinGrams - consumed.protein } }
    var carbsRemaining: Double? { targets.map { $0.carbsGrams - consumed.carbs } }
    var fatRemaining: Double? { targets.map { $0.fatGrams - consumed.fat } }

    var caloriesProgress: Double { progress(consumed.calories, of: calorieBudget) }
    var proteinProgress: Double { progress(consumed.protein, of: targets?.proteinGrams) }
    var carbsProgress: Double { progress(consumed.carbs, of: targets?.carbsGrams) }
    var fatProgress: Double { progress(consumed.fat, of: targets?.fatGrams) }

    private func progress(_ value: Double, of target: Double?) -> Double {
        guard let target, target.isFinite, target > 0, value.isFinite else { return 0 }
        return min(1, max(0, value / target))
    }
}

/// Display helpers shared by phone, watch, and complication.
enum NutritionFormat {
    /// "1", "1.5", "0.25". Never more than two decimals.
    static func number(_ value: Double) -> String {
        guard value.isFinite else { return String(localized: "Unavailable") }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// Format directly as Double: Int conversion traps on non-finite values
    /// and large finite values arriving from pasted input or synced history.
    static func wholeNumber(_ value: Double) -> String {
        guard value.isFinite else { return String(localized: "Unavailable") }
        let rounded = value.rounded()
        return (rounded == 0 ? 0 : rounded).formatted(.number.grouping(.never).precision(.fractionLength(0)))
    }

    static func grams(_ value: Double) -> String {
        "\(wholeNumber(value)) g"
    }

    static func kcal(_ value: Double) -> String {
        "\(wholeNumber(value)) kcal"
    }

    /// "100 g", "1 cup", "1 serving".
    static func serving(size: Double, unit: String) -> String {
        "\(number(size)) \(unit)"
    }

    /// "42 g protein left" / "12 g protein over". Whole numbers only; nobody
    /// plans a day around 0.4 g.
    static func remaining(_ value: Double, unit: String) -> String {
        guard value.isFinite else { return String(localized: "Amount unavailable") }
        let magnitude = wholeNumber(abs(value))
        return "\(magnitude) \(unit) \(value >= -0.5 ? "left" : "over")"
    }
}
