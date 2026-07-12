import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class CoachServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        container = try InMemoryContainer.make()
        context = container.mainContext
    }

    override func tearDown() async throws {
        context = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: - System prompt

    func test_systemPrompt_includesStyle() {
        let prompt = CoachService.systemPrompt(style: "stoic", customStylePrompt: nil)
        XCTAssertTrue(prompt.contains("Style: stoic."))
        XCTAssertTrue(prompt.contains("max 80 words"))
    }

    func test_systemPrompt_customStyleEmbedsUserPrompt() {
        let prompt = CoachService.systemPrompt(style: "custom", customStylePrompt: "Marcus Aurelius with reps")
        XCTAssertTrue(prompt.contains("custom: Marcus Aurelius with reps"))
    }

    // MARK: - gatherContext

    func test_gatherContext_emptyState_producesValidSummary() {
        let service = CoachService(modelContext: context, api: StubAPI())
        let profile = ensureProfile()
        let context = service.gatherContext(profile: profile)
        XCTAssertEqual(context.workoutStreakDays, 0)
        XCTAssertEqual(context.hydrationStreakDays, 0)
        XCTAssertFalse(context.summaryForPrompt.isEmpty)
        XCTAssertTrue(context.summaryForPrompt.contains("Today:"))
    }

    func test_gatherContext_hydrationFromDailyLog_surfacesInSummary() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let day = cal.startOfDay(for: Date())
        let log = DailyLog(date: day, calendar: cal)
        log.waterOz = 48
        context.insert(log)
        try context.save()

        let service = CoachService(
            modelContext: context,
            timezone: cal.timeZone,
            api: StubAPI()
        )
        let profile = ensureProfile()
        let ctx = service.gatherContext(profile: profile)
        XCTAssertEqual(ctx.hydrationOzToday, 48)
        XCTAssertTrue(ctx.summaryForPrompt.contains("48"))
    }

    // MARK: - Cache behavior

    func test_todayInsight_returnsCachedWithinTTL() async throws {
        let api = StubAPI(text: "Stay the course. Show up.")
        let service = CoachService(modelContext: context, api: api)
        _ = ensureProfile()

        let first = try await service.todayInsight()
        let second = try await service.todayInsight()

        XCTAssertEqual(api.callCount, 1, "Cache hit should not invoke API again")
        XCTAssertEqual(first.persistentModelID, second.persistentModelID)
        XCTAssertEqual(first.refreshCount, 0)
    }

    func test_refresh_forcesNewAPICall_andIncrementsRefreshCount() async throws {
        let api = StubAPI(text: "Initial")
        let service = CoachService(modelContext: context, api: api)
        _ = ensureProfile()

        _ = try await service.todayInsight()
        api.text = "Refreshed"
        let refreshed = try await service.refresh()

        XCTAssertEqual(api.callCount, 2)
        XCTAssertEqual(refreshed.insightText, "Refreshed")
        XCTAssertEqual(refreshed.refreshCount, 1)
    }

    func test_apiFailure_withoutPriorCache_throws() async {
        let api = StubAPI(error: ClaudeAPIError.invalidResponse)
        let service = CoachService(modelContext: context, api: api)
        _ = ensureProfile()

        do {
            _ = try await service.todayInsight()
            XCTFail("Expected throw")
        } catch is CoachServiceError {
            // expected
        } catch {
            XCTFail("Expected CoachServiceError, got \(error)")
        }
    }

    func test_missingAPIKey_mapsToCoachServiceError() async {
        let api = StubAPI(error: ClaudeAPIError.missingAPIKey)
        let service = CoachService(modelContext: context, api: api)
        _ = ensureProfile()

        do {
            _ = try await service.todayInsight()
            XCTFail("Expected throw")
        } catch CoachServiceError.missingAPIKey {
            // expected
        } catch {
            XCTFail("Expected missingAPIKey, got \(error)")
        }
    }

    func test_cachedInsight_returnsLatestRow() async throws {
        let api = StubAPI(text: "First")
        let service = CoachService(modelContext: context, api: api)
        _ = ensureProfile()
        _ = try await service.todayInsight()

        let cached = service.cachedInsight()
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.insightText, "First")
    }

    // MARK: - Token usage logged

    func test_tokenUsage_persistedOnInsight() async throws {
        let api = StubAPI(text: "Show up.", inputTokens: 80, outputTokens: 30)
        let service = CoachService(modelContext: context, api: api)
        _ = ensureProfile()
        let insight = try await service.todayInsight()
        XCTAssertEqual(insight.tokenUsage, 110)
    }

    // MARK: - Style change produces different prompts

    func test_systemPrompt_differs_forDifferentStyles() {
        let stoic = CoachService.systemPrompt(style: "stoic", customStylePrompt: nil)
        let warrior = CoachService.systemPrompt(style: "warrior", customStylePrompt: nil)
        XCTAssertNotEqual(stoic, warrior)
    }

    // MARK: - Helpers

    private func ensureProfile() -> UserProfile {
        if let existing = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first {
            return existing
        }
        let p = UserProfile()
        context.insert(p)
        try? context.save()
        return p
    }
}

// MARK: - StubAPI

@MainActor
final class StubAPI: CoachAPIInvoking {
    nonisolated(unsafe) var text: String
    nonisolated(unsafe) var inputTokens: Int
    nonisolated(unsafe) var outputTokens: Int
    nonisolated(unsafe) var error: Error?
    nonisolated(unsafe) var callCount: Int = 0

    init(text: String = "Default insight.",
         inputTokens: Int = 50,
         outputTokens: Int = 20,
         error: Error? = nil) {
        self.text = text
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.error = error
    }

    nonisolated func complete(model: String,
                              systemPrompt: String,
                              userPrompt: String,
                              maxTokens: Int) async throws -> ClaudeAPIClient.Response {
        callCount += 1
        if let error { throw error }
        return ClaudeAPIClient.Response(text: text, inputTokens: inputTokens, outputTokens: outputTokens, modelUsed: .sonnet46)
    }
}
