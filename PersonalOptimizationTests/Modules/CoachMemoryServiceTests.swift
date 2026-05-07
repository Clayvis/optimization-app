import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class CoachMemoryServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var service: CoachMemoryService!

    override func setUp() async throws {
        try await super.setUp()
        container = try InMemoryContainer.make()
        context = container.mainContext
        service = CoachMemoryService(modelContext: context)
    }

    override func tearDown() async throws {
        service = nil
        context = nil
        container = nil
        try await super.tearDown()
    }

    func test_add_persistsRow() throws {
        _ = try service.add(value: "Sick kid this week", expiresIn: 7)
        XCTAssertEqual(service.active().count, 1)
    }

    func test_add_emptyValue_throws() {
        XCTAssertThrowsError(try service.add(value: "  "))
    }

    func test_add_withSameKey_replacesPrevious() throws {
        _ = try service.add(value: "achilles flaring v1", key: "achilles_flare")
        _ = try service.add(value: "achilles flaring v2", key: "achilles_flare")
        XCTAssertEqual(service.active().count, 1)
        XCTAssertEqual(service.active().first?.value, "achilles flaring v2")
    }

    func test_active_filtersExpired() throws {
        let m = try service.add(value: "old note", expiresIn: 1)
        m.expiresAt = Date().addingTimeInterval(-3600)
        try context.save()
        XCTAssertEqual(service.active().count, 0)
    }

    func test_active_sortsByImportanceDescending() throws {
        _ = try service.add(value: "low priority", importance: 2)
        _ = try service.add(value: "high priority", importance: 5)
        _ = try service.add(value: "mid priority", importance: 3)
        let actives = service.active()
        XCTAssertEqual(actives.first?.value, "high priority")
    }

    func test_summaryForCoach_isEmptyWhenNoRows() {
        XCTAssertEqual(service.summaryForCoach(), "")
    }

    func test_summaryForCoach_includesActiveItems() throws {
        _ = try service.add(value: "achilles flare", importance: 5)
        _ = try service.add(value: "going on vacation 5/15", importance: 4)
        let summary = service.summaryForCoach()
        XCTAssertTrue(summary.contains("achilles flare"))
        XCTAssertTrue(summary.contains("vacation"))
    }
}
