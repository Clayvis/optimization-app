import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class CustomActivityServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var service: CustomActivityService!

    override func setUp() async throws {
        try await super.setUp()
        container = try InMemoryContainer.make()
        context = container.mainContext
        service = CustomActivityService(modelContext: context)
    }

    override func tearDown() async throws {
        service = nil
        context = nil
        container = nil
        try await super.tearDown()
    }

    func test_addTemplate_persistsRow() throws {
        _ = try service.addTemplate(name: "Running", systemImageName: "figure.run", defaultDurationMinutes: 30, trackDistance: true)
        XCTAssertEqual(service.templates().count, 1)
        XCTAssertEqual(service.templates().first?.name, "Running")
        XCTAssertTrue(service.templates().first?.trackDistance ?? false)
    }

    func test_archiveTemplate_hidesFromTemplatesList() throws {
        let t = try service.addTemplate(name: "Yoga")
        XCTAssertEqual(service.templates().count, 1)
        try service.archiveTemplate(t)
        XCTAssertEqual(service.templates().count, 0)
    }

    func test_seedDefaultsIfNeeded_onlyRunsWhenEmpty() throws {
        try service.seedDefaultsIfNeeded()
        let firstRun = service.templates().count
        XCTAssertEqual(firstRun, 6, "Starter set should ship six templates")
        try service.seedDefaultsIfNeeded()
        XCTAssertEqual(service.templates().count, firstRun, "Second run is a no-op")
    }

    func test_endSession_writesWorkoutEvent_andCompletionHistory() throws {
        let t = try service.addTemplate(name: "HIIT")
        let s = try service.startSession(for: t)
        try service.endSession(s, durationMinutes: 25, intensity: "hard")

        let events = try context.fetch(FetchDescriptor<WorkoutEvent>())
        XCTAssertTrue(events.contains { $0.completed && $0.source == WorkoutEventSource.custom.rawValue },
                      "Custom activity end should write a WorkoutEvent")

        let history = try context.fetch(FetchDescriptor<CompletionHistory>())
        XCTAssertTrue(history.contains { $0.domain == StreakDomain.workout.rawValue })
    }

    func test_currentSession_returnsRowMatchingTemplateAndDay() throws {
        let t = try service.addTemplate(name: "Walking")
        _ = try service.startSession(for: t)
        XCTAssertNotNil(service.currentSession(for: t))
        // After ending, no longer current.
        let s = try XCTUnwrap(service.currentSession(for: t))
        try service.endSession(s, durationMinutes: 30)
        XCTAssertNil(service.currentSession(for: t))
    }
}
