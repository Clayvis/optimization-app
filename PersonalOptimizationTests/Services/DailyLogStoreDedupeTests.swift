import XCTest
import SwiftData
@testable import PersonalOptimization

/// Covers the non-destructive DailyLog dedupe (decision 013, R1). The contract:
/// duplicates are merged into a canonical row and retained as neutralized,
/// superseded tombstones. Nothing is deleted, and aggregates never double-count.
@MainActor
final class DailyLogStoreDedupeTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private let jst = TimeZone(identifier: "Asia/Tokyo")!

    override func setUp() async throws {
        try await super.setUp()
        container = try InMemoryContainer.make()
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        try await super.tearDown()
    }

    private func calendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = jst
        return cal
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        let cal = calendar()
        return cal.startOfDay(for: cal.date(from: DateComponents(year: y, month: m, day: d))!)
    }

    func test_dedupe_mergesAndSupersedes_withoutDeleting() throws {
        let cal = calendar()
        let theDay = day(2026, 5, 4)
        let a = DailyLog(date: theDay, calendar: cal); a.waterOz = 40; a.japaneseMinutes = 20
        let b = DailyLog(date: theDay, calendar: cal); b.waterOz = 24; b.guitarMinutes = 15
        context.insert(a)
        context.insert(b)
        try context.save()

        try DailyLogStore(modelContext: context, calendar: cal).dedupe()

        let all = try context.fetch(FetchDescriptor<DailyLog>())
        XCTAssertEqual(all.count, 2, "Dedupe must not delete rows (retention).")

        let active = all.filter { $0.supersededAt == nil }
        let tombstones = all.filter { $0.supersededAt != nil }
        XCTAssertEqual(active.count, 1, "Exactly one canonical row remains active.")
        XCTAssertEqual(tombstones.count, 1, "The duplicate is retained as a superseded tombstone.")

        // Canonical carries the merged data (sum of counters, union of fields).
        let canonical = active[0]
        XCTAssertEqual(canonical.waterOz, 64, "waterOz should sum (40 + 24).")
        XCTAssertEqual(canonical.japaneseMinutes, 20)
        XCTAssertEqual(canonical.guitarMinutes, 15)

        // Tombstone is neutralized: contributes nothing.
        let tombstone = tombstones[0]
        XCTAssertEqual(tombstone.waterOz, 0)
        XCTAssertEqual(tombstone.japaneseMinutes, 0)
        XCTAssertEqual(tombstone.guitarMinutes, 0)

        // Aggregate across ALL rows (no reader-side filter) stays correct.
        let totalWater = all.reduce(0.0) { $0 + $1.waterOz }
        XCTAssertEqual(totalWater, 64, "Tombstone must not double-count.")
    }

    func test_dedupe_isIdempotent() throws {
        let cal = calendar()
        let theDay = day(2026, 5, 4)
        let a = DailyLog(date: theDay, calendar: cal); a.waterOz = 10
        let b = DailyLog(date: theDay, calendar: cal); b.waterOz = 10
        context.insert(a); context.insert(b)
        try context.save()

        let store = DailyLogStore(modelContext: context, calendar: cal)
        try store.dedupe()
        let afterFirst = try context.fetch(FetchDescriptor<DailyLog>()).filter { $0.supersededAt != nil }.count
        try store.dedupe()
        let afterSecond = try context.fetch(FetchDescriptor<DailyLog>()).filter { $0.supersededAt != nil }.count

        XCTAssertEqual(afterFirst, 1)
        XCTAssertEqual(afterSecond, 1, "Re-running dedupe must be a no-op.")
    }

    func test_upsert_returnsCanonicalNotTombstone() throws {
        let cal = calendar()
        let theDay = day(2026, 5, 4)
        let a = DailyLog(date: theDay, calendar: cal); a.waterOz = 30
        let b = DailyLog(date: theDay, calendar: cal); b.waterOz = 12
        context.insert(a); context.insert(b)
        try context.save()

        let store = DailyLogStore(modelContext: context, calendar: cal)
        try store.dedupe()

        let row = store.upsert(for: theDay)
        XCTAssertNil(row.supersededAt, "upsert must return the canonical row, never a tombstone.")
        XCTAssertEqual(row.waterOz, 42)
    }
}
