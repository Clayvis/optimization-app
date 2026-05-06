import XCTest
import SwiftData
@testable import PersonalOptimization

final class LearningStreakCalculatorTests: XCTestCase {
    private let jst = TimeZone(identifier: "Asia/Tokyo")!

    func test_currentStreak_consecutiveDaysAtThreshold_increments() {
        let asOf = jstDate(2026, 5, 6, 10, 0)
        let hist = [
            DailyMinutes(date: jstDate(2026, 5, 4, 10, 0), minutes: 30),  // Mon, met
            DailyMinutes(date: jstDate(2026, 5, 5, 10, 0), minutes: 35),  // Tue, met
            DailyMinutes(date: jstDate(2026, 5, 6, 10, 0), minutes: 30),  // Wed, met (today)
        ]
        XCTAssertEqual(LearningStreakCalculator.currentStreak(history: hist, threshold: 30, asOf: asOf, timezone: jst), 3)
    }

    func test_currentStreak_todayBelowThreshold_doesNotBreakStreak() {
        let asOf = jstDate(2026, 5, 6, 10, 0)
        let hist = [
            DailyMinutes(date: jstDate(2026, 5, 4, 10, 0), minutes: 30),
            DailyMinutes(date: jstDate(2026, 5, 5, 10, 0), minutes: 35),
            DailyMinutes(date: jstDate(2026, 5, 6, 10, 0), minutes: 5),   // today in progress
        ]
        XCTAssertEqual(LearningStreakCalculator.currentStreak(history: hist, threshold: 30, asOf: asOf, timezone: jst), 2)
    }

    func test_currentStreak_gapBreaksStreak() {
        let asOf = jstDate(2026, 5, 6, 10, 0)
        let hist = [
            DailyMinutes(date: jstDate(2026, 5, 3, 10, 0), minutes: 30),  // Sun
            // gap on Mon
            DailyMinutes(date: jstDate(2026, 5, 5, 10, 0), minutes: 35),  // Tue
            DailyMinutes(date: jstDate(2026, 5, 6, 10, 0), minutes: 35),  // Wed
        ]
        XCTAssertEqual(LearningStreakCalculator.currentStreak(history: hist, threshold: 30, asOf: asOf, timezone: jst), 2)
    }

    func test_currentStreak_emptyHistory_returnsZero() {
        let asOf = jstDate(2026, 5, 6, 10, 0)
        XCTAssertEqual(LearningStreakCalculator.currentStreak(history: [], threshold: 30, asOf: asOf, timezone: jst), 0)
    }

    func test_currentStreak_yesterdayMissedTodayMet_returns1() {
        let asOf = jstDate(2026, 5, 6, 10, 0)
        let hist = [
            DailyMinutes(date: jstDate(2026, 5, 5, 10, 0), minutes: 5),  // missed
            DailyMinutes(date: jstDate(2026, 5, 6, 10, 0), minutes: 30), // today met
        ]
        XCTAssertEqual(LearningStreakCalculator.currentStreak(history: hist, threshold: 30, asOf: asOf, timezone: jst), 1)
    }

    func test_longestStreak_findsLongestRun() {
        let hist = [
            DailyMinutes(date: jstDate(2026, 4, 1, 10, 0), minutes: 30),
            DailyMinutes(date: jstDate(2026, 4, 2, 10, 0), minutes: 30),
            DailyMinutes(date: jstDate(2026, 4, 3, 10, 0), minutes: 30),
            // gap
            DailyMinutes(date: jstDate(2026, 4, 5, 10, 0), minutes: 30),
            DailyMinutes(date: jstDate(2026, 4, 6, 10, 0), minutes: 30),
        ]
        XCTAssertEqual(LearningStreakCalculator.longestStreak(history: hist, threshold: 30, timezone: jst), 3)
    }

    func test_perf_currentStreak_365DayWindow_under20ms() {
        var hist: [DailyMinutes] = []
        let baseDate = jstDate(2025, 5, 1, 10, 0)
        for offset in 0..<365 {
            let date = Calendar.current.date(byAdding: .day, value: offset, to: baseDate) ?? baseDate
            hist.append(DailyMinutes(date: date, minutes: 30))
        }
        let asOf = jstDate(2026, 4, 30, 10, 0)
        measure {
            for _ in 0..<10 {
                _ = LearningStreakCalculator.currentStreak(history: hist, threshold: 30, asOf: asOf, timezone: jst)
            }
        }
    }

    private func jstDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = jst
        return cal.date(from: c)!
    }
}

@MainActor
final class LearningServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var service: LearningService!
    private let jst = TimeZone(identifier: "Asia/Tokyo")!

    override func setUp() async throws {
        try await super.setUp()
        container = try InMemoryContainer.make()
        context = container.mainContext
        service = LearningService(modelContext: context, timezone: jst)
    }

    override func tearDown() async throws {
        service = nil
        context = nil
        container = nil
        try await super.tearDown()
    }

    func test_logMinutes_japanese_writesToDailyLog() throws {
        let date = jstDate(2026, 5, 6, 10, 0)
        try service.logMinutes(module: .japanese, minutes: 30, at: date)
        let logs = try context.fetch(FetchDescriptor<DailyLog>())
        XCTAssertEqual(logs.first?.japaneseMinutes, 30)
        XCTAssertEqual(logs.first?.guitarMinutes, 0)
    }

    func test_logMinutes_guitar_writesToDailyLog() throws {
        let date = jstDate(2026, 5, 6, 10, 0)
        try service.logMinutes(module: .guitar, minutes: 25, at: date)
        let logs = try context.fetch(FetchDescriptor<DailyLog>())
        XCTAssertEqual(logs.first?.guitarMinutes, 25)
    }

    func test_logMinutes_accumulatesAcrossCalls() throws {
        let date = jstDate(2026, 5, 6, 10, 0)
        try service.logMinutes(module: .japanese, minutes: 15, at: date)
        try service.logMinutes(module: .japanese, minutes: 20, at: date)
        let logs = try context.fetch(FetchDescriptor<DailyLog>())
        XCTAssertEqual(logs.first?.japaneseMinutes, 35)
    }

    func test_logMinutes_recomputesStreak() throws {
        let date = jstDate(2026, 5, 6, 10, 0)
        let yesterday = jstDate(2026, 5, 5, 10, 0)

        // Hit yesterday's threshold first.
        try service.logMinutes(module: .japanese, minutes: 30, at: yesterday)
        // Today: hit threshold.
        let streak = try service.logMinutes(module: .japanese, minutes: 30, at: date)
        XCTAssertEqual(streak.currentStreak, 2)
        XCTAssertEqual(streak.totalMinutesAllTime, 60)
    }

    func test_recomputeStreak_emptyHistory_returnsZero() throws {
        let streak = try service.recomputeStreak(module: .japanese, asOf: jstDate(2026, 5, 6, 10, 0))
        XCTAssertEqual(streak.currentStreak, 0)
        XCTAssertEqual(streak.longestStreak, 0)
    }

    func test_currentStreak_returnsLearningStreakEntity() {
        let streak = service.currentStreak(module: .guitar)
        XCTAssertEqual(streak.module, "guitar")
        XCTAssertEqual(streak.currentStreak, 0)
    }

    private func jstDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = jst
        return cal.date(from: c)!
    }
}
