import XCTest
@testable import PersonalOptimization

/// Coverage for retry classification, fallback laddering, and JSON
/// resilience. We test the pure decision functions
/// (`isRetryable`, `shouldFallback`, `estimateTokens`, `decodeJSON`) and
/// the ClaudeModel.fallback ladder without a live HTTP round-trip — that
/// keeps the tests deterministic and offline.
final class ClaudeAPIClientRetryTests: XCTestCase {

    // MARK: - Retry classification

    func test_isRetryable_trueOn429() {
        XCTAssertTrue(ClaudeAPIClient.isRetryable(error: .http(429, "")))
    }

    func test_isRetryable_trueOn529() {
        XCTAssertTrue(ClaudeAPIClient.isRetryable(error: .http(529, "overloaded")))
    }

    func test_isRetryable_trueOn500Series() {
        for code in [500, 502, 503, 504, 599] {
            XCTAssertTrue(ClaudeAPIClient.isRetryable(error: .http(code, "")), "\(code) should be retryable")
        }
    }

    func test_isRetryable_falseOn400() {
        XCTAssertFalse(ClaudeAPIClient.isRetryable(error: .http(400, "bad")))
    }

    func test_isRetryable_falseOn401() {
        XCTAssertFalse(ClaudeAPIClient.isRetryable(error: .http(401, "auth")))
    }

    func test_isRetryable_trueOnTransport() {
        let transport = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        XCTAssertTrue(ClaudeAPIClient.isRetryable(error: .transport(transport)))
    }

    func test_isRetryable_falseOnMissingKey() {
        XCTAssertFalse(ClaudeAPIClient.isRetryable(error: .missingAPIKey))
    }

    func test_isRetryable_falseOnDecoding() {
        let inner = NSError(domain: "JSON", code: 1)
        XCTAssertFalse(ClaudeAPIClient.isRetryable(error: .decoding(inner)))
    }

    // MARK: - Fallback ladder

    func test_shouldFallback_trueOn529() {
        XCTAssertTrue(ClaudeAPIClient.shouldFallback(error: .http(529, "")))
    }

    func test_shouldFallback_trueOn500Series() {
        XCTAssertTrue(ClaudeAPIClient.shouldFallback(error: .http(503, "")))
    }

    func test_shouldFallback_trueOnAllRetriesFailed() {
        XCTAssertTrue(ClaudeAPIClient.shouldFallback(error: .allRetriesFailed(last: "x")))
    }

    func test_shouldFallback_falseOn400() {
        XCTAssertFalse(ClaudeAPIClient.shouldFallback(error: .http(400, "")))
    }

    func test_modelFallback_opusToSonnetToHaiku() {
        XCTAssertEqual(ClaudeModel.opus47.fallback, .sonnet46)
        XCTAssertEqual(ClaudeModel.sonnet46.fallback, .haiku45)
        XCTAssertNil(ClaudeModel.haiku45.fallback, "Haiku is the floor; no further fallback.")
    }

    func test_modelFromString_unknownDefaultsToSonnet() {
        XCTAssertEqual(ClaudeModel.from(string: "unknown-model-id"), .sonnet46)
        XCTAssertEqual(ClaudeModel.from(string: "claude-opus-4-7"), .opus47)
    }

    // MARK: - Token estimation

    func test_estimateTokens_roughly4CharsPerToken() {
        let system = String(repeating: "x", count: 400)
        let user = String(repeating: "y", count: 800)
        // 400+800 chars → 1200 / 4 = 300 + maxTokens(256) = 556.
        XCTAssertEqual(ClaudeAPIClient.estimateTokens(systemPrompt: system, userPrompt: user, maxTokens: 256), 556)
    }

    func test_estimateTokens_zeroPromptsReturnsMaxTokensOnly() {
        XCTAssertEqual(ClaudeAPIClient.estimateTokens(systemPrompt: "", userPrompt: "", maxTokens: 512), 512)
    }

    // MARK: - JSON decode

    struct SamplePayload: Codable, Equatable {
        let name: String
        let count: Int
    }

    func test_decodeJSON_plainJSON() throws {
        let raw = #"{"name":"clay","count":42}"#
        let out = try ClaudeAPIClient.decodeJSON(raw, as: SamplePayload.self)
        XCTAssertEqual(out, SamplePayload(name: "clay", count: 42))
    }

    func test_decodeJSON_stripsTripleBacktickFence() throws {
        let raw = """
        ```json
        {"name":"clay","count":42}
        ```
        """
        let out = try ClaudeAPIClient.decodeJSON(raw, as: SamplePayload.self)
        XCTAssertEqual(out, SamplePayload(name: "clay", count: 42))
    }

    func test_decodeJSON_throwsOnMalformed() {
        XCTAssertThrowsError(try ClaudeAPIClient.decodeJSON("not json", as: SamplePayload.self)) { error in
            guard case ClaudeAPIError.decoding = error else {
                XCTFail("Expected ClaudeAPIError.decoding, got \(error)")
                return
            }
        }
    }
}
