import XCTest
@testable import PersonalOptimization

final class PimsleurDeepLinkTests: XCTestCase {

    func test_preferredURL_isPimsleurScheme() {
        XCTAssertEqual(PimsleurDeepLink.preferredURL().scheme, "pimsleur")
    }

    func test_fallbackURL_isAppStore() {
        let host = PimsleurDeepLink.fallbackURL().host ?? ""
        XCTAssertEqual(PimsleurDeepLink.fallbackURL().scheme, "itms-apps")
        XCTAssertTrue(host.contains("itunes.apple.com"))
    }

    func test_appStoreURL_includesItemID() {
        let absoluteString = PimsleurDeepLink.fallbackURL().absoluteString
        XCTAssertTrue(absoluteString.contains("1422256900"))
    }
}
