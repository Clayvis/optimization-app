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
}
