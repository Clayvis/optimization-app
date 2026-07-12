import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class LapseDetectionServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var service: LapseDetectionService!
    private var jstCal: Calendar!

    override func setUp() async throws {
        try await super.setUp()
        container = try InMemoryContainer.make()
        context = container.mainContext
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        jstCal = cal
        service = LapseDetectionService(modelContext: context, timezone: cal.timeZone)
    }

    override func tearDown() async throws {
        service = nil
        context = nil
        container = nil
        jstCal = nil
        try await super.tearDown()
    }

    func test_noArchives_returnsNoLapse() throws {
        let result = try service.recompute()
        XCTAssertNil(result)
    }

    func test_singleLowDay_doesNotTripSoftLapse() throws {
        try seedArchive(daysAgo: 0, metric: 0.1)
        let result = try service.recompute()
        XCTAssertNil(result, "1 day < 30% should not flag lapse (threshold is 2)")
    }

    func test_twoConsecutiveLowDays_tripsSoftLapse() throws {
        try seedArchive(daysAgo: 0, metric: 0.1)
        try seedArchive(daysAgo: 1, metric: 0.1)
        let result = try service.recompute()
        XCTAssertEqual(result?.severity, .soft)
    }

    func test_fiveConsecutiveLowDays_tripsHardLapse() throws {
        for offset in 0..<5 {
            try seedArchive(daysAgo: offset, metric: 0.1)
        }
        let result = try service.recompute()
        XCTAssertEqual(result?.severity, .hard)
    }

    func test_fourteenConsecutiveLowDays_tripsCrisisLapse() throws {
        for offset in 0..<14 {
            try seedArchive(daysAgo: offset, metric: 0.1)
        }
        let result = try service.recompute()
        XCTAssertEqual(result?.severity, .crisis)
    }

    func test_recoveredDayResolvesActiveLapse() throws {
        // Soft lapse over the prior two days, then today is a recovery day.
        try seedArchive(daysAgo: 1, metric: 0.1)
        try seedArchive(daysAgo: 2, metric: 0.1)
        _ = try service.recompute(asOf: dateDaysAgo(1))
        XCTAssertNotNil(service.currentActiveLapse(), "Lapse should be open before recovery")

        try seedArchive(daysAgo: 0, metric: 0.6)
        _ = try service.recompute()
        XCTAssertNil(service.currentActiveLapse(), "Lapse should resolve when adherence climbs")
    }

    // MARK: - Helpers

    private func seedArchive(daysAgo: Int, metric: Double) throws {
        let day = dateDaysAgo(daysAgo)
        let archive = ActivityArchive(date: day)
        archive.masterMetric = metric
        context.insert(archive)
        try context.save()
    }

    private func dateDaysAgo(_ n: Int) -> Date {
        let today = jstCal.startOfDay(for: Date())
        return jstCal.date(byAdding: .day, value: -n, to: today) ?? today
    }
}
