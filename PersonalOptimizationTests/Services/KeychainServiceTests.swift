import XCTest
@testable import PersonalOptimization

final class KeychainServiceTests: XCTestCase {
    private let service = KeychainService.shared

    override func setUp() async throws {
        try await super.setUp()
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
