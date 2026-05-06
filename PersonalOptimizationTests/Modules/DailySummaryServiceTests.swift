import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class DailySummaryServiceTests: XCTestCase {
    private let jst = TimeZone(identifier: "Asia/Tokyo")!
    private var container: ModelContainer!
    private var context: ModelContext!
    private var service: DailySummaryService!

    override func setUp() async throws {
        try await super.setUp()
        container = try InMemoryContainer.make()
        context = container.mainContext
        service = DailySummaryService(modelContext: context, timezone: jst)
    }

    override func tearDown() async throws {
        service = nil
        context = nil
        container = nil
        try await super.tearDown()
    }

    func test_emptyDay_nothingScheduled_returnsThreeAlwaysOnDomains() {
        // Wednesday 5/6/2026, no blocks seeded, no logs.
        let tally = service.todayProtocol(asOf: jstDate(2026, 5, 6, 14, 0))
        XCTAssertEqual(tally.domains.count, 4)
        // Workout is not scheduled when no training block exists.
        XCTAssertEqual(tally.scheduledCount, 3)
        XCTAssertEqual(tally.completedCount, 0)
    }

    func test_workoutScheduledNotDone_countsAsScheduled() {
        let block = ScheduleBlock(dayOfWeek: 3, startTime: "16:00", endTime: "17:00",
                                  activity: "Lift A", type: .training, module: "lift_a")
        context.insert(block)
        let tally = service.todayProtocol(asOf: jstDate(2026, 5, 6, 14, 0))
        XCTAssertEqual(tally.scheduledCount, 4)
        XCTAssertEqual(tally.completedCount, 0)
    }

    func test_workoutLogged_countsAsCompleted() throws {
        let block = ScheduleBlock(dayOfWeek: 3, startTime: "16:00", endTime: "17:00",
                                  activity: "Lift A", type: .training, module: "lift_a")
        context.insert(block)
        let day = jstDate(2026, 5, 6, 0, 0)
        context.insert(WorkoutEvent(date: day, completed: true, source: .lift))
        try context.save()
        let tally = service.todayProtocol(asOf: jstDate(2026, 5, 6, 14, 0))
        XCTAssertEqual(tally.completedCount, 1)
    }

    func test_allDomainsCompleted_returnsFullAdherence() throws {
        let block = ScheduleBlock(dayOfWeek: 3, startTime: "16:00", endTime: "17:00",
                                  activity: "Lift A", type: .training, module: "lift_a")
        context.insert(block)
        let day = jstDate(2026, 5, 6, 0, 0)
        context.insert(WorkoutEvent(date: day, completed: true, source: .lift))
        let log = DailyLog(date: day)
        log.fastEnd = jstDate(2026, 5, 6, 10, 0)
        log.waterOz = 100
        log.japaneseMinutes = 35
        context.insert(log)
        try context.save()
        let tally = service.todayProtocol(asOf: jstDate(2026, 5, 6, 14, 0))
        XCTAssertEqual(tally.completedCount, 4)
        XCTAssertEqual(tally.scheduledCount, 4)
        XCTAssertEqual(tally.displayText, "4/4 of today's protocol complete")
    }

    func test_travelMode_marksAllScheduledDomainsCompleted() throws {
        let profile = UserProfile()
        profile.travelModeActiveUntil = jstDate(2026, 5, 12, 23, 59)
        context.insert(profile)
        let block = ScheduleBlock(dayOfWeek: 3, startTime: "16:00", endTime: "17:00",
                                  activity: "Lift A", type: .training, module: "lift_a")
        context.insert(block)
        try context.save()
        let tally = service.todayProtocol(asOf: jstDate(2026, 5, 6, 14, 0))
        XCTAssertEqual(tally.completedCount, 4)
    }

    func test_partialCompletion_reportsCorrectFraction() throws {
        let day = jstDate(2026, 5, 6, 0, 0)
        let log = DailyLog(date: day)
        log.waterOz = 80
        log.fastEnd = nil
        context.insert(log)
        try context.save()
        let tally = service.todayProtocol(asOf: jstDate(2026, 5, 6, 14, 0))
        XCTAssertEqual(tally.scheduledCount, 3)
        XCTAssertEqual(tally.completedCount, 1) // hydration only
    }

    private func jstDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = jst
        return cal.date(from: c)!
    }
}
