import XCTest
@testable import PersonalOptimization

@MainActor
final class LearningReminderSchedulerTests: XCTestCase {
    private let jst = TimeZone(identifier: "Asia/Tokyo")!

    private func loadFile() throws -> DefaultScheduleFile {
        let bundle = ScheduleSeedTests.resourceBundle()
        return try ScheduleSeed.loadDefaultScheduleFile(bundle: bundle)
    }

    // MARK: - plannedTimes

    func test_plannedTimes_includesJapaneseTimesFromSchedule() throws {
        let file = try loadFile()
        let times = LearningReminderScheduler.plannedTimes(scheduleFile: file)

        let japanese = times.filter { $0.module == .japanese }
        XCTAssertFalse(japanese.isEmpty)

        // Wed (3) at 14:00 is one of the Japanese blocks per default_schedule.json.
        let hasWed14 = japanese.contains { $0.isoWeekday == 3 && $0.hour == 14 && $0.minute == 0 }
        XCTAssertTrue(hasWed14, "Expected Japanese reminder Wed 14:00")
    }

    func test_plannedTimes_guitarHas5Weekday1600And2Weekend1900() throws {
        let file = try loadFile()
        let times = LearningReminderScheduler.plannedTimes(scheduleFile: file)
        let guitar = times.filter { $0.module == .guitar }

        let weekday1600 = guitar.filter { (1...5).contains($0.isoWeekday) && $0.hour == 16 && $0.minute == 0 }
        let weekend1900 = guitar.filter { [6, 7].contains($0.isoWeekday) && $0.hour == 19 && $0.minute == 0 }

        XCTAssertEqual(weekday1600.count, 5)
        XCTAssertEqual(weekend1900.count, 2)
    }

    // MARK: - upcomingDates

    func test_upcomingDates_startingFromMonday_returnsTodayLater() {
        let times = [
            LearningReminderTime(module: .guitar, isoWeekday: 1, hour: 16, minute: 0)
        ]
        let monday0900 = jstDate(2026, 5, 4, 9, 0)
        let result = LearningReminderScheduler.upcomingDates(from: times, startingFrom: monday0900, timezone: jst)
        XCTAssertEqual(result.count, 1)
        let scheduled = result[0].1
        XCTAssertGreaterThan(scheduled, monday0900)
    }

    func test_upcomingDates_startingFromAfterTime_skipsToday() {
        let times = [
            LearningReminderTime(module: .guitar, isoWeekday: 1, hour: 16, minute: 0)
        ]
        let monday1700 = jstDate(2026, 5, 4, 17, 0)
        let result = LearningReminderScheduler.upcomingDates(from: times, startingFrom: monday1700, timezone: jst)
        XCTAssertTrue(result.isEmpty, "Should skip today's 16:00 because we're already past it")
    }

    func test_upcomingDates_doesNotCreateDuplicatesAcrossWeek() throws {
        let file = try loadFile()
        let times = LearningReminderScheduler.plannedTimes(scheduleFile: file)
        let monday0000 = jstDate(2026, 5, 4, 0, 0)
        let result = LearningReminderScheduler.upcomingDates(from: times, startingFrom: monday0000, timezone: jst)

        // Verify no two pairs have the same scheduled date.
        let dates = result.map { $0.1 }
        XCTAssertEqual(dates.count, Set(dates).count)
    }

    private func jstDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = jst
        return cal.date(from: c)!
    }
}
