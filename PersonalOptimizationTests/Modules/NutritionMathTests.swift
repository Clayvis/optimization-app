import XCTest
@testable import PersonalOptimization

final class NutritionMathTests: XCTestCase {

    // MARK: - MacroTotals

    func test_scaledMultipliesEveryMacroIncludingOptionalOnes() {
        let base = MacroTotals(calories: 100, protein: 10, carbs: 20, fat: 5, fiber: 2, sugar: nil)
        let scaled = base.scaled(by: 1.5)
        XCTAssertEqual(scaled.calories, 150)
        XCTAssertEqual(scaled.protein, 15)
        XCTAssertEqual(scaled.carbs, 30)
        XCTAssertEqual(scaled.fat, 7.5)
        XCTAssertEqual(scaled.fiber, 3)
        XCTAssertNil(scaled.sugar)
    }

    func test_sumKeepsSubMacroNilOnlyWhenNoItemReportsIt() {
        let a = MacroTotals(calories: 100, protein: 10, carbs: 5, fat: 2, fiber: 3, sugar: nil)
        let b = MacroTotals(calories: 50, protein: 5, carbs: 5, fat: 1, fiber: nil, sugar: nil)
        let total = MacroTotals.sum([a, b])
        XCTAssertEqual(total.calories, 150)
        XCTAssertEqual(total.protein, 15)
        XCTAssertEqual(total.fiber, 3, "A food without a fiber figure must not zero out the day's fiber")
        XCTAssertNil(total.sugar)
        XCTAssertEqual(MacroTotals.sum([]), .zero)
    }

    func test_caloriesFromMacrosUsesFourFourNine() {
        let macros = MacroTotals(calories: 0, protein: 10, carbs: 20, fat: 5)
        XCTAssertEqual(macros.caloriesFromMacros, 165)
    }

    // MARK: - Targets

    func test_prefillFromBodyWeight() {
        let values = NutritionTargetValues.prefill(weightLbs: 150)
        XCTAssertEqual(values.calories, 2000)
        XCTAssertEqual(values.proteinGrams, 120)     // 0.8 g per lb
        XCTAssertEqual(values.fatGrams, 56)          // 25% of 2000 kcal / 9
        XCTAssertEqual(values.carbsGrams, 254)       // (2000 - 480 - 504) / 4
        XCTAssertFalse(values.eatBackExerciseCalories)
        XCTAssertEqual(values.exerciseEatBackPercent, 0.5)
    }

    func test_prefillWithoutWeightUsesFlatProtein() {
        XCTAssertEqual(NutritionTargetValues.prefill(weightLbs: nil).proteinGrams, 140)
    }

    func test_percentSplitDerivesFromGrams() {
        let values = NutritionTargetValues(calories: 2000, proteinGrams: 150, carbsGrams: 200, fatGrams: 60)
        XCTAssertEqual(values.proteinPercent, 0.30, accuracy: 0.0001)
        XCTAssertEqual(values.carbsPercent, 0.40, accuracy: 0.0001)
        XCTAssertEqual(values.fatPercent, 0.27, accuracy: 0.0001)
        XCTAssertEqual(values.caloriesFromMacros, 1940)
    }

    func test_sanitizedClampsNegativesAndPercent() {
        let values = NutritionTargetValues(calories: -10, proteinGrams: -1, carbsGrams: 100, fatGrams: 50,
                                           eatBackExerciseCalories: true, exerciseEatBackPercent: 1.5).sanitized()
        XCTAssertEqual(values.calories, 0)
        XCTAssertEqual(values.proteinGrams, 0)
        XCTAssertEqual(values.exerciseEatBackPercent, 1)
        XCTAssertTrue(values.isUsable)
        XCTAssertFalse(NutritionTargetValues(calories: 0, proteinGrams: 0, carbsGrams: 0, fatGrams: 0).isUsable)
    }

    // MARK: - Day summary

    private func summary(consumedKcal: Double = 500, protein: Double = 40,
                         targets: NutritionTargetValues?, burned: Double?) -> NutritionDaySummary {
        NutritionDaySummary(date: Date(timeIntervalSince1970: 0),
                            consumed: MacroTotals(calories: consumedKcal, protein: protein, carbs: 50, fat: 20),
                            targets: targets,
                            activeEnergyKcal: burned,
                            entryCount: 2)
    }

