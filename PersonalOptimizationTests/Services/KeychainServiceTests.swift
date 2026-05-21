import XCTest
@testable import PersonalOptimization

final class KeychainServiceTests: XCTestCase {
    private let service = KeychainService.shared

    /// True when the host process isn't signed with the `keychain-access-groups`
    /// entitlement. `CODE_SIGNING_ALLOWED=NO` builds and CI without a real
    /// dev team land here. The keychain SDK returns -34018
    /// (errSecMissingEntitlement) in that mode.
    private var keychainAvailable: Bool {
        // Probe by writing a transient value. If the OS denies access we
        // assume the entitlement isn't embedded and skip the suite.
        let probeKey = "__probe__"
        do {
            try service.setApiKey(probeKey)
            try service.deleteApiKey()
            return true
        } catch {
            return false
        }
    }

    override func setUp() async throws {
        try await super.setUp()
        guard keychainAvailable else {
            throw XCTSkip("Keychain access denied (errSecMissingEntitlement). Run with code signing enabled to exercise these tests.")
        }
        try? service.deleteApiKey()
    }

    override func tearDown() async throws {
        try? service.deleteApiKey()
        try await super.tearDown()
    }

    func test_setApiKey_thenGet_returnsSameValue() throws {
        try service.setApiKey("test-key-12345")
        XCTAssertEqual(try service.getApiKey(), "test-key-12345")
    }

    func test_setApiKey_overwritesExisting() throws {
        try service.setApiKey("old-key")
        try service.setApiKey("new-key")
        XCTAssertEqual(try service.getApiKey(), "new-key")
    }

    func test_getApiKey_whenMissing_throwsItemNotFound() throws {
        XCTAssertThrowsError(try service.getApiKey()) { error in
            guard case KeychainError.itemNotFound = error else {
                XCTFail("Expected itemNotFound, got \(error)")
                return
            }
        }
    }

    func test_deleteApiKey_whenMissing_doesNotThrow() {
        XCTAssertNoThrow(try service.deleteApiKey())
    }

    func test_deleteApiKey_thenGet_throwsItemNotFound() throws {
        try service.setApiKey("ephemeral")
        try service.deleteApiKey()
        XCTAssertThrowsError(try service.getApiKey())
    }
}
