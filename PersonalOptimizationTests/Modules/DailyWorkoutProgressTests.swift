import XCTest
@testable import PersonalOptimization

final class DailyWorkoutProgressTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    private func date(_ day: Int, hour: Int = 12, month: Int = 3) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func progress(days: [Date] = [], exercise: Int = 0, sessions: Int = 0,
                          goal: Int = 10, asOf: Date? = nil) -> DailyWorkoutProgress {
        DailyWorkoutProgress(workoutDates: days, exerciseMinutes: exercise, sessionMinutes: sessions,
                             goalMinutes: goal, asOf: asOf ?? date(9), calendar: calendar)
    }

    func test_emptyStoreStartsAtLevelOneWithoutInventedCredit() {
        let value = progress()
        XCTAssertEqual(value.totalXP, 0)
        XCTAssertEqual(value.level, 1)
        XCTAssertEqual(value.xpToNextLevel, 250)
        XCTAssertFalse(value.trainedToday)
        XCTAssertEqual(value.weekDays.count, 7)
    }

    func test_multipleWorkoutsAndDuplicateImportsEarnOnlyOneDailyReward() {
        let value = progress(days: [date(9, hour: 8), date(9, hour: 8), date(9, hour: 10)])
        XCTAssertEqual(value.totalXP, 50)
        XCTAssertEqual(value.daysThisWeek, 1)
        XCTAssertTrue(value.trainedToday)
    }

    func test_healthAndLocalSessionMinutesAreNotAddedTwice() {
        XCTAssertEqual(progress(exercise: 30, sessions: 20).movementMinutes, 30)
        XCTAssertEqual(progress(exercise: 10, sessions: 20).movementMinutes, 20)
    }

    func test_futureEventsDoNotEarnCredit() {
        XCTAssertEqual(progress(days: [date(10)]).totalXP, 0)
    }

    func test_negativeInputsCannotReverseRings() {
        let value = progress(exercise: -20, sessions: -3, goal: 0)
        XCTAssertEqual(value.movementMinutes, 0)
        XCTAssertEqual(value.goalMinutes, 1)
        XCTAssertEqual(value.movementProgress, 0)
    }

    func test_progressCapsAtOneAndKeepsActualMinutes() {
        let value = progress(exercise: 45)
        XCTAssertEqual(value.movementMinutes, 45)
        XCTAssertEqual(value.movementProgress, 1)
    }

    func test_weekStartsMondayAndIncludesSundayAcrossDST() {
        let value = progress(days: [date(2), date(8)], asOf: date(8, hour: 23))
        XCTAssertEqual(value.weekDays.first, date(2, hour: 0))
        XCTAssertEqual(value.weekDays.last, date(8, hour: 0))
        XCTAssertEqual(value.daysThisWeek, 2)
    }

    func test_newWeekResetsWeeklyRingAndKeepsLifetimeXP() {
        let value = progress(days: [date(2), date(8)], asOf: date(9))
        XCTAssertEqual(value.daysThisWeek, 0)
        XCTAssertEqual(value.totalXP, 100)
        XCTAssertFalse(value.trainedToday)
    }

    func test_fiveWorkoutDaysEarnNextLevel() {
        let value = progress(days: (2...6).map { date($0) })
        XCTAssertEqual(value.totalXP, 250)
        XCTAssertEqual(value.level, 2)
        XCTAssertEqual(value.xpInLevel, 0)
        XCTAssertEqual(value.xpToNextLevel, 250)
    }

    func test_changingGoalCannotFarmXP() {
        XCTAssertEqual(progress(days: [date(9)], goal: 5).totalXP,
                       progress(days: [date(9)], goal: 20).totalXP)
    }

    func test_skipsAndGraceNeverEarnWorkoutCredit() {
        for source in ["freeze", "manual_skip", "sick_day", "travel", "unknown"] {
            XCTAssertFalse(DailyWorkoutProgress.earnsWorkoutCredit(source: source))
        }
        for source in ["lift", "basketball", "swim", "custom"] {
            XCTAssertTrue(DailyWorkoutProgress.earnsWorkoutCredit(source: source))
        }
    }

    func test_overlappingSessionIntervalsCountOnce() {
        let start = date(9, hour: 10)
        let intervals = [DateInterval(start: start, duration: 1200),
                         DateInterval(start: start.addingTimeInterval(600), duration: 1200)]
        XCTAssertEqual(DailyWorkoutProgress.sessionMinutes(intervals: intervals, asOf: date(9), calendar: calendar), 30)
    }

    func test_overnightAndFutureSessionMinutesAreClipped() {
        let midnight = date(9, hour: 0)
        let intervals = [DateInterval(start: midnight.addingTimeInterval(-600), duration: 1200),
                         DateInterval(start: date(10), duration: 1800)]
        XCTAssertEqual(DailyWorkoutProgress.sessionMinutes(intervals: intervals, asOf: date(9), calendar: calendar), 10)
    }

    func test_DSTSessionUsesElapsedTimeNotWallClockHours() {
        // Spring forward: 1am to 4am is only two elapsed hours.
        let intervals = [DateInterval(start: date(8, hour: 1), end: date(8, hour: 4))]
        XCTAssertEqual(DailyWorkoutProgress.sessionMinutes(intervals: intervals, asOf: date(8), calendar: calendar), 120)
    }

    func test_missedDaysKeepXPAndCoachWelcomesReturn() {
        let value = progress(days: [date(2)])
        let coach = DailyWorkoutCoach.make(progress: value, resting: false, easing: false, calendar: calendar)
        XCTAssertEqual(value.totalXP, 50)
        XCTAssertEqual(coach.title, "Welcome back. Start small.")
        XCTAssertTrue(coach.message.contains("50 XP"))
    }

    func test_restTakesPriorityOverMoreTraining() {
        let value = progress(days: [date(9)])
        let coach = DailyWorkoutCoach.make(progress: value, resting: true, easing: false, calendar: calendar)
        XCTAssertEqual(coach.title, "Recovery belongs in your week.")
        XCTAssertEqual(value.totalXP, 50)
    }

    func test_workoutWinDoesNotRequireOtherHabitsOrMoreExercise() {
        let coach = DailyWorkoutCoach.make(progress: progress(days: [date(9)]), resting: false,
                                          easing: false, calendar: calendar)
        XCTAssertTrue(coach.message.contains("More training is optional"))
    }

    func test_coldStartCoachWorksWithoutPersonalDataOrAPIKey() {
        let coach = DailyWorkoutCoach.make(progress: progress(), resting: false, easing: false, calendar: calendar)
        XCTAssertEqual(coach.title, "One small win today.")
        XCTAssertFalse(coach.message.isEmpty)
    }
}
