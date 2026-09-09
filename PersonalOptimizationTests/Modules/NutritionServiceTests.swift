import XCTest
import SwiftData
import HealthKit
@testable import PersonalOptimization

@MainActor
final class NutritionServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var fake: FakeHealthKitService!
    private var service: NutritionService!
    private let jst = TimeZone(identifier: "Asia/Tokyo")!

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = jst
        return cal
    }

    override func setUp() async throws {
        try await super.setUp()
        container = try InMemoryContainer.make()
        context = container.mainContext
        fake = FakeHealthKitService()
        fake.setNutritionStatus(.sharingAuthorized)
        service = NutritionService(modelContext: context, calendar: calendar, healthKit: fake)
    }

    override func tearDown() async throws {
        service = nil
        fake = nil
        context = nil
        container = nil
        try await super.tearDown()
    }

    private func jstDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    /// 165 kcal, 31 g protein, 3.6 g fat per 100 g.
    private func makeFood(name: String = "Chicken breast",
                          calories: Double = 165,
                          protein: Double = 31,
                          carbs: Double = 0,
                          fat: Double = 3.6) throws -> FoodItem {
        try service.createFood(name: name, servingSize: 100, servingUnit: "g",
                               macros: MacroTotals(calories: calories, protein: protein, carbs: carbs, fat: fat))
    }

    private func awaitHealthKit() async {
        await service.lastHealthKitTask?.value
    }

    // MARK: - Day boundary (JST)

    func test_lateDinnerLandsOnThatJSTDate() throws {
        let entry = try service.logEntry(food: try makeFood(), servings: 1, meal: .dinner,
                                         at: jstDate(2026, 9, 9, 23, 45))
        XCTAssertEqual(entry.date, jstDate(2026, 9, 9, 0, 0))
        XCTAssertEqual(service.entries(for: jstDate(2026, 9, 9, 12, 0)).count, 1)
        XCTAssertEqual(service.entries(for: jstDate(2026, 9, 10, 12, 0)).count, 0)
    }

    func test_earlyBreakfastLandsOnTheNewJSTDateNotThePreviousUTCDate() throws {
        // 00:30 JST on the 10th is 15:30 UTC on the 9th. A UTC-midnight
        // assumption would file it under the 9th.
        let entry = try service.logEntry(food: try makeFood(), servings: 1, meal: .breakfast,
                                         at: jstDate(2026, 9, 10, 0, 30))
        XCTAssertEqual(entry.date, jstDate(2026, 9, 10, 0, 0))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertNotEqual(entry.date, utc.startOfDay(for: entry.loggedAt))
        XCTAssertEqual(service.entries(for: jstDate(2026, 9, 9, 12, 0)).count, 0)
    }

    // MARK: - Entries

    func test_entrySnapshotsTheFoodAndScalesByServings() throws {
        let food = try makeFood()
        let entry = try service.logEntry(food: food, servings: 1.5, meal: .lunch, at: jstDate(2026, 9, 9, 12, 0))
        XCTAssertEqual(entry.totals.calories, 247.5, accuracy: 0.001)
        XCTAssertEqual(entry.totals.protein, 46.5, accuracy: 0.001)
        XCTAssertEqual(entry.foodID, food.id)
        XCTAssertEqual(entry.portionLabel, "1.5 × 100 g")

        try service.updateFood(food, name: "Chicken breast", brand: nil, servingSize: 100, servingUnit: "g",
                               macros: MacroTotals(calories: 999, protein: 99, carbs: 0, fat: 0))
        XCTAssertEqual(entry.calories, 165, "Editing a food must not rewrite history")
        XCTAssertEqual(food.calories, 999)
    }

    func test_useCountAndLastUsedAdvanceOnEveryLog() throws {
        let food = try makeFood()
        XCTAssertEqual(food.useCount, 0)
        XCTAssertNil(food.lastUsed)
        let first = jstDate(2026, 9, 9, 8, 0)
        let second = first.addingTimeInterval(3600)
        try service.logEntry(food: food, servings: 1, meal: .breakfast, at: first)
        try service.logEntry(food: food, servings: 1, meal: .lunch, at: second)
        XCTAssertEqual(food.useCount, 2)
        XCTAssertEqual(food.lastUsed, second)
    }

    func test_foodsListPutsMostRecentlyUsedFirstAndSearchesNameAndBrand() throws {
        let oats = try service.createFood(name: "Oats", brand: "Quaker", servingSize: 40, servingUnit: "g",
                                          macros: MacroTotals(calories: 150, protein: 5, carbs: 27, fat: 3))
        let eggs = try makeFood(name: "Eggs")
        // Newest first while nothing has been logged.
        XCTAssertEqual(service.foods().map(\.name), ["Eggs", "Oats"])
        try service.logEntry(food: oats, servings: 1, meal: .breakfast, at: Date().addingTimeInterval(60))
        XCTAssertEqual(service.foods().map(\.name), ["Oats", "Eggs"])
        XCTAssertEqual(service.foods(matching: "quak").map(\.name), ["Oats"])
        XCTAssertEqual(service.foods(matching: "EGG").map(\.name), ["Eggs"])
        XCTAssertTrue(service.foods(matching: "tofu").isEmpty)
        _ = eggs
    }

    func test_invalidInputsThrowAndPersistNothing() throws {
        XCTAssertThrowsError(try service.createFood(name: "   ", servingSize: 1, servingUnit: "g", macros: .zero))
        let food = try makeFood()
        XCTAssertThrowsError(try service.logEntry(food: food, servings: 0, meal: .snack))
        XCTAssertThrowsError(try service.logEntry(food: food, servings: -1, meal: .snack))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FoodEntry>()), 0)
        XCTAssertEqual(food.useCount, 0)
    }

    // MARK: - Targets

    func test_targetsHistoryKeepsPastDaysOnTheirOwnTargets() throws {
        try service.setTargets(NutritionTargetValues(calories: 2000, proteinGrams: 150, carbsGrams: 200, fatGrams: 60),
                               from: jstDate(2026, 9, 1, 9, 0))
        try service.setTargets(NutritionTargetValues(calories: 1800, proteinGrams: 160, carbsGrams: 150, fatGrams: 55),
                               from: jstDate(2026, 9, 8, 9, 0))
        XCTAssertNil(service.targets(for: jstDate(2026, 8, 31, 12, 0)))
        XCTAssertEqual(service.targets(for: jstDate(2026, 9, 5, 12, 0))?.calories, 2000)
        XCTAssertEqual(service.targets(for: jstDate(2026, 9, 8, 0, 0))?.calories, 1800)
        XCTAssertEqual(service.targets(for: jstDate(2026, 9, 9, 23, 59))?.calories, 1800)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<NutritionTargets>()), 2)
    }

    func test_settingTargetsTwiceOnOneDayUpdatesInPlace() throws {
        try service.setTargets(NutritionTargetValues(calories: 2000, proteinGrams: 150, carbsGrams: 200, fatGrams: 60),
                               from: jstDate(2026, 9, 8, 9, 0))
        try service.setTargets(NutritionTargetValues(calories: 1700, proteinGrams: 150, carbsGrams: 200, fatGrams: 60),
                               from: jstDate(2026, 9, 8, 21, 0))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<NutritionTargets>()), 1)
        XCTAssertEqual(service.targets(for: jstDate(2026, 9, 8, 12, 0))?.calories, 1700)
    }

    func test_targetsAreSanitizedAndAllZeroIsRejected() throws {
        XCTAssertThrowsError(try service.setTargets(NutritionTargetValues(calories: 0, proteinGrams: 0, carbsGrams: 0, fatGrams: 0)))
        let row = try service.setTargets(NutritionTargetValues(calories: 2000, proteinGrams: -5, carbsGrams: 200, fatGrams: 60,
                                                               eatBackExerciseCalories: true, exerciseEatBackPercent: 1.7))
        XCTAssertEqual(row.proteinGrams, 0)
        XCTAssertEqual(row.exerciseEatBackPercent, 1)
        XCTAssertTrue(row.eatBackExerciseCalories)
    }

    // MARK: - Day summary

    func test_summaryRemainingWithExerciseEatBack() throws {
        let day = jstDate(2026, 9, 9, 12, 0)
        try service.setTargets(NutritionTargetValues(calories: 2000, proteinGrams: 150, carbsGrams: 200, fatGrams: 60,
                                                     eatBackExerciseCalories: true, exerciseEatBackPercent: 0.5),
                               from: day)
        let log = DailyLogStore(modelContext: context, calendar: calendar).upsert(for: day)
        log.activeEnergyBurnedKcal = 400
        try context.save()
        try service.logEntry(food: try makeFood(), servings: 2, meal: .lunch, at: day)   // 330 kcal, 62 g protein

        let summary = service.summary(for: day)
        XCTAssertEqual(summary.entryCount, 1)
        XCTAssertEqual(summary.exerciseAdjustmentKcal, 200)
        XCTAssertEqual(summary.calorieBudget, 2200)
        XCTAssertEqual(summary.caloriesRemaining!, 1870, accuracy: 0.001)
        XCTAssertEqual(summary.proteinRemaining!, 88, accuracy: 0.001)
    }

    func test_summaryIgnoresBurnWhenEatBackIsOff() throws {
        let day = jstDate(2026, 9, 9, 12, 0)
        try service.setTargets(NutritionTargetValues(calories: 2000, proteinGrams: 150, carbsGrams: 200, fatGrams: 60), from: day)
        let log = DailyLogStore(modelContext: context, calendar: calendar).upsert(for: day)
        log.activeEnergyBurnedKcal = 400
        try context.save()
        try service.logEntry(food: try makeFood(), servings: 2, meal: .lunch, at: day)
        let summary = service.summary(for: day)
        XCTAssertEqual(summary.exerciseAdjustmentKcal, 0)
        XCTAssertEqual(summary.caloriesRemaining!, 1670, accuracy: 0.001)
    }

    func test_summaryWithoutTargetsStillTotalsTheDay() throws {
        let day = jstDate(2026, 9, 9, 12, 0)
        try service.logEntry(food: try makeFood(), servings: 1, meal: .dinner, at: day)
        let summary = service.summary(for: day)
        XCTAssertFalse(summary.hasTargets)
        XCTAssertNil(summary.caloriesRemaining)
        XCTAssertEqual(summary.consumed.calories, 165)
    }

    func test_summaryReadsBurnFromTheCanonicalDailyLogNotASupersededDuplicate() throws {
        let day = jstDate(2026, 9, 9, 12, 0)
        try service.setTargets(NutritionTargetValues(calories: 2000, proteinGrams: 150, carbsGrams: 200, fatGrams: 60,
                                                     eatBackExerciseCalories: true, exerciseEatBackPercent: 1),
                               from: day)
        let canonical = DailyLogStore(modelContext: context, calendar: calendar).upsert(for: day)
        canonical.activeEnergyBurnedKcal = 100
        let duplicate = DailyLog(date: day, calendar: calendar)
        duplicate.activeEnergyBurnedKcal = 999
        duplicate.supersededAt = Date()
        context.insert(duplicate)
        try context.save()
        XCTAssertEqual(service.summary(for: day).exerciseAdjustmentKcal, 100)
    }

    // MARK: - HealthKit mirror

    func test_logWritesOneFoodCorrelationAndStoresItsSampleIDs() async throws {
        let entry = try service.logEntry(food: try makeFood(), servings: 2, meal: .dinner, at: jstDate(2026, 9, 9, 19, 0))
        await awaitHealthKit()
        XCTAssertEqual(fake.savedNutrition.count, 1)
        let sample = try XCTUnwrap(fake.savedNutrition.first)
        XCTAssertEqual(sample.entryID, entry.id)
        XCTAssertEqual(sample.name, "Chicken breast")
        XCTAssertEqual(sample.date, entry.loggedAt)
        XCTAssertEqual(sample.calories, 330, accuracy: 0.001)
        XCTAssertEqual(sample.protein, 62, accuracy: 0.001)
        XCTAssertEqual(sample.fat, 7.2, accuracy: 0.001)
        XCTAssertNil(sample.fiber)
        XCTAssertEqual(entry.healthKitSampleIDs.count, 5)
        XCTAssertNotNil(entry.healthKitSyncedAt)
    }

    func test_editDeletesTheOldSamplesBeforeRewriting() async throws {
        let entry = try service.logEntry(food: try makeFood(), servings: 2, meal: .dinner, at: jstDate(2026, 9, 9, 19, 0))
        await awaitHealthKit()
        let firstIDs = entry.healthKitSampleIDs
        XCTAssertFalse(firstIDs.isEmpty)

        try service.updateEntry(entry, servings: 3, meal: .snack)
        XCTAssertTrue(entry.healthKitSampleIDs.isEmpty, "Old ids are dropped the moment the entry changes")
        XCTAssertNil(entry.healthKitSyncedAt)
        await awaitHealthKit()

        let deletion = try XCTUnwrap(fake.deletedNutrition.last)
        XCTAssertEqual(deletion.entryID, entry.id)
        XCTAssertEqual(deletion.sampleIDs, firstIDs)
        XCTAssertEqual(fake.savedNutrition.count, 2)
        XCTAssertEqual(fake.savedNutrition.last?.calories ?? 0, 495, accuracy: 0.001)
        XCTAssertEqual(entry.healthKitSampleIDs.count, 5)
        XCTAssertNotEqual(entry.healthKitSampleIDs, firstIDs)
        XCTAssertEqual(entry.mealSlot, .snack)
        XCTAssertEqual(entry.servings, 3)
    }

    func test_deleteRemovesTheEntryAndItsHealthKitSamples() async throws {
        let entry = try service.logEntry(food: try makeFood(), servings: 1, meal: .lunch, at: jstDate(2026, 9, 9, 12, 0))
        await awaitHealthKit()
        let ids = entry.healthKitSampleIDs
        let entryID = entry.id

        try service.deleteEntry(entry)
        await awaitHealthKit()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FoodEntry>()), 0)
        let deletion = try XCTUnwrap(fake.deletedNutrition.last)
        XCTAssertEqual(deletion.entryID, entryID)
        XCTAssertEqual(deletion.sampleIDs, ids)
    }

    func test_failedWriteKeepsTheEntryRetriesAndRecordsAFailure() async throws {
        fake.setNutritionSaveFails(true)
        let entry = try service.logEntry(food: try makeFood(), servings: 1, meal: .lunch, at: jstDate(2026, 9, 9, 12, 0))
        await awaitHealthKit()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FoodEntry>()), 1, "Local log never depends on Health")
        XCTAssertNil(entry.healthKitSyncedAt)
        XCTAssertTrue(entry.healthKitSampleIDs.isEmpty)
        XCTAssertEqual(fake.savedNutrition.count, NutritionService.maxHealthKitAttempts)
        let failures = try context.fetch(FetchDescriptor<HealthKitWriteFailure>())
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures.first?.retryCount, NutritionService.maxHealthKitAttempts)
        XCTAssertTrue(failures.first?.errorDescription.hasPrefix("Nutrition write") ?? false)
        XCTAssertEqual(failures.first?.totalEnergyKcal ?? 0, 165, accuracy: 0.001)
    }

    func test_withoutAHealthStoreLoggingStillWorksLocally() throws {
        let local = NutritionService(modelContext: context, calendar: calendar, healthKit: nil)
        let food = try local.createFood(name: "Rice", servingSize: 1, servingUnit: "cup",
                                        macros: MacroTotals(calories: 200, protein: 4, carbs: 45, fat: 0))
        try local.logEntry(food: food, servings: 1, meal: .dinner, at: jstDate(2026, 9, 9, 19, 0))
        XCTAssertEqual(local.entries(for: jstDate(2026, 9, 9, 19, 0)).count, 1)
        XCTAssertNil(local.lastHealthKitTask)
        XCTAssertEqual(local.nutritionAuthorizationStatus, .notDetermined)
    }

    func test_deniedOrUnansweredAuthorizationKeepsEntriesLocalWithoutNagging() async throws {
        fake.setNutritionStatus(.sharingDenied)
        let entry = try service.logEntry(food: try makeFood(), servings: 1, meal: .lunch, at: jstDate(2026, 9, 9, 12, 0))
        await awaitHealthKit()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FoodEntry>()), 1)
        XCTAssertTrue(fake.savedNutrition.isEmpty, "No write is attempted without sharing authorization")
        XCTAssertTrue(fake.deletedNutrition.isEmpty)
        XCTAssertNil(entry.healthKitSyncedAt)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<HealthKitWriteFailure>()), 0,
                       "A refusal is not a failure; it must not surface as a sync problem")
        try service.deleteEntry(entry)
        await awaitHealthKit()
        XCTAssertTrue(fake.deletedNutrition.isEmpty)
    }

    func test_authorizationIsRequestedOnceWhileUndetermined() async {
        fake.setNutritionStatus(.notDetermined)
        let first = await service.requestNutritionAuthorizationIfNeeded()
        XCTAssertEqual(first, .sharingAuthorized)
        XCTAssertEqual(fake.nutritionRequestCount, 1)
        let second = await service.requestNutritionAuthorizationIfNeeded()
        XCTAssertEqual(second, .sharingAuthorized)
        XCTAssertEqual(fake.nutritionRequestCount, 1, "Only the first open asks")
    }
}
