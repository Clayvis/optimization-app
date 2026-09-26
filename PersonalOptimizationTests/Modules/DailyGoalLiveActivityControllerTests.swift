import XCTest
import ActivityKit
@testable import PersonalOptimization

@MainActor
final class DailyGoalLiveActivityControllerTests: XCTestCase {

    private func jstCal() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        return c
    }

    func test_refresh_startsWhenStartIfNeededTrue() async {
        var startCalls = 0
        var capturedState: DailyGoalActivityAttributes.State?
        let controller = DailyGoalLiveActivityController(
            start: { _, state, _ in startCalls += 1; capturedState = state; return "id-1" },
            update: { _, _, _ in },
            end: { _ in },
            endAll: { },
            existing: { [] }
        )
        await controller.refreshInstance(completedDomains: 2, totalDomains: 4, streak: 5, startIfNeeded: true)
        XCTAssertEqual(startCalls, 1)
        XCTAssertEqual(capturedState?.completedDomains, 2)
        XCTAssertEqual(capturedState?.totalDomains, 4)
        XCTAssertEqual(capturedState?.streak, 5)
        XCTAssertTrue(controller.isRunning)
    }

    func test_refresh_doesNotStartWhenStartIfNeededFalse() async {
        var startCalls = 0
        let controller = DailyGoalLiveActivityController(
            start: { _, _, _ in startCalls += 1; return "x" },
            update: { _, _, _ in },
            end: { _ in },
            endAll: { },
            existing: { [] }
        )
        await controller.refreshInstance(completedDomains: 1, totalDomains: 4, streak: 0, startIfNeeded: false)
        XCTAssertEqual(startCalls, 0)
        XCTAssertFalse(controller.isRunning)
    }

    func test_refresh_updatesExistingActivity() async {
        var startCalls = 0
        var updateCalls = 0
        var registry: [(id: String, dayStart: Date)] = []
        let controller = DailyGoalLiveActivityController(
            start: { attrs, _, _ in startCalls += 1; registry = [("id-1", attrs.dayStart)]; return "id-1" },
            update: { _, _, _ in updateCalls += 1 },
            end: { _ in },
            endAll: { },
            existing: { registry }
        )
        await controller.refreshInstance(completedDomains: 1, totalDomains: 4, streak: 0, startIfNeeded: true)
        await controller.refreshInstance(completedDomains: 2, totalDomains: 4, streak: 0, startIfNeeded: true)
        XCTAssertEqual(startCalls, 1)
        XCTAssertEqual(updateCalls, 1)
    }

    func test_refresh_noopWhenNothingScheduled() async {
        var startCalls = 0
        let controller = DailyGoalLiveActivityController(
            start: { _, _, _ in startCalls += 1; return "x" },
            update: { _, _, _ in },
            end: { _ in },
            endAll: { },
            existing: { [] }
        )
        await controller.refreshInstance(completedDomains: 0, totalDomains: 0, streak: 0, startIfNeeded: true)
        XCTAssertEqual(startCalls, 0)
    }

    func test_newDay_endsPriorAndRestarts() async {
        var startCalls = 0
        var endAllCalls = 0
        let controller = DailyGoalLiveActivityController(
            start: { _, _, _ in startCalls += 1; return "id-\(startCalls)" },
            update: { _, _, _ in },
            end: { _ in },
            endAll: { endAllCalls += 1 },
            existing: { [] }
        )
        let cal = jstCal()
        let day1 = cal.date(from: DateComponents(year: 2026, month: 5, day: 6, hour: 10))!
        let day2 = cal.date(from: DateComponents(year: 2026, month: 5, day: 7, hour: 10))!
        await controller.refreshInstance(completedDomains: 1, totalDomains: 4, streak: 1, startIfNeeded: true, asOf: day1, calendar: cal)
        await controller.refreshInstance(completedDomains: 1, totalDomains: 4, streak: 2, startIfNeeded: true, asOf: day2, calendar: cal)
        XCTAssertEqual(startCalls, 2, "A new day starts a fresh activity.")
        XCTAssertEqual(endAllCalls, 1, "The prior day's activity is ended first.")
    }

    func test_endAll_clearsRunningState() async {
        let controller = DailyGoalLiveActivityController(
            start: { _, _, _ in "id" },
            update: { _, _, _ in },
            end: { _ in },
            endAll: { },
            existing: { [] }
        )
        await controller.refreshInstance(completedDomains: 1, totalDomains: 4, streak: 0, startIfNeeded: true)
        XCTAssertTrue(controller.isRunning)
        await controller.endAllInstance()
        XCTAssertFalse(controller.isRunning)
    }

    // MARK: - Registry reconciliation (post-restart safety)

    func test_reconcile_adoptsExistingTodayActivity_insteadOfStartingDuplicate() async {
        var startCalls = 0
        let cal = jstCal()
        let today = cal.date(from: DateComponents(year: 2026, month: 5, day: 6, hour: 10))!
        let day = cal.startOfDay(for: today)
        // Fresh controller (no in-memory handle) but iOS still has today's activity.
        let controller = DailyGoalLiveActivityController(
            start: { _, _, _ in startCalls += 1; return "new" },
            update: { _, _, _ in },
            end: { _ in },
            endAll: { },
            existing: { [(id: "existing-today", dayStart: day)] }
        )
        await controller.refreshInstance(completedDomains: 1, totalDomains: 4, streak: 1, startIfNeeded: true, asOf: today, calendar: cal)
        XCTAssertEqual(startCalls, 0, "Adopts the existing activity rather than starting a duplicate.")
        XCTAssertTrue(controller.isRunning)
    }

    func test_reconcile_endsPriorDayStray_onPassivePath() async {
        var ended: [String] = []
        let cal = jstCal()
        let today = cal.date(from: DateComponents(year: 2026, month: 5, day: 7, hour: 10))!
        let yesterday = cal.startOfDay(for: cal.date(byAdding: .day, value: -1, to: today)!)
        let controller = DailyGoalLiveActivityController(
            start: { _, _, _ in "new" },
            update: { _, _, _ in },
            end: { id in ended.append(id) },
            endAll: { },
            existing: { [(id: "stray-yesterday", dayStart: yesterday)] }
        )
        // Passive app-open (startIfNeeded false) must still clean up the stray.
        await controller.refreshInstance(completedDomains: 1, totalDomains: 4, streak: 1, startIfNeeded: false, asOf: today, calendar: cal)
        XCTAssertEqual(ended, ["stray-yesterday"])
        XCTAssertFalse(controller.isRunning)
    }

    func test_update_threadsStaleDate() async {
        var capturedStale: Date?
        var registry: [(id: String, dayStart: Date)] = []
        let controller = DailyGoalLiveActivityController(
            start: { attrs, _, _ in registry = [("id", attrs.dayStart)]; return "id" },
            update: { _, _, stale in capturedStale = stale },
            end: { _ in },
            endAll: { },
            existing: { registry }
        )
        await controller.refreshInstance(completedDomains: 1, totalDomains: 4, streak: 0, startIfNeeded: true)
        await controller.refreshInstance(completedDomains: 2, totalDomains: 4, streak: 0, startIfNeeded: true)
        XCTAssertNotNil(capturedStale, "Updates preserve the freshness deadline.")
    }

    func test_expiredActivityIsNotUpdatedAndRestartsOnlyInForeground() async {
        var starts = 0
        var updates = 0
        let controller = DailyGoalLiveActivityController(
            start: { _, _, _ in starts += 1; return "id-\(starts)" },
            update: { _, _, _ in updates += 1 }, end: { _ in }, endAll: {}, existing: { [] })
        await controller.refreshInstance(completedDomains: 1, totalDomains: 4, streak: 0, startIfNeeded: true)
        // The OS registry is now empty, simulating dismissal or expiration.
        await controller.refreshInstance(completedDomains: 2, totalDomains: 4, streak: 0, startIfNeeded: false)
        XCTAssertFalse(controller.isRunning)
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(updates, 0)
        await controller.refreshInstance(completedDomains: 2, totalDomains: 4, streak: 0, startIfNeeded: true)
        XCTAssertTrue(controller.isRunning)
        XCTAssertEqual(starts, 2)
    }

    func test_state_progressAndComplete() {
        let partial = DailyGoalActivityAttributes.State(completedDomains: 1, totalDomains: 4, streak: 0)
        XCTAssertEqual(partial.progress, 0.25, accuracy: 0.0001)
        XCTAssertFalse(partial.isComplete)
        let done = DailyGoalActivityAttributes.State(completedDomains: 4, totalDomains: 4, streak: 9)
        XCTAssertTrue(done.isComplete)
    }
    func test_overlappingRefreshesStartOnlyOneActivity() async {
        var starts = 0
        var updates = 0
        var registry: [(id: String, dayStart: Date)] = []
        let controller = DailyGoalLiveActivityController(
            start: { attrs, _, _ in
                // Suspend like a real ActivityKit round trip. Without the serial
                // queue a second refresh would also see "no activity" and start one.
                await Task.yield()
                starts += 1
                registry = [("id-\(starts)", attrs.dayStart)]
                return "id-\(starts)"
            },
            update: { _, _, _ in updates += 1 }, end: { _ in }, endAll: {}, existing: { registry })
        await withTaskGroup(of: Void.self) { group in
            for done in 1...3 {
                group.addTask {
                    await controller.refreshInstance(completedDomains: done, totalDomains: 4, streak: 0, startIfNeeded: true)
                }
            }
        }
        XCTAssertEqual(starts, 1, "Launch, foreground and log refreshes arriving together start one activity.")
        XCTAssertEqual(updates, 2)
    }

    func test_freshnessDeadlineIsEarliestOfHourTransitionAndMidnight() {
        let cal = jstCal()
        let at = cal.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 15, minute: 40))!
        let transition = cal.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 16))!
        let hourLater = cal.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 16, minute: 40))!
        XCTAssertEqual(DailyGoalLiveActivityController.freshnessDeadline(asOf: at, freshUntil: transition, calendar: cal), transition)
        XCTAssertEqual(DailyGoalLiveActivityController.freshnessDeadline(asOf: at, freshUntil: nil, calendar: cal), hourLater)
        XCTAssertEqual(DailyGoalLiveActivityController.freshnessDeadline(asOf: at, freshUntil: at.addingTimeInterval(-60), calendar: cal),
                       hourLater, "A transition already past never makes content stale on arrival.")
        let late = cal.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 23, minute: 30))!
        XCTAssertEqual(DailyGoalLiveActivityController.freshnessDeadline(asOf: late, freshUntil: nil, calendar: cal),
                       cal.date(from: DateComponents(year: 2026, month: 9, day: 27))!)
    }

    func test_endedAndDismissedActivitiesReleaseTodaysSlot() {
        XCTAssertTrue(DailyGoalLiveActivityController.holdsSlot(.active))
        XCTAssertTrue(DailyGoalLiveActivityController.holdsSlot(.stale))
        XCTAssertFalse(DailyGoalLiveActivityController.holdsSlot(.ended))
        XCTAssertFalse(DailyGoalLiveActivityController.holdsSlot(.dismissed))
    }

    func test_scheduleTransitionShortensTheStaleDate() async {
        let cal = jstCal()
        let at = cal.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 15, minute: 40))!
        let transition = cal.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 16))!
        var stale: Date?
        let controller = DailyGoalLiveActivityController(
            start: { _, _, deadline in stale = deadline; return "status" },
            update: { _, _, _ in }, end: { _ in }, endAll: {}, existing: { [] })
        await controller.refreshInstance(completedDomains: 1, totalDomains: 4, streak: 0, startIfNeeded: true,
                                         statusMessage: "Next: Guitar at 16:00", freshUntil: transition,
                                         asOf: at, calendar: cal)
        XCTAssertEqual(stale, transition)
    }

    func test_liveStatusCarriesMessageAndFreshnessDeadline() async throws {
        let now = Date()
        var state: DailyGoalActivityAttributes.State?
        var stale: Date?
        let controller = DailyGoalLiveActivityController(
            start: { _, value, deadline in state = value; stale = deadline; return "status" },
            update: { _, _, _ in }, end: { _ in }, endAll: {}, existing: { [] })
        await controller.refreshInstance(completedDomains: 1, totalDomains: 4, streak: 2,
                                         startIfNeeded: true, statusMessage: "Japanese 10/30 min",
                                         asOf: now, calendar: jstCal())
        XCTAssertEqual(state?.statusMessage, "Japanese 10/30 min")
        XCTAssertEqual(state?.updatedAt, now)
        XCTAssertLessThanOrEqual(try XCTUnwrap(stale).timeIntervalSince(now), 3600)
    }

}
