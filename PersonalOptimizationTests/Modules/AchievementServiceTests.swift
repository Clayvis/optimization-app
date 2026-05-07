import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class AchievementServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var service: AchievementService!

    override func setUp() async throws {
        try await super.setUp()
        container = try InMemoryContainer.make()
        context = container.mainContext
        service = AchievementService(modelContext: context)
    }

    override func tearDown() async throws {
        service = nil
        context = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: - Registry sanity

    func test_registry_hasAtLeastTwentyAchievements() {
        XCTAssertGreaterThanOrEqual(AchievementRegistry.allAchievements.count, 20)
    }

    func test_registry_idsAreUnique() {
        let ids = AchievementRegistry.allAchievements.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Achievement identifiers must be unique")
    }

    func test_registry_groupsCoverAllCategories() {
        let groups = AchievementRegistry.groupedByCategory
        XCTAssertEqual(groups.count, AchievementCategory.allCases.count)
    }

    // MARK: - Evaluation

    func test_evaluate_emptyState_unlocksNothing() throws {
        let unlocked = try service.evaluate()
        XCTAssertTrue(unlocked.isEmpty)
    }

    func test_evaluate_singleLift_unlocksFirstLift() throws {
        let lift = LiftSession(date: Date(), template: "Lift A")
        context.insert(lift)
        try context.save()

        let unlocked = try service.evaluate()
        XCTAssertTrue(unlocked.contains { $0.identifier == "first_lift" })
    }

    func test_evaluate_isIdempotent() throws {
        let lift = LiftSession(date: Date(), template: "Lift A")
        context.insert(lift)
        try context.save()

        let firstRun = try service.evaluate()
        XCTAssertFalse(firstRun.isEmpty)
        let secondRun = try service.evaluate()
        XCTAssertTrue(secondRun.isEmpty, "Second evaluation must not re-unlock the same achievement")
    }

    func test_evaluate_tonnage25k_unlocksOnEnoughVolume() throws {
        for _ in 0..<3 {
            let lift = LiftSession(date: Date(), template: "Lift A")
            lift.totalVolumeLbs = 10_000
            context.insert(lift)
        }
        try context.save()
        let unlocked = try service.evaluate()
        XCTAssertTrue(unlocked.contains { $0.identifier == "tonnage_25k" })
    }

    func test_evaluate_belowThreshold_doesNotUnlock() throws {
        let lift = LiftSession(date: Date(), template: "Lift A")
        lift.totalVolumeLbs = 5_000
        context.insert(lift)
        try context.save()
        let unlocked = try service.evaluate()
        XCTAssertFalse(unlocked.contains { $0.identifier == "tonnage_25k" })
    }

    func test_unlockImperative_addsRow() throws {
        try service.unlockImperative("diagnostics_clean")
        let rows = try context.fetch(FetchDescriptor<Achievement>())
        XCTAssertTrue(rows.contains { $0.identifier == "diagnostics_clean" })
    }

    func test_unlockImperative_isIdempotent() throws {
        try service.unlockImperative("diagnostics_clean")
        try service.unlockImperative("diagnostics_clean")
        let rows = try context.fetch(FetchDescriptor<Achievement>())
        let dx = rows.filter { $0.identifier == "diagnostics_clean" }
        XCTAssertEqual(dx.count, 1)
    }

    func test_nextPendingCelebration_returnsUnshown() throws {
        let lift = LiftSession(date: Date(), template: "Lift A")
        context.insert(lift)
        try context.save()
        _ = try service.evaluate()

        let pending = service.nextPendingCelebration()
        XCTAssertNotNil(pending)
        service.markCelebrationShown(pending!)
        XCTAssertNil(service.nextPendingCelebration())
    }

    func test_unlockedByID_mapsAllUnlocked() throws {
        try service.unlockImperative("diagnostics_clean")
        let map = service.unlockedByID()
        XCTAssertNotNil(map["diagnostics_clean"])
    }
}
