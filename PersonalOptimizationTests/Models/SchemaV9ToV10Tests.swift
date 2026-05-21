import XCTest
import SwiftData
@testable import PersonalOptimization

/// Example schema migration round-trip test. Verifies the SchemaV9 → V10
/// lightweight migration preserves UserProfile rows and that the V10
/// additive fields default correctly without backfill.
@MainActor
final class SchemaV9ToV10Tests: XCTestCase {

    var tempURL: URL?

    override func tearDown() async throws {
        if let url = tempURL { SchemaMigrationTestHarness.cleanup(at: url) }
        tempURL = nil
        try await super.tearDown()
    }

    func test_v9toV10_preservesUserProfile() throws {
        let (migrated, url) = try SchemaMigrationTestHarness.migrate(
            seedAt: SchemaV9.self,
            target: SchemaV10.self
        ) { ctx in
            let profile = UserProfile(name: "Clay", dob: Date(timeIntervalSince1970: 0), sex: "male")
            profile.timezone = "Asia/Tokyo"
            ctx.insert(profile)
        }
        self.tempURL = url

        let profiles = try migrated.mainContext.fetch(FetchDescriptor<UserProfile>())
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.name, "Clay")
        XCTAssertEqual(profiles.first?.timezone, "Asia/Tokyo")
    }

    func test_v9toV10_addsV10DefaultsToExistingProfile() throws {
        let (migrated, url) = try SchemaMigrationTestHarness.migrate(
            seedAt: SchemaV9.self,
            target: SchemaV10.self
        ) { ctx in
            let profile = UserProfile(name: "Clay", dob: .distantPast, sex: "male")
            ctx.insert(profile)
        }
        self.tempURL = url

        let migratedProfile = try migrated.mainContext.fetch(FetchDescriptor<UserProfile>()).first
        XCTAssertNotNil(migratedProfile)
        // V10 additive fields default to their declared values for rows that
        // existed pre-V10. These are the toggles introduced for the pre-
        // TestFlight P0/P1 hardening pass.
        XCTAssertEqual(migratedProfile?.travelModeFollowsDevice, false)
        XCTAssertEqual(migratedProfile?.sleepWindowStartHHMM, "22:00")
        XCTAssertEqual(migratedProfile?.sleepWindowEndHHMM, "07:00")
        XCTAssertEqual(migratedProfile?.dailyTokenBudget, 50_000)
    }

    func test_v9toV10_addsTokenUsageEntryEntity() throws {
        let (migrated, url) = try SchemaMigrationTestHarness.migrate(
            seedAt: SchemaV9.self,
            target: SchemaV10.self
        ) { _ in /* no seed rows needed */ }
        self.tempURL = url

        // TokenUsageEntry is a new V10 entity; an empty fetch must succeed
        // (proving the table exists post-migration).
        let entries = try migrated.mainContext.fetch(FetchDescriptor<TokenUsageEntry>())
        XCTAssertTrue(entries.isEmpty)

        // Write a row to confirm the entity is fully functional.
        let entry = TokenUsageEntry(date: Date(), inputTokens: 1, outputTokens: 2, callCount: 1, lastCallAt: Date())
        migrated.mainContext.insert(entry)
        try migrated.mainContext.save()
        XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<TokenUsageEntry>()).count, 1)
    }

    func test_v9toV10_addsBackgroundTaskLogEntity() throws {
        let (migrated, url) = try SchemaMigrationTestHarness.migrate(
            seedAt: SchemaV9.self,
            target: SchemaV10.self
        ) { _ in }
        self.tempURL = url

        let logs = try migrated.mainContext.fetch(FetchDescriptor<BackgroundTaskLog>())
        XCTAssertTrue(logs.isEmpty)
        let log = BackgroundTaskLog(taskId: "test")
        migrated.mainContext.insert(log)
        try migrated.mainContext.save()
        XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<BackgroundTaskLog>()).count, 1)
    }
}
