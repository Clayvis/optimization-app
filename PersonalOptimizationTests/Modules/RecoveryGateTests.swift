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

    // MARK: - evaluateDetailed (Gap 3 transparent breakdown)

    private func cal() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = jst
        return c
    }

    func test_detail_noData_hidesCard() throws {
        let profile = UserProfile()
        context.insert(profile)
        try context.save()
        let d = gate.evaluateDetailed(profile: profile)
        XCTAssertFalse(d.hasData)
        XCTAssertTrue(d.components.isEmpty)
    }

    func test_detail_hrvComponent_showsUnfavorableDownDirection() throws {
        let profile = UserProfile()
        context.insert(profile)
        let c = cal()
        let today = c.startOfDay(for: Date())
        for i in 1...4 {
            let log = DailyLog(date: c.date(byAdding: .day, value: -i, to: today)!)
            log.hrvRmssd = 58
            log.restingHR = 50
            log.sleepHours = 7.5
            context.insert(log)
        }
        let todayLog = DailyLog(date: today)
        todayLog.hrvRmssd = 42
        todayLog.restingHR = 50
        todayLog.sleepHours = 7.5
        context.insert(todayLog)
        try context.save()

        let d = gate.evaluateDetailed(profile: profile)
        XCTAssertTrue(d.hasData)
        let hrv = d.components.first { $0.label == "HRV" }
        XCTAssertEqual(hrv?.direction, .down)
        XCTAssertEqual(hrv?.isFavorable, false)
    }

    func test_detail_lowSleep_downgrade_reducesLoad() throws {
        let profile = UserProfile()
        context.insert(profile)
        let log = DailyLog(date: cal().startOfDay(for: Date()))
        log.sleepHours = 5.0
        context.insert(log)
        try context.save()

        let d = gate.evaluateDetailed(profile: profile)
        XCTAssertEqual(d.recommendation, .downgrade)
        XCTAssertEqual(d.loadMultiplier, 0.7, accuracy: 0.001)
        XCTAssertEqual(d.loadAdjustment, "Reduce today's load ~30%")
        XCTAssertEqual(d.headline, "Ease off today")
        let sleep = d.components.first { $0.label == "Sleep" }
        XCTAssertEqual(sleep?.isFavorable, false)
    }

    func test_detail_veryLowSleep_rest_loadZero() throws {
        let profile = UserProfile()
        context.insert(profile)
        let log = DailyLog(date: cal().startOfDay(for: Date()))
        log.sleepHours = 4.0
        context.insert(log)
        try context.save()

        let d = gate.evaluateDetailed(profile: profile)
        XCTAssertEqual(d.recommendation, .rest)
        XCTAssertEqual(d.loadMultiplier, 0.0, accuracy: 0.001)
        XCTAssertEqual(d.headline, "Rest day")
    }

    func test_detail_doesNotFabricateHRVorRHRfromBaseline() throws {
        let profile = UserProfile()
        context.insert(profile)
        let c = cal()
        let today = c.startOfDay(for: Date())
        for i in 1...4 {
            let log = DailyLog(date: c.date(byAdding: .day, value: -i, to: today)!)
            log.hrvRmssd = 58
            log.restingHR = 50
            log.sleepHours = 7.5
            context.insert(log)
        }
        let todayLog = DailyLog(date: today)
        todayLog.sleepHours = 7.5   // sleep synced today, but no HRV/RHR sample
        context.insert(todayLog)
        try context.save()

        let d = gate.evaluateDetailed(profile: profile)
        XCTAssertNil(d.components.first { $0.label == "HRV" }, "No HRV reading today; must not fabricate from baseline.")
        XCTAssertNil(d.components.first { $0.label == "Resting HR" })
        XCTAssertNotNil(d.components.first { $0.label == "Sleep" })
    }

    func test_detail_achillesOnly_isDataAndComponentShown() throws {
        let profile = UserProfile()
        context.insert(profile)
        let log = DailyLog(date: cal().startOfDay(for: Date()))
        log.achillesPain = 6   // no HRV/RHR/sleep today, only achilles
        context.insert(log)
        try context.save()

        let d = gate.evaluateDetailed(profile: profile)
        XCTAssertTrue(d.hasData, "Achilles pain is same-day data, so the card renders.")
        XCTAssertNotNil(d.components.first { $0.label == "Achilles" })
        XCTAssertEqual(d.recommendation, .downgrade)
    }

    func test_detail_normal_fullLoadAndData() throws {
        let profile = UserProfile()
        context.insert(profile)
        let log = DailyLog(date: cal().startOfDay(for: Date()))
        log.sleepHours = 7.5
        context.insert(log)
        try context.save()

        let d = gate.evaluateDetailed(profile: profile)
        XCTAssertEqual(d.recommendation, .normal)
        XCTAssertEqual(d.loadMultiplier, 1.0, accuracy: 0.001)
        XCTAssertEqual(d.headline, "Recovered")
        XCTAssertTrue(d.hasData)
    }
}
