import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class StreakServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var service: StreakService!
    private let jst = TimeZone(identifier: "Asia/Tokyo")!

    override func setUp() async throws {
        try await super.setUp()
        container = try InMemoryContainer.make()
        context = container.mainContext
        service = StreakService(modelContext: context, timezone: jst)
    }

    override func tearDown() async throws {
        service = nil
        context = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: - Workout domain

    func test_recompute_workout_emptyHistory_returnsZero() throws {
        let counter = try service.recompute(domain: .workout, asOf: jstDate(2026, 5, 6, 10, 0))
        XCTAssertEqual(counter.currentStreak, 0)
        XCTAssertEqual(counter.longestStreak, 0)
        XCTAssertNil(counter.lastCompletedDate)
    }

    func test_recompute_workout_threeConsecutiveDays_returnsThree() throws {
        for offset in 0..<3 {
            let day = jstDate(2026, 5, 4 + offset, 10, 0)
            try service.recordWorkoutLedger(date: day, source: .lift)
        }
        let counter = try service.recompute(domain: .workout, asOf: jstDate(2026, 5, 6, 18, 0))
        XCTAssertEqual(counter.currentStreak, 3)
        XCTAssertEqual(counter.longestStreak, 3)
    }

    func test_recompute_workout_gapBreaksStreak() throws {
        try service.recordWorkoutLedger(date: jstDate(2026, 5, 3, 10, 0), source: .lift)
        // Gap: nothing on 5/4
        try service.recordWorkoutLedger(date: jstDate(2026, 5, 5, 10, 0), source: .basketball)
        try service.recordWorkoutLedger(date: jstDate(2026, 5, 6, 10, 0), source: .swim)
        let counter = try service.recompute(domain: .workout, asOf: jstDate(2026, 5, 6, 18, 0))
        XCTAssertEqual(counter.currentStreak, 2)
        XCTAssertEqual(counter.longestStreak, 2)
    }

    // MARK: - Freezes

    func test_applyFreeze_workout_marksTodayAndDecrementsAvailable() throws {
        let counter = try service.applyFreeze(domain: .workout, asOf: jstDate(2026, 5, 6, 10, 0))
        XCTAssertEqual(counter.currentStreak, 1)
        XCTAssertEqual(counter.freezesAvailable, 1)
        XCTAssertEqual(counter.freezesUsedThisMonth, 1)
    }

    func test_applyFreeze_writesWorkoutEventForWorkoutDomain() throws {
        _ = try service.applyFreeze(domain: .workout, asOf: jstDate(2026, 5, 6, 10, 0))
        let events = try context.fetch(FetchDescriptor<WorkoutEvent>())
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.source, "freeze")
    }

    func test_applyFreeze_writesFreezeApplicationForNonWorkoutDomain() throws {
        _ = try service.applyFreeze(domain: .hydration, asOf: jstDate(2026, 5, 6, 10, 0))
        let freezes = try context.fetch(FetchDescriptor<FreezeApplication>())
        XCTAssertEqual(freezes.count, 1)
        XCTAssertEqual(freezes.first?.domain, "hydration")
    }

    func test_applyFreeze_exhausted_throws() throws {
        let day = jstDate(2026, 5, 6, 10, 0)
        _ = try service.applyFreeze(domain: .workout, asOf: day)
        _ = try service.applyFreeze(domain: .workout, asOf: day)
        XCTAssertThrowsError(try service.applyFreeze(domain: .workout, asOf: day)) { error in
            guard case StreakServiceError.noFreezesAvailable = error else {
                return XCTFail("Expected noFreezesAvailable, got \(error)")
            }
        }
    }

    // MARK: - Monthly reset

    func test_resetMonthlyFreezes_sameMonth_isNoOp() throws {
        let day = jstDate(2026, 5, 6, 10, 0)
        _ = try service.applyFreeze(domain: .workout, asOf: day)
        try service.resetMonthlyFreezes(asOf: jstDate(2026, 5, 20, 10, 0))
        let counter = try service.recompute(domain: .workout, asOf: jstDate(2026, 5, 20, 10, 0))
        XCTAssertEqual(counter.freezesAvailable, 1)
        XCTAssertEqual(counter.freezesUsedThisMonth, 1)
    }

    func test_resetMonthlyFreezes_newMonth_resetsToTwo() throws {
        let day = jstDate(2026, 5, 6, 10, 0)
        _ = try service.applyFreeze(domain: .workout, asOf: day)
        _ = try service.applyFreeze(domain: .workout, asOf: day)
        try service.resetMonthlyFreezes(asOf: jstDate(2026, 6, 1, 0, 0))
        let counter = try service.recompute(domain: .workout, asOf: jstDate(2026, 6, 1, 10, 0))
        XCTAssertEqual(counter.freezesAvailable, 2)
        XCTAssertEqual(counter.freezesUsedThisMonth, 0)
    }

    // MARK: - Travel and Sick day

    func test_travelMode_preservesStreakAcrossDaysWithoutData() throws {
        try service.recordWorkoutLedger(date: jstDate(2026, 5, 5, 10, 0), source: .lift)
        try service.activateTravelMode(days: 7, asOf: jstDate(2026, 5, 6, 8, 0))
        // No workout from 5/6 through 5/12; travel mode ledger should preserve the streak.
        let counter = try service.recompute(domain: .workout, asOf: jstDate(2026, 5, 12, 18, 0))
        XCTAssertEqual(counter.currentStreak, 8) // 5/5 + 5/6..5/12 (7 travel days)
    }

    func test_sickDay_preservesTodaysStreak() throws {
        let asOf = jstDate(2026, 5, 6, 10, 0)
        try service.recordWorkoutLedger(date: jstDate(2026, 5, 5, 10, 0), source: .lift)
        try service.activateSickDay(asOf: asOf)
        let counter = try service.recompute(domain: .workout, asOf: asOf)
        XCTAssertEqual(counter.currentStreak, 2)
    }

    func test_sickDay_endedYesterday_streakHoldsAtOneTodayInProgress() throws {
        try service.recordWorkoutLedger(date: jstDate(2026, 5, 5, 10, 0), source: .lift)
        try service.activateSickDay(asOf: jstDate(2026, 5, 5, 8, 0))
        // No workout today and sick window ended yesterday.
        // 5/5 was a real workout (and also sick-day-flagged); 5/6 in-progress without
        // a flag or workout shouldn't count, but the streak from 5/5 still stands.
        let counter = try service.recompute(domain: .workout, asOf: jstDate(2026, 5, 6, 18, 0))
        XCTAssertEqual(counter.currentStreak, 1)
    }

    // MARK: - Learning domain

    func test_recompute_learning_japaneseOrGuitarMeetsThreshold() throws {
        let day = jstDate(2026, 5, 6, 10, 0)
        let log = DailyLog(date: day)
        log.japaneseMinutes = 30
        context.insert(log)
        try context.save()
        let counter = try service.recompute(domain: .learning, asOf: day)
        XCTAssertEqual(counter.currentStreak, 1)
    }

    func test_recompute_learning_belowThreshold_doesNotCount() throws {
        let day = jstDate(2026, 5, 6, 10, 0)
        let log = DailyLog(date: day)
        log.japaneseMinutes = 5
        log.guitarMinutes = 5
        context.insert(log)
        try context.save()
        let counter = try service.recompute(domain: .learning, asOf: day)
        XCTAssertEqual(counter.currentStreak, 0)
    }

    // MARK: - Weekend rest days (workout)

    func test_recompute_workout_weekendBridges_streakSurvivesWithoutWorkouts() throws {
        // Mon 5/4, Tue 5/5, Wed 5/6, Thu 5/7, Fri 5/8 all completed.
        // Sat 5/9 and Sun 5/10 are auto rest days. Mon 5/11 today, no workout yet.
        for d in [4, 5, 6, 7, 8] {
            try service.recordWorkoutLedger(date: jstDate(2026, 5, d, 10, 0), source: .lift)
        }
        let counter = try service.recompute(domain: .workout, asOf: jstDate(2026, 5, 11, 9, 0))
        // Today is in-progress; weekend bridges Fri→Mon. Streak from Fri walking back = 5.
        XCTAssertEqual(counter.currentStreak, 5)
    }

    func test_recompute_workout_weekendDoesNotBridgeWeekdayMiss() throws {
        // Skip Tuesday entirely. Mon yes, Wed yes, Thu yes, Fri yes. Sat (rest), today=Mon next week.
        try service.recordWorkoutLedger(date: jstDate(2026, 5, 4, 10, 0), source: .lift)
        // 5/5 Tue intentionally skipped
        for d in [6, 7, 8] {
            try service.recordWorkoutLedger(date: jstDate(2026, 5, d, 10, 0), source: .lift)
        }
        let counter = try service.recompute(domain: .workout, asOf: jstDate(2026, 5, 11, 9, 0))
        // Walk back from Mon 5/11: rest 5/10, rest 5/9, Fri 5/8 yes (1), Thu 5/7 yes (2), Wed 5/6 yes (3),
        // Tue 5/5 missed (not rest) → break.
        XCTAssertEqual(counter.currentStreak, 3)
    }

    func test_recompute_workout_restDaysComeFromSchedule_midweekRestBridges() throws {
        // Custom schedule: training Mon/Tue/Thu/Fri only. Wed/Sat/Sun are rest days.
        for day in [1, 2, 4, 5] {
            context.insert(ScheduleBlock(
                dayOfWeek: day, startTime: "09:00", endTime: "10:00",
                activity: "Lift", type: .training, module: "lift_a"
            ))
        }
        try context.save()
        // Mon 5/4, Tue 5/5 done. Wed 5/6 today, no workout.
        try service.recordWorkoutLedger(date: jstDate(2026, 5, 4, 10, 0), source: .lift)
        try service.recordWorkoutLedger(date: jstDate(2026, 5, 5, 10, 0), source: .lift)
        let counter = try service.recompute(domain: .workout, asOf: jstDate(2026, 5, 6, 18, 0))
        // Wed today is in-progress (rest day). Walk back: Tue yes (1), Mon yes (2), Sun rest, Sat rest,
        // Fri (no event, weekday=5 IS in trainingDays so not rest) → break. Streak = 2.
        XCTAssertEqual(counter.currentStreak, 2)
    }

    func test_recompute_workout_weekendBridge_doesNotApplyToOtherDomains() throws {
        // Hydration: Friday completed, today Monday with no log. No auto-bridge for hydration.
        let log = DailyLog(date: jstDate(2026, 5, 8, 10, 0))
        log.waterOz = 200
        context.insert(log)
        try context.save()
        let counter = try service.recompute(domain: .hydration, asOf: jstDate(2026, 5, 11, 9, 0))
        // Walk back from Mon: today no log → 0. Sun no log → break (no rest bridge for hydration).
        XCTAssertEqual(counter.currentStreak, 0)
    }

    // MARK: - Longest

    func test_recompute_persistsHistoricalLongestStreak() throws {
        // Old run of 5 days that's broken
        for offset in 0..<5 {
            try service.recordWorkoutLedger(date: jstDate(2026, 4, 1 + offset, 10, 0), source: .lift)
        }
        // Recent run of 2 days
        for offset in 0..<2 {
            try service.recordWorkoutLedger(date: jstDate(2026, 5, 5 + offset, 10, 0), source: .lift)
        }
        let counter = try service.recompute(domain: .workout, asOf: jstDate(2026, 5, 6, 18, 0))
        XCTAssertEqual(counter.currentStreak, 2)
        XCTAssertEqual(counter.longestStreak, 5)
    }

    // MARK: - Auto-grace (forgiveness from day one)

    func test_autoGrace_protectsYesterday_whenStreakWouldBreak() throws {
        // Mon + Tue trained, Wed missed, "today" is Thu morning.
        try service.recordWorkoutLedger(date: jstDate(2026, 5, 4, 10, 0), source: .lift)
        try service.recordWorkoutLedger(date: jstDate(2026, 5, 5, 10, 0), source: .lift)
        let asOf = jstDate(2026, 5, 7, 9, 0)

        let protectedDay = try service.autoApplyGraceIfNeeded(domain: .workout, asOf: asOf)
        XCTAssertNotNil(protectedDay, "Wednesday's miss should be auto-protected.")

        // A freeze-sourced event now covers Wednesday and a freeze was spent.
        let counter = try service.recompute(domain: .workout, asOf: asOf)
        XCTAssertEqual(counter.freezesAvailable, 1)
        XCTAssertEqual(counter.freezesUsedThisMonth, 1)
        XCTAssertEqual(counter.currentStreak, 3, "Mon, Tue, and the protected Wed keep the chain alive.")
    }

    func test_autoGrace_noOp_whenYesterdayAlreadyCompleted() throws {
        for offset in 0..<3 {
            try service.recordWorkoutLedger(date: jstDate(2026, 5, 4 + offset, 10, 0), source: .lift)
        }
        let asOf = jstDate(2026, 5, 7, 9, 0)
        XCTAssertNil(try service.autoApplyGraceIfNeeded(domain: .workout, asOf: asOf))
        let counter = try service.recompute(domain: .workout, asOf: asOf)
        XCTAssertEqual(counter.freezesAvailable, 2, "No freeze spent when yesterday was completed.")
    }

    func test_autoGrace_noOp_whenNoLiveStreakToSave() throws {
        // Only Monday trained; Tue and Wed missed. The chain already broke at
        // Tue, so protecting Wed would not save anything.
        try service.recordWorkoutLedger(date: jstDate(2026, 5, 4, 10, 0), source: .lift)
        let asOf = jstDate(2026, 5, 7, 9, 0)
        XCTAssertNil(try service.autoApplyGraceIfNeeded(domain: .workout, asOf: asOf))
        let counter = try service.recompute(domain: .workout, asOf: asOf)
        XCTAssertEqual(counter.freezesAvailable, 2)
    }

    func test_autoGrace_noOp_whenNoFreezesAvailable() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = jst
        let asOf = jstDate(2026, 5, 7, 9, 0)
        let monthAnchor = cal.date(from: cal.dateComponents([.year, .month], from: asOf))!
        let counter = StreakCounter(domain: .workout)
        counter.freezesAvailable = 0
        counter.freezeMonthAnchor = monthAnchor
        context.insert(counter)
        try service.recordWorkoutLedger(date: jstDate(2026, 5, 4, 10, 0), source: .lift)
        try service.recordWorkoutLedger(date: jstDate(2026, 5, 5, 10, 0), source: .lift)
        try context.save()

        XCTAssertNil(try service.autoApplyGraceIfNeeded(domain: .workout, asOf: asOf))
    }

    func test_autoGrace_isIdempotent() throws {
        try service.recordWorkoutLedger(date: jstDate(2026, 5, 4, 10, 0), source: .lift)
        try service.recordWorkoutLedger(date: jstDate(2026, 5, 5, 10, 0), source: .lift)
        let asOf = jstDate(2026, 5, 7, 9, 0)

        XCTAssertNotNil(try service.autoApplyGraceIfNeeded(domain: .workout, asOf: asOf))
        XCTAssertNil(try service.autoApplyGraceIfNeeded(domain: .workout, asOf: asOf),
                     "A second run finds yesterday already covered.")
        let counter = try service.recompute(domain: .workout, asOf: asOf)
        XCTAssertEqual(counter.freezesAvailable, 1, "Only one freeze spent across two runs.")
    }

    private func jstDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = jst
        return cal.date(from: c)!
    }
}
