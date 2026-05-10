import XCTest
import SwiftData
@testable import PersonalOptimization

/// Round-trip tests for the JSON export/import pipeline. The 30-day TestFlight
/// test (per M3_7a_TEST_BUILD_SPEC.md) treats this pipeline as the bulletproof
/// backup before handing the app to the second tester.
@MainActor
final class DataExportImportTests: XCTestCase {

    // Containers are held as instance state so they outlive a single fetch.
    // Discarding a ModelContainer mid-test invalidates @Model objects in
    // SwiftData and crashes inside the export pipeline (swift_weakLoadStrong
    // on a freed context).
    private var srcContainer: ModelContainer!
    private var destContainer: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        srcContainer = try InMemoryContainer.make()
        destContainer = try InMemoryContainer.make()
    }

    override func tearDown() async throws {
        srcContainer = nil
        destContainer = nil
        try await super.tearDown()
    }

    private var srcCtx: ModelContext { srcContainer.mainContext }
    private var destCtx: ModelContext { destContainer.mainContext }

    // MARK: - Empty DB

    func test_export_emptyDB_decodesCleanly() throws {
        let data = try JSONExportService.export(modelContext: srcCtx)
        XCTAssertGreaterThan(data.count, 0)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(ExportPayload.self, from: data)
        XCTAssertNil(payload.userProfile)
        XCTAssertTrue(payload.scheduleBlocks.isEmpty)
        XCTAssertTrue(payload.dailyLogs.isEmpty)
        XCTAssertTrue(payload.liftSessions.isEmpty)
    }

    func test_export_emptyDB_thenImport_emptyDB_isStillEmpty() throws {
        let data = try JSONExportService.export(modelContext: srcCtx)
        try JSONImportService.restore(data: data, modelContext: destCtx)

        let profiles = try destCtx.fetch(FetchDescriptor<UserProfile>())
        let blocks = try destCtx.fetch(FetchDescriptor<ScheduleBlock>())
        XCTAssertTrue(profiles.isEmpty)
        XCTAssertTrue(blocks.isEmpty)
    }

    // MARK: - Single user, 7 days

    func test_roundTrip_sevenDaysOfData_preservesEverything() throws {
        seedDays(count: 7, into: srcCtx)
        let beforeProfiles = (try srcCtx.fetch(FetchDescriptor<UserProfile>())).count
        let beforeLogs = (try srcCtx.fetch(FetchDescriptor<DailyLog>())).count
        let beforeBlocks = (try srcCtx.fetch(FetchDescriptor<ScheduleBlock>())).count
        let beforeLifts = (try srcCtx.fetch(FetchDescriptor<LiftSession>())).count
        XCTAssertEqual(beforeProfiles, 1)
        XCTAssertEqual(beforeLogs, 7)
        XCTAssertGreaterThan(beforeBlocks, 0)
        XCTAssertGreaterThan(beforeLifts, 0)

        let data = try JSONExportService.export(modelContext: srcCtx)
        try JSONImportService.restore(data: data, modelContext: destCtx)

        let afterProfiles = try destCtx.fetch(FetchDescriptor<UserProfile>())
        let afterLogs = try destCtx.fetch(FetchDescriptor<DailyLog>())
        let afterBlocks = try destCtx.fetch(FetchDescriptor<ScheduleBlock>())
        let afterLifts = try destCtx.fetch(FetchDescriptor<LiftSession>())
        XCTAssertEqual(afterProfiles.count, beforeProfiles)
        XCTAssertEqual(afterLogs.count, beforeLogs)
        XCTAssertEqual(afterBlocks.count, beforeBlocks)
        XCTAssertEqual(afterLifts.count, beforeLifts)

        XCTAssertEqual(afterProfiles.first?.name, "Test User")
        XCTAssertEqual(afterProfiles.first?.primaryGoal, "build muscle")
    }

    // MARK: - 30 days of data (volume sanity)

    func test_roundTrip_thirtyDaysOfData_preservesCounts() throws {
        seedDays(count: 30, into: srcCtx)
        let beforeLogs = (try srcCtx.fetch(FetchDescriptor<DailyLog>())).count
        let beforeLifts = (try srcCtx.fetch(FetchDescriptor<LiftSession>())).count
        XCTAssertEqual(beforeLogs, 30)

        let data = try JSONExportService.export(modelContext: srcCtx)
        try JSONImportService.restore(data: data, modelContext: destCtx)

        let afterLogs = (try destCtx.fetch(FetchDescriptor<DailyLog>())).count
        let afterLifts = (try destCtx.fetch(FetchDescriptor<LiftSession>())).count
        XCTAssertEqual(afterLogs, beforeLogs)
        XCTAssertEqual(afterLifts, beforeLifts)
    }

    // MARK: - Replace-all semantics

    func test_import_replacesExistingData_doesNotMerge() throws {
        seedDays(count: 7, into: srcCtx)
        let snapshot = try JSONExportService.export(modelContext: srcCtx)

        let extra = DailyLog(date: Date().addingTimeInterval(-86400 * 100))
        extra.waterOz = 999
        srcCtx.insert(extra)
        try srcCtx.save()
        let beforeReplace = (try srcCtx.fetch(FetchDescriptor<DailyLog>())).count
        XCTAssertEqual(beforeReplace, 8)

        try JSONImportService.restore(data: snapshot, modelContext: srcCtx)
        let afterReplace = (try srcCtx.fetch(FetchDescriptor<DailyLog>())).count
        XCTAssertEqual(afterReplace, 7, "Restore must replace, not merge")
    }

    // MARK: - Helpers

    private func seedDays(count: Int, into ctx: ModelContext) {
        let profile = UserProfile()
        profile.name = "Test User"
        profile.primaryGoal = "build muscle"
        ctx.insert(profile)

        for i in 0..<count {
            let day = Date().addingTimeInterval(-Double(i) * 86_400)
            let log = DailyLog(date: day)
            log.waterOz = Double(50 + i)
            log.japaneseMinutes = 15
            ctx.insert(log)

            if i % 2 == 0 {
                let lift = LiftSession(date: day, template: "Lift A")
                lift.totalVolumeLbs = Double(8000 + i * 100)
                lift.durationMinutes = 60
                ctx.insert(lift)
            }
        }

        let block = ScheduleBlock(dayOfWeek: 1, startTime: "06:00", endTime: "07:00",
                                  activity: "Lift A", type: .training, module: "lift_a")
        ctx.insert(block)

        try? ctx.save()
    }
}
