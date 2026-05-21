import XCTest
import SwiftData
@testable import PersonalOptimization

/// Daylight saving boundary coverage. JST never observes DST so the codebase
/// has no DST tests in tree. The user (and partner) will travel to the US
/// where Pacific time observes spring-forward and fall-back. These tests
/// pin the behavior on dates where the wall-clock hour skips or repeats.
@MainActor
final class DSTBoundaryTests: XCTestCase {

    private let pacific = TimeZone(identifier: "America/Los_Angeles")!

    /// Spring forward in US/Pacific: March 8, 2026 at 02:00 PT → 03:00 PT
    /// (clocks skip 02:00–02:59).
    func test_dailyLogStore_acrossSpringForward_oneRowPerDay() throws {
        let container = try InMemoryContainer.make()
        let ctx = container.mainContext
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = pacific

        // Two writes both inside March 8 PT, straddling the 02:00→03:00 jump.
        let beforeJump = dateAt(year: 2026, month: 3, day: 8, hour: 1, in: pacific)
        let afterJump = dateAt(year: 2026, month: 3, day: 8, hour: 4, in: pacific)

        let store = DailyLogStore(modelContext: ctx, calendar: cal)
        let a = store.upsert(for: beforeJump)
        let b = store.upsert(for: afterJump)
        XCTAssertTrue(a === b, "Two upserts on the same PT day should collapse to one row even across spring-forward.")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<DailyLog>()).count, 1)
    }

    /// Fall back in US/Pacific: November 1, 2026 at 02:00 PDT → 01:00 PST
    /// (01:00–01:59 happens twice). A single PT calendar day still spans
    /// 25 wall-clock hours.
    func test_dailyLogStore_acrossFallBack_oneRowPerDay() throws {
        let container = try InMemoryContainer.make()
        let ctx = container.mainContext
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = pacific

        // Both inside Nov 1 PT, one before the fall-back, one after.
        let beforeFallBack = dateAt(year: 2026, month: 11, day: 1, hour: 0, in: pacific)
        let afterFallBack = dateAt(year: 2026, month: 11, day: 1, hour: 23, in: pacific)

        let store = DailyLogStore(modelContext: ctx, calendar: cal)
        let a = store.upsert(for: beforeFallBack)
        let b = store.upsert(for: afterFallBack)
        XCTAssertTrue(a === b, "Two upserts on the same PT day should collapse across fall-back.")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<DailyLog>()).count, 1)
    }

    /// Day boundary math across spring forward: startOfDay applied twice
    /// should produce the same key for any instant within the same PT day.
    func test_startOfDay_idempotent_acrossSpringForward() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = pacific
        let before = dateAt(year: 2026, month: 3, day: 8, hour: 1, in: pacific)
        let after = dateAt(year: 2026, month: 3, day: 8, hour: 23, in: pacific)
        XCTAssertEqual(cal.startOfDay(for: before), cal.startOfDay(for: after))
    }

    /// AdaptiveNotificationTiming computes minutes-from-midnight in local
    /// time. Same wall-clock hour-of-day before and after DST should map to
    /// the same minutes-from-midnight regardless of UTC offset shift.
    func test_minutesFromMidnight_acrossDST() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = pacific
        // 08:30 PT on March 7 (PST) and on March 9 (PDT) — same wall-clock,
        // different UTC offsets.
        let preDST = dateAt(year: 2026, month: 3, day: 7, hour: 8, minute: 30, in: pacific)
        let postDST = dateAt(year: 2026, month: 3, day: 9, hour: 8, minute: 30, in: pacific)
        let preComps = cal.dateComponents([.hour, .minute], from: preDST)
        let postComps = cal.dateComponents([.hour, .minute], from: postDST)
        let preMinutes = (preComps.hour ?? 0) * 60 + (preComps.minute ?? 0)
        let postMinutes = (postComps.hour ?? 0) * 60 + (postComps.minute ?? 0)
        XCTAssertEqual(preMinutes, postMinutes, "Same wall-clock hour should yield same minutes-from-midnight across DST.")
        XCTAssertEqual(preMinutes, 8 * 60 + 30)
    }

    // MARK: - Helpers

    private func dateAt(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0, in tz: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        return cal.date(from: comps) ?? Date()
    }
}
