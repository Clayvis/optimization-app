import XCTest
@testable import PersonalOptimization

@MainActor
final class ActiveStatusServiceTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return cal
    }

    private func at(_ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: hour, minute: minute))!
    }

    private let practiceDay = [
        StatusBlock(activity: "Japanese study", startTime: "06:00", endTime: "06:30", module: "japanese"),
        StatusBlock(activity: "Lift A", startTime: "10:00", endTime: "11:00", module: "lift_a"),
        StatusBlock(activity: "Guitar", startTime: "16:00", endTime: "16:20", module: "guitar")
    ]

    func test_currentBlockLeadsAndStaysFreshUntilItEnds() {
        let content = ActiveStatusService.compose(blocks: practiceDay, practiceMinutes: [.japanese: 10],
                                                  moveKcal: 312.4, asOf: at(10, 15), calendar: calendar)
        XCTAssertEqual(content.message, "Now: Lift A · Japanese 10/30 min · Guitar 0/20 min · Move 312 kcal")
        XCTAssertEqual(content.freshUntil, at(11, 0))
    }

    func test_betweenBlocksShowsNextAndTurnsStaleWhenItStarts() {
        let content = ActiveStatusService.compose(blocks: practiceDay, practiceMinutes: [:],
                                                  moveKcal: nil, asOf: at(12, 0), calendar: calendar)
        XCTAssertEqual(content.message, "Next: Guitar at 16:00 · Japanese 0/30 min · Guitar 0/20 min")
        XCTAssertEqual(content.freshUntil, at(16, 0))
    }

    func test_practiceTargetsFollowTheUsersOwnSchedule() {
        // A tester without Japanese or guitar blocks never sees those targets.
        let blocks = [StatusBlock(activity: "Walk", startTime: "07:00", endTime: "07:30", module: nil)]
        let content = ActiveStatusService.compose(blocks: blocks, practiceMinutes: [.japanese: 0, .guitar: 0, .music: 0],
                                                  moveKcal: 120, asOf: at(8, 0), calendar: calendar)
        XCTAssertEqual(content.message, "Move 120 kcal")
        XCTAssertNil(content.freshUntil)
    }

    func test_loggedPracticeShowsEvenWhenUnscheduled() {
        let content = ActiveStatusService.compose(blocks: [], practiceMinutes: [.music: 15],
                                                  moveKcal: nil, asOf: at(20, 0), calendar: calendar)
        XCTAssertEqual(content.message, "Music 15/20 min")
    }

    func test_emptyDayHasNoMessageOrDeadline() {
        let content = ActiveStatusService.compose(blocks: [], practiceMinutes: [:],
                                                  moveKcal: nil, asOf: at(9, 0), calendar: calendar)
        XCTAssertNil(content.message)
        XCTAssertNil(content.freshUntil)
    }
}
