import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class ProfileServiceTests: XCTestCase {

    func test_currentOrCreate_createsWhenAbsent() throws {
        let container = try InMemoryContainer.make()
        let ctx = container.mainContext
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<UserProfile>()).isEmpty)

        let profile = ProfileService.currentOrCreate(modelContext: ctx)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<UserProfile>()).count, 1)
        XCTAssertEqual(profile.timezone, "Asia/Tokyo", "Default timezone seeds JST.")
    }

    func test_currentOrCreate_idempotentOnSecondCall() throws {
        let container = try InMemoryContainer.make()
        let ctx = container.mainContext
        let first = ProfileService.currentOrCreate(modelContext: ctx)
        let second = ProfileService.currentOrCreate(modelContext: ctx)
        XCTAssertTrue(first === second, "Second call must return the same instance.")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<UserProfile>()).count, 1)
    }

    func test_currentOrCreate_preservesExistingFields() throws {
        let container = try InMemoryContainer.make()
        let ctx = container.mainContext
        let profile = ProfileService.currentOrCreate(modelContext: ctx)
        profile.name = "Clay"
        profile.dailyTokenBudget = 25_000
        profile.onboardingCompleted = true
        try ctx.save()

        let again = ProfileService.currentOrCreate(modelContext: ctx)
        XCTAssertEqual(again.name, "Clay")
        XCTAssertEqual(again.dailyTokenBudget, 25_000)
        XCTAssertTrue(again.onboardingCompleted)
    }

    func test_currentOrCreate_defaultsAreSane() throws {
        let container = try InMemoryContainer.make()
        let profile = ProfileService.currentOrCreate(modelContext: container.mainContext)
        XCTAssertEqual(profile.timezone, "Asia/Tokyo")
        XCTAssertFalse(profile.travelModeFollowsDevice)
        XCTAssertEqual(profile.sleepWindowStartHHMM, "22:00")
        XCTAssertEqual(profile.sleepWindowEndHHMM, "07:00")
        XCTAssertEqual(profile.dailyTokenBudget, 50_000)
        XCTAssertEqual(profile.mascotVariant, "ninja_male")
        XCTAssertTrue(profile.mascotEnabled)
        XCTAssertFalse(profile.onboardingCompleted)
    }

    private func quickDraft() -> QuickProfileDraft {
        var draft = QuickProfileDraft()
        draft.name = "  Alex  "
        draft.heightMajor = "5"
        draft.heightMinor = "4"
        draft.weight = "145"
        draft.goal = "Get stronger"
        draft.weeklyWorkouts = 4
        draft.dailyMinutes = 20
        draft.mascotVariant = "ninja_female"
        return draft
    }

    func test_quickSetupStartsWithNoAssumedMeasurements() {
        let draft = QuickProfileDraft()
        XCTAssertNil(draft.heightInches)
        XCTAssertNil(draft.weightLbs)
        XCTAssertThrowsError(try draft.validateBody())
    }

    func test_quickSetupSavesProfileAndActualDailyTargetsTogether() throws {
        let container = try InMemoryContainer.make()
        let context = container.mainContext
        let profile = ProfileService.currentOrCreate(modelContext: context)
        let suite = "QuickProfileTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try ProfileService.completeQuickSetup(quickDraft(), profile: profile, modelContext: context, defaults: defaults)
        let saved = try ModelContext(container).fetch(FetchDescriptor<UserProfile>()).first!
        XCTAssertEqual(saved.name, "Alex")
        XCTAssertEqual(saved.heightInches, 64)
        XCTAssertEqual(saved.weightLbs, 145)
        XCTAssertEqual(saved.primaryGoal, "Get stronger")
        XCTAssertEqual(saved.weeklyTrainingTargetSessions, 4)
        XCTAssertEqual(saved.mascotVariant, "ninja_female")
        XCTAssertEqual(saved.timezone, TimeZone.current.identifier)
        XCTAssertTrue(saved.onboardingCompleted)
        XCTAssertEqual(saved.metadata("quickProfile.completed", as: Bool.self), true)
        XCTAssertEqual(defaults.integer(forKey: "dailyWorkout.goalMinutes"), 20)
        XCTAssertEqual(defaults.integer(forKey: "dailyWorkout.weeklyGoal"), 4)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutEvent>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduleBlock>()), 0)
    }

    func test_quickSetupConvertsMetricAndKeepsUnitSwitchValues() throws {
        var draft = quickDraft()
        draft.changeUnits(toMetric: true)
        XCTAssertEqual(draft.heightInches ?? 0, 64, accuracy: 0.01)
        XCTAssertEqual(draft.weightLbs ?? 0, 145, accuracy: 0.02)
        try draft.validateBody()
        draft.changeUnits(toMetric: false)
        XCTAssertEqual(draft.heightInches ?? 0, 64, accuracy: 0.01)
        XCTAssertEqual(draft.weightLbs ?? 0, 145, accuracy: 0.03)
        draft.usesMetric = true
        draft.heightMajor = "180"
        draft.weight = "80"
        XCTAssertEqual(draft.heightInches ?? 0, 70.866, accuracy: 0.001)
        XCTAssertEqual(draft.weightLbs ?? 0, 176.370, accuracy: 0.001)
        draft.heightMajor = "182.87"
        draft.changeUnits(toMetric: false)
        XCTAssertEqual(draft.heightMajor, "6")
        XCTAssertEqual(draft.heightMinor, "0", "Rounding carries into feet instead of producing 12 inches")
        XCTAssertEqual(draft.heightInches ?? 0, 72, accuracy: 0.01)
        try draft.validateBody()
    }

    func test_invalidQuickSetupCannotOverwriteOrFinishProfile() throws {
        let container = try InMemoryContainer.make()
        let context = container.mainContext
        let profile = ProfileService.currentOrCreate(modelContext: context)
        profile.name = "Original"
        try context.save()
        for value in ["", "nan", "inf", "-2", "100000000000000000000000"] {
            var draft = quickDraft()
            draft.weight = value
            XCTAssertThrowsError(try ProfileService.completeQuickSetup(draft, profile: profile, modelContext: context))
            XCTAssertFalse(profile.onboardingCompleted)
            XCTAssertEqual(profile.name, "Original")
            XCTAssertNil(profile.primaryGoal)
        }
        var draft = quickDraft()
        draft.heightMinor = "12"
        XCTAssertThrowsError(try draft.validateBody())
        draft = quickDraft()
        draft.weeklyWorkouts = 0
        XCTAssertThrowsError(try ProfileService.completeQuickSetup(draft, profile: profile, modelContext: context))
        XCTAssertFalse(profile.onboardingCompleted)
    }

    func test_repeatedQuickSetupPreservesReturningUsersSettings() throws {
        let container = try InMemoryContainer.make()
        let context = container.mainContext
        let profile = ProfileService.currentOrCreate(modelContext: context)
        profile.name = "Existing"
        profile.weightLbs = 170
        profile.primaryGoal = "My own goal"
        profile.onboardingCompleted = true
        try context.save()
        try ProfileService.completeQuickSetup(quickDraft(), profile: profile, modelContext: context)
        XCTAssertEqual(profile.name, "Existing")
        XCTAssertEqual(profile.weightLbs, 170)
        XCTAssertEqual(profile.primaryGoal, "My own goal")
        XCTAssertNil(profile.metadata("quickProfile.completed", as: Bool.self))
    }
}
