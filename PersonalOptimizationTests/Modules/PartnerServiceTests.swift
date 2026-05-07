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
}
