import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class WeeklyReflectionServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var service: WeeklyReflectionService!
    private var jstCal: Calendar!

    override func setUp() async throws {
        try await super.setUp()
        container = try InMemoryContainer.make()
        context = container.mainContext
        service = WeeklyReflectionService(modelContext: context)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        jstCal = cal
    }

    override func tearDown() async throws {
        service = nil
        context = nil
        container = nil
        jstCal = nil
        try await super.tearDown()
    }

    func test_currentOrGenerate_emptyArchive_returnsZeroAdherence() throws {
        let r = try service.currentOrGenerate()
        XCTAssertEqual(r.adherencePercent, 0, accuracy: 0.001)
        XCTAssertEqual(r.workoutCount, 0)
    }

    func test_currentOrGenerate_isIdempotentPerWeek() throws {
        let first = try service.currentOrGenerate()
        let second = try service.currentOrGenerate()
        XCTAssertEqual(first.persistentModelID, second.persistentModelID)
    }

    func test_regenerate_replacesExistingRow() throws {
        let first = try service.currentOrGenerate()
        first.userNote = "manual override"
        try context.save()

        let regenerated = try service.regenerate()
        XCTAssertNotEqual(first.persistentModelID, regenerated.persistentModelID)
    }

    func test_weekRollupAggregatesArchives() throws {
        let monday = service.mondayOfWeek(containing: Date())
        // Seed three days within the week with different metric values.
        for offset in 0..<3 {
            let day = jstCal.date(byAdding: .day, value: offset, to: monday)!
            let archive = ActivityArchive(date: day)
            archive.masterMetric = 0.6
            archive.workoutCount = 1
            archive.hydrationOz = 80
            archive.fastingHours = 16
            archive.learningMinutes = 30
            archive.dominantMascotState = "proud"
            context.insert(archive)
        }
        try context.save()

        let r = try service.currentOrGenerate()
        XCTAssertEqual(r.workoutCount, 3)
        XCTAssertEqual(r.hydrationDaysMet, 3)
        XCTAssertEqual(r.fastingDaysCompleted, 3)
        XCTAssertEqual(r.learningMinutesTotal, 90)
        XCTAssertEqual(r.adherencePercent, 0.6, accuracy: 0.001)
        XCTAssertEqual(r.dominantMascotState, "proud")
    }

    func test_composeCoachMessage_thresholds() {
        XCTAssertTrue(WeeklyReflectionService.composeCoachMessage(adherence: 0.9, workouts: 5, bestDomain: "workout").contains("standard"))
        XCTAssertTrue(WeeklyReflectionService.composeCoachMessage(adherence: 0.7, workouts: 3, bestDomain: "hydration").contains("Solid"))
        XCTAssertTrue(WeeklyReflectionService.composeCoachMessage(adherence: 0.4, workouts: 1, bestDomain: "learning").contains("hits"))
        XCTAssertTrue(WeeklyReflectionService.composeCoachMessage(adherence: 0.1, workouts: 0, bestDomain: "fasting").contains("Tough"))
    }
}
