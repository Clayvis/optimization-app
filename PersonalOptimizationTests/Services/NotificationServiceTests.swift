import XCTest
import UserNotifications
@testable import PersonalOptimization

final class NotificationSuppressionRulesTests: XCTestCase {
    private let jst = TimeZone(identifier: "Asia/Tokyo")!

    func test_suppress_duringSleepWindow_2300_returnsTrue() {
        let date = jstDate(2026, 5, 4, 23, 0)
        XCTAssertTrue(NotificationSuppressionRules.shouldSuppressHydration(
            at: date, timezone: jst, morningIntakeOz: 0
        ))
    }

    func test_suppress_atSleepWindowStart_2200_returnsTrue() {
        let date = jstDate(2026, 5, 4, 22, 0)
        XCTAssertTrue(NotificationSuppressionRules.shouldSuppressHydration(
            at: date, timezone: jst, morningIntakeOz: 0
        ))
    }

    func test_suppress_duringSleepWindow_0500_returnsTrue() {
        let date = jstDate(2026, 5, 4, 5, 0)
        XCTAssertTrue(NotificationSuppressionRules.shouldSuppressHydration(
            at: date, timezone: jst, morningIntakeOz: 0
        ))
    }

    func test_suppress_atSleepWindowEnd_0700_returnsFalse() {
        // 07:00 is OUTSIDE the [22:00, 07:00) sleep range.
        let date = jstDate(2026, 5, 4, 7, 0)
        XCTAssertFalse(NotificationSuppressionRules.shouldSuppressHydration(
            at: date, timezone: jst, morningIntakeOz: 0
        ))
    }

    func test_suppress_afterHydrationCutoff_2100_returnsTrue() {
        let date = jstDate(2026, 5, 4, 21, 0)
        XCTAssertTrue(NotificationSuppressionRules.shouldSuppressHydration(
            at: date, timezone: jst, morningIntakeOz: 0
        ))
    }

    func test_suppress_pre1000WithMorningIntake_returnsTrue() {
        let date = jstDate(2026, 5, 4, 9, 0)
        XCTAssertTrue(NotificationSuppressionRules.shouldSuppressHydration(
            at: date, timezone: jst, morningIntakeOz: 24
        ))
    }

    func test_suppress_pre1000WithoutMorningIntake_returnsFalse() {
        let date = jstDate(2026, 5, 4, 9, 0)
        XCTAssertFalse(NotificationSuppressionRules.shouldSuppressHydration(
            at: date, timezone: jst, morningIntakeOz: 0
        ))
    }

    func test_suppress_midDay_noConditionsMatch_returnsFalse() {
        let date = jstDate(2026, 5, 4, 14, 0)
        XCTAssertFalse(NotificationSuppressionRules.shouldSuppressHydration(
            at: date, timezone: jst, morningIntakeOz: 0
        ))
    }

    private func jstDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = jst
        return cal.date(from: c)!
    }
}

// MARK: - Service tests with fake center

final class FakeNotificationCenter: NotificationCenterProtocol, @unchecked Sendable {
    var addedRequests: [UNNotificationRequest] = []
    var registeredCategories: Set<UNNotificationCategory> = []
    var authorizationRequestCount = 0
    var grantAuthorization = true

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        authorizationRequestCount += 1
        return grantAuthorization
    }

    func add(_ request: sending UNNotificationRequest) async throws {
        addedRequests.append(request)
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        registeredCategories = categories
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        addedRequests.removeAll { identifiers.contains($0.identifier) }
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        addedRequests
    }
}

@MainActor
final class NotificationServiceTests: XCTestCase {
    private var fake: FakeNotificationCenter!
    private var service: NotificationService!
    private let jst = TimeZone(identifier: "Asia/Tokyo")!

    override func setUp() async throws {
        try await super.setUp()
        fake = FakeNotificationCenter()
        service = NotificationService(center: fake)
    }

    override func tearDown() async throws {
        service = nil
        fake = nil
        try await super.tearDown()
    }

    func test_register_isIdempotent() async throws {
        try await service.register()
        try await service.register()
        try await service.register()
        XCTAssertEqual(fake.authorizationRequestCount, 1)
    }

