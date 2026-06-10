import XCTest
@testable import PersonalOptimization

/// The single shared definition of the protocol's per-day rules. Every surface
/// (streaks, tally, snapshot, trends, registries, complication) delegates here,
/// so these tests pin the behavior all of them inherit.
///
/// @MainActor because the hydration assertions read `ScheduleConfigLoader
/// .loadCached()`, which caches in a main-actor static.
@MainActor
final class ProtocolRulesTests: XCTestCase {

    private var gregorianUTC: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        gregorianUTC.date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"), year: y, month: m, day: d))!
    }

    // MARK: - ISO weekday

    func testIsoWeekdayMondayIsOneSundayIsSeven() {
        // 2026-06-08 is a Monday, 2026-06-14 is a Sunday.
        XCTAssertEqual(ProtocolRules.isoWeekday(for: date(2026, 6, 8), calendar: gregorianUTC), 1)
        XCTAssertEqual(ProtocolRules.isoWeekday(for: date(2026, 6, 14), calendar: gregorianUTC), 7)
    }

    // MARK: - Learning

    func testLearningMinutesSumsAllFourModules() {
        XCTAssertEqual(
            ProtocolRules.learningMinutes(japanese: 10, guitar: 5, coursework: 7, music: 3),
            25
        )
    }

    func testLearningDoneThresholds() {
        // Single module clears its own threshold.
        XCTAssertTrue(ProtocolRules.learningDone(japanese: 30, guitar: 0, coursework: 0, music: 0))
        XCTAssertTrue(ProtocolRules.learningDone(japanese: 0, guitar: 20, coursework: 0, music: 0))
        XCTAssertTrue(ProtocolRules.learningDone(japanese: 0, guitar: 0, coursework: 20, music: 0))
        XCTAssertTrue(ProtocolRules.learningDone(japanese: 0, guitar: 0, coursework: 0, music: 20))
        // Japanese below 30 but total reaches 20.
        XCTAssertTrue(ProtocolRules.learningDone(japanese: 12, guitar: 0, coursework: 0, music: 8))
        // Nothing clears and total < 20.
        XCTAssertFalse(ProtocolRules.learningDone(japanese: 10, guitar: 5, coursework: 0, music: 0))
        XCTAssertFalse(ProtocolRules.learningDone(japanese: 0, guitar: 0, coursework: 0, music: 0))
    }

    func testMusicCountsTowardTotalRegressionForRegistries() {
        // The registries previously omitted music; the shared rule includes it.
        // 19 non-music + 1 music = 20 total => done.
        XCTAssertTrue(ProtocolRules.learningDone(japanese: 19, guitar: 0, coursework: 0, music: 1))
    }

    // MARK: - Hydration target

    private func targets() -> HydrationTargetsOz? {
        // try? justified - bundled resource present in the test target.
        try? ScheduleConfigLoader.loadCached().hydrationTargetsOz
    }

    func testHydrationTargetNilTargetsFallsBackTo64() {
        XCTAssertEqual(
            ProtocolRules.hydrationTargetMin(for: date(2026, 6, 8), targets: nil, calendar: gregorianUTC),
            64
        )
    }

    func testHydrationTargetResolvesADayType() throws {
        let t = try XCTUnwrap(targets(), "bundled schedule config should load in tests")
        let value = ProtocolRules.hydrationTargetMin(for: date(2026, 6, 8), targets: t, calendar: gregorianUTC)
        // Whatever the day type, the floor is one of the configured minimums.
        let configured = [t.basketball.min, t.swim.min, t.lift.min, t.rest.min]
        XCTAssertTrue(configured.contains(value), "resolved \(value) not among \(configured)")
        XCTAssertGreaterThanOrEqual(value, 64, "every day-type floor is at least the base 64oz")
    }
}
