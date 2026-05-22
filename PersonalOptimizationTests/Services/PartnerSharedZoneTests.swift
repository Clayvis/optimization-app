import XCTest
import SwiftData
@testable import PersonalOptimization

/// Covers the `PartnerSharedZone` protocol seam and `PartnerService`'s
/// async snapshot path against `MemoryPartnerSharedZone`. No live CloudKit
/// calls; the live `CloudKitPartnerSharedZone` is deferred until the paid
/// Developer account lands.
@MainActor
final class PartnerSharedZoneTests: XCTestCase {

    private func makeService(zone: PartnerSharedZone) throws -> PartnerService {
        let container = try InMemoryContainer.make()
        return PartnerService(modelContext: container.mainContext, zone: zone)
    }

    private func makeRecord(streak: Int = 5,
                            metric: Double = 0.72,
                            mascot: String = "neutral",
                            userID: String = "user-1",
                            at: Date = Date()) -> PartnerSharedRecord {
        PartnerSharedRecord(
            userID: userID,
            currentStreak: streak,
            masterMetric: metric,
            mascotState: mascot,
            lastUpdate: at
        )
    }

    // MARK: - MemoryPartnerSharedZone behavior

    func test_memoryZone_writeThenFetchAsPartner_returnsRecord() async throws {
        let zone = MemoryPartnerSharedZone()
        zone.callerUserID = "me"
        try await zone.write(record: makeRecord(userID: "partner"))
        let snapshot = try await zone.fetchPartnerSnapshot()
        XCTAssertEqual(snapshot?.userID, "partner")
        XCTAssertEqual(zone.writeCalls, 1)
        XCTAssertEqual(zone.fetchCalls, 1)
    }

    func test_memoryZone_fetchExcludesOwnRecord() async throws {
        let zone = MemoryPartnerSharedZone()
        zone.callerUserID = "me"
        try await zone.write(record: makeRecord(userID: "me"))
        let snapshot = try await zone.fetchPartnerSnapshot()
        XCTAssertNil(snapshot, "fetch must skip the caller's own record")
    }

    func test_memoryZone_fetchReturnsLatestByLastUpdate() async throws {
        let zone = MemoryPartnerSharedZone()
        zone.callerUserID = "me"
        let early = makeRecord(userID: "partner", at: Date(timeIntervalSince1970: 1_000_000))
        let later = makeRecord(userID: "partner", at: Date(timeIntervalSince1970: 2_000_000))
        try await zone.write(record: early)
        try await zone.write(record: later)
        let snapshot = try await zone.fetchPartnerSnapshot()
        XCTAssertEqual(snapshot?.lastUpdate, later.lastUpdate)
    }

    func test_memoryZone_deleteAllClearsRecordsAndIncrementsCount() async throws {
        let zone = MemoryPartnerSharedZone()
        try await zone.write(record: makeRecord(userID: "a"))
        try await zone.write(record: makeRecord(userID: "b"))
        try await zone.deleteAll()
        XCTAssertEqual(zone.deleteAllCalls, 1)
        XCTAssertTrue(zone.records.isEmpty)
    }

    func test_memoryZone_failNextWrite_throwsOnceThenSucceeds() async throws {
        let zone = MemoryPartnerSharedZone()
        zone.failNextWrite = NSError(domain: "test.write", code: 1)
        do {
            try await zone.write(record: makeRecord())
            XCTFail("expected throw on first write")
        } catch {
            XCTAssertEqual((error as NSError).domain, "test.write")
        }
        try await zone.write(record: makeRecord())
        XCTAssertEqual(zone.records.count, 1)
    }

    // MARK: - NoopPartnerSharedZone behavior

    func test_noopZone_writeSucceedsButPersistsNothing() async throws {
        let zone = NoopPartnerSharedZone()
        try await zone.write(record: makeRecord())
        let snapshot = try await zone.fetchPartnerSnapshot()
        XCTAssertNil(snapshot)
    }

    // MARK: - PartnerService wired to the seam

    func test_publishSnapshot_writesThroughZone() async throws {
        let zone = MemoryPartnerSharedZone()
        let service = try makeService(zone: zone)
        let record = makeRecord(streak: 12)
        try await service.publishSnapshot(record)
        XCTAssertEqual(zone.writeCalls, 1)
        XCTAssertEqual(zone.records["user-1"]?.currentStreak, 12)
    }

    func test_publishSnapshot_propagatesZoneFailure() async throws {
        let zone = MemoryPartnerSharedZone()
        zone.failNextWrite = NSError(domain: "test.publish", code: 1)
        let service = try makeService(zone: zone)
        do {
            try await service.publishSnapshot(makeRecord())
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual((error as NSError).domain, "test.publish")
        }
    }

    func test_partnerSnapshot_returnsPartnerRecord() async throws {
        let zone = MemoryPartnerSharedZone()
        zone.callerUserID = "me"
        try await zone.write(record: makeRecord(streak: 7, userID: "partner"))
        let service = try makeService(zone: zone)
        let snapshot = try await service.partnerSnapshot()
        XCTAssertEqual(snapshot?.currentStreak, 7)
    }

    func test_unpairAsync_clearsLinkAndCallsDeleteAll() async throws {
        let zone = MemoryPartnerSharedZone()
        let container = try InMemoryContainer.make()
        let context = container.mainContext
        let service = PartnerService(modelContext: context, zone: zone)
        let profile = UserProfile(name: "T", dob: Date(timeIntervalSince1970: 0), sex: "male")
        profile.partnerRecordID = "partner-record"
        profile.partnerLinkedAt = Date()
        context.insert(profile)
        try context.save()

        try await service.unpairAsync(profile)
        XCTAssertNil(profile.partnerRecordID)
        XCTAssertNil(profile.partnerLinkedAt)
        XCTAssertEqual(zone.deleteAllCalls, 1)
    }

    func test_unpairAsync_propagatesDeleteAllFailure() async throws {
        let zone = MemoryPartnerSharedZone()
        zone.failNextDeleteAll = NSError(domain: "test.delete", code: 1)
        let container = try InMemoryContainer.make()
        let service = PartnerService(modelContext: container.mainContext, zone: zone)
        let profile = UserProfile(name: "T", dob: Date(timeIntervalSince1970: 0), sex: "male")
        container.mainContext.insert(profile)
        try container.mainContext.save()

        do {
            try await service.unpairAsync(profile)
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual((error as NSError).domain, "test.delete")
        }
    }
}
