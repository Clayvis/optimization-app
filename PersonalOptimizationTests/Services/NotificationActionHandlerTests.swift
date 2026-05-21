import XCTest
import UserNotifications
import SwiftData
@testable import PersonalOptimization

@MainActor
final class NotificationActionHandlerTests: XCTestCase {

    func test_log16ozAction_writesHydrationEntry() throws {
        let container = try InMemoryContainer.make()
        NotificationActionHandler.shared.attach(modelContainer: container)
        NotificationActionHandler.shared.handle(
            actionId: NotificationIdentifier.actionLog16oz,
            category: NotificationIdentifier.hydrationCategory
        )
        let entries = try container.mainContext.fetch(FetchDescriptor<HydrationEntry>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.amountOz, 16)
    }

    func test_log8ozAction_writesHydrationEntry() throws {
        let container = try InMemoryContainer.make()
        NotificationActionHandler.shared.attach(modelContainer: container)
        NotificationActionHandler.shared.handle(
            actionId: NotificationIdentifier.actionLog8oz,
            category: NotificationIdentifier.hydrationCategory
        )
        let entries = try container.mainContext.fetch(FetchDescriptor<HydrationEntry>())
        XCTAssertEqual(entries.first?.amountOz, 8)
    }

    func test_skipAction_doesNotWriteLog() throws {
        let container = try InMemoryContainer.make()
        NotificationActionHandler.shared.attach(modelContainer: container)
        NotificationActionHandler.shared.handle(
            actionId: NotificationIdentifier.actionSkip,
            category: NotificationIdentifier.hydrationCategory
        )
        let entries = try container.mainContext.fetch(FetchDescriptor<HydrationEntry>())
        XCTAssertTrue(entries.isEmpty)
    }

    func test_unknownCategory_isNoOp() throws {
        let container = try InMemoryContainer.make()
        NotificationActionHandler.shared.attach(modelContainer: container)
        NotificationActionHandler.shared.handle(
            actionId: NotificationIdentifier.actionLog16oz,
            category: "unknown.category"
        )
        let entries = try container.mainContext.fetch(FetchDescriptor<HydrationEntry>())
        XCTAssertTrue(entries.isEmpty)
    }

    func test_unknownAction_inHydrationCategory_isNoOp() throws {
        let container = try InMemoryContainer.make()
        NotificationActionHandler.shared.attach(modelContainer: container)
        NotificationActionHandler.shared.handle(
            actionId: "log_999oz",
            category: NotificationIdentifier.hydrationCategory
        )
        let entries = try container.mainContext.fetch(FetchDescriptor<HydrationEntry>())
        XCTAssertTrue(entries.isEmpty)
    }
}
