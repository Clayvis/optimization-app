import XCTest
@testable import PersonalOptimization

/// Exercises the closure-injectable `FastingLiveActivityController`.
/// xctest can't host ActivityKit's Activity<Attrs> runtime, so the
/// controller's `init(start:endAll:)` lets us replace those closures with
/// observers that record calls. The static facade keeps using
/// `shared` in production so call sites don't change.
@MainActor
final class FastingLiveActivityControllerTests: XCTestCase {

    private func makeWindow(durationHours: Int = 16) -> FastWindow {
        let start = Date()
        return FastWindow(
            start: start,
            end: start.addingTimeInterval(TimeInterval(durationHours * 3600)),
            label: "training"
        )
    }

    func test_startInstance_callsStartWithCorrectAttributesAndStaleDate() async throws {
        var capturedAttrs: FastingActivityAttributes?
        var capturedState: FastingActivityAttributes.State?
        var capturedStale: Date?

        let controller = FastingLiveActivityController(
            start: { attrs, state, stale in
                capturedAttrs = attrs
                capturedState = state
                capturedStale = stale
                return "fake-id-1"
            },
            endAll: { /* not called in this test */ }
        )

        let window = makeWindow()
        let id = await controller.startInstance(window: window)
        XCTAssertEqual(id, "fake-id-1")
        XCTAssertEqual(capturedAttrs?.windowLabel, "training")
        XCTAssertEqual(capturedAttrs?.startDate, window.start)
        XCTAssertEqual(capturedAttrs?.endDate, window.end)
        XCTAssertEqual(capturedState?.isFasting, true)
        XCTAssertEqual(capturedStale, window.end.addingTimeInterval(60))
        XCTAssertEqual(controller.trackedActivityCount, 1)
    }

    func test_startInstance_returnsNilWhenLiveStartReturnsNil() async throws {
        let controller = FastingLiveActivityController(
            start: { _, _, _ in nil },
            endAll: { }
        )
        let id = await controller.startInstance(window: makeWindow())
        XCTAssertNil(id)
        XCTAssertEqual(controller.trackedActivityCount, 0)
    }

    func test_startInstance_swallowsErrorAndReturnsNil() async {
        // Mirrors ActivityKit's behavior when activities are disabled or the
        // OS rejects the request — the controller logs and returns nil; the
        // caller's path is never blocked.
        let controller = FastingLiveActivityController(
            start: { _, _, _ in throw FakeActivityError.disabled },
            endAll: { }
        )
        let id = await controller.startInstance(window: makeWindow())
        XCTAssertNil(id)
        XCTAssertEqual(controller.trackedActivityCount, 0)
    }

    func test_endAllInstance_clearsTrackedIDs() async throws {
        var endCallCount = 0
        let controller = FastingLiveActivityController(
            start: { _, _, _ in "id-1" },
            endAll: { endCallCount += 1 }
        )
        _ = await controller.startInstance(window: makeWindow())
        XCTAssertEqual(controller.trackedActivityCount, 1)
        await controller.endAllInstance()
        XCTAssertEqual(endCallCount, 1)
        XCTAssertEqual(controller.trackedActivityCount, 0)
    }

    func test_endAllInstance_safeWhenNothingStarted() async {
        var endCallCount = 0
        let controller = FastingLiveActivityController(
            start: { _, _, _ in "x" },
            endAll: { endCallCount += 1 }
        )
        await controller.endAllInstance()
        // The live ActivityKit endAll is itself idempotent (iterates the
        // empty activities list), so the controller forwards even with no
        // tracked IDs.
        XCTAssertEqual(endCallCount, 1)
    }
}

private enum FakeActivityError: Error {
    case disabled
}
