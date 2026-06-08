import XCTest
@testable import PersonalOptimization

/// Unit tests for the goal-gradient "one more to close" helper. Pure struct, no
/// SwiftData needed.
final class ProtocolAdherenceTallyTests: XCTestCase {

    private func domain(_ d: StreakDomain, label: String, scheduled: Bool, completed: Bool) -> ProtocolDomainResult {
        ProtocolDomainResult(domain: d, label: label, scheduled: scheduled, completed: completed, detail: "")
    }

    func test_oneMoreToClose_namesSingleRemainingDomain() {
        let tally = ProtocolAdherenceTally(date: Date(), domains: [
            domain(.hydration, label: "Hydration", scheduled: true, completed: true),
            domain(.learning, label: "Learning", scheduled: true, completed: false),
            domain(.fasting, label: "Fasting", scheduled: false, completed: false)
        ])
        XCTAssertEqual(tally.oneMoreToClose?.label, "Learning")
    }

    func test_oneMoreToClose_nilWhenTwoRemain() {
        let tally = ProtocolAdherenceTally(date: Date(), domains: [
            domain(.hydration, label: "Hydration", scheduled: true, completed: false),
            domain(.learning, label: "Learning", scheduled: true, completed: false)
        ])
        XCTAssertNil(tally.oneMoreToClose)
    }

    func test_oneMoreToClose_nilWhenAllComplete() {
        let tally = ProtocolAdherenceTally(date: Date(), domains: [
            domain(.hydration, label: "Hydration", scheduled: true, completed: true)
        ])
        XCTAssertNil(tally.oneMoreToClose)
    }

    func test_oneMoreToClose_ignoresUnscheduledIncompleteDomains() {
        let tally = ProtocolAdherenceTally(date: Date(), domains: [
            domain(.hydration, label: "Hydration", scheduled: true, completed: false),
            domain(.workout, label: "Workout", scheduled: false, completed: false)
        ])
        XCTAssertEqual(tally.oneMoreToClose?.label, "Hydration")
    }
}
