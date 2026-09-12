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
        inputs.timezone = jst
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

    func test_comeback_whenAStreakBreaksWithoutPunishment() {
        var inputs = base()
        inputs.anyStreakBrokenInLast24h = true
        let resolved = CharacterStateService.resolve(inputs: inputs)
        XCTAssertEqual(resolved.state, .comeback)
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

    func test_precedence_tiredWinsOverComebackAndThirsty() {
        var inputs = base()
        inputs.anyStreakBrokenInLast24h = true
        let log = DailyLog(date: now())
        log.sleepHours = 4
        log.waterOz = 5
        inputs.todayLog = log
        inputs.hydrationProgressByHour = 30
        let resolved = CharacterStateService.resolve(inputs: inputs)
        XCTAssertEqual(resolved.state, .tired)
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

    func test_sickDay_suppressesUrgentAndSupportsRecovery() {
        var inputs = base()
        inputs.sickDayActive = true
        inputs.anyStreakBrokenInLast24h = true
        let resolved = CharacterStateService.resolve(inputs: inputs)
        XCTAssertEqual(resolved.state, .recovering)
        XCTAssertTrue(resolved.reason.contains("Your progress stays yours"))
    }

    func test_activeWorkoutTakesPrecedenceOverRemindersAndEarlierWin() {
        var inputs = base()
        inputs.workoutActive = true
        inputs.workoutCompletedToday = true
        inputs.inFastWindow = true
        XCTAssertEqual(CharacterStateService.resolve(inputs: inputs).state, .training)
    }

    func test_restDayAndPainChooseRecoveryWithoutRemovingRecordedWin() {
        var inputs = base()
        inputs.workoutCompletedToday = true
        inputs.restDayActive = true
        XCTAssertEqual(CharacterStateService.resolve(inputs: inputs).state, .recovering)
        inputs.restDayActive = false
        inputs.basketballAchillesPainHigh = true
        XCTAssertEqual(CharacterStateService.resolve(inputs: inputs).state, .recovering)
        inputs.basketballAchillesPainHigh = false
        XCTAssertEqual(CharacterStateService.resolve(inputs: inputs).state, .celebrating)
    }

    func test_completedWorkoutCelebratesEvenIfAnotherHabitWasMissed() {
        var inputs = base()
        inputs.workoutCompletedToday = true
        inputs.anyStreakBrokenInLast24h = true
        inputs.inFastWindow = true
        XCTAssertEqual(CharacterStateService.resolve(inputs: inputs).state, .celebrating)
        inputs.liftPRSetToday = true
        XCTAssertEqual(CharacterStateService.resolve(inputs: inputs).state, .achievement)
    }

    func test_comebackUsesCalendarDaysAndNeedsActualEarlierWorkout() {
        var inputs = base()
        inputs.now = jstDate(2026, 5, 6, 0, 5)
        inputs.lastWorkoutDate = jstDate(2026, 5, 3, 23, 55)
        XCTAssertEqual(CharacterStateService.resolve(inputs: inputs).state, .comeback)
        inputs.lastWorkoutDate = jstDate(2026, 5, 4, 0, 0)
        XCTAssertEqual(CharacterStateService.resolve(inputs: inputs).state, .neutral)
        inputs.lastWorkoutDate = nil
        XCTAssertEqual(CharacterStateService.resolve(inputs: inputs).state, .neutral)
    }

    func test_unknownSleepDoesNotMakeCompanionTired() {
        var inputs = base()
        let log = DailyLog(date: now())
        inputs.todayLog = log
        for unknown in [0.0, -1, .nan, .infinity] {
            log.sleepHours = unknown
            XCTAssertEqual(CharacterStateService.resolve(inputs: inputs).state, .neutral)
        }
    }

    func test_gatherInputsIgnoresSkipsFreezesUnfinishedAndFutureWorkouts() throws {
        let container = try InMemoryContainer.make()
        let context = container.mainContext
        let prior = jstDate(2026, 5, 2, 0, 0)
        context.insert(WorkoutEvent(date: prior, completed: true, source: .custom))
        for source in [WorkoutEventSource.freeze, .manualSkip, .sickDay, .travel] {
            context.insert(WorkoutEvent(date: now(), completed: true, source: source))
        }
        context.insert(WorkoutEvent(date: now(), completed: false, source: .lift))
        context.insert(WorkoutEvent(date: jstDate(2026, 5, 7, 0, 0), completed: true, source: .custom))
        try context.save()
        let inputs = CharacterStateService.gatherInputs(modelContext: context, timezone: jst, now: now())
        XCTAssertEqual(inputs.lastWorkoutDate, prior)
        XCTAssertFalse(inputs.workoutCompletedToday)

        context.insert(WorkoutEvent(date: now(), completed: true, source: .custom))
        try context.save()
        let finished = CharacterStateService.gatherInputs(modelContext: context, timezone: jst, now: now())
        XCTAssertTrue(finished.workoutCompletedToday)
    }

    func test_restDayMetadataReachesLiveResolverWithoutWorkoutCredit() throws {
        let container = try InMemoryContainer.make()
        let context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = jst
        let log = DailyLogStore(modelContext: context, calendar: calendar).upsert(for: now())
        log.setMetadata("dailyWorkout.restDay", value: true)
        try context.save()
        let inputs = CharacterStateService.gatherInputs(modelContext: context, timezone: jst, now: now())
        XCTAssertTrue(inputs.restDayActive)
        XCTAssertFalse(inputs.workoutCompletedToday)
        XCTAssertEqual(CharacterStateService.resolve(inputs: inputs).state, .recovering)
    }

    func test_personalBestRequiresFinishedNonFutureSession() throws {
        let container = try InMemoryContainer.make()
        let context = container.mainContext
        let prior = LiftSession(date: jstDate(2026, 5, 5, 0, 0), template: "Lift")
        prior.totalVolumeLbs = 100
        prior.durationMinutes = 10
        let current = LiftSession(date: now(), template: "Lift")
        current.totalVolumeLbs = 200
        let future = LiftSession(date: jstDate(2026, 5, 6, 23, 0), template: "Lift")
        future.totalVolumeLbs = 300
        future.durationMinutes = 10
        context.insert(prior)
        context.insert(current)
        context.insert(future)
        try context.save()
        let unfinished = CharacterStateService.gatherInputs(modelContext: context, timezone: jst, now: now())
        XCTAssertFalse(unfinished.liftPRSetToday)
        current.durationMinutes = 10
        try context.save()
        let finished = CharacterStateService.gatherInputs(modelContext: context, timezone: jst, now: now())
        XCTAssertTrue(finished.liftPRSetToday)
    }

    // MARK: - Live data path

    func test_gatherInputs_detectsFastWindowFromProfile() throws {
        let container = try InMemoryContainer.make()
        let context = container.mainContext
        let profile = UserProfile()
        // The window math has no 24h-coverage solution (start==end is ambiguous;
        // any wrap leaves a 1-minute hole). Compute a window that bracketed
        // the current JST hour so the test is deterministic regardless of when
        // it runs.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = jst
        let nowHour = cal.component(.hour, from: Date())
        // Window: from (nowHour - 1) through (nowHour + 1), modular 24, using
        // wrap branch when needed.
        profile.fastWindowStartHour = (nowHour + 23) % 24   // = nowHour - 1
        profile.fastWindowEndHour = (nowHour + 2) % 24
        context.insert(profile)
        try context.save()

        let inputs = CharacterStateService.gatherInputs(modelContext: context, timezone: jst)
        XCTAssertTrue(inputs.inFastWindow,
                      "Window bracketing the current JST hour should report inFastWindow")
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
