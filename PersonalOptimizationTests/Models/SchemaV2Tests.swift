import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class SchemaV2Tests: XCTestCase {

    func test_schemaV2_includesV1ModelsPlusEngagementEntities() {
        let names = Set(SchemaV2.models.map { String(describing: $0) })
        let v1Names = Set(SchemaV1.models.map { String(describing: $0) })
        XCTAssertTrue(v1Names.isSubset(of: names))
        XCTAssertTrue(names.contains("StreakCounter"))
        XCTAssertTrue(names.contains("WorkoutEvent"))
        XCTAssertTrue(names.contains("CompletionHistory"))
        XCTAssertTrue(names.contains("FreezeApplication"))
    }

    func test_schemaV2_versionIs2_0_0() {
        XCTAssertEqual(SchemaV2.versionIdentifier, Schema.Version(2, 0, 0))
    }

    func test_migrationPlan_listsV1ThenV2InOrder() {
        let versions = AppMigrationPlan.schemas.map { String(describing: $0) }
        XCTAssertEqual(versions, ["SchemaV1", "SchemaV2"])
        XCTAssertEqual(AppMigrationPlan.stages.count, 1)
    }

    func test_streakCounter_persistsAndRoundTrips() throws {
        let container = try InMemoryContainer.make()
        let context = container.mainContext
        let counter = StreakCounter(domain: .workout)
        counter.currentStreak = 5
        counter.longestStreak = 10
        counter.freezesAvailable = 2
        context.insert(counter)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<StreakCounter>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.domain, "workout")
        XCTAssertEqual(fetched.first?.currentStreak, 5)
        XCTAssertEqual(fetched.first?.longestStreak, 10)
        XCTAssertEqual(fetched.first?.freezesAvailable, 2)
    }

    func test_workoutEvent_persistsAllSources() throws {
        let container = try InMemoryContainer.make()
        let context = container.mainContext
        let day = Calendar.current.startOfDay(for: Date())
        for source in WorkoutEventSource.allCases {
            context.insert(WorkoutEvent(date: day, completed: true, source: source))
        }
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutEvent>()).count, WorkoutEventSource.allCases.count)
    }

    func test_completionHistory_appendsMultipleRowsForSameDomain() throws {
        let container = try InMemoryContainer.make()
        let context = container.mainContext
        let now = Date()
        for offset in 0..<5 {
            context.insert(CompletionHistory(domain: .hydration,
                                             timestamp: now.addingTimeInterval(Double(offset) * 60)))
        }
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<CompletionHistory>()).count, 5)
    }

    func test_freezeApplication_storesDomainAndDate() throws {
        let container = try InMemoryContainer.make()
        let context = container.mainContext
        let day = Calendar.current.startOfDay(for: Date())
        context.insert(FreezeApplication(domain: .learning, date: day))
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<FreezeApplication>())
        XCTAssertEqual(fetched.first?.domain, "learning")
        XCTAssertEqual(fetched.first?.date, day)
    }

    func test_userProfile_hasNewEngagementFields() throws {
        let container = try InMemoryContainer.make()
        let context = container.mainContext
        let p = UserProfile()
        p.sickDayActiveUntil = Date().addingTimeInterval(3600)
        p.travelModeActiveUntil = Date().addingTimeInterval(7 * 86400)
        context.insert(p)
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<UserProfile>())
        XCTAssertNotNil(fetched.first?.sickDayActiveUntil)
        XCTAssertNotNil(fetched.first?.travelModeActiveUntil)
    }

    /// Loads a SchemaV1 container, writes V1 data, then opens the same on-disk store
    /// with SchemaV2. New fields default correctly and old data is preserved.
    /// Uses an on-disk store to exercise the migration; cleans up after itself.
    func test_migration_v1ToV2_preservesExistingDataAndDefaultsNewFields() throws {
        let storeURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("po-migration-\(UUID().uuidString).store")
        defer {
            for ext in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: storeURL.appendingPathExtension(ext))
            }
            try? FileManager.default.removeItem(at: storeURL)
        }

        do {
            let v1Schema = Schema(versionedSchema: SchemaV1.self)
            let cfg = ModelConfiguration(schema: v1Schema, url: storeURL, cloudKitDatabase: .none)
            let v1Container = try ModelContainer(for: v1Schema, configurations: [cfg])
            let ctx = v1Container.mainContext
            let p = UserProfile(name: "Clay", dob: Date(timeIntervalSince1970: 764985600), sex: "male")
            ctx.insert(p)
            ctx.insert(DailyLog(date: Date()))
            ctx.insert(LearningStreak(module: "japanese"))
            try ctx.save()
        }

        let v2Schema = Schema(versionedSchema: SchemaV2.self)
        let cfg2 = ModelConfiguration(schema: v2Schema, url: storeURL, cloudKitDatabase: .none)
        let v2Container = try ModelContainer(
            for: v2Schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [cfg2]
        )
        let ctx2 = v2Container.mainContext

        let profiles = try ctx2.fetch(FetchDescriptor<UserProfile>())
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.name, "Clay")
        XCTAssertNil(profiles.first?.sickDayActiveUntil)
        XCTAssertNil(profiles.first?.travelModeActiveUntil)
        XCTAssertEqual(try ctx2.fetch(FetchDescriptor<DailyLog>()).count, 1)
        XCTAssertEqual(try ctx2.fetch(FetchDescriptor<LearningStreak>()).count, 1)
        XCTAssertEqual(try ctx2.fetch(FetchDescriptor<StreakCounter>()).count, 0)
    }
}
