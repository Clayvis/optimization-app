import XCTest
import SwiftData
@testable import PersonalOptimization

/// Covers the fail-soft fetch helpers added in Item 16. Logger output is
/// not asserted here (os.Logger doesn't expose a programmatic readback);
/// the happy-path coverage proves the helpers return the same results as
/// `try? ctx.fetch(d)` would for the successful case.
@MainActor
final class SwiftDataHelpersTests: XCTestCase {

    func test_fetchOrEmpty_returnsResults() throws {
        let container = try InMemoryContainer.make()
        let ctx = container.mainContext
        let profile = UserProfile(name: "T", dob: Date(timeIntervalSince1970: 0), sex: "male")
        ctx.insert(profile)
        try ctx.save()
        let results = ctx.fetchOrEmpty(FetchDescriptor<UserProfile>())
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.name, "T")
    }

    func test_fetchOrEmpty_returnsEmptyWhenStoreEmpty() throws {
        let container = try InMemoryContainer.make()
        let results = container.mainContext.fetchOrEmpty(FetchDescriptor<UserProfile>())
        XCTAssertTrue(results.isEmpty)
    }

    func test_fetchFirstOrNil_returnsFirstWhenPresent() throws {
        let container = try InMemoryContainer.make()
        let ctx = container.mainContext
        ctx.insert(UserProfile(name: "First", dob: Date(timeIntervalSince1970: 0), sex: "male"))
        try ctx.save()
        let first = ctx.fetchFirstOrNil(FetchDescriptor<UserProfile>())
        XCTAssertEqual(first?.name, "First")
    }

    func test_fetchFirstOrNil_returnsNilWhenEmpty() throws {
        let container = try InMemoryContainer.make()
        let first = container.mainContext.fetchFirstOrNil(FetchDescriptor<UserProfile>())
        XCTAssertNil(first)
    }

    func test_fetchCountOrZero_returnsRowCount() throws {
        let container = try InMemoryContainer.make()
        let ctx = container.mainContext
        for i in 0..<3 {
            ctx.insert(UserProfile(name: "U\(i)", dob: Date(timeIntervalSince1970: 0), sex: "male"))
        }
        try ctx.save()
        XCTAssertEqual(ctx.fetchCountOrZero(FetchDescriptor<UserProfile>()), 3)
    }

    func test_fetchCountOrZero_returnsZeroWhenEmpty() throws {
        let container = try InMemoryContainer.make()
        XCTAssertEqual(container.mainContext.fetchCountOrZero(FetchDescriptor<UserProfile>()), 0)
    }
}
