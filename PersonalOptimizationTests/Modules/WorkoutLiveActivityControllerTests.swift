import XCTest
@testable import PersonalOptimization

/// Mirror of `FastingLiveActivityControllerTests` for the workout
/// controller. Same closure-injection pattern, exercised with stubbed
/// start/update/endAll closures so ActivityKit doesn't need to be live.
@MainActor
final class WorkoutLiveActivityControllerTests: XCTestCase {

    func test_startInstance_callsStartWithCorrectAttributesAndStaleDate() async throws {
        var capturedAttrs: WorkoutActivityAttributes?
        var capturedState: WorkoutActivityAttributes.State?
        var capturedStale: Date?

        let controller = WorkoutLiveActivityController(
            start: { attrs, state, stale in
                capturedAttrs = attrs
                capturedState = state
                capturedStale = stale
                return "fake-workout-1"
            },
            update: { _, _ in },
            endAll: { }
        )

        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let id = await controller.startInstance(workoutType: "Lift A", startDate: start)
        XCTAssertEqual(id, "fake-workout-1")
        XCTAssertEqual(capturedAttrs?.workoutType, "Lift A")
        XCTAssertEqual(capturedAttrs?.startDate, start)
        XCTAssertEqual(capturedState?.elapsedSeconds, 0)
        XCTAssertEqual(capturedState?.primaryMetric, "—")
        XCTAssertEqual(capturedStale, start.addingTimeInterval(6 * 3600))
        XCTAssertEqual(controller.trackedActivityCount, 1)
    }

    func test_startInstance_returnsNilWhenLiveStartReturnsNil() async throws {
        let controller = WorkoutLiveActivityController(
            start: { _, _, _ in nil },
            update: { _, _ in },
            endAll: { }
        )
        let id = await controller.startInstance(workoutType: "Basketball")
        XCTAssertNil(id)
        XCTAssertEqual(controller.trackedActivityCount, 0)
    }

    func test_startInstance_swallowsErrorAndReturnsNil() async {
        let controller = WorkoutLiveActivityController(
            start: { _, _, _ in throw FakeError.activitiesDisabled },
            update: { _, _ in },
            endAll: { }
        )
        let id = await controller.startInstance(workoutType: "Lift", startDate: Date())
        XCTAssertNil(id)
        XCTAssertEqual(controller.trackedActivityCount, 0)
    }

    func test_updateInstance_callsUpdateWithCurrentValues() async {
        var capturedElapsed: Int?
        var capturedMetric: String?
        let controller = WorkoutLiveActivityController(
            start: { _, _, _ in "id" },
            update: { elapsed, metric in
                capturedElapsed = elapsed
                capturedMetric = metric
            },
            endAll: { }
        )
        await controller.updateInstance(elapsedSeconds: 305, primaryMetric: "12 reps")
        XCTAssertEqual(capturedElapsed, 305)
        XCTAssertEqual(capturedMetric, "12 reps")
    }

    func test_endAllInstance_clearsTrackedIDs() async throws {
        var endCallCount = 0
        let controller = WorkoutLiveActivityController(
            start: { _, _, _ in "id-1" },
            update: { _, _ in },
            endAll: { endCallCount += 1 }
        )
        _ = await controller.startInstance(workoutType: "Swim")
        await controller.endAllInstance()
        XCTAssertEqual(endCallCount, 1)
        XCTAssertEqual(controller.trackedActivityCount, 0)
    }
}

private enum FakeError: Error {
    case activitiesDisabled
}
