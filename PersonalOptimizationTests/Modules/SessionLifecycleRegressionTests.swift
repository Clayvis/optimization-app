import XCTest
import HealthKit
import SwiftData
@testable import PersonalOptimization

/// Regression tests for the M3.6 Block 1 fix: SwiftData is the authoritative source
/// for session state; HealthKit failures must not block session-end paths or crash.
@MainActor
final class SessionLifecycleRegressionTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        container = try InMemoryContainer.make()
        context = container.mainContext
        // The shared service is global state; clear any leftover dispatched task.
        SessionLifecycleService.shared.lastDispatchedTask = nil
    }

    override func tearDown() async throws {
        context = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: - HealthKit unavailable

    func test_endLift_withNilHealthKit_sessionMarkedCompleteNoCrash() throws {
        let templates = LiftServiceTests.fixtureTemplates
        let service = LiftService(modelContext: context, templatesFile: templates, healthKit: nil)
        let session = try service.startSession(templateName: "Lift A")
        try service.logSet(in: session, exerciseName: "Back Squat", weightLbs: 225, reps: 5)
        try service.endSession(session, durationMinutes: 60)
        XCTAssertEqual(session.durationMinutes, 60)
        XCTAssertGreaterThan(session.totalVolumeLbs, 0)
    }

    func test_endBasketball_withNilHealthKit_sessionEnded() throws {
        let service = BasketballService(modelContext: context, healthKit: nil)
        let start = Date()
        let session = try service.startSession(at: start)
        try service.endSession(session,
                               endTime: start.addingTimeInterval(3600),
                               achillesPostScore: 5,
                               hydrationOz: 100)
        XCTAssertNotEqual(session.startTime, session.endTime)
        XCTAssertEqual(session.achillesPostScore, 5)
    }

    func test_endSwim_withNilHealthKit_sessionEnded() throws {
        let service = SwimService(modelContext: context, healthKit: nil)
        let s = try service.startSession(at: Date(), poolLengthMeters: 25)
        try service.logLap(in: s, count: 20)
        try service.endSession(s, durationMinutes: 30)
        XCTAssertEqual(s.durationMinutes, 30)
        XCTAssertEqual(s.totalMeters, 500)
    }

    // MARK: - HealthKit failing

    func test_endLift_withFailingHealthKit_sessionStillCompletesAndFailureLogged() async throws {
        let failing = FailingHealthKitService()
        let templates = LiftServiceTests.fixtureTemplates
        let service = LiftService(modelContext: context, templatesFile: templates, healthKit: failing)
        let session = try service.startSession(templateName: "Lift A")
        try service.logSet(in: session, exerciseName: "Back Squat", weightLbs: 225, reps: 5)
        try service.endSession(session, durationMinutes: 60)
        await SessionLifecycleService.shared.lastDispatchedTask?.value

        XCTAssertEqual(session.durationMinutes, 60)
        let failures = SessionLifecycleService.shared.recentFailures(modelContext: context)
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures.first?.activityTypeRaw, UInt(HKWorkoutActivityType.functionalStrengthTraining.rawValue))
        XCTAssertEqual(failures.first?.retryCount, 3)
    }

    func test_endBasketball_withFailingHealthKit_sessionStillCompletesAndFailureLogged() async throws {
        let failing = FailingHealthKitService()
        let service = BasketballService(modelContext: context, healthKit: failing)
        let start = Date()
        let session = try service.startSession(at: start)
        try service.endSession(session,
                               endTime: start.addingTimeInterval(3600),
                               achillesPostScore: nil,
                               hydrationOz: 50)
        await SessionLifecycleService.shared.lastDispatchedTask?.value

        let failures = SessionLifecycleService.shared.recentFailures(modelContext: context)
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures.first?.activityTypeRaw, UInt(HKWorkoutActivityType.basketball.rawValue))
    }

    func test_endSwim_withFailingHealthKit_sessionStillCompletesAndFailureLogged() async throws {
        let failing = FailingHealthKitService()
        let service = SwimService(modelContext: context, healthKit: failing)
        let s = try service.startSession(at: Date(), poolLengthMeters: 25)
        try service.logLap(in: s, count: 32)
        try service.endSession(s, durationMinutes: 45)
        await SessionLifecycleService.shared.lastDispatchedTask?.value

        let failures = SessionLifecycleService.shared.recentFailures(modelContext: context)
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures.first?.activityTypeRaw, UInt(HKWorkoutActivityType.swimming.rawValue))
    }

    func test_endFastEarly_succeedsRegardlessOfHealthKit() throws {
        let profile = UserProfile()
        context.insert(profile)
        try context.save()

        let defaults = FastingDefaults(
            weeks_1_2: Phase1FastingDefaults(
                trainingDays: FastingWindowSpec(start: "22:00", end: "10:00"),
                trainingDayNumbers: [1, 3, 5],
                otherDays: FastingWindowSpec(start: "20:00", end: "10:00")
            ),
            weeks_3_plus: Phase2FastingDefaults(all: FastingWindowSpec(start: "22:00", end: "10:00"))
        )
        let jst = TimeZone(identifier: "Asia/Tokyo")!
        let service = FastingService(modelContext: context, timezone: jst, defaults: defaults)
        // Pick a moment inside the window: 23:00 weekday during phase 1.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = jst
        let inside = cal.date(from: DateComponents(year: 2026, month: 5, day: 7, hour: 23, minute: 0))!
        try service.logEarlyBreak(at: inside, reason: "social", profile: profile)

        let logs = try context.fetch(FetchDescriptor<DailyLog>())
        XCTAssertTrue(logs.contains { $0.fastBrokeEarly })
    }

    // MARK: - Failure record retry-count

    func test_healthKitWriteFailure_recordsThreeRetries() async throws {
        let failing = FailingHealthKitService()
        SessionLifecycleService.shared.dispatchHealthKitWorkout(
            activityType: .running,
            start: Date(),
            end: Date().addingTimeInterval(60),
            totalEnergyKcal: 50,
            totalDistanceMeters: 500,
            healthKit: failing,
            modelContainer: container
        )
        await SessionLifecycleService.shared.lastDispatchedTask?.value

        XCTAssertEqual(failing.callCount, 3)
        let failures = SessionLifecycleService.shared.recentFailures(modelContext: context)
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures.first?.retryCount, 3)
    }

    func test_diagnostics_recentFailures_returnsNewestFirst() throws {
        let now = Date()
        for offset in 0..<5 {
            let f = HealthKitWriteFailure(
                timestamp: now.addingTimeInterval(Double(offset)),
                activityTypeRaw: UInt(HKWorkoutActivityType.basketball.rawValue),
                startTime: now,
                endTime: now,
                totalEnergyKcal: nil,
                totalDistanceMeters: nil,
                errorDescription: "test \(offset)",
                retryCount: 3
            )
            context.insert(f)
        }
        try context.save()
        let recent = SessionLifecycleService.shared.recentFailures(modelContext: context)
        XCTAssertEqual(recent.count, 5)
        XCTAssertEqual(recent.first?.errorDescription, "test 4")
    }
}

