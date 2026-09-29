import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class LiftServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var service: LiftService!

    static let fixtureTemplates: LiftTemplatesFile = {
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

    func test_sessionUsesTemplateTargetsForProgressionAndFirstSet() throws {
        let session = try service.startSession(templateName: "Lift A")
        let exercise = try XCTUnwrap(session.exercises?.first { $0.name == "Back Squat" })
        XCTAssertEqual(exercise.progressionSets, 4)
        XCTAssertEqual(exercise.progressionLowerReps, 5)
        XCTAssertEqual(exercise.progressionUpperReps, 5)
        let draft = try service.suggestedSet(for: exercise)
        XCTAssertEqual(draft.reps, 5)
        XCTAssertEqual(draft.weightLbs, 0, "No ungrounded default load")
        XCTAssertNil(draft.repsInReserve)
        XCTAssertEqual(exercise.sets?.count, 0)
    }

    func test_prefillUsesHistoryThenCurrentSetWithoutLoggingAnything() throws {
        let old = try service.startSession(templateName: "Lift A", at: Date(timeIntervalSince1970: 100))
        let previous = try XCTUnwrap(old.exercises?.first { $0.name == "Back Squat" })
        try service.logSet(in: old, exercise: previous, weightLbs: 82.5, reps: 7, restSeconds: 90, repsInReserve: 2)
        old.durationMinutes = 30
        try context.save()
        let current = try service.startSession(templateName: "Lift A")
        let exercise = try XCTUnwrap(current.exercises?.first { $0.name == "Back Squat" })
        let history = try service.suggestedSet(for: exercise)
        XCTAssertEqual(history.weightLbs, 82.5)
        XCTAssertEqual(history.reps, 7)
        XCTAssertEqual(history.repsInReserve, 2)
        XCTAssertEqual(exercise.sets?.count, 0)
        try service.logSet(in: current, exercise: exercise, weightLbs: 85, reps: 6)
        XCTAssertEqual(try service.suggestedSet(for: exercise).weightLbs, 85)
    }

    func test_duplicateExerciseNamesLogToExactExercise() throws {
        let session = try service.startSession(templateName: "Lift A")
        // Relationship arrays are unordered, so hold the template's own
        // exercise by identity rather than assuming it is `first`.
        let original = try XCTUnwrap(session.exercises?.first { $0.name == "Back Squat" && !$0.isCustom })
        let extra = try service.addCustomExercise(in: session, name: "Back Squat")
        XCTAssertFalse(original === extra)
        let set = try service.logSet(in: session, exercise: extra, weightLbs: 50, reps: 10)
        XCTAssertTrue(set.exercise === extra)
        XCTAssertEqual(extra.sets?.count, 1)
        XCTAssertEqual(original.sets?.count, 0, "Logging to the added duplicate leaves the template's Back Squat untouched")
        XCTAssertThrowsError(try service.logSet(in: session, exerciseName: "Back Squat", weightLbs: 50, reps: 10))
    }

    func test_invalidSetsAndEditsLeaveOriginalDataIntact() throws {
        let session = try service.startSession(templateName: "Lift A")
        let exercise = try XCTUnwrap(session.exercises?.first)
        let set = try service.logSet(in: session, exercise: exercise, weightLbs: 82.5, reps: 8, repsInReserve: 2)
        for weight in [Double.nan, .infinity, -1] {
            XCTAssertThrowsError(try service.logSet(in: session, exercise: exercise, weightLbs: weight, reps: 5))
        }
        XCTAssertThrowsError(try service.logSet(in: session, exercise: exercise, weightLbs: 50, reps: 0))
        XCTAssertThrowsError(try service.updateSet(set, in: session, weightLbs: 100, reps: 5,
                                                 restSeconds: nil, repsInReserve: 11))
        XCTAssertEqual(set.weightLbs, 82.5)
        XCTAssertEqual(set.reps, 8)
        XCTAssertEqual(exercise.sets?.count, 1)
        try service.updateSet(set, in: session, weightLbs: 87.5, reps: 9, restSeconds: 60, repsInReserve: 1)
        XCTAssertEqual(set.weightLbs, 87.5)
        XCTAssertEqual(LiftService.totalVolume(session: session), 787.5)
        XCTAssertEqual(exercise.sets?.count, 1)
    }

    func test_reviewThenStartLinksExactSuggestionAndFinishIsIdempotent() throws {
        let prescription = PrescribedWorkout(generatedAt: Date(), forDate: Date(), workoutType: .liftA,
            template: #"{"exercises":[{"name":"Seated calf raise","sets":3,"reps":12,"weightLbs":82.5,"restSec":90,"rir":2}]}"#)
        context.insert(prescription)
        try context.save()
        let plan = try SuggestedLiftPlan.read(prescription)
        let template = plan.template(title: "Calf focus", rationale: "A reviewed plan")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LiftSession>()), 0, "Review is not a workout")
        XCTAssertEqual(prescription.status, .suggested)
        let session = try service.startSession(template: template, prescription: prescription)
        XCTAssertNotNil(session.sessionID)
        XCTAssertEqual(session.sessionID, prescription.sessionUUID)
        XCTAssertEqual(prescription.status, .accepted)
        let exercise = try XCTUnwrap(session.exercises?.first)
        XCTAssertEqual(exercise.name, "Seated calf raise")
        XCTAssertEqual(exercise.progressionSets, 3)
        XCTAssertEqual(exercise.progressionUpperReps, 12)
        XCTAssertEqual(exercise.sets?.count, 0)
        let draft = try service.suggestedSet(for: exercise, target: template.exercises.first)
        XCTAssertEqual(draft.weightLbs, 82.5)
        XCTAssertEqual(draft.restSeconds, 90)
        XCTAssertNil(draft.repsInReserve, "A target RIR is not measured effort")
        let resumed = try service.startSession(template: template, prescription: prescription)
        XCTAssertTrue(resumed === session)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LiftSession>()), 1)
        try service.logSet(in: session, exercise: exercise, weightLbs: 80, reps: 12)
        try service.endSession(session, durationMinutes: 20)
        try service.endSession(session, durationMinutes: 20)
        XCTAssertEqual(prescription.status, .completed)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutEvent>()), 1)
        XCTAssertThrowsError(try service.logSet(in: session, exercise: exercise, weightLbs: 80, reps: 12))
    }

    func test_missingLinkedSessionDoesNotCreateDuplicateWorkout() throws {
        let prescription = PrescribedWorkout(generatedAt: Date(), forDate: Date(), workoutType: .liftA)
        prescription.sessionUUID = UUID()
        context.insert(prescription)
        let plan = try LiftTemplatesLoader.template(named: "Lift A", file: Self.fixtureTemplates)
        XCTAssertThrowsError(try service.startSession(template: plan, prescription: prescription))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LiftSession>()), 0)
    }

    func test_invalidSuggestionCannotBecomeWorkout() throws {
        for payload in ["not json", #"{"exercises":[]}"#,
                        #"{"exercises":[{"name":"Calf raise","sets":0,"reps":12}]}"#,
                        #"{"exercises":[{"name":"Calf raise","sets":3,"reps":12,"weightLbs":-10}]}"#] {
            let prescription = PrescribedWorkout(generatedAt: Date(), forDate: Date(), workoutType: .liftA, template: payload)
            XCTAssertThrowsError(try SuggestedLiftPlan.read(prescription))
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LiftSession>()), 0)
    }

    func test_backupPreservesSuggestionSessionIdentity() throws {
        let prescription = PrescribedWorkout(generatedAt: Date(), forDate: Date(), workoutType: .liftA)
        context.insert(prescription)
        let plan = try LiftTemplatesLoader.template(named: "Lift A", file: Self.fixtureTemplates)
        let session = try service.startSession(template: plan, prescription: prescription)
        let data = try JSONExportService.export(modelContext: context)
        let destination = try InMemoryContainer.make()
        try JSONImportService.restore(data: data, modelContext: destination.mainContext)
        let restored = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<LiftSession>()).first)
        let restoredPlan = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<PrescribedWorkout>()).first)
        XCTAssertEqual(restored.sessionID, session.sessionID)
        XCTAssertEqual(restoredPlan.sessionUUID, restored.sessionID)
    }

    // MARK: - Workouts that vary (no fixed template)

    private func finishedSession(_ name: String, day: Int, exercises: [(String, [Int])]) throws -> LiftSession {
        let session = try service.startFreestyleSession(name: name, at: Date(timeIntervalSince1970: TimeInterval(day) * 86_400))
        for (exerciseName, reps) in exercises {
            let exercise = try service.addCustomExercise(in: session, name: exerciseName)
            for rep in reps { try service.logSet(in: session, exercise: exercise, weightLbs: 100, reps: rep, restSeconds: 90) }
        }
        session.durationMinutes = 40
        try context.save()
        return session
    }

    func test_freestyleWorkoutStartsEmptyWithItsOwnName() throws {
        let unnamed = try service.startFreestyleSession(name: "  ")
        XCTAssertEqual(unnamed.template, LiftService.freestyleName)
        XCTAssertEqual(unnamed.exercises?.count, 0)
        XCTAssertNotNil(unnamed.sessionID)
        XCTAssertEqual(try service.startFreestyleSession(name: " Pull day ").template, "Pull day")
    }

    func test_addedExerciseReusesHistorySpellingAndTargets() throws {
        let old = try service.startSession(templateName: "Lift A", at: Date(timeIntervalSince1970: 100))
        old.durationMinutes = 30
        try context.save()
        let today = try service.startFreestyleSession(name: "Legs")
        let added = try service.addCustomExercise(in: today, name: "back squat")
        XCTAssertEqual(added.name, "Back Squat", "History spelling keeps prefill and progress linked")
        XCTAssertEqual(added.progressionSets, 4)
        XCTAssertEqual(added.progressionLowerReps, 5)
        let new = try service.addCustomExercise(in: today, name: "Sissy squat")
        XCTAssertEqual(new.progressionSets, 3, "An exercise with no history keeps the defaults")
    }

    func test_recentWorkoutsAreFinishedDistinctAndNewestFirst() throws {
        _ = try finishedSession("Legs", day: 1, exercises: [("Squat", [5]), ("Calf raise", [12])])
        _ = try finishedSession("Pull", day: 2, exercises: [("Row", [8])])
        let latestLegs = try finishedSession("Legs", day: 3, exercises: [("Squat", [5]), ("Calf raise", [12])])
        _ = try finishedSession("Empty", day: 4, exercises: [])
        _ = try service.startFreestyleSession(name: "Unfinished", at: Date(timeIntervalSince1970: 5 * 86_400))
        let recent = try service.recentWorkouts(limit: 5, before: Date(timeIntervalSince1970: 10 * 86_400))
        XCTAssertEqual(recent.map(\.template), ["Legs", "Pull"])
        XCTAssertTrue(recent.first === latestLegs)
    }

    func test_quickPicksRankByUseAndSkipCurrentExercises() throws {
        _ = try finishedSession("A", day: 1, exercises: [("Squat", [5]), ("Row", [8])])
        _ = try finishedSession("B", day: 2, exercises: [("Squat", [5]), ("Dip", [10])])
        _ = try finishedSession("C", day: 3, exercises: [("Planned only", [])])
        XCTAssertEqual(try service.recentExerciseNames(), ["Squat", "Dip", "Row"])
        XCTAssertEqual(try service.recentExerciseNames(excluding: ["squat"]), ["Dip", "Row"])
    }

    func test_repeatPlanCopiesExercisesAndPerformedShapeButNoSets() throws {
        let source = try finishedSession("Leg focus", day: 1, exercises: [("Goblet squat", [10, 10, 8]), ("Calf raise", [])])
        let plan = try XCTUnwrap(LiftService.template(repeating: source))
        XCTAssertEqual(plan.name, "Leg focus")
        XCTAssertEqual(plan.exercises.map(\.name), ["Goblet squat", "Calf raise"])
        XCTAssertEqual(plan.exercises[0].targetSets, 3)
        XCTAssertEqual(plan.exercises[0].targetReps, 10)
        XCTAssertEqual(plan.exercises[0].restSeconds, 90)
        XCTAssertEqual(plan.exercises[1].targetSets, 3, "No sets logged: the exercise's own target")
        let repeated = try service.startSession(template: plan)
        XCTAssertEqual(repeated.template, "Leg focus")
        XCTAssertEqual((repeated.exercises ?? []).flatMap { $0.sets ?? [] }.count, 0, "Nothing is copied as performed")
        let squat = try XCTUnwrap(repeated.exercises?.first { $0.name == "Goblet squat" })
        XCTAssertEqual(try service.suggestedSet(for: squat).weightLbs, 100, "Loads prefill from last time")
        XCTAssertNil(LiftService.template(repeating: try service.startFreestyleSession(name: "Nothing yet")))
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