    func test_remainingIsTargetMinusLogged() {
        let targets = NutritionTargetValues(calories: 2000, proteinGrams: 150, carbsGrams: 200, fatGrams: 60)
        let day = summary(targets: targets, burned: 400)
        XCTAssertEqual(day.caloriesRemaining, 1500)
        XCTAssertEqual(day.proteinRemaining, 110)
        XCTAssertEqual(day.carbsRemaining, 150)
        XCTAssertEqual(day.fatRemaining, 40)
        XCTAssertEqual(day.exerciseAdjustmentKcal, 0, "Eat-back is off by default; a burn changes nothing")
    }

    func test_eatBackAddsPercentOfBurnToCalorieBudgetOnly() {
        let targets = NutritionTargetValues(calories: 2000, proteinGrams: 150, carbsGrams: 200, fatGrams: 60,
                                            eatBackExerciseCalories: true, exerciseEatBackPercent: 0.5)
        let day = summary(targets: targets, burned: 400)
        XCTAssertEqual(day.exerciseAdjustmentKcal, 200)
        XCTAssertEqual(day.calorieBudget, 2200)
        XCTAssertEqual(day.caloriesRemaining, 1700)
        XCTAssertEqual(day.proteinRemaining, 110, "Exercise never changes the protein target")
        XCTAssertEqual(summary(targets: targets, burned: nil).exerciseAdjustmentKcal, 0)
    }

    func test_withoutTargetsNothingIsRemaining() {
        let day = summary(targets: nil, burned: 400)
        XCTAssertFalse(day.hasTargets)
        XCTAssertNil(day.caloriesRemaining)
        XCTAssertNil(day.proteinRemaining)
        XCTAssertEqual(day.consumed.calories, 500)
        XCTAssertEqual(day.caloriesProgress, 0)
    }

    func test_progressClampsToOneWhenOver() {
        let targets = NutritionTargetValues(calories: 400, proteinGrams: 30, carbsGrams: 10, fatGrams: 10)
        let day = summary(targets: targets, burned: nil)
        XCTAssertEqual(day.caloriesProgress, 1)
        XCTAssertEqual(day.proteinProgress, 1)
        XCTAssertEqual(day.caloriesRemaining, -100)
    }

    // MARK: - Formatting and slots

    func test_remainingReadsLeftOrOver() {
        XCTAssertEqual(NutritionFormat.remaining(42.4, unit: "g protein"), "42 g protein left")
        XCTAssertEqual(NutritionFormat.remaining(-12, unit: "kcal"), "12 kcal over")
        XCTAssertEqual(NutritionFormat.remaining(0.3, unit: "g"), "0 g left")
    }

    func test_numberFormattingDropsNoise() {
        XCTAssertEqual(NutritionFormat.number(1), "1")
        XCTAssertEqual(NutritionFormat.number(1.5), "1.5")
        XCTAssertEqual(NutritionFormat.number(0.25), "0.25")
        XCTAssertEqual(NutritionFormat.number(1.333), "1.33")
        XCTAssertEqual(NutritionFormat.serving(size: 100, unit: "g"), "100 g")
    }

    func test_mealSlotSuggestionFollowsTheClock() {
        XCTAssertEqual(MealSlot.suggested(forHour: 7), .breakfast)
        XCTAssertEqual(MealSlot.suggested(forHour: 12), .lunch)
        XCTAssertEqual(MealSlot.suggested(forHour: 16), .snack)
        XCTAssertEqual(MealSlot.suggested(forHour: 19), .dinner)
        XCTAssertEqual(MealSlot.suggested(forHour: 23), .snack)
        XCTAssertEqual(MealSlot.suggested(forHour: 2), .snack)
    }

    func test_photoEstimatesStayOutOfFrequent() {
        XCTAssertFalse(FoodSource.photoEstimate.countsTowardFrequent)
        XCTAssertTrue(FoodSource.userCreated.countsTowardFrequent)
        XCTAssertTrue(FoodSource.openFoodFacts.countsTowardFrequent)
    }
}
