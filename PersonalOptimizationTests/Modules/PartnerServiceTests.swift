import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class PartnerServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var service: PartnerService!

    override func setUp() async throws {
        try await super.setUp()
        container = try InMemoryContainer.make()
        context = container.mainContext
        service = PartnerService(modelContext: context)
    }

    override func tearDown() async throws {
        service = nil
        context = nil
        container = nil
        try await super.tearDown()
    }

    func test_makeCode_isSixCharacters() {
        let code = PartnerService.makeCode()
        XCTAssertEqual(code.count, 6)
    }

    func test_makeCode_excludesAmbiguousCharacters() {
        // 0/O/1/I should never appear; verify across many samples.
        let banned: Set<Character> = ["0", "O", "1", "I"]
        for _ in 0..<200 {
            let code = PartnerService.makeCode()
            for ch in code { XCTAssertFalse(banned.contains(ch), "\(code) contains banned char \(ch)") }
        }
    }

    func test_generatePairingCode_persistsOnProfile() throws {
        let profile = UserProfile()
        context.insert(profile)
        let code = try service.generatePairingCode(for: profile)
        XCTAssertEqual(profile.partnerPairingCode, code)
        XCTAssertNotNil(profile.partnerPairingCodeExpiresAt)
    }

    func test_activeCode_returnsNilWhenExpired() throws {
        let profile = UserProfile()
        context.insert(profile)
        _ = try service.generatePairingCode(for: profile)
        profile.partnerPairingCodeExpiresAt = Date().addingTimeInterval(-3600)
        XCTAssertNil(service.activeCode(for: profile))
    }

    func test_acceptCode_setsPartnerLink_andClearsPairingCode() throws {
        let profile = UserProfile()
        context.insert(profile)
        _ = try service.generatePairingCode(for: profile)
        try service.acceptCode("ABCDEF", partnerRecordID: "stub:remote-user", on: profile)
        XCTAssertEqual(profile.partnerRecordID, "stub:remote-user")
        XCTAssertNotNil(profile.partnerLinkedAt)
        XCTAssertNil(profile.partnerPairingCode)
    }

    func test_acceptCode_withWrongLength_throws() throws {
        let profile = UserProfile()
        context.insert(profile)
        XCTAssertThrowsError(try service.acceptCode("ABC", partnerRecordID: "x", on: profile))
    }

    func test_unpair_clearsLink() throws {
        let profile = UserProfile()
        context.insert(profile)
        try service.acceptCode("ABCDEF", partnerRecordID: "stub:x", on: profile)
        try service.unpair(profile)
        XCTAssertNil(profile.partnerRecordID)
        XCTAssertNil(profile.partnerLinkedAt)
    }

    // MARK: - Joint streak + nudge (cooperative dyad)

    private func jstCalendar() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        return c
    }

    func test_jointStatus_unpaired_whenNoPartner() {
        let status = PartnerService.jointStatus(
            ownStreak: 5, ownClosedToday: true, partner: nil, calendar: jstCalendar()
        )
        XCTAssertFalse(status.partnerPaired)
        XCTAssertEqual(status.jointStreak, 0)
        XCTAssertNil(status.partnerStreak)
    }

    func test_jointStatus_isMinOfBothStreaks() {
        let partner = PartnerSharedRecord(userID: "p", currentStreak: 12, masterMetric: 0.5, mascotState: "neutral", lastUpdate: Date())
        let status = PartnerService.jointStatus(
            ownStreak: 5, ownClosedToday: false, partner: partner, calendar: jstCalendar()
        )
        XCTAssertTrue(status.partnerPaired)
        XCTAssertEqual(status.partnerStreak, 12)
        XCTAssertEqual(status.jointStreak, 5, "Joint streak is bounded by the shorter chain.")
    }

    func test_jointStatus_bothClosedToday_whenPartnerFreshAndComplete() {
        let cal = jstCalendar()
        let partner = PartnerSharedRecord(userID: "p", currentStreak: 8, masterMetric: 1.0, mascotState: "proud", lastUpdate: Date())
        let status = PartnerService.jointStatus(
            ownStreak: 8, ownClosedToday: true, partner: partner, calendar: cal
        )
        XCTAssertTrue(status.bothClosedToday)
    }

    func test_jointStatus_notBothClosed_whenPartnerSnapshotStale() {
        let cal = jstCalendar()
        let yesterday = cal.date(byAdding: .day, value: -1, to: Date())!
        let partner = PartnerSharedRecord(userID: "p", currentStreak: 8, masterMetric: 1.0, mascotState: "proud", lastUpdate: yesterday)
        let status = PartnerService.jointStatus(
            ownStreak: 8, ownClosedToday: true, partner: partner, calendar: cal
        )
        XCTAssertFalse(status.bothClosedToday, "A stale partner snapshot does not count as closed today.")
    }

    func test_sendNudge_callsZone() async throws {
        let zone = MemoryPartnerSharedZone()
        let svc = PartnerService(modelContext: context, zone: zone)
        try await svc.sendNudge(message: "Close your day.")
        XCTAssertEqual(zone.nudgeCalls, 1)
        XCTAssertEqual(zone.sentNudges.first?.message, "Close your day.")
    }

    func test_pendingNudge_returnsZoneNudge() async throws {
        let zone = MemoryPartnerSharedZone()
        zone.pendingNudge = PartnerNudge(message: "Thinking of you.")
        let svc = PartnerService(modelContext: context, zone: zone)
        let nudge = try await svc.pendingNudge()
        XCTAssertEqual(nudge?.message, "Thinking of you.")
    }
}
