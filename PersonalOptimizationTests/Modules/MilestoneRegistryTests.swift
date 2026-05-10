import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class MilestoneRegistryTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var service: MilestoneService!

    override func setUp() async throws {
        try await super.setUp()
        container = try InMemoryContainer.make()
        context = container.mainContext
        service = MilestoneService(modelContext: context)
    }

    override func tearDown() async throws {
        service = nil
        context = nil
        container = nil
        try await super.tearDown()
    }

    func test_registry_hasAtLeastTwelveMilestones() {
        XCTAssertGreaterThanOrEqual(MilestoneRegistry.allMilestones.count, 12)
    }

    func test_registry_idsAreUnique() {
        let ids = MilestoneRegistry.allMilestones.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Milestone identifiers must be unique")
    }

    func test_evaluate_emptyState_unlocksNothing() throws {
        let unlocked = try service.evaluate()
        XCTAssertTrue(unlocked.isEmpty)
    }

    func test_evaluate_streakOf7_unlocksFirstWeek() throws {
        let counter = StreakCounter(domain: .workout)
        counter.currentStreak = 7
        context.insert(counter)
        try context.save()

        let unlocked = try service.evaluate()
        XCTAssertTrue(unlocked.contains { $0.identifier == "first_week" })
    }

    func test_evaluate_isIdempotent() throws {
        let counter = StreakCounter(domain: .workout)
        counter.currentStreak = 30
        context.insert(counter)
        try context.save()

        let firstRun = try service.evaluate()
        XCTAssertFalse(firstRun.isEmpty)
        let secondRun = try service.evaluate()
        XCTAssertTrue(secondRun.isEmpty, "Second evaluation should not re-unlock")
    }

    func test_volumeMilestone_unlocksOnLifts() throws {
        for _ in 0..<6 {
            let lift = LiftSession(date: Date(), template: "Lift A")
            lift.totalVolumeLbs = 9_000
            context.insert(lift)
        }
        try context.save()

        let unlocked = try service.evaluate()
        XCTAssertTrue(unlocked.contains { $0.identifier == "tonnage_50k" })
    }

    func test_nextPendingCelebration_returnsUnshown() throws {
        let counter = StreakCounter(domain: .workout)
        counter.currentStreak = 7
        context.insert(counter)
        try context.save()
        _ = try service.evaluate()

        let pending = service.nextPendingCelebration()
        XCTAssertNotNil(pending)
        service.markCelebrationShown(pending!)
        XCTAssertNil(service.nextPendingCelebration())
    }
}
