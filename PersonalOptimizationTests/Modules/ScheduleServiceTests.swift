import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class ScheduleServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var service: ScheduleService!
    private let jst = TimeZone(identifier: "Asia/Tokyo")!

    override func setUp() async throws {
        try await super.setUp()
        container = try InMemoryContainer.make()
        context = container.mainContext
        try ScheduleSeed.seedIfNeeded(modelContext: context, bundle: ScheduleSeedTests.resourceBundle())
        service = ScheduleService(modelContext: context, timezone: jst)
    }

    override func tearDown() async throws {
        service = nil
        context = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: - parseTimeToMinutes

    func test_parseTimeToMinutes_validInput_returnsCorrectMinutes() {
        XCTAssertEqual(ScheduleService.parseTimeToMinutes("00:00"), 0)
        XCTAssertEqual(ScheduleService.parseTimeToMinutes("09:30"), 570)
        XCTAssertEqual(ScheduleService.parseTimeToMinutes("23:59"), 23 * 60 + 59)
    }

    func test_parseTimeToMinutes_invalidInput_returnsNil() {
        XCTAssertNil(ScheduleService.parseTimeToMinutes(""))
        XCTAssertNil(ScheduleService.parseTimeToMinutes("9:30:45"))
        XCTAssertNil(ScheduleService.parseTimeToMinutes("24:00"))
        XCTAssertNil(ScheduleService.parseTimeToMinutes("12:60"))
        XCTAssertNil(ScheduleService.parseTimeToMinutes("ab:cd"))
    }

    // MARK: - isoWeekday

    func test_isoWeekday_mapsCalendarWeekdayToISO() {
        // 2026-05-04 is a Monday in JST.
        let monday = jstDate(year: 2026, month: 5, day: 4, hour: 12, minute: 0)
        XCTAssertEqual(service.isoWeekday(for: monday), 1)

        // Sunday should be 7.
        let sunday = jstDate(year: 2026, month: 5, day: 3, hour: 12, minute: 0)
        XCTAssertEqual(service.isoWeekday(for: sunday), 7)
    }

    // MARK: - todayBlocks

    func test_todayBlocks_monday_returnsExactly8Blocks() {
        let monday = jstDate(year: 2026, month: 5, day: 4, hour: 12, minute: 0)
        let blocks = service.todayBlocks(for: monday)
        XCTAssertEqual(blocks.count, 8)
        XCTAssertEqual(blocks.first?.startTime, "09:00")
        XCTAssertEqual(blocks.last?.endTime, "17:00")
    }

    func test_todayBlocks_saturday_returnsTwoBlocks() {
        let saturday = jstDate(year: 2026, month: 5, day: 9, hour: 12, minute: 0)
        let blocks = service.todayBlocks(for: saturday)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks.first?.startTime, "07:00")
        XCTAssertEqual(blocks.last?.startTime, "19:00")
    }

    // MARK: - currentBlock

    func test_currentBlock_atMidBlock_returnsThatBlock() {
        // Monday 10:30 JST — should be inside the 09:30-11:00 lift_a block.
        let date = jstDate(year: 2026, month: 5, day: 4, hour: 10, minute: 30)
        let block = service.currentBlock(at: date)
        XCTAssertEqual(block?.module, "lift_a")
    }

    func test_currentBlock_atBlockStart_returnsThatBlock() {
        // Monday 09:00 — start of "Drop-off + drive to gym" (09:00-09:30 transit).
        let date = jstDate(year: 2026, month: 5, day: 4, hour: 9, minute: 0)
        let block = service.currentBlock(at: date)
        XCTAssertEqual(block?.activity, "Drop-off + drive to gym")
    }

    func test_currentBlock_atBlockEnd_returnsNextBlockOrGap() {
        // Monday 17:00 — Pickup prep ends, no later block. Should return nil.
        let date = jstDate(year: 2026, month: 5, day: 4, hour: 17, minute: 0)
        XCTAssertNil(service.currentBlock(at: date))
    }

    func test_currentBlock_inGap_returnsNil() {
        // Monday 18:00 — well past last scheduled block (17:00).
        let date = jstDate(year: 2026, month: 5, day: 4, hour: 18, minute: 0)
        XCTAssertNil(service.currentBlock(at: date))
    }

    func test_currentBlock_beforeFirstBlock_returnsNil() {
        // Monday 06:00 — before 09:00 first block.
        let date = jstDate(year: 2026, month: 5, day: 4, hour: 6, minute: 0)
        XCTAssertNil(service.currentBlock(at: date))
    }

    // MARK: - nextBlock

    func test_nextBlock_inGap_returnsLaterBlock() {
        // Monday 06:00 -> next block is 09:00 transit.
        let date = jstDate(year: 2026, month: 5, day: 4, hour: 6, minute: 0)
        let next = service.nextBlock(after: date)
        XCTAssertEqual(next?.startTime, "09:00")
    }

    func test_nextBlock_afterLast_returnsNil() {
        // Monday 18:00 -> no later block on this weekday.
        let date = jstDate(year: 2026, month: 5, day: 4, hour: 18, minute: 0)
        XCTAssertNil(service.nextBlock(after: date))
    }

    // MARK: - timeUntilNextTransition

    func test_timeUntilNextTransition_midBlock_returnsTimeToBlockEnd() throws {
        // Monday 10:00 — 09:30-11:00 lift block. End is 11:00. 60 minutes = 3600s.
        let date = jstDate(year: 2026, month: 5, day: 4, hour: 10, minute: 0)
        let interval = try XCTUnwrap(service.timeUntilNextTransition(from: date))
        XCTAssertEqual(interval, 3600, accuracy: 1)
    }

    func test_timeUntilNextTransition_inGap_returnsTimeToNextStart() throws {
        // Monday 06:30 -> 09:00 = 150 min = 9000s.
        let date = jstDate(year: 2026, month: 5, day: 4, hour: 6, minute: 30)
        let interval = try XCTUnwrap(service.timeUntilNextTransition(from: date))
        XCTAssertEqual(interval, 9000, accuracy: 1)
    }

    func test_timeUntilNextTransition_afterLast_returnsNil() {
        // Monday 17:00 — no later boundary today.
        let date = jstDate(year: 2026, month: 5, day: 4, hour: 17, minute: 0)
        XCTAssertNil(service.timeUntilNextTransition(from: date))
    }

    // MARK: - Performance

    func test_currentBlock_under50ms() throws {
        let date = jstDate(year: 2026, month: 5, day: 4, hour: 10, minute: 30)
        measure {
            for _ in 0..<100 {
                _ = service.currentBlock(at: date)
            }
        }
    }

    // MARK: - Helpers

    private func jstDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = jst
        return cal.date(from: comps)!
    }
}
