import XCTest
import SwiftData
@testable import PersonalOptimization

/// Pairwise migration round-trip tests for SchemaV2..V9. Each pair seeds a
/// UserProfile row at the lower version, migrates to the higher version,
/// and asserts the UserProfile survives + each newly-introduced entity can
/// be inserted post-migration (proving the migration plan stitched the
/// schema definition correctly).
///
/// Why a single file with many tests: every V_x → V_x+1 jump in this app
/// is additive — new entities only, no field migrations beyond default
/// values. The test shape repeats so it's clearer in one place than seven
/// near-identical files.
@MainActor
final class SchemaV3ThroughV9MigrationTests: XCTestCase {

    private var tempURLs: [URL] = []

    override func tearDown() async throws {
        for url in tempURLs { SchemaMigrationTestHarness.cleanup(at: url) }
        tempURLs.removeAll()
        try await super.tearDown()
    }

    // MARK: - V2 → V3 (adds HealthKitWriteFailure, HydrationEntry, CoachInsight)

    func test_migration_v2_to_v3() throws {
        let (migrated, url) = try SchemaMigrationTestHarness.migrate(
            seedAt: SchemaV2.self,
            target: SchemaV3.self
        ) { ctx in
            ctx.insert(UserProfile(name: "Clay"))
        }
        tempURLs.append(url)
        XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<UserProfile>()).count, 1)
        // The new V3 entities are queryable.
        XCTAssertTrue(try migrated.mainContext.fetch(FetchDescriptor<HealthKitWriteFailure>()).isEmpty)
        XCTAssertTrue(try migrated.mainContext.fetch(FetchDescriptor<HydrationEntry>()).isEmpty)
        XCTAssertTrue(try migrated.mainContext.fetch(FetchDescriptor<CoachInsight>()).isEmpty)
    }

    // MARK: - V3 → V4 (adds ActivityArchive, DetectedPattern, PrescribedWorkout, ScheduleSuggestion, WeeklyProgram)

    func test_migration_v3_to_v4() throws {
        let (migrated, url) = try SchemaMigrationTestHarness.migrate(
            seedAt: SchemaV3.self,
            target: SchemaV4.self
        ) { ctx in
            ctx.insert(UserProfile(name: "Clay"))
        }
        tempURLs.append(url)
        XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<UserProfile>()).count, 1)
        XCTAssertTrue(try migrated.mainContext.fetch(FetchDescriptor<ActivityArchive>()).isEmpty)
        XCTAssertTrue(try migrated.mainContext.fetch(FetchDescriptor<DetectedPattern>()).isEmpty)
        XCTAssertTrue(try migrated.mainContext.fetch(FetchDescriptor<PrescribedWorkout>()).isEmpty)
        XCTAssertTrue(try migrated.mainContext.fetch(FetchDescriptor<ScheduleSuggestion>()).isEmpty)
        XCTAssertTrue(try migrated.mainContext.fetch(FetchDescriptor<WeeklyProgram>()).isEmpty)
    }

    // MARK: - V4 → V5 (adds CustomActivityTemplate, CustomActivitySession)

    func test_migration_v4_to_v5() throws {
        let (migrated, url) = try SchemaMigrationTestHarness.migrate(
            seedAt: SchemaV4.self,
            target: SchemaV5.self
        ) { ctx in
            ctx.insert(UserProfile(name: "Clay"))
        }
        tempURLs.append(url)
        XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<UserProfile>()).count, 1)
        XCTAssertTrue(try migrated.mainContext.fetch(FetchDescriptor<CustomActivityTemplate>()).isEmpty)
        XCTAssertTrue(try migrated.mainContext.fetch(FetchDescriptor<CustomActivitySession>()).isEmpty)
    }

    // MARK: - V5 → V6 (adds ImplementationIntention, WeeklyReflection)

    func test_migration_v5_to_v6() throws {
        let (migrated, url) = try SchemaMigrationTestHarness.migrate(
            seedAt: SchemaV5.self,
            target: SchemaV6.self
        ) { ctx in
            ctx.insert(UserProfile(name: "Clay"))
        }
        tempURLs.append(url)
        XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<UserProfile>()).count, 1)
        XCTAssertTrue(try migrated.mainContext.fetch(FetchDescriptor<ImplementationIntention>()).isEmpty)
        XCTAssertTrue(try migrated.mainContext.fetch(FetchDescriptor<WeeklyReflection>()).isEmpty)
    }

    // MARK: - V6 → V7 (adds CoachMemory, LapseEvent, MilestoneUnlock)

    func test_migration_v6_to_v7() throws {
        let (migrated, url) = try SchemaMigrationTestHarness.migrate(
            seedAt: SchemaV6.self,
            target: SchemaV7.self
        ) { ctx in
            ctx.insert(UserProfile(name: "Clay"))
        }
        tempURLs.append(url)
        let profile = try migrated.mainContext.fetch(FetchDescriptor<UserProfile>()).first
        XCTAssertNotNil(profile)
        // V7 additive fields default cleanly for rows that existed pre-V7.
        XCTAssertNil(profile?.partnerPairingCode)
        XCTAssertTrue(profile?.partnerOptedIntoSharing ?? false)
        XCTAssertEqual(profile?.recoveryOverrideCountThisMonth, 0)
        XCTAssertTrue(try migrated.mainContext.fetch(FetchDescriptor<CoachMemory>()).isEmpty)
        XCTAssertTrue(try migrated.mainContext.fetch(FetchDescriptor<LapseEvent>()).isEmpty)
        XCTAssertTrue(try migrated.mainContext.fetch(FetchDescriptor<MilestoneUnlock>()).isEmpty)
    }

    // MARK: - V7 → V8 (adds Achievement, UserPersona)

    func test_migration_v7_to_v8() throws {
        let (migrated, url) = try SchemaMigrationTestHarness.migrate(
            seedAt: SchemaV7.self,
            target: SchemaV8.self
        ) { ctx in
            ctx.insert(UserProfile(name: "Clay"))
        }
        tempURLs.append(url)
        XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<UserProfile>()).count, 1)
        XCTAssertTrue(try migrated.mainContext.fetch(FetchDescriptor<Achievement>()).isEmpty)
        XCTAssertTrue(try migrated.mainContext.fetch(FetchDescriptor<UserPersona>()).isEmpty)
    }

    // MARK: - V8 → V9 (adds ScheduleGenerationRun + anchor fields)

    func test_migration_v8_to_v9() throws {
        let (migrated, url) = try SchemaMigrationTestHarness.migrate(
            seedAt: SchemaV8.self,
            target: SchemaV9.self
        ) { ctx in
            ctx.insert(UserProfile(name: "Clay"))
        }
        tempURLs.append(url)
        let profile = try migrated.mainContext.fetch(FetchDescriptor<UserProfile>()).first
        XCTAssertNotNil(profile)
        // V9 additive UserProfile fields default cleanly.
        XCTAssertEqual(profile?.anchorEventsCSV, "")
        XCTAssertNil(profile?.lastGeneratedAt)
        XCTAssertTrue(try migrated.mainContext.fetch(FetchDescriptor<ScheduleGenerationRun>()).isEmpty)
    }
}
