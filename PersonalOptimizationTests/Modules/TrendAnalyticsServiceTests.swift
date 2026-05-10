import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class TrendAnalyticsServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var jstCal: Calendar!

    override func setUp() async throws {
        try await super.setUp()
        container = try InMemoryContainer.make()
        context = container.mainContext
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        jstCal = cal
    }

    override func tearDown() async throws {
        context = nil
        container = nil
        jstCal = nil
        try await super.tearDown()
    }

    // MARK: - dailyAdherence

    func test_dailyAdherence_emptyData_allZeros() {
        let service = TrendAnalyticsService(modelContext: context)
        let range = DateRange.lastNDays(7, asOf: jstNow)
        let result = service.dailyAdherence(over: range)
        XCTAssertEqual(result.count, 7)
        for (_, ratio) in result {
            XCTAssertEqual(ratio, 0)
        }
    }

    func test_dailyAdherence_readsArchiveWhenPresent() throws {
        let day = jstCal.startOfDay(for: jstNow)
        let archive = ActivityArchive(date: day)
        archive.masterMetric = 0.75
        context.insert(archive)
        try context.save()

        let service = TrendAnalyticsService(modelContext: context)
        let range = DateRange(start: day, end: day)
        let result = service.dailyAdherence(over: range)
        XCTAssertEqual(result[day], 0.75)
    }

    // MARK: - volumeProgression

    func test_volumeProgression_lift_sumsByDay() throws {
        let today = jstCal.startOfDay(for: jstNow)
        let yesterday = jstCal.date(byAdding: .day, value: -1, to: today)!
        let liftA = LiftSession(date: today, template: "Lift A")
        liftA.totalVolumeLbs = 10_000
        let liftB = LiftSession(date: today, template: "Lift B")
        liftB.totalVolumeLbs = 5_000
        let liftYesterday = LiftSession(date: yesterday, template: "Lift A")
        liftYesterday.totalVolumeLbs = 8_000
        context.insert(liftA); context.insert(liftB); context.insert(liftYesterday)
        try context.save()

        let service = TrendAnalyticsService(modelContext: context)
        let range = DateRange(start: yesterday, end: today)
        let result = service.volumeProgression(domain: .lift, over: range)
        XCTAssertEqual(result[today], 15_000)
        XCTAssertEqual(result[yesterday], 8_000)
    }

    func test_volumeProgression_swim_sumsTotalMeters() throws {
        let day = jstCal.startOfDay(for: jstNow)
        let swim = SwimSession(date: day, poolLengthMeters: 25)
        swim.totalMeters = 1_000
        context.insert(swim)
        try context.save()

        let service = TrendAnalyticsService(modelContext: context)
        let range = DateRange(start: day, end: day)
        let result = service.volumeProgression(domain: .swim, over: range)
        XCTAssertEqual(result[day], 1_000)
    }

    func test_volumeProgression_learning_sumsMinutes() throws {
        let day = jstCal.startOfDay(for: jstNow)
        let log = DailyLog(date: day)
        log.japaneseMinutes = 30
        log.guitarMinutes = 20
        log.courseworkMinutes = 60
        context.insert(log)
        try context.save()

        let service = TrendAnalyticsService(modelContext: context)
        let range = DateRange(start: day, end: day)
        let result = service.volumeProgression(domain: .learning, over: range)
        XCTAssertEqual(result[day], 110)
    }

    // MARK: - patternsDetected

    func test_patternsDetected_volumeDecline_belowThreshold_returnsPattern() throws {
        let service = TrendAnalyticsService(modelContext: context)
        let today = jstCal.startOfDay(for: jstNow)
        // Days -13 to -7: 1000 lb each. Days -6 to 0: 200 lb each.
        for i in -13...0 {
            let day = jstCal.date(byAdding: .day, value: i, to: today)!
            let lift = LiftSession(date: day, template: "Lift A")
            lift.totalVolumeLbs = (i < -6) ? 1000 : 200
            context.insert(lift)
        }
        try context.save()
        let range = DateRange.lastNDays(14, asOf: jstNow)
        let patterns = service.patternsDetected(over: range)
        XCTAssertTrue(patterns.contains { $0.patternType == .volumeDecline })
    }

    func test_patternsDetected_volumeStable_returnsNoVolumeDeclinePattern() throws {
        let service = TrendAnalyticsService(modelContext: context)
        let today = jstCal.startOfDay(for: jstNow)
        for i in -13...0 {
            let day = jstCal.date(byAdding: .day, value: i, to: today)!
            let lift = LiftSession(date: day, template: "Lift A")
            lift.totalVolumeLbs = 1000
            context.insert(lift)
        }
        try context.save()
        let range = DateRange.lastNDays(14, asOf: jstNow)
        let patterns = service.patternsDetected(over: range)
        XCTAssertFalse(patterns.contains { $0.patternType == .volumeDecline })
    }

    func test_patternsDetected_hydrationCorrelation_detectsHigherAdherence() throws {
        let service = TrendAnalyticsService(modelContext: context)
        let today = jstCal.startOfDay(for: jstNow)
        // 5 hydrated days with archive adherence 0.9, 5 dry days with adherence 0.3
        for i in 0..<10 {
            let day = jstCal.date(byAdding: .day, value: -i, to: today)!
            let log = DailyLog(date: day)
            log.waterOz = (i < 5) ? 100 : 20
            context.insert(log)
            let archive = ActivityArchive(date: day)
            archive.masterMetric = (i < 5) ? 0.9 : 0.3
            context.insert(archive)
        }
        try context.save()
        let range = DateRange.lastNDays(10, asOf: jstNow)
        let patterns = service.patternsDetected(over: range)
        XCTAssertTrue(patterns.contains { $0.patternType == .hydrationCorrelation })
    }

    func test_patternsDetected_sleepImpact_detectsLowSleepCorrelation() throws {
        let service = TrendAnalyticsService(modelContext: context)
        let today = jstCal.startOfDay(for: jstNow)
        // 5 nights of low sleep, each followed by adherence-zero day
        for i in 1...5 {
            let priorDay = jstCal.date(byAdding: .day, value: -(i + 1), to: today)!
            let logPrior = DailyLog(date: priorDay)
            logPrior.sleepHours = 4.5
            context.insert(logPrior)
            let day = jstCal.date(byAdding: .day, value: -i, to: today)!
            let archive = ActivityArchive(date: day)
            archive.masterMetric = 0.2
            context.insert(archive)
        }
        try context.save()
        let range = DateRange.lastNDays(10, asOf: jstNow)
        let patterns = service.patternsDetected(over: range)
        XCTAssertTrue(patterns.contains { $0.patternType == .sleepImpact })
    }

    func test_patternsDetected_fastingConsistency_detectsDecline() throws {
        let service = TrendAnalyticsService(modelContext: context)
        let today = jstCal.startOfDay(for: jstNow)
        // First half of 14d range: completed fasts. Second half: not completed.
        for i in 0..<14 {
            let day = jstCal.date(byAdding: .day, value: -(13 - i), to: today)!
            let log = DailyLog(date: day)
            if i < 7 {
                log.fastStart = day
                log.fastEnd = jstCal.date(byAdding: .hour, value: 16, to: day)
            }
            context.insert(log)
        }
        try context.save()
        let range = DateRange.lastNDays(14, asOf: jstNow)
        let patterns = service.patternsDetected(over: range)
        XCTAssertTrue(patterns.contains { $0.patternType == .fastingConsistency })
    }

    func test_patternsDetected_learningStreakDecay_detectsDrop() throws {
        let service = TrendAnalyticsService(modelContext: context)
        let today = jstCal.startOfDay(for: jstNow)
        // 4 weeks of data. Weeks 1-2: 100 min/wk learning. Weeks 3-4: 10 min/wk.
        for i in 0..<28 {
            let day = jstCal.date(byAdding: .day, value: -(27 - i), to: today)!
            let log = DailyLog(date: day)
            log.japaneseMinutes = (i < 14) ? 14 : 1
            context.insert(log)
        }
        try context.save()
        let range = DateRange.lastNDays(28, asOf: jstNow)
        let patterns = service.patternsDetected(over: range)
        XCTAssertTrue(patterns.contains { $0.patternType == .learningStreakDecay })
    }

    func test_patternsDetected_emptyData_returnsEmptyList() {
        let service = TrendAnalyticsService(modelContext: context)
        let range = DateRange.lastNDays(7, asOf: jstNow)
        let patterns = service.patternsDetected(over: range)
        XCTAssertTrue(patterns.isEmpty)
    }

    // MARK: - summaryForCoach

    func test_summaryForCoach_withFullData_producesAllFields() throws {
        let service = TrendAnalyticsService(modelContext: context)
        let today = jstCal.startOfDay(for: jstNow)
        for i in 0..<14 {
            let day = jstCal.date(byAdding: .day, value: -(13 - i), to: today)!
            let archive = ActivityArchive(date: day)
            archive.masterMetric = 0.7
            context.insert(archive)
            let log = DailyLog(date: day)
            log.waterOz = 80
            log.japaneseMinutes = 30
            log.fastStart = day
            log.fastEnd = jstCal.date(byAdding: .hour, value: 16, to: day)
            context.insert(log)
            if i % 2 == 0 {
                let event = WorkoutEvent(date: day, completed: true, source: .lift)
                context.insert(event)
                let lift = LiftSession(date: day, template: "Lift A")
                lift.totalVolumeLbs = 10_000
                context.insert(lift)
            }
        }
        try context.save()

        let range = DateRange.lastNDays(14, asOf: jstNow)
        let summary = service.summaryForCoach(over: range)

        XCTAssertGreaterThan(summary.dailyAdherenceMean, 0)
        XCTAssertGreaterThan(summary.workoutsPerWeekMean, 0)
        XCTAssertGreaterThan(summary.fastingCompletionRate, 0.9)
        XCTAssertGreaterThan(summary.learningMinutesPerWeekMean, 100)
        XCTAssertFalse(summary.summaryForPrompt.isEmpty)
        XCTAssertTrue(summary.summaryForPrompt.contains("Workouts/week"))
    }

    func test_summaryForCoach_emptyData_doesNotCrash() {
        let service = TrendAnalyticsService(modelContext: context)
        let range = DateRange.lastNDays(7, asOf: jstNow)
        let summary = service.summaryForCoach(over: range)
        XCTAssertEqual(summary.workoutsPerWeekMean, 0)
        XCTAssertEqual(summary.fastingCompletionRate, 0)
    }

    // MARK: - DateRange

    func test_dateRange_lastNDays_inclusive() {
        let range = DateRange.lastNDays(7, asOf: jstNow)
        let days = numberOfDays(from: range.start, to: range.end)
        XCTAssertEqual(days, 6)  // 6 day-deltas covering 7 inclusive days
    }

    // MARK: - Helpers

    private var jstNow: Date {
        // Anchor to a fixed date to keep tests deterministic across the run.
        return jstCal.date(from: DateComponents(year: 2026, month: 5, day: 7, hour: 9))!
    }

    private func numberOfDays(from start: Date, to end: Date) -> Int {
        return jstCal.dateComponents([.day], from: start, to: end).day ?? 0
    }
}
