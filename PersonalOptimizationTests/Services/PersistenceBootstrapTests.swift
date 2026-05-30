import XCTest
import SwiftData
@testable import PersonalOptimization

/// Covers the non-destructive store-open recovery ladder that replaced the
/// launch-time `fatalError`. The contract under test: a store that cannot be
/// opened must degrade to a launchable container instead of crashing, and must
/// never delete on-disk data.
@MainActor
final class PersistenceBootstrapTests: XCTestCase {

    private let dob = Date(timeIntervalSince1970: 764_985_600)

    // MARK: - PersistenceMode

    func testDurabilityMapping() {
        XCTAssertTrue(PersistenceMode.full.isDurable)
        XCTAssertTrue(PersistenceMode.localOnly(reason: "x").isDurable)
        XCTAssertFalse(PersistenceMode.recovery(reason: "x").isDurable,
                       "Recovery is in-memory; writes must not be treated as durable.")
    }

    // MARK: - In-memory rung

    func testInMemoryContainerRoundTrips() throws {
        let container = PersistenceBootstrap.inMemory()
        let context = container.mainContext
        context.insert(UserProfile(name: "Test", dob: dob, sex: "male"))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<UserProfile>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "Test")
    }

    // MARK: - Recovery ladder

    /// An on-disk store that cannot be created (path under /dev/null is not a
    /// directory) must NOT crash. Both disk rungs throw, so the ladder lands on
    /// the in-memory recovery rung, reports `.recovery`, and still hands back a
    /// usable container so the app can launch to a recovery screen.
    func testUnopenableStoreDegradesToRecoveryWithoutCrashing() throws {
        let unwritable = URL(fileURLWithPath: "/dev/null/PersonalOptimization/cannot.store")

        let bootstrap = PersistenceBootstrap.makeAppContainer(storeURL: unwritable)

        XCTAssertFalse(bootstrap.mode.isDurable)
        guard case .recovery = bootstrap.mode else {
            return XCTFail("Expected .recovery, got \(bootstrap.mode)")
        }

        // Container is launchable: an in-memory write/read round-trips, proving
        // the app would reach UI rather than crash.
        let context = bootstrap.container.mainContext
        context.insert(UserProfile(name: "Recovery", dob: dob, sex: "male"))
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<UserProfile>()).count, 1)
    }
}