/// Test double that always throws on saveWorkout. Tracks call count so tests can assert
/// the retry behavior.
final class FailingHealthKitService: HealthKitServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _callCount = 0
    var callCount: Int { lock.withLock { _callCount } }

    enum FailingError: Error { case simulated }

    func requestAuthorization() async throws -> Bool { false }
    func saveWorkout(activityType: HKWorkoutActivityType,
                     start: Date,
                     end: Date,
                     totalEnergyBurnedKcal: Double?,
                     totalDistanceMeters: Double?) async throws {
        lock.withLock { _callCount += 1 }
        throw FailingError.simulated
    }

    // M4.2: protocol surface expansion. All fetches return nil for this fake.
    func fetchLatestQuantity(_ identifier: HKQuantityTypeIdentifier,
                             unit: HKUnit,
                             on date: Date) async throws -> Double? { nil }
    func fetchSumQuantity(_ identifier: HKQuantityTypeIdentifier,
                          unit: HKUnit,
                          for date: Date) async throws -> Double? { nil }
    func fetchSleepHours(for date: Date) async throws -> Double? { nil }
    func fetchMindfulMinutes(for date: Date) async throws -> Double? { nil }
    func fetchWorkouts(in range: DateInterval) async throws -> [HKWorkout] { [] }
}
