import XCTest
import SwiftData
@testable import PersonalOptimization

/// Parity guarantee for the shared goal snapshot: every glanceable surface
/// (watch home, complication, Live Activity refresh) reads this, so its
/// scheduled-domain math must match DailySummaryService.todayProtocol exactly
/// and honor grace and tombstones. The audit found this file had zero direct
/// coverage despite being the anti-drift keystone.
@MainActor
final class ProtocolGoalSnapshotTests: XCTestCase {

    /// Retained for the test's lifetime. A local container dropped after the
    /// helper returns leaves `mainContext` dangling and traps EXC_BREAKPOINT
    /// (documented container-retention hazard).
    private var container: ModelContainer!

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    private func makeContext() throws -> ModelContext {
        let made = try InMemoryContainer.make()
        container = made
        return made.mainContext
    }

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    /// Seed a training block for the asOf weekday so workout becomes scheduled.
    private func seedTrainingBlock(_ context: ModelContext, asOf: Date) {
        let weekday = ProtocolRules.isoWeekday(for: asOf, calendar: cal)
        context.insert(ScheduleBlock(
            dayOfWeek: weekday,
            startTime: "09:30",
            endTime: "11:00",
            activity: "Lift A",
            type: .training,
            module: "lift_a"
        ))
    }

    func testRestDayTotalsThreeDomains() throws {
        let context = try makeContext()
        // No schedule blocks at all → workout unscheduled → 3 always-on domains.
        let snap = ProtocolGoalSnapshot.make(modelContext: context)
        XCTAssertEqual(snap.totalDomains, 3)
        XCTAssertEqual(snap.completedDomains, 0)
    }

    func testTrainingDayTotalsFourDomains() throws {
        let context = try makeContext()
        let now = Date()
        seedTrainingBlock(context, asOf: now)
        let snap = ProtocolGoalSnapshot.make(modelContext: context, asOf: now)
        XCTAssertEqual(snap.totalDomains, 4)
    }

    func testCompletedDomainsCount() throws {
        let context = try makeContext()
        let now = Date()
        seedTrainingBlock(context, asOf: now)

        let log = DailyLog(date: now)
        log.fastEnd = now                       // fasting done
        log.waterOz = 200                       // above any day-type target
        log.japaneseMinutes = 30                // learning done
        context.insert(log)
        context.insert(WorkoutEvent(date: now, completed: true, source: .lift))
        try context.save()

        let snap = ProtocolGoalSnapshot.make(modelContext: context, asOf: now)
        XCTAssertEqual(snap.completedDomains, 4)
        XCTAssertEqual(snap.totalDomains, 4)
        XCTAssertEqual(snap.progress, 1.0)
    }

    func testGraceCoversScheduledDomains() throws {
        let context = try makeContext()
        let now = Date()
        seedTrainingBlock(context, asOf: now)
        let profile = UserProfile()
        profile.travelModeActiveUntil = cal.date(byAdding: .day, value: 2, to: now)
        context.insert(profile)
        try context.save()

        let snap = ProtocolGoalSnapshot.make(modelContext: context, asOf: now)
        XCTAssertEqual(snap.completedDomains, snap.totalDomains, "travel grace completes every scheduled domain")
    }

    func testTombstonedLogIsIgnored() throws {
        let context = try makeContext()
        let now = Date()

        let tombstone = DailyLog(date: now)
        tombstone.fastEnd = now
        tombstone.waterOz = 200
        tombstone.japaneseMinutes = 60
        tombstone.supersededAt = now
        context.insert(tombstone)
        try context.save()

        let snap = ProtocolGoalSnapshot.make(modelContext: context, asOf: now)
        XCTAssertEqual(snap.completedDomains, 0, "a superseded duplicate must contribute nothing")
    }

    func testParityWithDailySummaryTally() throws {
        let context = try makeContext()
        let now = Date()
        seedTrainingBlock(context, asOf: now)

        let log = DailyLog(date: now)
        log.fastEnd = now
        log.waterOz = 200
        // learning intentionally NOT done; workout not done either.
        context.insert(log)
        try context.save()

        let snap = ProtocolGoalSnapshot.make(modelContext: context, asOf: now)
        // try? justified - bundled resource; nil targets and the summary's own
        // fallback exercise the same shared 64oz floor.
        let targets = try? ScheduleConfigLoader.loadCached().hydrationTargetsOz
        let tally = DailySummaryService(modelContext: context, hydrationTargets: targets)
            .todayProtocol(asOf: now)

        XCTAssertEqual(snap.completedDomains, tally.completedCount)
        XCTAssertEqual(snap.totalDomains, tally.scheduledCount)
    }

    func testStreakValueFlowsThrough() throws {
        let context = try makeContext()
        let counter = StreakCounter(domain: .protocolAdherence)
        counter.currentStreak = 12
        context.insert(counter)
        try context.save()

        let snap = ProtocolGoalSnapshot.make(modelContext: context)
        XCTAssertEqual(snap.streak, 12)
    }
}
