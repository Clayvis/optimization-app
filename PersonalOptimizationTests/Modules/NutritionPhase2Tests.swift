import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class NutritionPhase2Tests: XCTestCase {
    private var containers: [ModelContainer] = []
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return value
    }
    private func date(_ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: 45))!
    }
    private func setup() throws -> (ModelContext, NutritionService, FoodItem) {
        let container = try InMemoryContainer.make()
        containers.append(container)
        let context = container.mainContext
        let service = NutritionService(modelContext: context, calendar: calendar)
        let food = try service.createFood(name: "Oats", servingSize: 40, servingUnit: "g",
                                         macros: MacroTotals(calories: 150, protein: 5, carbs: 27, fat: 3))
        return (context, service, food)
    }

    func test_copyPreservesSnapshotsPortionsAndCreatesFreshIdentity() throws {
        let (_, service, food) = try setup()
        let original = try service.logEntry(food: food, servings: 2.5, meal: .dinner, at: date(25, 23))
        original.healthKitSampleIDs = [UUID()]
        food.calories = 999
        let copies = try service.copyEntries([original], to: date(26), meal: .lunch)
        let copy = try XCTUnwrap(copies.first)
        XCTAssertEqual(copy.calories, 150)
        XCTAssertEqual(copy.servings, 2.5)
        XCTAssertEqual(copy.date, calendar.startOfDay(for: date(26)))
        XCTAssertEqual(copy.mealSlot, .lunch)
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertTrue(copy.healthKitSampleIDs.isEmpty)
        XCTAssertEqual(original.mealSlot, .dinner)
        XCTAssertEqual(original.healthKitSampleIDs.count, 1)
        XCTAssertEqual(food.useCount, 2)
    }

    func test_invalidBatchDoesNotPartiallyLogOrIncrementCounters() throws {
        let (_, service, food) = try setup()
        let a = try service.logEntry(food: food, servings: 1, meal: .breakfast, at: date(25))
        let b = try service.logEntry(food: food, servings: 1, meal: .dinner, at: date(25))
        b.servings = .infinity
        XCTAssertThrowsError(try service.copyEntries([a, b], to: date(26)))
        XCTAssertTrue(service.entries(for: date(26)).isEmpty)
        XCTAssertEqual(food.useCount, 2)
    }

    func test_savedMealSurvivesMissingFoodAndCountsOneMealUse() throws {
        let (context, service, food) = try setup()
        let original = try service.logEntry(food: food, servings: 1.5, meal: .breakfast, at: date(24))
        let saved = try service.saveMeal(name: " Usual breakfast ", entries: [original])
        context.delete(food); try context.save()
        let result = try service.logSavedMeal(saved, to: .breakfast, at: date(26))
        XCTAssertEqual(saved.name, "Usual breakfast")
        XCTAssertEqual(saved.useCount, 1)
        XCTAssertEqual(saved.lastUsed, date(26))
        XCTAssertEqual(result.first?.totals.calories, 225)
        XCTAssertEqual(saved.orderedItems.first?.servings, 1.5)
        XCTAssertEqual(try service.savedMeals().count, 1)
    }

    func test_recentCutoffAndFrequentExcludesPhotoEstimates() throws {
        let (_, service, food) = try setup()
        try service.logEntry(food: food, servings: 1, meal: .breakfast, at: date(12))
        XCTAssertTrue(try service.recentFoods(asOf: date(26)).isEmpty)
        try service.logEntry(food: food, servings: 1, meal: .breakfast, at: date(13, 0))
        XCTAssertEqual(try service.recentFoods(asOf: date(26)).count, 1)
        XCTAssertEqual(try service.recentMeals(asOf: date(26)).count, 1)
        food.source = FoodSource.photoEstimate.rawValue
        XCTAssertTrue(try service.frequentFoods().isEmpty)
    }

    func test_copyDayPreservesSlotsAndBackfillDoesNotRegressRecents() throws {
        let (_, service, food) = try setup()
        let a = try service.logEntry(food: food, servings: 1, meal: .breakfast, at: date(25, 8))
        let b = try service.logEntry(food: food, servings: 2, meal: .dinner, at: date(25, 23))
        let copied = try service.copyEntries([a, b], to: date(24))
        XCTAssertEqual(copied.map(\.mealSlot), [.breakfast, .dinner])
        XCTAssertTrue(copied.allSatisfy { calendar.isDate($0.loggedAt, inSameDayAs: date(24)) })
        XCTAssertEqual(food.lastUsed, date(25, 23))
    }

    func test_backupRoundTripPreservesSavedMealSnapshots() throws {
        let (context, service, food) = try setup()
        let entry = try service.logEntry(food: food, servings: 2, meal: .breakfast, at: date(25))
        try service.saveMeal(name: "Breakfast", entries: [entry])
        let data = try JSONExportService.export(modelContext: context)
        let restoredContainer = try InMemoryContainer.make()
        containers.append(restoredContainer)
        let restored = restoredContainer.mainContext
        try JSONImportService.restore(data: data, modelContext: restored)
        let newService = NutritionService(modelContext: restored, calendar: calendar)
        let saved = try XCTUnwrap(newService.savedMeals().first)
        XCTAssertEqual(saved.name, "Breakfast")
        XCTAssertEqual(saved.totals.calories, 300)
        let copied = try newService.logSavedMeal(saved, to: .breakfast, at: date(26))
        XCTAssertEqual(copied.first?.servings, 2)
    }

    func test_repeatedMealKeepsTheOrderItWasLoggedIn() throws {
        let (_, service, oats) = try setup()
        let eggs = try service.createFood(name: "Eggs", servingSize: 2, servingUnit: "large",
                                          macros: MacroTotals(calories: 140, protein: 12, carbs: 1, fat: 10))
        let coffee = try service.createFood(name: "Coffee", servingSize: 1, servingUnit: "cup",
                                            macros: MacroTotals(calories: 5, protein: 0, carbs: 1, fat: 0))
        try service.logEntry(food: oats, servings: 1, meal: .breakfast, at: date(25, 7))
        try service.logEntry(food: eggs, servings: 1, meal: .breakfast, at: date(25, 8))
        try service.logEntry(food: coffee, servings: 1, meal: .breakfast, at: date(25, 9))
        let meal = try XCTUnwrap(service.recentMeals(asOf: date(26)).first)
        XCTAssertEqual(meal.entries.map(\.name), ["Oats", "Eggs", "Coffee"])
        let copied = try service.copyEntries(meal.entries, to: date(24), meal: .breakfast)
        XCTAssertEqual(copied.map(\.name), ["Oats", "Eggs", "Coffee"])
        XCTAssertEqual(service.entries(for: date(24)).map(\.name), ["Oats", "Eggs", "Coffee"],
                       "The day list, sorted by time, shows the copied meal in its original order")
        XCTAssertTrue(copied.allSatisfy { calendar.isDate($0.loggedAt, inSameDayAs: date(24)) })
    }

    func test_everyCopiedItemIsMirroredToHealth() async throws {
        let (context, _, food) = try setup()
        let fake = FakeHealthKitService()
        fake.setNutritionStatus(.sharingAuthorized)
        let service = NutritionService(modelContext: context, calendar: calendar, healthKit: fake)
        let original = try service.logEntry(food: food, servings: 2, meal: .lunch, at: date(25))
        await service.lastHealthKitTask?.value
        let copied = try service.copyEntries([original, original], to: date(26))
        await service.lastHealthKitTask?.value
        XCTAssertEqual(copied.count, 2)
        XCTAssertTrue(copied.allSatisfy { $0.healthKitSyncedAt != nil && !$0.healthKitSampleIDs.isEmpty })
        XCTAssertNotEqual(copied[0].healthKitSampleIDs, copied[1].healthKitSampleIDs)
    }
}
