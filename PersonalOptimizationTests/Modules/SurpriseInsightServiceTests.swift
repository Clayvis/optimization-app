import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class SurpriseInsightServiceTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        return c
    }()

    private var containers: [ModelContainer] = []

    private func makeContext() throws -> ModelContext {
        let container = try InMemoryContainer.make()
        containers.append(container)
        return container.mainContext
    }

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "surprise-test-\(UUID().uuidString)")!
    }

    private func firstDay() -> Date {
        cal.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 8))!
    }

    private func day(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: firstDay())!
    }

    private func service(_ ctx: ModelContext, defaults: UserDefaults) -> SurpriseInsightService {
        SurpriseInsightService(modelContext: ctx, calendar: cal, firstLaunch: firstDay(), hydrationTargets: nil, defaults: defaults)
    }

    private func seedStreak(_ ctx: ModelContext, longest: Int) {
        let c = StreakCounter(domain: .protocolAdherence)
        c.longestStreak = longest
        ctx.insert(c)
    }

    func test_surprise_whenEligibleAndRollLow() throws {
        let ctx = try makeContext()
        seedStreak(ctx, longest: 12)
        try ctx.save()
        let svc = service(ctx, defaults: freshDefaults())
        let s = svc.surpriseForToday(asOf: day(10), rollOverride: 0.10)
        XCTAssertNotNil(s)
        XCTAssertTrue(s?.body.contains("12 days") ?? false)
    }

    func test_noSurprise_whenRollAboveProbability() throws {
        let ctx = try makeContext()
        seedStreak(ctx, longest: 12)
        try ctx.save()
        let svc = service(ctx, defaults: freshDefaults())
        XCTAssertNil(svc.surpriseForToday(asOf: day(10), rollOverride: 0.90))
    }

    func test_noSurprise_beforeMinDataDays() throws {
        let ctx = try makeContext()
        seedStreak(ctx, longest: 12)
        try ctx.save()
        let svc = service(ctx, defaults: freshDefaults())
        XCTAssertNil(svc.surpriseForToday(asOf: day(3), rollOverride: 0.10), "Too early for surprises.")
    }

    func test_noSurprise_whenNothingNotable() throws {
        let ctx = try makeContext()
        // No streak counter, no patterns.
        let svc = service(ctx, defaults: freshDefaults())
        XCTAssertNil(svc.surpriseForToday(asOf: day(10), rollOverride: 0.10))
    }

    func test_cooldown_blocksWithinCooldownDays() throws {
        let ctx = try makeContext()
        seedStreak(ctx, longest: 12)
        try ctx.save()
        let defaults = freshDefaults()
        let svc = service(ctx, defaults: defaults)
        svc.markShown(asOf: day(9), body: "cached surprise")   // shown yesterday
        XCTAssertNil(svc.surpriseForToday(asOf: day(10), rollOverride: 0.10), "Within cooldown after a recent surprise.")
    }

    func test_cooldown_allowsAfterCooldown() throws {
        let ctx = try makeContext()
        seedStreak(ctx, longest: 12)
        try ctx.save()
        let defaults = freshDefaults()
        let svc = service(ctx, defaults: defaults)
        svc.markShown(asOf: day(5), body: "cached surprise")   // shown 5 days ago, cooldown is 3
        XCTAssertNotNil(svc.surpriseForToday(asOf: day(10), rollOverride: 0.10))
    }

    func test_idempotentWithinDay_keepsShowingAfterMarked() throws {
        let ctx = try makeContext()
        seedStreak(ctx, longest: 12)
        try ctx.save()
        let defaults = freshDefaults()
        let svc = service(ctx, defaults: defaults)
        svc.markShown(asOf: day(10), body: "cached surprise")  // already surfaced today
        // Even with a high roll, today's surprise keeps showing the SAME cached
        // body so the card is stable across re-renders.
        let s = svc.surpriseForToday(asOf: day(10), rollOverride: 0.99)
        XCTAssertEqual(s?.body, "cached surprise")
    }

    func test_dailyRoll_isStableAcrossCalls() throws {
        let ctx = try makeContext()
        seedStreak(ctx, longest: 12)
        try ctx.save()
        let svc = service(ctx, defaults: freshDefaults())
        // No rollOverride: uses the stable per-day roll. Two calls on the same day
        // must agree (deterministic).
        let a = svc.surpriseForToday(asOf: day(10))
        let b = svc.surpriseForToday(asOf: day(10))
        XCTAssertEqual(a == nil, b == nil, "The per-day decision must be stable across calls.")
    }
}
