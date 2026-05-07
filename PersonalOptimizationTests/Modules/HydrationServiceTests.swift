import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class HydrationServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var service: HydrationService!
    private let jst = TimeZone(identifier: "Asia/Tokyo")!

    private static let fixtureTargets: HydrationTargetsOz = {
        let json = """
        {
          "rest":       { "min": 110, "max": 130, "appliesTo": [3, 7] },
          "lift":       { "min": 140, "max": 160, "appliesTo": [1, 5] },
          "basketball": { "min": 160, "max": 190, "appliesTo": [2, 4] },
          "swim":       { "min": 120, "max": 140, "appliesTo": [3] }
        }
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(HydrationTargetsOz.self, from: json)
    }()

    override func setUp() async throws {
        try await super.setUp()
        container = try InMemoryContainer.make()
        context = container.mainContext
        service = HydrationService(modelContext: context, timezone: jst, targets: Self.fixtureTargets)
    }

    override func tearDown() async throws {
        service = nil
        context = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: - dayType

    func test_dayType_monday_isLift() {
        XCTAssertEqual(service.dayType(for: jstDate(2026, 5, 4, 12, 0)), .lift)
    }

    func test_dayType_tuesday_isBasketball() {
        XCTAssertEqual(service.dayType(for: jstDate(2026, 5, 5, 12, 0)), .basketball)
    }

    func test_dayType_wednesday_priorityPicksSwimOverRest() {
        XCTAssertEqual(service.dayType(for: jstDate(2026, 5, 6, 12, 0)), .swim)
    }

    func test_dayType_thursday_isBasketball() {
        XCTAssertEqual(service.dayType(for: jstDate(2026, 5, 7, 12, 0)), .basketball)
    }

    func test_dayType_friday_isLift() {
        XCTAssertEqual(service.dayType(for: jstDate(2026, 5, 8, 12, 0)), .lift)
    }

    func test_dayType_saturday_fallsBackToRest() {
        // Saturday is not in any appliesTo, default to rest.
        XCTAssertEqual(service.dayType(for: jstDate(2026, 5, 9, 12, 0)), .rest)
    }

    func test_dayType_sunday_isRest() {
        XCTAssertEqual(service.dayType(for: jstDate(2026, 5, 10, 12, 0)), .rest)
    }

    // MARK: - targetRange

    func test_targetRange_lift_140to160() {
        XCTAssertEqual(service.targetRange(for: jstDate(2026, 5, 4, 12, 0)), 140...160)
    }

    func test_targetRange_basketball_160to190() {
        XCTAssertEqual(service.targetRange(for: jstDate(2026, 5, 5, 12, 0)), 160...190)
    }

    func test_targetRange_swim_120to140() {
        XCTAssertEqual(service.targetRange(for: jstDate(2026, 5, 6, 12, 0)), 120...140)
    }

    // MARK: - logBottle

    func test_logBottle_createsDailyLogWithAmount() throws {
        let date = jstDate(2026, 5, 4, 9, 0)
        try service.logBottle(oz: 16, at: date)

        let logs = try context.fetch(FetchDescriptor<DailyLog>())
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.waterOz, 16)
    }

    func test_logBottle_accumulatesAcrossMultipleCalls() throws {
        let date = jstDate(2026, 5, 4, 9, 0)
        try service.logBottle(oz: 16, at: date)
        try service.logBottle(oz: 24, at: date.addingTimeInterval(3600))
        try service.logBottle(oz: 32, at: date.addingTimeInterval(7200))

        let logs = try context.fetch(FetchDescriptor<DailyLog>())
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.waterOz, 72)
    }

    func test_logBottle_separatesDays() throws {
        let monday = jstDate(2026, 5, 4, 9, 0)
        let tuesday = jstDate(2026, 5, 5, 9, 0)
        try service.logBottle(oz: 16, at: monday)
        try service.logBottle(oz: 24, at: tuesday)

        let logs = try context.fetch(FetchDescriptor<DailyLog>(sortBy: [SortDescriptor(\.date)]))
        XCTAssertEqual(logs.count, 2)
        XCTAssertEqual(logs.first?.waterOz, 16)
        XCTAssertEqual(logs.last?.waterOz, 24)
    }

    // MARK: - logElectrolyte

    func test_logElectrolyte_incrementsCounter() throws {
        let date = jstDate(2026, 5, 4, 9, 0)
        try service.logElectrolyte(at: date)
        try service.logElectrolyte(at: date)
        try service.logElectrolyte(at: date)

        let logs = try context.fetch(FetchDescriptor<DailyLog>())
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.electrolyteSessions, 3)
    }

    // MARK: - intakeForDay & electrolyteCount

    func test_intakeForDay_emptyDay_returnsZero() {
        XCTAssertEqual(service.intakeForDay(of: jstDate(2026, 5, 4, 12, 0)), 0)
    }

    func test_intakeForDay_returnsLoggedTotal() throws {
        let date = jstDate(2026, 5, 4, 9, 0)
        try service.logBottle(oz: 16, at: date)
        try service.logBottle(oz: 24, at: date)
        XCTAssertEqual(service.intakeForDay(of: date), 40)
    }

    func test_electrolyteCount_returnsLoggedSessions() throws {
        let date = jstDate(2026, 5, 4, 9, 0)
        try service.logElectrolyte(at: date)
        try service.logElectrolyte(at: date)
        XCTAssertEqual(service.electrolyteCount(for: date), 2)
    }

    // MARK: - Edit / delete (M3.7+ pass)

    func test_updateEntry_adjustsDailyLogWaterOz() throws {
        let date = jstDate(2026, 5, 8, 9, 0)
        let log1 = try service.logBeverage(amountOz: 16, beverageType: .water, at: date)
        XCTAssertEqual(log1.waterOz, 16)

        let entries = service.entriesForDay(of: date)
        let entry = try XCTUnwrap(entries.first)

        try service.updateEntry(entry, newAmountOz: 20, newBeverageType: .water)
        let log2 = try XCTUnwrap(service.entriesForDay(of: date).first)
        XCTAssertEqual(log2.amountOz, 20)
        XCTAssertEqual(service.intakeForDay(of: date), 20)
    }

    func test_updateEntry_changingBeverageRecomputesEffectiveOz() throws {
        let date = jstDate(2026, 5, 8, 9, 0)
        _ = try service.logBeverage(amountOz: 10, beverageType: .water, at: date)
        let entry = try XCTUnwrap(service.entriesForDay(of: date).first)

        try service.updateEntry(entry, newAmountOz: 10, newBeverageType: .coffee)
        // Coffee coefficient 0.8 → 8 effective oz.
        XCTAssertEqual(service.intakeForDay(of: date), 8, accuracy: 0.001)
    }

    func test_deleteEntry_rollsBackWaterOz() throws {
        let date = jstDate(2026, 5, 8, 9, 0)
        _ = try service.logBeverage(amountOz: 16, beverageType: .water, at: date)
        _ = try service.logBeverage(amountOz: 8, beverageType: .water, at: date)
        XCTAssertEqual(service.intakeForDay(of: date), 24)

        let entries = service.entriesForDay(of: date)
        let toDelete = try XCTUnwrap(entries.first { $0.amountOz == 16 })
        try service.deleteEntry(toDelete)
        XCTAssertEqual(service.intakeForDay(of: date), 8)
    }

    func test_deleteEntry_electrolyte_decrementsSessionCount() throws {
        let date = jstDate(2026, 5, 8, 9, 0)
        _ = try service.logElectrolyte(at: date, servingOz: 16)
        XCTAssertEqual(service.electrolyteCount(for: date), 1)

        let entry = try XCTUnwrap(service.entriesForDay(of: date).first)
        try service.deleteEntry(entry)
        XCTAssertEqual(service.electrolyteCount(for: date), 0)
    }

    // MARK: - Helpers

    private func jstDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = jst
        return cal.date(from: c)!
    }
}
