import XCTest
import SwiftData
import HealthKit
@testable import PersonalOptimization

/// Covers automatic workout import (the "app realizes you worked out" fix).
/// Exercises the pure persistence + dedupe logic with synthetic ImportedWorkout
/// values, plus the HKWorkoutActivityType source mapping.
@MainActor
final class WorkoutImportServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private let jst = TimeZone(identifier: "Asia/Tokyo")!

    override func setUp() async throws {
        try await super.setUp()
        container = try InMemoryContainer.make()
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        try await super.tearDown()
    }

    private func calendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = jst
        return cal
    }

    private func service() -> WorkoutImportService {
        WorkoutImportService(modelContext: context, calendar: calendar())
    }

    private func sample(
        _ source: WorkoutEventSource = .lift,
        start: Date = Date(timeIntervalSince1970: 1_760_000_000)
    ) -> ImportedWorkout {
        ImportedWorkout(hkUUID: UUID(), source: source, start: start, end: start.addingTimeInterval(1800))
    }

    func test_import_createsWorkoutEventAndCompletionHistory() throws {
        let w = sample(.lift)
        XCTAssertEqual(try service().importWorkouts([w]), 1)

        let events = try context.fetch(FetchDescriptor<WorkoutEvent>())
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.hkWorkoutUUID, w.hkUUID)
        XCTAssertEqual(events.first?.completed, true)
        XCTAssertEqual(events.first?.source, WorkoutEventSource.lift.rawValue)

        let workoutHistory = try context.fetch(FetchDescriptor<CompletionHistory>())
            .filter { $0.domain == StreakDomain.workout.rawValue }
        XCTAssertEqual(workoutHistory.count, 1)
    }

    func test_import_dedupesAcrossCalls() throws {
        let w = sample()
        XCTAssertEqual(try service().importWorkouts([w]), 1)
        XCTAssertEqual(try service().importWorkouts([w]), 0, "Same HealthKit UUID must not import twice.")
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutEvent>()).count, 1)
    }

    func test_import_dedupesWithinBatch() throws {
        let w = sample()
        XCTAssertEqual(try service().importWorkouts([w, w, w]), 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutEvent>()).count, 1)
    }

    func test_import_skipsWhenLedgerAlreadyHasUUID() throws {
        let uuid = UUID()
        context.insert(WorkoutEvent(date: Date(), completed: true, source: .lift, hkWorkoutUUID: uuid))
        try context.save()

        let w = ImportedWorkout(hkUUID: uuid, source: .swim, start: Date(), end: Date().addingTimeInterval(600))
        XCTAssertEqual(try service().importWorkouts([w]), 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutEvent>()).count, 1)
    }

    func test_import_usesUserCalendarDayKey() throws {
        // A 23:30 JST workout keys to that JST day, not the device day.
        let cal = calendar()
        let start = cal.date(from: DateComponents(year: 2026, month: 5, day: 4, hour: 23, minute: 30))!
        let w = ImportedWorkout(hkUUID: UUID(), source: .custom, start: start, end: start.addingTimeInterval(1800))
        try service().importWorkouts([w])
        let event = try XCTUnwrap(try context.fetch(FetchDescriptor<WorkoutEvent>()).first)
        XCTAssertEqual(event.date, cal.startOfDay(for: start))
    }

    func test_sourceMapping() {
        XCTAssertEqual(WorkoutEventSource.from(.functionalStrengthTraining), .lift)
        XCTAssertEqual(WorkoutEventSource.from(.traditionalStrengthTraining), .lift)
        XCTAssertEqual(WorkoutEventSource.from(.basketball), .basketball)
        XCTAssertEqual(WorkoutEventSource.from(.swimming), .swim)
        XCTAssertEqual(WorkoutEventSource.from(.running), .custom)
        XCTAssertEqual(WorkoutEventSource.from(.yoga), .custom)
    }

    func test_ownPhoneExportsDoNotEarnDuplicateCredit() throws {
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        for bundle in [BuildConfig.bundlePrefix] {
            let workout = ImportedWorkout(hkUUID: UUID(), source: .custom, start: start,
                                          end: start.addingTimeInterval(600), sourceBundleIdentifier: bundle)
            XCTAssertEqual(try service().importWorkouts([workout]), 0)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutEvent>()), 0)
    }

    func test_watchWorkoutArrivingBeforeCloudKitStillEarnsCredit() throws {
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        let workout = ImportedWorkout(hkUUID: UUID(), source: .custom, start: start,
                                      end: start.addingTimeInterval(600),
                                      sourceBundleIdentifier: "\(BuildConfig.bundlePrefix).watchkitapp")
        XCTAssertEqual(try service().importWorkouts([workout]), 1)
    }

    func test_watchWorkoutWithMatchingLocalSessionIsNotCountedAgain() throws {
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        context.insert(CustomActivitySession(date: start, templateName: "Walking", durationMinutes: 10))
        context.insert(WorkoutEvent(date: calendar().startOfDay(for: start), completed: true, source: .custom))
        try context.save()
        let workout = ImportedWorkout(hkUUID: UUID(), source: .custom, start: start,
                                      end: start.addingTimeInterval(610),
                                      sourceBundleIdentifier: "\(BuildConfig.bundlePrefix).watchkitapp")
        XCTAssertEqual(try service().importWorkouts([workout]), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutEvent>()), 1)
    }

    func test_thirdPartyWorkoutStillEarnsCredit() throws {
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        let workout = ImportedWorkout(hkUUID: UUID(), source: .custom, start: start,
                                      end: start.addingTimeInterval(600), sourceBundleIdentifier: "com.example.workout")
        XCTAssertEqual(try service().importWorkouts([workout]), 1)
    }

    func test_zeroLengthAndReversedWorkoutsAreIgnored() throws {
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        for duration: TimeInterval in [0, -60] {
            let workout = ImportedWorkout(hkUUID: UUID(), source: .custom, start: start,
                                          end: start.addingTimeInterval(duration))
            XCTAssertEqual(try service().importWorkouts([workout]), 0)
        }
    }
}
