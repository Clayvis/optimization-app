import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class ReleasedStoreMigrationTests: XCTestCase {
    func test_upgradeFromReleasedNutritionPreservesWorkoutGraphAndDefaults() throws {
        try verifyLegacyUpgrade(from: ReleasedNutritionSchema.self, hasNutrition: true)
    }

    func test_upgradeFromReleasedPreNutritionPreservesWorkoutGraphAndDefaults() throws {
        try verifyLegacyUpgrade(from: ReleasedPreNutritionSchema.self, hasNutrition: false)
    }

    private func verifyLegacyUpgrade(from source: any VersionedSchema.Type, hasNutrition: Bool) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        defer { SchemaMigrationTestHarness.cleanup(at: url) }
        let healthIDs = [UUID(), UUID()]
        do {
            let schema = Schema(versionedSchema: source)
            let container = try ModelContainer(for: schema,
                configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let session = ReleasedNutritionSchema.LiftSession(date: Date(), template: "Preserve me")
            let exercise = ReleasedNutritionSchema.LiftExercise(name: "Calf raise", orderIndex: 0, isCustom: true)
            let set = ReleasedNutritionSchema.LiftSet(weightLbs: 80, reps: 12, orderIndex: 0)
            set.exercise = exercise; exercise.sets = [set]
            exercise.session = session; session.exercises = [exercise]
            container.mainContext.insert(session)
            container.mainContext.insert(UserProfile(name: "Upgrade fixture"))
            if hasNutrition { seedNutrition(context: container.mainContext, healthIDs: healthIDs) }
            try container.mainContext.save()
        }
        let current = AppSchema.schema()
        do {
            let migrated = try ModelContainer(for: current, migrationPlan: AppMigrationPlan.self,
                configurations: [ModelConfiguration(schema: current, url: url, cloudKitDatabase: .none)])
            let context = migrated.mainContext
            XCTAssertEqual(try context.fetch(FetchDescriptor<UserProfile>()).first?.name, "Upgrade fixture")
            if hasNutrition { try verifyNutrition(context: context, healthIDs: healthIDs) }
            let session = try XCTUnwrap(context.fetch(FetchDescriptor<LiftSession>()).first)
            XCTAssertEqual(session.template, "Preserve me")
            let exercise = try XCTUnwrap(session.exercises?.first)
            XCTAssertEqual(exercise.name, "Calf raise")
            XCTAssertTrue(exercise.isCustom)
            XCTAssertEqual(exercise.session, session)
            XCTAssertEqual(exercise.progressionSets, 3)
            XCTAssertEqual(exercise.progressionLowerReps, 10)
            XCTAssertEqual(exercise.progressionUpperReps, 15)
            let set = try XCTUnwrap(exercise.sets?.first)
            XCTAssertEqual(set.exercise, exercise)
            XCTAssertEqual(set.weightLbs, 80)
            XCTAssertEqual(set.reps, 12)
            XCTAssertNil(set.repsInReserve)
            set.repsInReserve = 2
            exercise.progressionUpperReps = 20
            try context.save()
        }
        // A second launch must recognize the migrated current schema, too.
        let reopened = try ModelContainer(for: current, migrationPlan: AppMigrationPlan.self,
            configurations: [ModelConfiguration(schema: current, url: url, cloudKitDatabase: .none)])
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<LiftSet>()).first?.repsInReserve, 2)
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<LiftExercise>()).first?.progressionUpperReps, 20)
    }

    func test_alreadyReleasedInBodyStoreReopensWithoutLosingNewFields() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        defer { SchemaMigrationTestHarness.cleanup(at: url) }
        let healthIDs = [UUID(), UUID()]
        do {
            let schema = Schema(versionedSchema: ReleasedInBodySchema.self)
            let original = try ModelContainer(for: schema,
                configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let session = ReleasedInBodySchema.LiftSession(date: Date(), template: "Current workout")
            let exercise = ReleasedInBodySchema.LiftExercise(name: "Calf raise", orderIndex: 0)
            exercise.progressionSets = 4
            exercise.progressionLowerReps = 12
            exercise.progressionUpperReps = 20
            let set = ReleasedInBodySchema.LiftSet(weightLbs: 100, reps: 16, orderIndex: 0)
            set.repsInReserve = 1
            set.exercise = exercise; exercise.sets = [set]
            exercise.session = session; session.exercises = [exercise]
            original.mainContext.insert(session)
            var values = InBodyValues()
            values.weightLb = 200
            original.mainContext.insert(InBodyScan(values: values))
            seedNutrition(context: original.mainContext, healthIDs: healthIDs)
            try original.mainContext.save()
        }
        let schema = AppSchema.schema()
        let reopened = try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        let context = reopened.mainContext
        let exercise = try XCTUnwrap(context.fetch(FetchDescriptor<LiftExercise>()).first)
        XCTAssertEqual(exercise.progressionSets, 4)
        XCTAssertEqual(exercise.progressionLowerReps, 12)
        XCTAssertEqual(exercise.progressionUpperReps, 20)
        XCTAssertEqual(exercise.sets?.first?.repsInReserve, 1)
        XCTAssertEqual(exercise.session?.template, "Current workout")
        XCTAssertEqual(try context.fetch(FetchDescriptor<InBodyScan>()).first?.weightLb, 200)
        try verifyNutrition(context: context, healthIDs: healthIDs)
    }

    private func seedNutrition(context: ModelContext, healthIDs: [UUID]) {
        let food = FoodItem(name: "Preserved oats", calories: 150, protein: 5, carbs: 27, fat: 3)
        food.useCount = 8
        let entry = FoodEntry(date: .distantPast, loggedAt: .distantPast, meal: .breakfast, food: food, servings: 2)
        entry.healthKitSampleIDs = healthIDs
        entry.healthKitSyncedAt = .distantPast
        let meal = SavedMeal(name: "Preserved breakfast")
        let item = SavedMealItem(food: food, servings: 2, orderIndex: 0)
        item.meal = meal; meal.items = [item]
        context.insert(food)
        context.insert(entry)
        context.insert(meal)
        context.insert(NutritionTargets(effectiveFrom: .distantPast,
            values: NutritionTargetValues(calories: 2200, proteinGrams: 150, carbsGrams: 240, fatGrams: 70)))
    }

    private func verifyNutrition(context: ModelContext, healthIDs: [UUID]) throws {
        let food = try XCTUnwrap(context.fetch(FetchDescriptor<FoodItem>()).first)
        XCTAssertEqual(food.name, "Preserved oats")
        XCTAssertEqual(food.useCount, 8)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<FoodEntry>()).first)
        XCTAssertEqual(entry.foodID, food.id)
        XCTAssertEqual(entry.totals.calories, 300)
        XCTAssertEqual(entry.healthKitSampleIDs, healthIDs)
        XCTAssertEqual(entry.healthKitSyncedAt, .distantPast)
        let meal = try XCTUnwrap(context.fetch(FetchDescriptor<SavedMeal>()).first)
        XCTAssertEqual(meal.name, "Preserved breakfast")
        XCTAssertEqual(meal.items?.first?.meal, meal)
        XCTAssertEqual(meal.items?.first?.foodID, food.id)
        XCTAssertEqual(meal.totals.calories, 300)
        XCTAssertEqual(try context.fetch(FetchDescriptor<NutritionTargets>()).first?.calories, 2200)
    }

}
