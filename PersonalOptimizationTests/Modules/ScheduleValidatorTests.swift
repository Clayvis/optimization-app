import XCTest
@testable import PersonalOptimization

final class ScheduleValidatorTests: XCTestCase {

    private let defaults = ScheduleValidator.Constraints.default

    // MARK: - Happy path

    func test_validSchedule_passesWithoutError() throws {
        let blocks = [
            block(day: 1, "18:00", "19:00", module: "lift_a"),
            block(day: 3, "18:00", "19:00", module: "lift_b"),
            block(day: 5, "18:00", "19:00", module: "lift_a")
        ]
        XCTAssertNoThrow(try ScheduleValidator.validate(blocks, against: defaults))
    }

    // MARK: - Weekday

    func test_invalidWeekday_zero() {
        let blocks = [block(day: 0, "18:00", "19:00")]
        let errors = ScheduleValidator.collect(blocks, against: defaults)
        XCTAssertTrue(errors.contains(.invalidWeekday(blockIndex: 0, value: 0)))
    }

    func test_invalidWeekday_eight() {
        let blocks = [block(day: 8, "18:00", "19:00")]
        let errors = ScheduleValidator.collect(blocks, against: defaults)
        XCTAssertTrue(errors.contains(.invalidWeekday(blockIndex: 0, value: 8)))
    }

    // MARK: - Time format

    func test_invalidStartTime_format() {
        let blocks = [block(day: 1, "25:00", "26:00")]
        let errors = ScheduleValidator.collect(blocks, against: defaults)
        XCTAssertTrue(errors.contains { if case .invalidTimeFormat = $0 { return true }; return false })
    }

    func test_timeRangeInverted_endBeforeStart() {
        let blocks = [block(day: 1, "19:00", "18:00")]
        let errors = ScheduleValidator.collect(blocks, against: defaults)
        XCTAssertTrue(errors.contains(.timeRangeInverted(blockIndex: 0, start: "19:00", end: "18:00")))
    }

    func test_timeRangeInverted_endEqualsStart() {
        let blocks = [block(day: 1, "18:00", "18:00")]
        let errors = ScheduleValidator.collect(blocks, against: defaults)
        XCTAssertTrue(errors.contains(.timeRangeInverted(blockIndex: 0, start: "18:00", end: "18:00")))
    }

    // MARK: - Module + anchor vocabulary

    func test_invalidModule_caughtByValidator() {
        let blocks = [block(day: 1, "18:00", "19:00", module: "lift_c")]
        let errors = ScheduleValidator.collect(blocks, against: defaults)
        XCTAssertTrue(errors.contains(.invalidModule(blockIndex: 0, value: "lift_c")))
    }

    func test_nilModule_isAlwaysValid() {
        let blocks = [block(day: 1, "18:00", "19:00", module: nil)]
        XCTAssertNoThrow(try ScheduleValidator.validate(blocks, against: defaults))
    }

    func test_invalidAnchor_caughtByValidator() {
        let blocks = [block(day: 1, "18:00", "19:00", anchor: "after_lunch_with_clay")]
        let errors = ScheduleValidator.collect(blocks, against: defaults)
        XCTAssertTrue(errors.contains(.invalidAnchor(blockIndex: 0, value: "after_lunch_with_clay")))
    }

    func test_knownAnchor_passes() throws {
        let blocks = [block(day: 1, "18:00", "19:00", anchor: "after_kid_dropoff")]
        XCTAssertNoThrow(try ScheduleValidator.validate(blocks, against: defaults))
    }

    // MARK: - Overlap

    func test_overlap_sameDay_detected() {
        let blocks = [
            block(day: 1, "18:00", "19:00"),
            block(day: 1, "18:30", "19:30")
        ]
        let errors = ScheduleValidator.collect(blocks, against: defaults)
        XCTAssertTrue(errors.contains(.overlap(blockA: 0, blockB: 1, day: 1)))
    }

    func test_overlap_differentDays_notDetected() throws {
        let blocks = [
            block(day: 1, "18:00", "19:00"),
            block(day: 2, "18:00", "19:00")
        ]
        XCTAssertNoThrow(try ScheduleValidator.validate(blocks, against: defaults))
    }

    func test_overlap_backToBack_isAllowed() throws {
        let blocks = [
            block(day: 1, "18:00", "19:00"),
            block(day: 1, "19:00", "20:00")
        ]
        XCTAssertNoThrow(try ScheduleValidator.validate(blocks, against: defaults))
    }

    // MARK: - Sleep window

    func test_sleepWindow_blockInsideWindow_caught() {
        // Default sleep window: 22:00-06:00 (wraps midnight).
        let blocks = [block(day: 1, "23:00", "23:30")]
        let errors = ScheduleValidator.collect(blocks, against: defaults)
        XCTAssertTrue(errors.contains { if case .sleepWindowIntersect = $0 { return true }; return false })
    }

    func test_sleepWindow_blockBeforeWindow_notCaught() throws {
        let blocks = [block(day: 1, "20:00", "21:00")]
        XCTAssertNoThrow(try ScheduleValidator.validate(blocks, against: defaults))
    }

    func test_sleepWindow_earlyMorningBlock_caught() {
        // 05:30-06:00 is inside the wrapping window 22:00-06:00.
        let blocks = [block(day: 1, "05:30", "06:00")]
        let errors = ScheduleValidator.collect(blocks, against: defaults)
        XCTAssertTrue(errors.contains { if case .sleepWindowIntersect = $0 { return true }; return false })
    }

    // MARK: - Weekly volume

    func test_weeklyLiftLimit_exceeded() {
        let blocks = (1...7).map { block(day: $0, "18:00", "19:00", module: "lift_a") }
        let errors = ScheduleValidator.collect(blocks, against: defaults)
        XCTAssertTrue(errors.contains(.weeklyVolumeExceeded(domain: "lift", count: 7, max: 6)))
    }

    func test_weeklyLiftLimit_atCap_passes() throws {
        let blocks = (1...6).map { block(day: $0, "18:00", "19:00", module: "lift_a") }
        XCTAssertNoThrow(try ScheduleValidator.validate(blocks, against: defaults))
    }

    // MARK: - Summarize

    func test_summarize_emptyList_noErrorsMessage() {
        XCTAssertEqual(ScheduleValidator.summarize([]), "No validation errors.")
    }

    func test_summarize_includesAllErrors() {
        let summary = ScheduleValidator.summarize([
            .invalidWeekday(blockIndex: 0, value: 9),
            .overlap(blockA: 1, blockB: 2, day: 3)
        ])
        XCTAssertTrue(summary.contains("invalid ISO weekday 9"))
        XCTAssertTrue(summary.contains("overlap"))
    }

    // MARK: - Performance benchmark (SPEC: < 5ms for 14-block week)

    func test_performance_14BlockWeek_underBudget() {
        let blocks = (0..<14).map { i in
            block(day: (i % 7) + 1, "18:00", "19:00", module: i.isMultiple(of: 2) ? "lift_a" : nil)
        }
        let start = Date()
        _ = ScheduleValidator.collect(blocks, against: defaults)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 0.005, "Validator must run a 14-block week in <5ms; got \(elapsed * 1000) ms")
    }

    // MARK: - Helpers

    private func block(day: Int,
                       _ start: String,
                       _ end: String,
                       type: String = "training",
                       module: String? = nil,
                       anchor: String? = nil) -> ScheduleValidator.Block {
        ScheduleValidator.Block(
            dayOfWeek: day,
            startTime: start,
            endTime: end,
            type: type,
            module: module,
            anchorEvent: anchor
        )
    }
}
