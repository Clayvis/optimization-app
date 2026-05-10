import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class JSONExportImportTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        container = try InMemoryContainer.make()
        context = container.mainContext
    }

    override func tearDown() async throws {
        context = nil
        container = nil
        try await super.tearDown()
    }

    func test_export_emptyStore_produces_valid_JSON_with_currentVersion() throws {
        let data = try JSONExportService.export(modelContext: context)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(ExportPayload.self, from: data)
        XCTAssertEqual(payload.version, 2, "M3.7 bumps export to version 2")
        XCTAssertNil(payload.userProfile)
        XCTAssertTrue(payload.scheduleBlocks.isEmpty)
        XCTAssertTrue(payload.dailyLogs.isEmpty)
        XCTAssertTrue((payload.activityArchives ?? []).isEmpty, "Empty store has no archives")
    }

    func test_roundtrip_preserves_M3_7_entities() throws {
        let day = Calendar(identifier: .gregorian).startOfDay(for: Date())

        let archive = ActivityArchive(date: day)
        archive.workoutVolumeTotal = 12_400
        archive.workoutCount = 1
        archive.fastingHours = 16
        archive.hydrationOz = 100
        archive.learningMinutes = 45
        archive.dominantMascotState = "proud"
        archive.masterMetric = 0.85
        archive.stepsHK = 9_000
        context.insert(archive)

        let pattern = DetectedPattern(
            detectedAt: day,
            patternType: .volumeDecline,
            confidence: 0.65,
            summary: "Lift volume down 35% vs prior week.",
            detail: "Last 7d: 200 lb/day. Prior 7d: 1000 lb/day.",
            actionableSuggestion: "Deload."
        )
        context.insert(pattern)

        let prescribed = PrescribedWorkout(
            generatedAt: Date(),
            forDate: day,
            workoutType: .liftA,
            template: "{\"sets\":[{\"name\":\"Squat\",\"reps\":5,\"weight\":225}]}",
            rationale: "You hit a fresh PR last week — push.",
            tokenUsage: 800
        )
        prescribed.statusRaw = PrescribedWorkoutStatus.suggested.rawValue
        context.insert(prescribed)

        let suggestion = ScheduleSuggestion(
            generatedAt: Date(),
            summary: "Shift Wed lift to Thu.",
            detail: "Pattern shows you've moved the lift 4 weeks running.",
            changeType: .shiftBlock,
            changePayload: "{\"from\":3,\"to\":4}",
            rationaleData: "schedule_drift confidence 0.8"
        )
        context.insert(suggestion)

        let weekly = WeeklyProgram(
            weekStartDate: day,
            generatedAt: Date(),
            programJSON: "{\"mon\":\"lift_a\",\"tue\":\"basketball\"}",
            coachNarrative: "Build a strength base this week.",
            tokenUsage: 1200
        )
        context.insert(weekly)

        let profile = UserProfile(name: "Clay")
        profile.mascotVariant = "ninja_male"
        profile.primaryGoal = "build muscle"
        profile.equipmentAccess = "gym"
        profile.weeklyTrainingTargetSessions = 5
        context.insert(profile)
        try context.save()

        let data = try JSONExportService.export(modelContext: context)
        try JSONImportService.restore(data: data, modelContext: context)

        let archives = try context.fetch(FetchDescriptor<ActivityArchive>())
        XCTAssertEqual(archives.count, 1)
        XCTAssertEqual(archives.first?.dominantMascotState, "proud")
        XCTAssertEqual(archives.first?.masterMetric ?? 0, 0.85, accuracy: 0.001)

        let patterns = try context.fetch(FetchDescriptor<DetectedPattern>())
        XCTAssertEqual(patterns.count, 1)
        XCTAssertEqual(patterns.first?.patternType, .volumeDecline)

        let pws = try context.fetch(FetchDescriptor<PrescribedWorkout>())
        XCTAssertEqual(pws.count, 1)
        XCTAssertEqual(pws.first?.workoutType, .liftA)
        XCTAssertEqual(pws.first?.tokenUsage, 800)

        let suggestions = try context.fetch(FetchDescriptor<ScheduleSuggestion>())
        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.changeType, .shiftBlock)

        let weeklies = try context.fetch(FetchDescriptor<WeeklyProgram>())
        XCTAssertEqual(weeklies.count, 1)
        XCTAssertEqual(weeklies.first?.tokenUsage, 1200)

        let profiles = try context.fetch(FetchDescriptor<UserProfile>())
        XCTAssertEqual(profiles.first?.mascotVariant, "ninja_male")
        XCTAssertEqual(profiles.first?.primaryGoal, "build muscle")
        XCTAssertEqual(profiles.first?.weeklyTrainingTargetSessions, 5)
    }

    func test_roundtrip_preservesUserProfileScheduleAndDailyLog() throws {
        // Seed
        let profile = UserProfile(name: "Clay", dob: Date(timeIntervalSince1970: 764985600), sex: "male")
        profile.timezone = "Asia/Tokyo"
        profile.bottleSizeOz = 28
        context.insert(profile)

        try ScheduleSeed.seedIfNeeded(modelContext: context, bundle: ScheduleSeedTests.resourceBundle())

        let log = DailyLog(date: Date(timeIntervalSince1970: 1_762_300_000))
        log.waterOz = 96
        log.electrolyteSessions = 2
        log.japaneseMinutes = 30
        log.subjectiveEnergy = 8
        context.insert(log)

        try context.save()

        let exported = try JSONExportService.export(modelContext: context)

        // Wipe + restore using import
        try JSONImportService.restore(data: exported, modelContext: context)

        let profiles = try context.fetch(FetchDescriptor<UserProfile>())
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.name, "Clay")
        XCTAssertEqual(profiles.first?.bottleSizeOz, 28)

        let blocks = try context.fetch(FetchDescriptor<ScheduleBlock>())
        XCTAssertEqual(blocks.count, 39)

        let logs = try context.fetch(FetchDescriptor<DailyLog>())
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.waterOz, 96)
        XCTAssertEqual(logs.first?.subjectiveEnergy, 8)
    }

    func test_roundtrip_preservesLiftSessionWithExercisesAndSets() throws {
        let session = LiftSession(date: Date(timeIntervalSince1970: 1_762_300_000), template: "Lift A")
        session.totalVolumeLbs = 12500
        session.durationMinutes = 75
        let squat = LiftExercise(name: "Squat", orderIndex: 0)
        squat.rpe = 8
        squat.sets = [
            LiftSet(weightLbs: 225, reps: 5, orderIndex: 0),
            LiftSet(weightLbs: 245, reps: 3, orderIndex: 1)
        ]
        session.exercises = [squat]
        context.insert(session)
        try context.save()

        let data = try JSONExportService.export(modelContext: context)
        try JSONImportService.restore(data: data, modelContext: context)

        let restored = try context.fetch(FetchDescriptor<LiftSession>())
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.totalVolumeLbs, 12500)
        XCTAssertEqual(restored.first?.exercises?.count, 1)
        XCTAssertEqual(restored.first?.exercises?.first?.sets?.count, 2)
        let sets = (restored.first?.exercises?.first?.sets ?? []).sorted { $0.orderIndex < $1.orderIndex }
        XCTAssertEqual(sets.first?.weightLbs, 225)
        XCTAssertEqual(sets.first?.reps, 5)
        XCTAssertEqual(sets.last?.weightLbs, 245)
    }

    func test_roundtrip_preservesLabDrawValuesDictionary() throws {
        let lab = LabDraw(date: Date(timeIntervalSince1970: 1_762_300_000),
                          values: ["glucose": 100, "tsh": 0.425, "creatinine": 1.15])
        lab.sourcePdfFilename = "DOD-Q4-2025.pdf"
        context.insert(lab)
        try context.save()

        let data = try JSONExportService.export(modelContext: context)
        try JSONImportService.restore(data: data, modelContext: context)

        let restored = try context.fetch(FetchDescriptor<LabDraw>())
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.values["glucose"], 100)
        XCTAssertEqual(restored.first?.values["tsh"], 0.425)
        XCTAssertEqual(restored.first?.values["creatinine"], 1.15)
        XCTAssertEqual(restored.first?.sourcePdfFilename, "DOD-Q4-2025.pdf")
    }

    func test_import_unsupportedVersion_throws() throws {
        let bogus = #"{"version":99,"exportedAt":"2026-01-01T00:00:00Z","scheduleBlocks":[],"dailyLogs":[],"liftSessions":[],"basketballSessions":[],"swimSessions":[],"labDraws":[],"wearableEntries":[],"protocolEntries":[],"pomodoroSessions":[],"adminTasks":[],"learningStreaks":[],"characterStateLogs":[]}"#
        let data = bogus.data(using: .utf8)!
        XCTAssertThrowsError(try JSONImportService.restore(data: data, modelContext: context)) { error in
            guard case JSONImportError.unsupportedVersion(99) = error else {
                XCTFail("Expected unsupportedVersion(99), got \(error)")
                return
            }
        }
    }

    func test_import_malformedJSON_throwsDecodingFailed() throws {
        let bogus = "not json".data(using: .utf8)!
        XCTAssertThrowsError(try JSONImportService.restore(data: bogus, modelContext: context)) { error in
            guard case JSONImportError.decodingFailed = error else {
                XCTFail("Expected decodingFailed, got \(error)")
                return
            }
        }
    }
}
