import XCTest
@testable import PersonalOptimization

@MainActor
final class DailyQuoteServiceTests: XCTestCase {

    // MARK: - curated quotes

    func test_curatedQuote_balancedFallback() {
        let service = DailyQuoteService(now: { self.fixedDate })
        let q = service.curatedQuote(style: "balanced")
        XCTAssertFalse(q.text.isEmpty)
        XCTAssertEqual(q.style, "balanced")
    }

    func test_curatedQuote_invalidStyleResolvesToBalanced() {
        let service = DailyQuoteService(now: { self.fixedDate })
        let q = service.curatedQuote(style: "nonexistent")
        XCTAssertEqual(q.style, "balanced")
    }

    func test_curatedQuote_stableWithinDay() {
        let service = DailyQuoteService(now: { self.fixedDate })
        let a = service.curatedQuote(style: "stoic")
        let b = service.curatedQuote(style: "stoic")
        XCTAssertEqual(a, b, "Same day same style must return identical quote")
    }

    func test_curatedQuote_differentStylesProduceDifferentQuotes() {
        let service = DailyQuoteService(now: { self.fixedDate })
        let stoic = service.curatedQuote(style: "stoic")
        let warrior = service.curatedQuote(style: "warrior")
        XCTAssertNotEqual(stoic.text, warrior.text)
    }

    // MARK: - parsing

    func test_parse_emDashAuthorAttribution() {
        let q = DailyQuoteService.parse("Discipline equals freedom. — Jocko Willink", style: "warrior")
        XCTAssertEqual(q.text, "Discipline equals freedom.")
        XCTAssertEqual(q.attribution, "Jocko Willink")
    }

    func test_parse_noAttribution() {
        let q = DailyQuoteService.parse("\"Show up.\"", style: "balanced")
        XCTAssertEqual(q.text, "Show up.")
        XCTAssertNil(q.attribution)
    }

    func test_parse_hyphenAttribution() {
        let q = DailyQuoteService.parse("Be water - Bruce Lee", style: "warrior")
        XCTAssertEqual(q.text, "Be water")
        XCTAssertEqual(q.attribution, "Bruce Lee")
    }

    // MARK: - aiQuotes flow

    func test_aiDisabled_returnsCurated() async {
        let service = DailyQuoteService(api: TestAPI(), now: { self.fixedDate })
        let q = await service.dailyQuote(style: "stoic", customStylePrompt: nil, aiEnabled: false)
        let curated = service.curatedQuote(style: "stoic")
        XCTAssertEqual(q.text, curated.text)
    }

    func test_aiEnabled_callsAPI_andCachesPerDay() async {
        let api = TestAPI(text: "Move with intent. — Test")
        let service = DailyQuoteService(api: api, now: { self.fixedDate })
        let q1 = await service.dailyQuote(style: "stoic", customStylePrompt: nil, aiEnabled: true)
        let q2 = await service.dailyQuote(style: "stoic", customStylePrompt: nil, aiEnabled: true)
        XCTAssertEqual(api.callCount, 1, "AI quote should be cached for the same day")
        XCTAssertEqual(q1, q2)
        XCTAssertEqual(q1.text, "Move with intent.")
        XCTAssertEqual(q1.attribution, "Test")
    }

    func test_aiFailure_fallsBackToCurated() async {
        let api = TestAPI(error: ClaudeAPIError.invalidResponse)
        let service = DailyQuoteService(api: api, now: { self.fixedDate })
        let q = await service.dailyQuote(style: "warrior", customStylePrompt: nil, aiEnabled: true)
        let curated = service.curatedQuote(style: "warrior")
        XCTAssertEqual(q.text, curated.text)
    }

    // MARK: - Helpers

    private var fixedDate: Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return cal.date(from: DateComponents(year: 2026, month: 5, day: 7, hour: 9))!
    }
}

@MainActor
private final class TestAPI: CoachAPIInvoking {
    nonisolated(unsafe) var text: String
    nonisolated(unsafe) var error: Error?
    nonisolated(unsafe) var callCount: Int = 0

    init(text: String = "Show up.", error: Error? = nil) {
        self.text = text
        self.error = error
    }

    nonisolated func complete(model: String,
                              systemPrompt: String,
                              userPrompt: String,
                              maxTokens: Int) async throws -> ClaudeAPIClient.Response {
        callCount += 1
        if let error { throw error }
        return ClaudeAPIClient.Response(text: text, inputTokens: 10, outputTokens: 5)
    }
}
