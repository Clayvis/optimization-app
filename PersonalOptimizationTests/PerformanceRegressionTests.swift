import XCTest
import SwiftData
@testable import PersonalOptimization

/// Performance baselines for the hot paths called out in PERFORMANCE.md.
/// Each test seeds a realistic-volume in-memory store and times the
/// operation. XCTest's measure block records the baseline; subsequent
/// runs flag regressions when the runtime drifts beyond the configured
/// stddev. Numbers here target simulator; real-hardware thresholds in
/// PERFORMANCE.md still apply for milestone gates.
@MainActor
final class PerformanceRegressionTests: XCTestCase {

    /// PERFORMANCE.md target: schedule resolution <50ms. Seeded with a
    /// realistic 50-block weekly schedule plus a year of DailyLog rows so
    /// the test exercises the predicate path on a non-trivial table.
    func test_perf_schedule_currentBlock() throws {
        let container = try InMemoryContainer.make()
        let ctx = container.mainContext
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())

        // Seed a 7-day x ~7 blocks per day = 49 blocks weekly schedule.
        for day in 1...7 {
            for hour in stride(from: 6, to: 22, by: 2) {
                let block = ScheduleBlock(
                    dayOfWeek: day,
                    startTime: String(format: "%02d:00", hour),
                    endTime: String(format: "%02d:00", hour + 1),
                    activity: "block-\(day)-\(hour)",
                    type: .training,
                    module: hour == 6 ? "lift" : nil
                )
                ctx.insert(block)
            }
        }
        // 365 DailyLog rows so unbounded fetches show up as slow if they slip in.
        for offset in 0..<365 {
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            ctx.insert(DailyLog(date: d))
        }
        try ctx.save()

        let scheduleService = ScheduleService(modelContext: ctx)
        measure {
            for _ in 0..<10 {
                _ = scheduleService.currentBlock(at: Date())
            }
        }
    }

    /// PERFORMANCE.md target: character state recompute <30ms. The
    /// `gatherInputs` predicates take the heavy lifting; we seed enough
    /// rows that an unbounded fetch regression would be obvious.
    func test_perf_characterState_gatherInputs() throws {
        let container = try InMemoryContainer.make()
        let ctx = container.mainContext
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())

        // 365 DailyLog rows, plus 100 LiftSession rows (PR check fans out).
        for offset in 0..<365 {
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            ctx.insert(DailyLog(date: d))
        }
        for offset in 0..<100 {
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let session = LiftSession(date: d, template: "Lift A")
            session.totalVolumeLbs = Double(1000 + offset * 25)
            ctx.insert(session)
        }
        try ctx.save()

        let tz = TimeZone(identifier: "Asia/Tokyo") ?? .current
        measure {
            for _ in 0..<10 {
                _ = CharacterStateService.gatherInputs(modelContext: ctx, timezone: tz)
            }
        }
    }

    /// PERFORMANCE.md target: DailySummaryService.todayProtocol fast enough
    /// that TodayView's body evaluation stays under 100ms. With the Item 5
    /// predicate push-down, this should remain stable as DailyLog grows.
    func test_perf_dailySummary_todayProtocol_under1k_rows() throws {
        let container = try InMemoryContainer.make()
        let ctx = container.mainContext
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())

        // Match Item 5 plan's threshold: 1000 DailyLog rows + 1000 WorkoutEvents.
        for offset in 0..<1000 {
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let log = DailyLog(date: d)
            log.waterOz = 32
            ctx.insert(log)
            ctx.insert(WorkoutEvent(date: d, completed: true, source: .lift))
        }
        try ctx.save()

        let service = DailySummaryService(modelContext: ctx)
        measure {
            for _ in 0..<10 {
                _ = service.todayProtocol(asOf: Date())
            }
        }
    }
}
