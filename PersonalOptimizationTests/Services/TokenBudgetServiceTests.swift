import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class TokenBudgetServiceTests: XCTestCase {

    func test_wouldExceed_trueWhenBudgetIsZero() throws {
        let container = try InMemoryContainer.make()
        let profile = UserProfile()
        profile.dailyTokenBudget = 0
        container.mainContext.insert(profile)
        try container.mainContext.save()

        let service = TokenBudgetService(modelContext: container.mainContext)
        XCTAssertTrue(service.wouldExceed(estimatedTokens: 1))
        XCTAssertTrue(service.wouldExceed(estimatedTokens: 0))
    }

    func test_wouldExceed_falseWhenWithinBudget() throws {
        let container = try InMemoryContainer.make()
        let profile = UserProfile()
        profile.dailyTokenBudget = 10_000
        container.mainContext.insert(profile)
        try container.mainContext.save()
        let service = TokenBudgetService(modelContext: container.mainContext)
        XCTAssertFalse(service.wouldExceed(estimatedTokens: 5_000))
    }

    func test_wouldExceed_trueAtExactCap() throws {
        let container = try InMemoryContainer.make()
        let profile = UserProfile()
        profile.dailyTokenBudget = 10_000
        container.mainContext.insert(profile)
        try container.mainContext.save()
        let service = TokenBudgetService(modelContext: container.mainContext)
        service.record(inputTokens: 9_000, outputTokens: 0)
        XCTAssertFalse(service.wouldExceed(estimatedTokens: 1_000))
        XCTAssertTrue(service.wouldExceed(estimatedTokens: 1_001))
    }

    func test_record_accumulatesIntoTodaysEntry() throws {
        let container = try InMemoryContainer.make()
        let profile = UserProfile()
        profile.dailyTokenBudget = 50_000
        container.mainContext.insert(profile)
        try container.mainContext.save()
        let service = TokenBudgetService(modelContext: container.mainContext)
        service.record(inputTokens: 100, outputTokens: 200)
        service.record(inputTokens: 50, outputTokens: 50)
        XCTAssertEqual(service.spentToday(), 400)
    }

    func test_spentToday_zeroBeforeAnyRecord() throws {
        let container = try InMemoryContainer.make()
        let profile = UserProfile()
        profile.dailyTokenBudget = 50_000
        container.mainContext.insert(profile)
        try container.mainContext.save()
        let service = TokenBudgetService(modelContext: container.mainContext)
        XCTAssertEqual(service.spentToday(), 0)
    }

    func test_dayBoundary_yesterdayUsageDoesNotCountToday() throws {
        let container = try InMemoryContainer.make()
        let profile = UserProfile()
        profile.dailyTokenBudget = 1_000
        container.mainContext.insert(profile)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: Date()))!
        let priorEntry = TokenUsageEntry(
            date: yesterday,
            inputTokens: 5_000,
            outputTokens: 5_000,
            callCount: 1,
            lastCallAt: yesterday
        )
        container.mainContext.insert(priorEntry)
        try container.mainContext.save()

        let service = TokenBudgetService(modelContext: container.mainContext, calendar: cal)
        XCTAssertEqual(service.spentToday(), 0)
        XCTAssertFalse(service.wouldExceed(estimatedTokens: 500))
    }

    func test_spentThisMonth_aggregatesAllEntries() throws {
        let container = try InMemoryContainer.make()
        let profile = UserProfile()
        profile.dailyTokenBudget = 50_000
        container.mainContext.insert(profile)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let today = cal.startOfDay(for: Date())
        let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: today)!
        container.mainContext.insert(TokenUsageEntry(
            date: twoDaysAgo, inputTokens: 100, outputTokens: 200, callCount: 1, lastCallAt: twoDaysAgo
        ))
        container.mainContext.insert(TokenUsageEntry(
            date: today, inputTokens: 50, outputTokens: 50, callCount: 1, lastCallAt: today
        ))
        try container.mainContext.save()
        let service = TokenBudgetService(modelContext: container.mainContext, calendar: cal)
        XCTAssertEqual(service.spentThisMonth(), 400)
    }

    func test_record_ignoresZeroTotal() throws {
        let container = try InMemoryContainer.make()
        let profile = UserProfile()
        profile.dailyTokenBudget = 50_000
        container.mainContext.insert(profile)
        try container.mainContext.save()
        let service = TokenBudgetService(modelContext: container.mainContext)
        service.record(inputTokens: 0, outputTokens: 0)
        XCTAssertEqual(service.spentToday(), 0)
        let entries = try container.mainContext.fetch(FetchDescriptor<TokenUsageEntry>())
        XCTAssertTrue(entries.isEmpty)
    }
}
