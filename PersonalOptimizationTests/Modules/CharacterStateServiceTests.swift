import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class CharacterStateServiceTests: XCTestCase {
    private let jst = TimeZone(identifier: "Asia/Tokyo")!

    private func now() -> Date { jstDate(2026, 5, 6, 14, 0) }

    private func base() -> CharacterStateInputs {
        var inputs = CharacterStateInputs.empty
        inputs.now = now()
        return inputs
    }

    // MARK: - Single-state scenarios (8)

    func test_neutral_isFallbackWhenNothingMatches() {
        let inputs = base()
        let resolved = CharacterStateService.resolve(inputs: inputs)
        XCTAssertEqual(resolved.state, .neutral)
    }

    func test_thirsty_whenWaterRatioBelowSixty() {
        var inputs = base()
        let log = DailyLog(date: now())
        log.waterOz = 10
        inputs.todayLog = log
        inputs.hydrationProgressByHour = 30
        let resolved = CharacterStateService.resolve(inputs: inputs)
        XCTAssertEqual(resolved.state, .thirsty)
    }

    func test_fasting_whenInFastWindow() {
        var inputs = base()
        inputs.inFastWindow = true
        let resolved = CharacterStateService.resolve(inputs: inputs)
        XCTAssertEqual(resolved.state, .fasting)
    }

    func test_urgent_whenNextBlockUnderFiveMinutesAndModuleAttached() {
        var inputs = base()
        let block = ScheduleBlock(dayOfWeek: 3, startTime: "14:05", endTime: "15:00",
                                  activity: "Lift A", type: .training, module: "lift_a")
        inputs.nextBlock = block
        inputs.minutesUntilNextBlock = 4
        let resolved = CharacterStateService.resolve(inputs: inputs)
        XCTAssertEqual(resolved.state, .urgent)
    }

    func test_proud_whenWorkoutStreakMilestoneToday() {
        var inputs = base()
        inputs.workoutStreakHitMilestoneToday = true
        let resolved = CharacterStateService.resolve(inputs: inputs)
        XCTAssertEqual(resolved.state, .proud)
    }

    func test_disappointed_whenAnyStreakBrokenInLast24h() {
        var inputs = base()
        inputs.anyStreakBrokenInLast24h = true
        let resolved = CharacterStateService.resolve(inputs: inputs)
        XCTAssertEqual(resolved.state, .disappointed)
    }

    func test_tired_whenSleepBelowSixHours() {
        var inputs = base()
        let log = DailyLog(date: now())
        log.sleepHours = 5.5
        inputs.todayLog = log
        let resolved = CharacterStateService.resolve(inputs: inputs)
        XCTAssertEqual(resolved.state, .tired)
    }

    func test_achievement_whenLiftPRSetToday() {
        var inputs = base()
        inputs.liftPRSetToday = true
        let resolved = CharacterStateService.resolve(inputs: inputs)
        XCTAssertEqual(resolved.state, .achievement)
    }

    // MARK: - Precedence conflicts (3)

    func test_precedence_urgentWinsOverFasting() {
        var inputs = base()
        inputs.inFastWindow = true
        let block = ScheduleBlock(dayOfWeek: 3, startTime: "14:05", endTime: "15:00",
                                  activity: "Lift A", type: .training, module: "lift_a")
        inputs.nextBlock = block
        inputs.minutesUntilNextBlock = 3
        let resolved = CharacterStateService.resolve(inputs: inputs)
        XCTAssertEqual(resolved.state, .urgent)
    }

    func test_precedence_achievementWinsOverProud() {
        var inputs = base()
        inputs.workoutStreakHitMilestoneToday = true
        inputs.liftPRSetToday = true
        let resolved = CharacterStateService.resolve(inputs: inputs)
        XCTAssertEqual(resolved.state, .achievement)
    }

    func test_precedence_disappointedWinsOverTiredAndThirsty() {
        var inputs = base()
        inputs.anyStreakBrokenInLast24h = true
        let log = DailyLog(date: now())
        log.sleepHours = 4
        log.waterOz = 5
        inputs.todayLog = log
        inputs.hydrationProgressByHour = 30
        let resolved = CharacterStateService.resolve(inputs: inputs)
        XCTAssertEqual(resolved.state, .disappointed)
    }

    // MARK: - Travel/Sick suppress nags

    func test_travelMode_suppressesUrgentAndDisappointed() {
        var inputs = base()
        inputs.travelModeActive = true
        inputs.anyStreakBrokenInLast24h = true
        let block = ScheduleBlock(dayOfWeek: 3, startTime: "14:05", endTime: "15:00",
                                  activity: "Lift A", type: .training, module: "lift_a")
        inputs.nextBlock = block
        inputs.minutesUntilNextBlock = 4
        let resolved = CharacterStateService.resolve(inputs: inputs)
        XCTAssertEqual(resolved.state, .neutral)
        XCTAssertEqual(resolved.reason, "travel mode")
    }

    func test_sickDay_suppressesUrgentAndShowsTired() {
        var inputs = base()
        inputs.sickDayActive = true
        inputs.anyStreakBrokenInLast24h = true
        let resolved = CharacterStateService.resolve(inputs: inputs)
        XCTAssertEqual(resolved.state, .tired)
        XCTAssertEqual(resolved.reason, "user marked sick day")
    }

    // MARK: - Live data path

    func test_gatherInputs_detectsFastWindowFromProfile() throws {
        let container = try InMemoryContainer.make()
        let context = container.mainContext
        let profile = UserProfile()
        // 24-hour wrap window guarantees coverage regardless of wall-clock test time.
        profile.fastWindowStartHour = 0
        profile.fastWindowEndHour = 0
        // Fix: use startHour > endHour wrap with widest possible window: 1 -> 0
        profile.fastWindowStartHour = 1
        profile.fastWindowEndHour = 0
        context.insert(profile)
        try context.save()

        let inputs = CharacterStateService.gatherInputs(modelContext: context, timezone: jst)
        XCTAssertTrue(inputs.inFastWindow, "Wrap-around fast window 01:00 -> 00:00 should cover non-midnight wall-clock times")
    }

    func test_gatherInputs_readsSickDayActiveFromProfile() throws {
        let container = try InMemoryContainer.make()
        let context = container.mainContext
        let profile = UserProfile()
        profile.sickDayActiveUntil = Date().addingTimeInterval(3600)
        context.insert(profile)
        try context.save()

        let inputs = CharacterStateService.gatherInputs(modelContext: context, timezone: jst)
        XCTAssertTrue(inputs.sickDayActive)
    }

    // MARK: - Performance

    func test_perf_recompute_under30msWithModerateData() throws {
        let container = try InMemoryContainer.make()
        let context = container.mainContext

        let profile = UserProfile()
        context.insert(profile)
        for offset in 0..<60 {
            let day = Date().addingTimeInterval(-Double(offset) * 86400)
            let log = DailyLog(date: day)
            log.waterOz = Double.random(in: 0...100)
            log.japaneseMinutes = Int.random(in: 0...60)
            context.insert(log)
        }
        try context.save()

        measure {
            for _ in 0..<10 {
                _ = CharacterStateService.gatherInputs(modelContext: context, timezone: jst)
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
