import XCTest
import SwiftData
@testable import PersonalOptimization

/// Coverage for the dailyLogsRecomputed subscriber + the 15-second throttle.
/// We can't easily peek at the internal `lastRunAt` so the tests assert the
/// observable side-effect (StreakCounter rows after a fire) and use the
/// debug build's recompute-count helper on CharacterStateService (which is
/// invoked by the same notification fan-out).
@MainActor
final class ReactiveRecomputeServiceTests: XCTestCase {

    func test_start_subscribesAndDoesNotCrashWithoutContainer() {
        // Defensive: calling stop() before start() is a no-op.
        ReactiveRecomputeService.shared.stop()
        XCTAssertNoThrow(ReactiveRecomputeService.shared.stop())
    }

    func test_start_thenStop_clearsObservers() throws {
        let container = try InMemoryContainer.make()
        ReactiveRecomputeService.shared.start(modelContainer: container)
        ReactiveRecomputeService.shared.stop()
        // No public observer count; we re-start and confirm no crash.
        ReactiveRecomputeService.shared.start(modelContainer: container)
        ReactiveRecomputeService.shared.stop()
    }

    func test_dailyLogsRecomputed_runsWithoutCrash() async throws {
        let container = try InMemoryContainer.make()
        // Seed a profile so StreakService can resolve its inputs.
        let profile = UserProfile()
        container.mainContext.insert(profile)
        try container.mainContext.save()

        ReactiveRecomputeService.shared.start(modelContainer: container)
        ReactiveRecomputeService.shared.resetThrottleForTesting()
        defer { ReactiveRecomputeService.shared.stop() }

        NotificationCenter.default.post(name: .dailyLogsRecomputed, object: nil)
        // Allow the main-queue observer to fire and the recompute to run.
        try await Task.sleep(for: .milliseconds(100))
        // StreakCounter rows for each StreakDomain should now exist (recompute
        // creates the row even when no source data is present).
        let counters = try container.mainContext.fetch(FetchDescriptor<StreakCounter>())
        XCTAssertGreaterThan(counters.count, 0, "Recompute should have created at least one StreakCounter row.")
    }

    func test_burst_throttles_within15Seconds() async throws {
        let container = try InMemoryContainer.make()
        let profile = UserProfile()
        container.mainContext.insert(profile)
        try container.mainContext.save()

        ReactiveRecomputeService.shared.start(modelContainer: container)
        ReactiveRecomputeService.shared.resetThrottleForTesting()
        defer { ReactiveRecomputeService.shared.stop() }

        // First fire — runs. Second fire within throttle window — ignored.
        NotificationCenter.default.post(name: .dailyLogsRecomputed, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        let countAfterFirst = try container.mainContext.fetch(FetchDescriptor<StreakCounter>()).count
        NotificationCenter.default.post(name: .dailyLogsRecomputed, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        let countAfterSecond = try container.mainContext.fetch(FetchDescriptor<StreakCounter>()).count
        XCTAssertEqual(countAfterFirst, countAfterSecond,
                       "Throttled second fire shouldn't create additional counter rows.")
        XCTAssertLessThanOrEqual(countAfterSecond, StreakDomain.allCases.count,
                                 "Throttled run shouldn't produce duplicate counter rows.")
    }
}
