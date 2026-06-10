import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class EngagementMetricsServiceTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        return c
    }()

    /// Retains every container for the test's lifetime. SwiftData traps
    /// (EXC_BREAKPOINT) on a fetch once the owning `ModelContainer` deallocates,
    /// so the inline `.make().mainContext` shorthand is unsafe. Released when the
    /// per-method test instance deallocates; no tearDown needed.
    private var containers: [ModelContainer] = []

    private func makeContext() throws -> ModelContext {
        let container = try InMemoryContainer.make()
        containers.append(container)
        return container.mainContext
    }

    /// Fixed first-launch day at JST midnight so day math is deterministic.
    private func firstDay() -> Date {
        cal.startOfDay(for: Self.jst(year: 2026, month: 3, day: 1))
    }

    private func day(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: firstDay())!
    }

    private static func jst(year: Int, month: Int, day: Int) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        return c.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func service(_ ctx: ModelContext, week4Defaults: UserDefaults = .standard) -> EngagementMetricsService {
        EngagementMetricsService(
            modelContext: ctx,
            calendar: cal,
            firstLaunch: firstDay(),
            hydrationTargets: nil,
            week4Defaults: week4Defaults
        )
    }

    /// Seeds a protocol-complete DailyLog for the given day offset. Decision
    /// 018: the protocol day now requires fasting + hydration + learning (and
    /// a workout only on scheduled training weekdays — none are seeded here, so
    /// workout is not required). fast ended + 64 oz + 30 learning minutes.
    private func seedProtocolDay(_ ctx: ModelContext, offset: Int) {
        let d = day(offset)
        let log = DailyLog(date: d, calendar: cal)
        log.fastEnd = cal.date(byAdding: .hour, value: 12, to: d)
        log.waterOz = 64
        log.japaneseMinutes = 30
        ctx.insert(log)
    }

    // MARK: - Indicator 1: establishment

    func test_establishment_inWeekOne_whenSevenConsecutiveProtocolDays() throws {
        let ctx = try makeContext()
        for i in 0..<7 { seedProtocolDay(ctx, offset: i) }
        try ctx.save()

        let m = service(ctx).compute(asOf: day(10))
        XCTAssertTrue(m.establishedSevenDayStreak)
        XCTAssertTrue(m.establishedInWeekOne, "Seventh day landed on day 6, within week one.")
        XCTAssertEqual(m.daysToEstablishment, 6)
    }

    func test_establishment_notWeekOne_whenStreakStartsLate() throws {
        let ctx = try makeContext()
        for i in 20..<27 { seedProtocolDay(ctx, offset: i) }
        try ctx.save()

        let m = service(ctx).compute(asOf: day(30))
        XCTAssertTrue(m.establishedSevenDayStreak)
        XCTAssertFalse(m.establishedInWeekOne)
        XCTAssertEqual(m.daysToEstablishment, 26)
    }

    func test_noEstablishment_whenFewerThanSevenConsecutive() throws {
        let ctx = try makeContext()
        for i in 0..<6 { seedProtocolDay(ctx, offset: i) }
        try ctx.save()

        let m = service(ctx).compute(asOf: day(10))
        XCTAssertFalse(m.establishedSevenDayStreak)
        XCTAssertNil(m.daysToEstablishment)
    }

    func test_noEstablishment_whenGapBreaksTheRun() throws {
        let ctx = try makeContext()
        for i in 0..<4 { seedProtocolDay(ctx, offset: i) }
        // gap at day 4
        for i in 5..<9 { seedProtocolDay(ctx, offset: i) }
        try ctx.save()

        let m = service(ctx).compute(asOf: day(12))
        XCTAssertFalse(m.establishedSevenDayStreak, "No 7 consecutive days exist across the gap.")
    }

    // MARK: - Indicator 2: day-over-day return rate (CURR)

    func test_dayOverDayReturnRate_computesConditionalProbability() throws {
        let ctx = try makeContext()
        // Active days {0,1,2,5}; today = day 7 so every eligible day's tomorrow
        // is a fully past, observable day.
        for i in [0, 1, 2, 5] {
            let log = DailyLog(date: day(i), calendar: cal)
            log.waterOz = 16
            ctx.insert(log)
        }
        try ctx.save()

        let m = service(ctx).compute(asOf: day(7))
        XCTAssertEqual(m.activeDaysCount, 4)
        // Eligible (tomorrow < today): {0,1,2,5}. Returned next-day: 0->1, 1->2.
        XCTAssertEqual(m.dayOverDayReturnRate ?? -1, 0.5, accuracy: 0.0001)
    }

    func test_establishment_notWeekOne_whenSeventhDayLandsOnDay8() throws {
        let ctx = try makeContext()
        // User skipped day 0; protocol-complete on offsets 1..7. The 7-run ends
        // on offset 7 (the 8th calendar day of use), outside week one.
        for i in 1...7 { seedProtocolDay(ctx, offset: i) }
        try ctx.save()

        let m = service(ctx).compute(asOf: day(10))
        XCTAssertTrue(m.establishedSevenDayStreak)
        XCTAssertFalse(m.establishedInWeekOne, "Seventh day on offset 7 is the 8th day, outside week one.")
        XCTAssertEqual(m.daysToEstablishment, 7)
    }

    func test_returnRate_nilWhenNoEligibleDays() throws {
        let ctx = try makeContext()
        // Only today is active; no day strictly before today.
        let log = DailyLog(date: day(0), calendar: cal)
        log.waterOz = 16
        ctx.insert(log)
        try ctx.save()

        let m = service(ctx).compute(asOf: day(0))
        XCTAssertNil(m.dayOverDayReturnRate)
    }

    func test_graceDays_excludedFromActiveDays() throws {
        let ctx = try makeContext()
        // A freeze-sourced workout event is protection, not engagement.
        ctx.insert(WorkoutEvent(date: day(0), completed: true, source: .freeze))
        try ctx.save()

        let m = service(ctx).compute(asOf: day(3))
        XCTAssertEqual(m.activeDaysCount, 0, "Grace days must not count as active engagement.")
    }

    // MARK: - Indicator 3: grace-day usage

    func test_graceUsage_countsDistinctDaysBySource() throws {
        let ctx = try makeContext()
        ctx.insert(FreezeApplication(domain: .hydration, date: day(1)))
        ctx.insert(WorkoutEvent(date: day(2), completed: true, source: .sickDay))
        ctx.insert(WorkoutEvent(date: day(3), completed: true, source: .travel))
        try ctx.save()

        let m = service(ctx).compute(asOf: day(5))
        XCTAssertEqual(m.graceDaysApplied, 3)
        XCTAssertEqual(m.graceBySource["freeze"], 1)
        XCTAssertEqual(m.graceBySource["sick day"], 1)
        XCTAssertEqual(m.graceBySource["travel"], 1)
    }

    func test_graceUsage_dedupesFanOutFreezeRowsToOneDay() throws {
        let ctx = try makeContext()
        // A sick day fans out one FreezeApplication per non-workout domain plus
        // a workout event, all on the same calendar day. Must count as ONE day.
        ctx.insert(WorkoutEvent(date: day(1), completed: true, source: .sickDay))
        for domain in [StreakDomain.fasting, .hydration, .learning, .protocolAdherence] {
            ctx.insert(FreezeApplication(domain: domain, date: day(1)))
        }
        try ctx.save()

        let m = service(ctx).compute(asOf: day(3))
        XCTAssertEqual(m.graceDaysApplied, 1, "All fan-out rows collapse to a single grace day.")
        XCTAssertEqual(m.graceBySource["sick day"], 1)
        XCTAssertNil(m.graceBySource["freeze"], "Freeze rows on a sick day are not double-labeled.")
    }

    // MARK: - Indicator 4: joint-streak survival

    func test_jointStreak_isMinOfSelfAndPartner_whenPaired() throws {
        let ctx = try makeContext()
        let counter = StreakCounter(domain: .protocolAdherence)
        counter.currentStreak = 5
        ctx.insert(counter)
        try ctx.save()

        let m = service(ctx).compute(asOf: day(5), partnerCurrentStreak: 3)
        XCTAssertTrue(m.partnerPaired)
        XCTAssertEqual(m.soloStreak, 5)
        XCTAssertEqual(m.jointStreak, 3)
    }

    func test_jointStreak_nilWhenNoPartner() throws {
        let ctx = try makeContext()
        let m = service(ctx).compute(asOf: day(5))
        XCTAssertFalse(m.partnerPaired)
        XCTAssertNil(m.jointStreak)
    }

    // MARK: - Indicator 5: insight engagement

    func test_insightEngagement_ratesAndGate() throws {
        let ctx = try makeContext()
        let interactions: [CoachInsightInteraction] = [.ignored, .viewed, .dismissed, .actedOn, .markedHelpful]
        for interaction in interactions {
            let insight = CoachInsight(generatedAt: day(2), insightText: "x")
            insight.userInteraction = interaction
            ctx.insert(insight)
        }
        try ctx.save()

        let m = service(ctx).compute(asOf: day(5))
        XCTAssertEqual(m.insightsShown, 5)
        // Deliberate interactions: dismissed, actedOn, markedHelpful = 3 of 5.
        XCTAssertEqual(m.insightInteractionRate ?? -1, 0.6, accuracy: 0.0001)
        XCTAssertEqual(m.insightHelpful, 1)
        XCTAssertEqual(m.insightUnhelpful, 0)
        XCTAssertTrue(m.meetsInsightGate, "60% interaction and 1:0 helpful clears the gate.")
    }

    func test_insightGate_failsWhenUnhelpfulDominates() throws {
        let ctx = try makeContext()
        let insight1 = CoachInsight(generatedAt: day(2), insightText: "x")
        insight1.userInteraction = .markedUnhelpful
        let insight2 = CoachInsight(generatedAt: day(2), insightText: "y")
        insight2.userInteraction = .markedHelpful
        ctx.insert(insight1)
        ctx.insert(insight2)
        try ctx.save()

        let m = service(ctx).compute(asOf: day(5))
        XCTAssertEqual(m.insightHelpful, 1)
        XCTAssertEqual(m.insightUnhelpful, 1)
        XCTAssertFalse(m.meetsInsightGate, "1:1 helpful:unhelpful is below the 3:1 gate.")
    }

    // MARK: - Indicator 6: qualitative week-4

    func test_week4_captureRoundTrips() throws {
        let ctx = try makeContext()
        let suite = UserDefaults(suiteName: "test-week4-\(UUID().uuidString)")!
        defer { suite.removePersistentDomain(forName: suite.description) }

        let before = service(ctx, week4Defaults: suite).compute(asOf: day(28))
        XCTAssertFalse(before.week4Captured)
        XCTAssertNil(before.week4FeelsMotivating)

        Week4CheckIn.record(feelsMotivating: false, into: suite)
        let after = service(ctx, week4Defaults: suite).compute(asOf: day(28))
        XCTAssertTrue(after.week4Captured)
        XCTAssertEqual(after.week4FeelsMotivating, false)
    }

    // MARK: - meta

    func test_daysSinceFirstLaunch() throws {
        let ctx = try makeContext()
        let m = service(ctx).compute(asOf: day(14))
        XCTAssertEqual(m.daysSinceFirstLaunch, 14)
    }
}
