import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class PartnerChallengeTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        cal.firstWeekday = 2
        return cal
    }

    private func weekStart(asOf: Date = Date()) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: asOf)!.start
    }

    private func myWeek(_ daily: [Int], asOf: Date = Date()) -> ChallengeWeek {
        ChallengeWeek(weekStart: weekStart(asOf: asOf), dailyPoints: daily)
    }

    private func partnerRecord(points: Int?, weekStart: Date?) -> PartnerSharedRecord {
        PartnerSharedRecord(userID: "partner",
                            currentStreak: 5,
                            masterMetric: 0.5,
                            mascotState: "neutral",
                            challengeWeekStart: weekStart,
                            challengeWeekPoints: points)
    }

    func test_standing_partnerSameWeek_scoresAndPicksLeader() {
        let now = Date()
        let standing = ChallengeScoring.standing(
            week: myWeek([4, 3, 4], asOf: now),
            partner: partnerRecord(points: 9, weekStart: weekStart(asOf: now)),
            calendar: calendar,
            asOf: now
        )
        XCTAssertEqual(standing.week.totalPoints, 11)
        XCTAssertEqual(standing.partnerPoints, 9)
        XCTAssertEqual(standing.leader, .me(by: 2))
    }

    func test_standing_partnerLeads() {
        let now = Date()
        let standing = ChallengeScoring.standing(
            week: myWeek([2, 2], asOf: now),
            partner: partnerRecord(points: 10, weekStart: weekStart(asOf: now)),
            calendar: calendar,
            asOf: now
        )
        XCTAssertEqual(standing.leader, .partner(by: 6))
    }

    func test_standing_tied() {
        let now = Date()
        let standing = ChallengeScoring.standing(
            week: myWeek([3, 3], asOf: now),
            partner: partnerRecord(points: 6, weekStart: weekStart(asOf: now)),
            calendar: calendar,
            asOf: now
        )
        XCTAssertEqual(standing.leader, .tied)
    }

    func test_standing_staleWeek_doesNotScore() {
        let now = Date()
        let lastWeek = calendar.date(byAdding: .day, value: -7, to: weekStart(asOf: now))!
        let standing = ChallengeScoring.standing(
            week: myWeek([4], asOf: now),
            partner: partnerRecord(points: 20, weekStart: lastWeek),
            calendar: calendar,
            asOf: now
        )
        XCTAssertNil(standing.partnerPoints)
        XCTAssertTrue(standing.partnerStale)
        XCTAssertNil(standing.leader)
    }

    func test_standing_noPartner_solo() {
        let standing = ChallengeScoring.standing(
            week: myWeek([1, 2]),
            partner: nil,
            calendar: calendar
        )
        XCTAssertNil(standing.partnerPoints)
        XCTAssertFalse(standing.partnerStale)
        XCTAssertNil(standing.leader)
    }

    func test_daysRemaining_countsTodayThroughSunday() {
        let start = weekStart()
        // As of the week's first day, all 7 days remain; on day 6, 1 remains.
        let onMonday = ChallengeScoring.standing(week: myWeek([0], asOf: start),
                                                 partner: nil, calendar: calendar, asOf: start)
        XCTAssertEqual(onMonday.daysRemaining, 7)
        let lastDay = calendar.date(byAdding: .day, value: 6, to: start)!
        let onSunday = ChallengeScoring.standing(week: ChallengeWeek(weekStart: start, dailyPoints: [0]),
                                                 partner: nil, calendar: calendar, asOf: lastDay)
        XCTAssertEqual(onSunday.daysRemaining, 1)
    }

    func test_sharedRecord_decodesLegacyPayloadWithoutChallengeFields() throws {
        let legacy = PartnerSharedRecord(userID: "u", currentStreak: 3,
                                         masterMetric: 1.0, mascotState: "proud")
        let data = try JSONEncoder().encode(legacy)
        // Strip the optional keys to simulate a record from an older build.
        var dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        dict.removeValue(forKey: "challengeWeekStart")
        dict.removeValue(forKey: "challengeWeekPoints")
        let stripped = try JSONSerialization.data(withJSONObject: dict)

        let decoded = try JSONDecoder().decode(PartnerSharedRecord.self, from: stripped)
        XCTAssertNil(decoded.challengeWeekStart)
        XCTAssertNil(decoded.challengeWeekPoints)
        XCTAssertEqual(decoded.currentStreak, 3)
    }

    func test_currentWeek_emptyStore_scoresZeroPerElapsedDay() throws {
        let container = try InMemoryContainer.make()
        let week = ChallengeScoring.currentWeek(modelContext: container.mainContext,
                                                calendar: calendar)
        XCTAssertEqual(week.weekStart, weekStart())
        XCTAssertFalse(week.dailyPoints.isEmpty)
        XCTAssertLessThanOrEqual(week.dailyPoints.count, 7)
        XCTAssertEqual(week.totalPoints, 0)
    }

    func test_service_challengeStanding_throughMemoryZone() async throws {
        let container = try InMemoryContainer.make()
        // Anchor the partner's week with the SAME calendar the service uses
        // (user profile timezone), not the test's fixture calendar, so the
        // same-week match is exercised rather than the timezone delta.
        let serviceCalendar = UserCalendar.current(modelContext: container.mainContext)
        let serviceWeekStart = serviceCalendar.dateInterval(of: .weekOfYear, for: Date())!.start
        let zone = MemoryPartnerSharedZone()
        zone.preloadPartner(partnerRecord(points: 4, weekStart: serviceWeekStart))
        let service = PartnerService(modelContext: container.mainContext, zone: zone)

        let standing = try await service.challengeStanding()
        XCTAssertEqual(standing.partnerPoints, 4)
        XCTAssertEqual(standing.leader, .partner(by: 4 - standing.week.totalPoints))
    }
}
