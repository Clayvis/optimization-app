import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class AdaptiveNotificationTimingTests: XCTestCase {
    private let jst = TimeZone(identifier: "Asia/Tokyo")!

    func test_coldStart_returnsNil() {
        let result = AdaptiveNotificationTiming.estimatePreferredTime(
            domain: .hydration,
            history: [],
            asOf: jstDate(2026, 5, 6, 14, 0),
            timezone: jst
        )
        XCTAssertNil(result)
    }

    func test_thirteenDays_isInsufficient() {
        let history = (0..<13).map { offset in
            CompletionHistory(domain: .hydration, timestamp: jstDate(2026, 5, 6 - offset, 9, 0))
        }
        let result = AdaptiveNotificationTiming.estimatePreferredTime(
            domain: .hydration,
            history: history,
            asOf: jstDate(2026, 5, 6, 14, 0),
            timezone: jst
        )
        XCTAssertNil(result)
    }

    func test_fourteenDays_returnsMedianTimeOnTodaysDate() {
        // 14 days, all logged at 09:30 JST.
        let history = (0..<14).map { offset in
            CompletionHistory(domain: .hydration, timestamp: jstDate(2026, 4, 23 + offset, 9, 30))
        }
        let result = AdaptiveNotificationTiming.estimatePreferredTime(
            domain: .hydration,
            history: history,
            asOf: jstDate(2026, 5, 6, 14, 0),
            timezone: jst
        )
        XCTAssertNotNil(result)
        if let time = result {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = jst
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: time)
            XCTAssertEqual(comps.year, 2026)
            XCTAssertEqual(comps.month, 5)
            XCTAssertEqual(comps.day, 6)
            XCTAssertEqual(comps.hour, 9)
            XCTAssertEqual(comps.minute, 30)
        }
    }

    func test_suppressIfAlreadyLogged_today_returnsTrue() {
        let history = [CompletionHistory(domain: .fasting, timestamp: jstDate(2026, 5, 6, 10, 0))]
        let suppress = AdaptiveNotificationTiming.shouldSuppressIfAlreadyLogged(
            domain: .fasting,
            history: history,
            asOf: jstDate(2026, 5, 6, 14, 0),
            timezone: jst
        )
        XCTAssertTrue(suppress)
    }

    func test_suppressIfAlreadyLogged_yesterdayOnly_returnsFalse() {
        let history = [CompletionHistory(domain: .fasting, timestamp: jstDate(2026, 5, 5, 10, 0))]
        let suppress = AdaptiveNotificationTiming.shouldSuppressIfAlreadyLogged(
            domain: .fasting,
            history: history,
            asOf: jstDate(2026, 5, 6, 14, 0),
            timezone: jst
        )
        XCTAssertFalse(suppress)
    }

    func test_completionHistoryWriter_persistsRow() throws {
        let container = try InMemoryContainer.make()
        let context = container.mainContext
        CompletionHistoryWriter.record(domain: .hydration, at: jstDate(2026, 5, 6, 9, 0), modelContext: context)
        let rows = try context.fetch(FetchDescriptor<CompletionHistory>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.domain, "hydration")
    }

    private func jstDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = jst
        return cal.date(from: c)!
    }
}
