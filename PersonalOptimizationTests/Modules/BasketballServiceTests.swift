import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class BasketballServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var service: BasketballService!

    override func setUp() async throws {
        try await super.setUp()
        container = try InMemoryContainer.make()
        context = container.mainContext
        service = BasketballService(modelContext: context)
    }

    override func tearDown() async throws {
        service = nil
        context = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: - zone classification

    func test_zone_atLowBpm_isZone1() {
        XCTAssertEqual(BasketballService.zone(for: 80, maxHR: 189), "zone1")
        XCTAssertEqual(BasketballService.zone(for: 100, maxHR: 189), "zone1")
    }

    func test_zone_at60Pct_isZone2() {
        XCTAssertEqual(BasketballService.zone(for: 114, maxHR: 189), "zone2")
    }

    func test_zone_at70Pct_isZone3() {
        XCTAssertEqual(BasketballService.zone(for: 133, maxHR: 189), "zone3")
    }

    func test_zone_at80Pct_isZone4() {
        XCTAssertEqual(BasketballService.zone(for: 152, maxHR: 189), "zone4")
    }

    func test_zone_at90Pct_isZone5() {
        XCTAssertEqual(BasketballService.zone(for: 171, maxHR: 189), "zone5")
    }

    func test_zone_zeroMaxHR_returnsZone1() {
        XCTAssertEqual(BasketballService.zone(for: 150, maxHR: 0), "zone1")
    }

    // MARK: - shouldPromptHydration

    func test_shouldPrompt_under30min_false() {
        XCTAssertFalse(BasketballService.shouldPromptHydration(elapsed: 29 * 60, lastPromptElapsed: nil))
    }

    func test_shouldPrompt_at30min_true() {
        XCTAssertTrue(BasketballService.shouldPromptHydration(elapsed: 30 * 60, lastPromptElapsed: nil))
    }

    func test_shouldPrompt_after30minPrompt_falseUntil60min() {
        XCTAssertFalse(BasketballService.shouldPromptHydration(elapsed: 35 * 60, lastPromptElapsed: 30 * 60))
        XCTAssertFalse(BasketballService.shouldPromptHydration(elapsed: 59 * 60, lastPromptElapsed: 30 * 60))
        XCTAssertTrue(BasketballService.shouldPromptHydration(elapsed: 60 * 60, lastPromptElapsed: 30 * 60))
    }

    func test_shouldPrompt_at90min_trueAfter60minPrompt() {
        XCTAssertTrue(BasketballService.shouldPromptHydration(elapsed: 90 * 60, lastPromptElapsed: 60 * 60))
    }

    // MARK: - logMinute

    func test_logMinute_accumulatesZoneCounter() throws {
        let session = try service.startSession(at: Date())
        try service.logMinute(in: session, bpm: 150, maxHR: 189)  // zone3
        try service.logMinute(in: session, bpm: 150, maxHR: 189)  // zone3
        try service.logMinute(in: session, bpm: 170, maxHR: 189)  // zone4
        XCTAssertEqual(session.hrZoneMinutes["zone3"], 2)
        XCTAssertEqual(session.hrZoneMinutes["zone4"], 1)
    }

    // MARK: - endSession

    func test_endSession_writesCheckInAndDailyLog() async throws {
        let start = Date()
        let session = try service.startSession(at: start)
        try service.endSession(session,
                              endTime: start.addingTimeInterval(4 * 3600),
                              achillesPostScore: 5,
                              hydrationOz: 120)

        XCTAssertEqual(session.achillesPostScore, 5)
        XCTAssertEqual(session.hydrationOz, 120)
        XCTAssertNotEqual(session.startTime, session.endTime)

        let logs = try context.fetch(FetchDescriptor<DailyLog>())
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.achillesPain, 5)
    }

    func test_endSession_persistsToHealthKit_whenWired() async throws {
        let fake = FakeHealthKitService()
        let bsk = BasketballService(modelContext: context, healthKit: fake)
        let start = Date()
        let session = try bsk.startSession(at: start)
        try bsk.endSession(session, endTime: start.addingTimeInterval(4 * 3600), achillesPostScore: 4, hydrationOz: 150, estimatedCalories: 800)
        await SessionLifecycleService.shared.lastDispatchedTask?.value

        XCTAssertEqual(fake.savedWorkouts.count, 1)
        XCTAssertEqual(fake.savedWorkouts[0].0, .basketball)
        XCTAssertEqual(fake.savedWorkouts[0].3, 800)
    }

    // MARK: - currentSession

    func test_currentSession_returnsActiveSession() throws {
        _ = try service.startSession(at: Date())
        XCTAssertNotNil(service.currentSession(at: Date()))
    }

    func test_currentSession_returnsNilAfterEnd() async throws {
        let s = try service.startSession(at: Date())
        try service.endSession(s, endTime: Date().addingTimeInterval(3600), achillesPostScore: 4, hydrationOz: 100)
        XCTAssertNil(service.currentSession(at: Date()))
    }

    // MARK: - Hydration bridge (M3.7+ pass)

    func test_endSession_writesHydrationEntry_andUpdatesDailyLog() throws {
        let start = Date()
        let s = try service.startSession(at: start)
        try service.endSession(s, endTime: start.addingTimeInterval(3600), achillesPostScore: 5, hydrationOz: 32)

        let entries = try context.fetch(FetchDescriptor<HydrationEntry>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.amountOz, 32)
        XCTAssertEqual(entries.first?.note, "basketball")

        let logs = try context.fetch(FetchDescriptor<DailyLog>())
        XCTAssertEqual(logs.first?.waterOz, 32)
    }

    func test_endSession_zeroHydration_doesNotCreateEntry() throws {
        let start = Date()
        let s = try service.startSession(at: start)
        try service.endSession(s, endTime: start.addingTimeInterval(3600), achillesPostScore: 5, hydrationOz: 0)

        let entries = try context.fetch(FetchDescriptor<HydrationEntry>())
        XCTAssertTrue(entries.isEmpty)
    }
}