    func test_register_setsAllFourCategories() async throws {
        try await service.register()
        let ids = Set(fake.registeredCategories.map { $0.identifier })
        XCTAssertEqual(ids, [
            NotificationIdentifier.fastStartCategory,
            NotificationIdentifier.fastEndCategory,
            NotificationIdentifier.hydrationCategory,
            NotificationIdentifier.learningCategory
        ])
    }

    func test_scheduleHydrationReminder_duringSleep_returnsNil() async throws {
        let date = jstDate(2026, 5, 4, 23, 0)
        let id = try await service.scheduleHydrationReminder(
            at: date, progressOz: 60, targetMaxOz: 130,
            timezone: jst, morningIntakeOz: 0
        )
        XCTAssertNil(id)
        XCTAssertTrue(fake.addedRequests.isEmpty)
    }

    func test_scheduleHydrationReminder_midDay_addsRequest() async throws {
        let date = jstDate(2026, 5, 4, 14, 0)
        let id = try await service.scheduleHydrationReminder(
            at: date, progressOz: 60, targetMaxOz: 130,
            timezone: jst, morningIntakeOz: 0
        )
        XCTAssertNotNil(id)
        XCTAssertEqual(fake.addedRequests.count, 1)
        XCTAssertEqual(fake.addedRequests.first?.content.categoryIdentifier, NotificationIdentifier.hydrationCategory)
    }

    func test_scheduleFastStart_addsRequest() async throws {
        let date = jstDate(2026, 5, 4, 22, 0)
        let id = try await service.scheduleFastStart(at: date, label: "training", timezone: jst)
        XCTAssertTrue(id.hasPrefix("fast.start"))
        XCTAssertEqual(fake.addedRequests.count, 1)
        XCTAssertEqual(fake.addedRequests.first?.content.categoryIdentifier, NotificationIdentifier.fastStartCategory)
    }

    func test_scheduleFastEnd_addsRequest() async throws {
        let date = jstDate(2026, 5, 5, 9, 0)
        let id = try await service.scheduleFastEnd(at: date, label: "training", timezone: jst)
        XCTAssertTrue(id.hasPrefix("fast.end"))
        XCTAssertEqual(fake.addedRequests.count, 1)
    }

    // W3: re-scheduling the same behavior on the same local day replaces rather
    // than stacks (cancel-before-schedule + stable id).
    func test_scheduleFastStart_isIdempotentPerDay() async throws {
        let morning = jstDate(2026, 5, 4, 21, 0)
        let later = jstDate(2026, 5, 4, 21, 30)
        let id1 = try await service.scheduleFastStart(at: morning, label: "training", timezone: jst)
        let id2 = try await service.scheduleFastStart(at: later, label: "training", timezone: jst)
        XCTAssertEqual(id1, id2, "Same behavior + local day must share a stable id.")
        XCTAssertEqual(fake.addedRequests.count, 1, "Re-scheduling must replace, not stack.")
    }

    // W2: the calendar trigger fires at the user's wall-clock time, carrying the
    // user's timezone rather than the device's.
    func test_scheduleFastStart_triggerUsesUserTimezone() async throws {
        let date = jstDate(2026, 5, 4, 22, 0)
        _ = try await service.scheduleFastStart(at: date, label: "training", timezone: jst)
        let trigger = fake.addedRequests.first?.trigger as? UNCalendarNotificationTrigger
        XCTAssertEqual(trigger?.dateComponents.timeZone, jst)
        XCTAssertEqual(trigger?.dateComponents.hour, 22)
        XCTAssertEqual(trigger?.dateComponents.minute, 0)
    }

    func test_cancel_removesPendingRequests() async throws {
        let date = jstDate(2026, 5, 4, 22, 0)
        let id = try await service.scheduleFastStart(at: date, label: "training", timezone: jst)
        XCTAssertEqual(fake.addedRequests.count, 1)
        service.cancel(identifiers: [id])
        XCTAssertEqual(fake.addedRequests.count, 0)
    }

    private func jstDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = jst
        return cal.date(from: c)!
    }
}
