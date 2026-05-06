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

    func test_export_emptyStore_produces_valid_JSON_with_version1() throws {
        let data = try JSONExportService.export(modelContext: context)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(ExportPayload.self, from: data)
        XCTAssertEqual(payload.version, 1)
        XCTAssertNil(payload.userProfile)
        XCTAssertTrue(payload.scheduleBlocks.isEmpty)
        XCTAssertTrue(payload.dailyLogs.isEmpty)
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
