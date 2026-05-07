import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class ImplementationIntentionServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var service: ImplementationIntentionService!

    override func setUp() async throws {
        try await super.setUp()
        container = try InMemoryContainer.make()
        context = container.mainContext
        service = ImplementationIntentionService(modelContext: context)
    }

    override func tearDown() async throws {
        service = nil
        context = nil
        container = nil
        try await super.tearDown()
    }

    func test_add_persistsRow() throws {
        _ = try service.add(trigger: "After morning coffee",
                            triggerType: .afterEvent,
                            action: "Drink 16 oz")
        XCTAssertEqual(service.active().count, 1)
        XCTAssertEqual(service.active().first?.trigger, "After morning coffee")
    }

    func test_add_emptyTrigger_throws() {
        XCTAssertThrowsError(try service.add(trigger: "  ",
                                             triggerType: .afterEvent,
                                             action: "Drink"))
    }

    func test_archive_hidesFromActive() throws {
        let intention = try service.add(trigger: "After dinner",
                                        triggerType: .afterEvent,
                                        action: "Close eating window")
        try service.archive(intention)
        XCTAssertEqual(service.active().count, 0)
    }

    func test_recordCompletion_setsLastCompletedAt() throws {
        let intention = try service.add(trigger: "Before bed",
                                        triggerType: .afterEvent,
                                        action: "Log Japanese")
        XCTAssertNil(intention.lastCompletedAt)
        try service.recordCompletion(intention)
        XCTAssertNotNil(intention.lastCompletedAt)
    }

    func test_seedStartersIfNeeded_addsFiveRows_onlyOnce() throws {
        let first = try service.seedStartersIfNeeded()
        XCTAssertEqual(first, 5)
        XCTAssertEqual(service.active().count, 5)
        let second = try service.seedStartersIfNeeded()
        XCTAssertEqual(second, 0, "Second call must be a no-op when rows exist")
        XCTAssertEqual(service.active().count, 5)
    }

    func test_update_changesFieldsAndPersists() throws {
        let intention = try service.add(trigger: "After dinner",
                                        triggerType: .afterEvent,
                                        action: "Close eating window")
        try service.update(intention,
                           trigger: "After 7pm",
                           triggerType: .time,
                           action: "Brush teeth + log",
                           triggerTimeMinutes: 19 * 60)
        XCTAssertEqual(intention.trigger, "After 7pm")
        XCTAssertEqual(intention.triggerType, .time)
        XCTAssertEqual(intention.triggerTimeMinutes, 19 * 60)
    }
}
