import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class LiftServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var service: LiftService!

    private static let fixtureTemplates: LiftTemplatesFile = {
        let json = """
        {
          "version": 1,
          "templates": [
            {
              "name": "Lift A",
              "focus": "legs",
              "exercises": [
                { "name": "Back Squat", "orderIndex": 0, "targetSets": 4, "targetReps": 5 },
                { "name": "Bench Press", "orderIndex": 1, "targetSets": 4, "targetReps": 5 }
              ]
            },
            {
              "name": "Lift B",
              "focus": "variation",
              "exercises": [
                { "name": "Front Squat", "orderIndex": 0, "targetSets": 4, "targetReps": 5 }
              ]
            }
          ]
        }
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(LiftTemplatesFile.self, from: json)
    }()

    override func setUp() async throws {
        try await super.setUp()
        container = try InMemoryContainer.make()
        context = container.mainContext
        service = LiftService(modelContext: context, templatesFile: Self.fixtureTemplates)
    }

    override func tearDown() async throws {
        service = nil
        context = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: - Templates loader

    func test_loadTemplates_fromBundle_decodesBothTemplates() throws {
        let bundle = LiftServiceTests.resourceBundle()
        let file = try LiftTemplatesLoader.load(bundle: bundle)
        XCTAssertEqual(file.version, 1)
        XCTAssertEqual(file.templates.count, 2)
        XCTAssertEqual(file.templates.map(\.name), ["Lift A", "Lift B"])
        XCTAssertEqual(file.templates[0].exercises.count, 5)
        XCTAssertEqual(file.templates[1].exercises.count, 5)
    }

    func test_template_named_returnsMatch() throws {
        let template = try LiftTemplatesLoader.template(named: "Lift A", file: Self.fixtureTemplates)
        XCTAssertEqual(template.name, "Lift A")
        XCTAssertEqual(template.exercises.count, 2)
    }

    func test_template_named_throwsTemplateNotFound() {
        XCTAssertThrowsError(try LiftTemplatesLoader.template(named: "Lift Z", file: Self.fixtureTemplates)) { error in
            guard case LiftTemplatesError.templateNotFound("Lift Z") = error else {
                XCTFail("Expected templateNotFound, got \(error)")
                return
            }
        }
    }

    // MARK: - startSession

    func test_startSession_insertsSessionAndExercises() throws {
        let session = try service.startSession(templateName: "Lift A")
        XCTAssertEqual(session.template, "Lift A")
        XCTAssertEqual(session.exercises?.count, 2)
        let sorted = (session.exercises ?? []).sorted { $0.orderIndex < $1.orderIndex }
        XCTAssertEqual(sorted.first?.name, "Back Squat")
        XCTAssertEqual(sorted.last?.name, "Bench Press")
    }

    func test_startSession_unknownTemplate_throws() {
        XCTAssertThrowsError(try service.startSession(templateName: "Lift Z"))
    }

    // MARK: - logSet

    func test_logSet_appendsSetWithIncrementingOrderIndex() throws {
        let session = try service.startSession(templateName: "Lift A")
        let s1 = try service.logSet(in: session, exerciseName: "Back Squat", weightLbs: 225, reps: 5)
        let s2 = try service.logSet(in: session, exerciseName: "Back Squat", weightLbs: 245, reps: 3)
        XCTAssertEqual(s1.orderIndex, 0)
        XCTAssertEqual(s2.orderIndex, 1)

        let squat = (session.exercises ?? []).first { $0.name == "Back Squat" }
        XCTAssertEqual(squat?.sets?.count, 2)
    }

    func test_logSet_unknownExercise_throws() throws {
        let session = try service.startSession(templateName: "Lift A")
        XCTAssertThrowsError(try service.logSet(in: session, exerciseName: "Nonexistent", weightLbs: 100, reps: 5))
    }

    // MARK: - totalVolume

    func test_totalVolume_emptySession_isZero() throws {
        let session = try service.startSession(templateName: "Lift A")
        XCTAssertEqual(LiftService.totalVolume(session: session), 0)
    }

    func test_totalVolume_acrossExercisesAndSets() throws {
        let session = try service.startSession(templateName: "Lift A")
        try service.logSet(in: session, exerciseName: "Back Squat", weightLbs: 225, reps: 5)   // 1125
        try service.logSet(in: session, exerciseName: "Back Squat", weightLbs: 245, reps: 3)   // 735
        try service.logSet(in: session, exerciseName: "Bench Press", weightLbs: 185, reps: 5)  // 925
        try service.logSet(in: session, exerciseName: "Bench Press", weightLbs: 205, reps: 3)  // 615
        XCTAssertEqual(LiftService.totalVolume(session: session), 1125 + 735 + 925 + 615)
    }

    // MARK: - endSession

    func test_endSession_recordsVolumeAndDuration() async throws {
        let session = try service.startSession(templateName: "Lift A")
        try service.logSet(in: session, exerciseName: "Back Squat", weightLbs: 225, reps: 5)
        try service.endSession(session, durationMinutes: 75, avgHR: 130)

        XCTAssertEqual(session.totalVolumeLbs, 1125)
        XCTAssertEqual(session.durationMinutes, 75)
        XCTAssertEqual(session.avgHR, 130)
    }

    func test_endSession_persistsToHealthKit_whenWired() async throws {
        let fake = FakeHealthKitService()
        let serviceWithHK = LiftService(modelContext: context, templatesFile: Self.fixtureTemplates, healthKit: fake)
        let session = try serviceWithHK.startSession(templateName: "Lift A")
        try serviceWithHK.logSet(in: session, exerciseName: "Back Squat", weightLbs: 225, reps: 5)
        try serviceWithHK.endSession(session, durationMinutes: 75, estimatedCalories: 350)
        await SessionLifecycleService.shared.lastDispatchedTask?.value

        XCTAssertEqual(fake.savedWorkouts.count, 1)
        XCTAssertEqual(fake.savedWorkouts[0].0, .functionalStrengthTraining)
        XCTAssertEqual(fake.savedWorkouts[0].3, 350)
    }

    // MARK: - currentSession

    func test_currentSession_returnsActiveSession() throws {
        _ = try service.startSession(templateName: "Lift A")
        let active = service.currentSession(at: Date())
        XCTAssertEqual(active?.template, "Lift A")
    }

    func test_currentSession_returnsNilAfterEnd() async throws {
        let s = try service.startSession(templateName: "Lift A")
        try service.endSession(s, durationMinutes: 60)
        XCTAssertNil(service.currentSession(at: Date()))
    }

    // MARK: - Helpers

    static func resourceBundle() -> Bundle {
        if Bundle.main.url(forResource: "lift_templates", withExtension: "json") != nil {
            return Bundle.main
        }
        return Bundle(for: LiftServiceTests.self)
    }
}
