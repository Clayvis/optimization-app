import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class FastingServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var service: FastingService!
    private var profile: UserProfile!
    private let jst = TimeZone(identifier: "Asia/Tokyo")!

    private static let fixtureDefaults: FastingDefaults = {
        let json = """
        {
          "weeks_1_2": {
            "trainingDays": { "start": "21:00", "end": "09:00" },
            "trainingDayNumbers": [1, 2, 4, 5],
            "otherDays": { "start": "22:00", "end": "10:00" }
          },
          "weeks_3_plus": {
            "all": { "start": "22:00", "end": "10:00" }
          }
        }
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(FastingDefaults.self, from: json)
    }()

    override func setUp() async throws {
        try await super.setUp()
        container = try InMemoryContainer.make()
        context = container.mainContext
        profile = UserProfile(name: "Test", dob: Date(timeIntervalSince1970: 764985600), sex: "male")
        profile.rolloutPhase = 1
        context.insert(profile)
        try context.save()
        service = FastingService(modelContext: context, timezone: jst, defaults: Self.fixtureDefaults)
    }

    override func tearDown() async throws {
        service = nil
        profile = nil
        context = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: - windowStartingOnDay

    func test_windowStartingOnDay_phase1_trainingDay_returnsTrainingWindow() {
        // Monday 2026-05-04 12:00 JST
        let monday = jstDate(2026, 5, 4, 12, 0)
        let window = service.windowStartingOnDay(of: monday, profile: profile)
        XCTAssertEqual(window.label, "training")
        XCTAssertEqual(jstHourMinute(window.start), HM(h: 21, m: 0))
        XCTAssertEqual(jstHourMinute(window.end), HM(h: 9, m: 0))
        // End must be on the day AFTER start.
        let cal = Calendar(identifier: .gregorian)
        XCTAssertEqual(cal.dateComponents(in: jst, from: window.end).day, 5)
    }

    func test_windowStartingOnDay_phase1_otherDay_returnsOtherWindow() {
        // Wednesday (3) is non-training.
        let wednesday = jstDate(2026, 5, 6, 12, 0)
        let window = service.windowStartingOnDay(of: wednesday, profile: profile)
        XCTAssertEqual(window.label, "other")
        XCTAssertEqual(jstHourMinute(window.start), HM(h: 22, m: 0))
        XCTAssertEqual(jstHourMinute(window.end), HM(h: 10, m: 0))
    }

    func test_windowStartingOnDay_phase2_alwaysAllWindow() {
        profile.rolloutPhase = 2
        let monday = jstDate(2026, 5, 4, 12, 0)
        let window = service.windowStartingOnDay(of: monday, profile: profile)
        XCTAssertEqual(window.label, "all")
        XCTAssertEqual(jstHourMinute(window.start), HM(h: 22, m: 0))
        XCTAssertEqual(jstHourMinute(window.end), HM(h: 10, m: 0))
    }

    // MARK: - currentWindow & state

    func test_state_insideTrainingWindow_returnsFasting() {
        // Mon 22:00 JST is inside Mon 21:00-Tue 09:00 training fast.
        let date = jstDate(2026, 5, 4, 22, 0)
        XCTAssertEqual(service.state(at: date, profile: profile), .fasting)
        XCTAssertEqual(service.currentWindow(at: date, profile: profile)?.label, "training")
    }

    func test_state_acrossMidnight_stillFasting() {
        // Tue 02:00 JST — within Mon-night training fast.
        let date = jstDate(2026, 5, 5, 2, 0)
        XCTAssertEqual(service.state(at: date, profile: profile), .fasting)
        XCTAssertEqual(service.currentWindow(at: date, profile: profile)?.label, "training")
    }

    func test_state_atFastStart_isFasting() {
        let date = jstDate(2026, 5, 4, 21, 0)
        XCTAssertEqual(service.state(at: date, profile: profile), .fasting)
    }

    func test_state_atFastEnd_isFasting() {
        // Tue 09:00 — last second of Mon training fast (inclusive end).
        let date = jstDate(2026, 5, 5, 9, 0)
        XCTAssertEqual(service.state(at: date, profile: profile), .fasting)
    }

    func test_state_outsideAllWindows_isEating() {
        // Wed 12:00 — between Tue fast (ended 09:00 Wed via Tue training window) and Wed 22:00 fast.
        let date = jstDate(2026, 5, 6, 12, 0)
        XCTAssertEqual(service.state(at: date, profile: profile), .eating)
        XCTAssertNil(service.currentWindow(at: date, profile: profile))
    }

    // MARK: - elapsed / remaining

    func test_elapsedFasting_returnsZero_whenEating() {
        let date = jstDate(2026, 5, 6, 12, 0)
        XCTAssertEqual(service.elapsedFasting(at: date, profile: profile), 0)
    }

    func test_elapsedFasting_returnsCorrectInterval_whenFasting() {
        // Mon 23:00 = 2 hours into Mon 21:00 training fast.
        let date = jstDate(2026, 5, 4, 23, 0)
        XCTAssertEqual(service.elapsedFasting(at: date, profile: profile), 7200, accuracy: 1)
    }

    func test_remainingInFast_isNil_whenEating() {
        let date = jstDate(2026, 5, 6, 12, 0)
        XCTAssertNil(service.remainingInFast(at: date, profile: profile))
    }

    func test_remainingInFast_returnsCorrectInterval_whenFasting() throws {
        // Mon 23:00 — 10 hours until Tue 09:00 end.
        let date = jstDate(2026, 5, 4, 23, 0)
        let remaining = try XCTUnwrap(service.remainingInFast(at: date, profile: profile))
        XCTAssertEqual(remaining, 10 * 3600, accuracy: 1)
    }

    // MARK: - nextWindow

    func test_nextWindow_returnsTodayWindow_whenBeforeStart() {
        // Mon 12:00, training day. Next fast starts Mon 21:00.
        let date = jstDate(2026, 5, 4, 12, 0)
        let next = service.nextWindow(after: date, profile: profile)
        XCTAssertEqual(jstHourMinute(next.start), HM(h: 21, m: 0))
        XCTAssertEqual(next.label, "training")
    }

    func test_nextWindow_returnsTomorrowWindow_whenAfterStart() {
        // Mon 22:00, already inside tonight's fast. Next window is Tue's.
        let date = jstDate(2026, 5, 4, 22, 0)
        let next = service.nextWindow(after: date, profile: profile)
        // Tuesday is also a training day so window is 21:00 the next eve.
        let cal = Calendar(identifier: .gregorian)
        XCTAssertEqual(cal.dateComponents(in: jst, from: next.start).day, 5)
        XCTAssertEqual(next.label, "training")
    }

    // MARK: - logEarlyBreak

    func test_logEarlyBreak_updatesDailyLog() throws {
        // Mon 23:00, fast started 21:00. Break at 23:00.
        let date = jstDate(2026, 5, 4, 23, 0)
        try service.logEarlyBreak(at: date, reason: "social dinner", profile: profile)

        let logs = try context.fetch(FetchDescriptor<DailyLog>())
        XCTAssertEqual(logs.count, 1)
        XCTAssertTrue(logs.first?.fastBrokeEarly ?? false)
        XCTAssertEqual(logs.first?.fastBreakReason, "social dinner")
        XCTAssertNotNil(logs.first?.fastStart)
        XCTAssertNotNil(logs.first?.fastEnd)
    }

    func test_logEarlyBreak_whenEating_throwsNoActiveFast() throws {
        let date = jstDate(2026, 5, 6, 12, 0)
        XCTAssertThrowsError(try service.logEarlyBreak(at: date, reason: "x", profile: profile)) { error in
            guard case FastingError.noActiveFast = error else {
                XCTFail("Expected noActiveFast, got \(error)")
                return
            }
        }
    }

    // MARK: - Helpers

    private func jstDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = jst
        return cal.date(from: c)!
    }

    // MARK: - Manual fast (M3.7+ pass)

    func test_startManualFast_outsideScheduledWindow_marksLogStarted() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = jst
        // Friday 14:00 — well outside any 21:00/22:00 fast window.
        let now = cal.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 14))!
        let log = try service.startManualFast(at: now, profile: profile)
        XCTAssertEqual(log.fastStart, now)
        XCTAssertNil(log.fastEnd)
        XCTAssertEqual(service.state(at: now, profile: profile), .fasting)
    }

    func test_endManualFast_setsFastEnd_andTransitionsToEating() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = jst
        let start = cal.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 14))!
        let end = cal.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 18))!
        _ = try service.startManualFast(at: start, profile: profile)
        let log = try service.endManualFast(at: end, reason: "Hungry")
        XCTAssertEqual(log.fastEnd, end)
        XCTAssertEqual(log.fastBreakReason, "Hungry")
        XCTAssertTrue(log.fastBrokeEarly)
        XCTAssertEqual(service.state(at: end, profile: profile), .eating)
    }

    func test_startManualFast_whenAlreadyFasting_throws() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = jst
        let start = cal.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 14))!
        _ = try service.startManualFast(at: start, profile: profile)
        XCTAssertThrowsError(try service.startManualFast(at: start.addingTimeInterval(60), profile: profile)) { err in
            XCTAssertTrue(err is FastingError)
        }
    }

    func test_endManualFast_acrossMidnight_findsYesterdaysOpenFast() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = jst
        // Started Thursday 22:30 JST.
        let start = cal.date(from: DateComponents(year: 2026, month: 5, day: 7, hour: 22, minute: 30))!
        // Ending Friday 06:30 JST — different day.
        let end = cal.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 6, minute: 30))!
        _ = try service.startManualFast(at: start, profile: profile)
        XCTAssertNoThrow(try service.endManualFast(at: end))
        let log = service.activeFastWindow(at: end, profile: profile)
        XCTAssertNil(log, "Fast should be ended after explicit endManualFast")
    }

    func test_endManualFast_whenNoneOpen_throwsNoActiveFast() {
        XCTAssertThrowsError(try service.endManualFast()) { err in
            guard let fastErr = err as? FastingError else {
                XCTFail("Expected FastingError, got \(err)")
                return
            }
            switch fastErr {
            case .noActiveFast: break
            default: XCTFail("Expected .noActiveFast, got \(fastErr)")
            }
        }
    }

    private struct HM: Equatable { let h: Int; let m: Int }

    private func jstHourMinute(_ date: Date) -> HM {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = jst
        let comps = cal.dateComponents([.hour, .minute], from: date)
        return HM(h: comps.hour ?? -1, m: comps.minute ?? -1)
    }
}
