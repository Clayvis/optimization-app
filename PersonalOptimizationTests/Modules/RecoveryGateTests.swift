import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class RecoveryGateTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var gate: RecoveryGate!
    private let jst = TimeZone(identifier: "Asia/Tokyo")!

    override func setUp() async throws {
        try await super.setUp()
        container = try InMemoryContainer.make()
        context = container.mainContext
        gate = RecoveryGate(modelContext: context, timezone: jst)
    }

    override func tearDown() async throws {
        gate = nil
        context = nil
        container = nil
        try await super.tearDown()
    }

    func test_emptyData_returnsNormal() {
        let profile = UserProfile()
        context.insert(profile)
        let status = gate.evaluate(profile: profile)
        XCTAssertEqual(status.recommendation, .normal)
    }

    func test_lowSleep_returnsDowngrade() throws {
        let profile = UserProfile()
        context.insert(profile)
        let log = DailyLog(date: Calendar(identifier: .gregorian).startOfDay(for: Date()))
        log.sleepHours = 5.0
        context.insert(log)
        try context.save()

        let status = gate.evaluate(profile: profile)
        XCTAssertEqual(status.recommendation, .downgrade)
    }

    func test_veryLowSleep_returnsRest() throws {
        let profile = UserProfile()
        context.insert(profile)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = jst
        let log = DailyLog(date: cal.startOfDay(for: Date()))
        log.sleepHours = 4.0
        context.insert(log)
        try context.save()

        let status = gate.evaluate(profile: profile)
        XCTAssertEqual(status.recommendation, .rest)
    }

    func test_highAchillesPain_returnsRest() throws {
        let profile = UserProfile()
        context.insert(profile)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = jst
        let log = DailyLog(date: cal.startOfDay(for: Date()))
        log.achillesPain = 8
        context.insert(log)
        try context.save()

        let status = gate.evaluate(profile: profile)
        XCTAssertEqual(status.recommendation, .rest)
    }

    func test_moderateAchillesPain_returnsDowngrade() throws {
        let profile = UserProfile()
        context.insert(profile)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = jst
        let log = DailyLog(date: cal.startOfDay(for: Date()))
        log.achillesPain = 5
        context.insert(log)
        try context.save()

        let status = gate.evaluate(profile: profile)
        XCTAssertEqual(status.recommendation, .downgrade)
    }

    func test_recordOverride_incrementsCounter() throws {
        let profile = UserProfile()
        context.insert(profile)
        try context.save()
        XCTAssertEqual(profile.recoveryOverrideCountThisMonth, 0)
        gate.recordOverride(profile: profile)
        XCTAssertEqual(profile.recoveryOverrideCountThisMonth, 1)
        gate.recordOverride(profile: profile)
        XCTAssertEqual(profile.recoveryOverrideCountThisMonth, 2)
    }
}
