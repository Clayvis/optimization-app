import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class DurabilityHeadlineServiceTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        return c
    }()

    /// Retains containers for the test's lifetime; SwiftData traps on a fetch
    /// once the owning ModelContainer deallocates. Released at instance dealloc.
    private var containers: [ModelContainer] = []

    private func makeContext() throws -> ModelContext {
        let container = try InMemoryContainer.make()
        containers.append(container)
        return container.mainContext
    }

    private func service(_ ctx: ModelContext, firstLaunch: Date) -> DurabilityHeadlineService {
        DurabilityHeadlineService(modelContext: ctx, calendar: cal, firstLaunch: firstLaunch, hydrationTargets: nil)
    }

    private func counter(_ ctx: ModelContext, _ domain: StreakDomain, current: Int = 0, longest: Int = 0) {
        let c = StreakCounter(domain: domain)
        c.currentStreak = current
        c.longestStreak = longest
        ctx.insert(c)
    }

    func test_bootstrapPhase_underThirtyDays_streakLeadsNoTrend() throws {
        let ctx = try makeContext()
        counter(ctx, .protocolAdherence, current: 5, longest: 5)
        try ctx.save()

        let now = Date()
        let firstLaunch = cal.date(byAdding: .day, value: -10, to: now)!
        let h = service(ctx, firstLaunch: firstLaunch).headline(asOf: now)

        XCTAssertEqual(h.phase, .bootstrap)
        XCTAssertNil(h.trendLine, "Bootstrap weeks keep the focus on the streak.")
        XCTAssertEqual(h.streakDays, 5)
    }

    func test_establishedPhase_afterThirtyDays_identityAndTrendLead() throws {
        let ctx = try makeContext()
        counter(ctx, .protocolAdherence, current: 32, longest: 32)
        try ctx.save()

        let now = Date()
        let firstLaunch = cal.date(byAdding: .day, value: -35, to: now)!
        let h = service(ctx, firstLaunch: firstLaunch).headline(asOf: now)

        XCTAssertEqual(h.phase, .established)
        XCTAssertFalse(h.identityLine.isEmpty)
        XCTAssertNotNil(h.trendLine, "Established phase always surfaces a trend or fallback line.")
        XCTAssertEqual(h.streakDays, 32)
    }

    func test_identityStatement_reflectsMostProvenDomain() throws {
        let ctx = try makeContext()
        counter(ctx, .workout, current: 4, longest: 10)
        counter(ctx, .hydration, current: 2, longest: 3)
        counter(ctx, .learning, current: 1, longest: 5)
        try ctx.save()

        let now = Date()
        let firstLaunch = cal.date(byAdding: .day, value: -40, to: now)!
        let h = service(ctx, firstLaunch: firstLaunch).headline(asOf: now)

        XCTAssertEqual(h.identityLine, IdentityCopy.identityStatement(topDomain: .workout))
    }

    func test_identityStatement_genericWhenNothingEstablished() throws {
        let ctx = try makeContext()
        try ctx.save()

        let now = Date()
        let firstLaunch = cal.date(byAdding: .day, value: -40, to: now)!
        let h = service(ctx, firstLaunch: firstLaunch).headline(asOf: now)

        XCTAssertEqual(h.identityLine, IdentityCopy.identityStatement(topDomain: nil))
    }

    func test_exactlyThirtyDays_isEstablished() throws {
        let ctx = try makeContext()
        try ctx.save()
        let now = Date()
        let firstLaunch = cal.date(byAdding: .day, value: -30, to: now)!
        let h = service(ctx, firstLaunch: firstLaunch).headline(asOf: now)
        XCTAssertEqual(h.phase, .established)
    }
}
