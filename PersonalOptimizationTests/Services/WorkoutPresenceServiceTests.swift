import XCTest
@testable import PersonalOptimization

@MainActor
final class WorkoutPresenceServiceTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        defaults = UserDefaults(suiteName: "WorkoutPresenceServiceTests")!
        defaults.removePersistentDomain(forName: "WorkoutPresenceServiceTests")
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: "WorkoutPresenceServiceTests")
        defaults = nil
        try await super.tearDown()
    }

    func testStartPersistsPresenceAndProducesCoachContext() {
        let service = WorkoutPresenceService(defaults: defaults)
        service.start(type: "basketball", at: Date())

        XCTAssertTrue(service.isActive)
        XCTAssertEqual(service.workoutType, "basketball")
        XCTAssertTrue(service.coachSummary.contains("Do not prescribe a second workout"))

        let restored = WorkoutPresenceService(defaults: defaults)
        XCTAssertTrue(restored.isActive)
        XCTAssertEqual(restored.workoutType, "basketball")
    }

    func testWatchEndEventClearsPresence() {
        let service = WorkoutPresenceService(defaults: defaults)
        service.start(type: "lift", at: Date())
        service.handle(WatchConnectivityEvent(kind: .workoutEnded, payload: ["type": "lift"]))

        XCTAssertFalse(service.isActive)
        XCTAssertNil(service.startedAt)
        XCTAssertEqual(service.coachSummary, "No live workout signal.")
    }

    func testStalePersistedWorkoutIsDiscarded() {
        defaults.set(true, forKey: "workoutPresence.active")
        defaults.set("run", forKey: "workoutPresence.type")
        defaults.set(Date().addingTimeInterval(-7 * 60 * 60), forKey: "workoutPresence.startedAt")

        XCTAssertFalse(WorkoutPresenceService(defaults: defaults).isActive)
    }
}
