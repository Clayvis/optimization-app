import Foundation
import os

enum ClaudeAPIError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidResponse
    case http(Int, String)
    case decoding(Error)
    case transport(Error)
    case budgetExceeded(spentToday: Int, dailyBudget: Int, estimated: Int)
    case allRetriesFailed(last: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Anthropic API key is not set in Keychain"
        case .invalidResponse:
            return "Anthropic API returned an unexpected response"
        case .http(let code, let body):
            return "Anthropic API HTTP \(code): \(body)"
        case .decoding(let underlying):
            return "Failed to decode response: \(underlying.localizedDescription)"
        case .transport(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        case .budgetExceeded(let spent, let budget, let estimated):
            return "Daily AI token budget would be exceeded (\(spent + estimated)/\(budget))"
        case .allRetriesFailed(let last):
            return "All retries exhausted: \(last)"
        }
    }

    static func == (lhs: ClaudeAPIError, rhs: ClaudeAPIError) -> Bool {
        lhs.localizedDescription == rhs.localizedDescription
    }
}

/// Anthropic Messages API client. Resilient single-shot prompts:
/// - exponential backoff with jitter for 5xx / 429 / 529 (overloaded)
/// - daily token budget enforcement via TokenBudgetService
/// - model fallback (Opus -> Sonnet -> Haiku) on retry exhaustion
/// - configurable model strings (no hardcoded strings inside the client)
///
/// Public surface keeps a String-based `complete(model:...)` overload so older
/// call sites compile unchanged; the canonical entry point is the
/// `ClaudeModel`-typed overload below.
struct ClaudeAPIClient: Sendable {
    struct Response: Sendable {
        let text: String
        let inputTokens: Int
        let outputTokens: Int
        let modelUsed: ClaudeModel
        var totalTokens: Int { inputTokens + outputTokens }
    }

    static let shared = ClaudeAPIClient()

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let anthropicVersion = "2023-06-01"
    private let session: URLSession
    private let logger = Logger.api

    /// Retry policy: max 3 attempts, base 500ms, cap 8s, jitter 0.2.
    private let maxAttempts = 3
    private let baseDelayMs: UInt64 = 500
    private let capDelayMs: UInt64 = 8_000

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Legacy entry point: accepts the model as a String for compatibility with
    /// CoachService and DiagnosticsView which read `profile.anthropicModel`.
    /// Internally wraps the typed `ClaudeModel` overload.
    func complete(model: String,
                  systemPrompt: String,
                  userPrompt: String,
                  maxTokens: Int = 256) async throws -> Response {
        try await complete(
            model: ClaudeModel.from(string: model),
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            maxTokens: maxTokens,
            allowFallback: true,
            budget: nil
        )
    }

    /// Canonical entry point. Single-shot completion with retries and optional
    /// model fallback. `budget` may be nil for callers that opt out of daily
    /// cap enforcement (mainly background tasks that already track usage
    /// elsewhere).
    func complete(model: ClaudeModel,
                  systemPrompt: String,
                  userPrompt: String,
                  maxTokens: Int = 256,
                  allowFallback: Bool = true,
                  budget: TokenBudgetService? = nil) async throws -> Response {
        if let budget {
            let estimate = Self.estimateTokens(systemPrompt: systemPrompt, userPrompt: userPrompt, maxTokens: maxTokens)
            // TokenBudgetService is MainActor-isolated; hop to read.
            let exceedInfo: (exceeded: Bool, spent: Int, cap: Int) = await MainActor.run {
                (budget.wouldExceed(estimatedTokens: estimate), budget.spentToday(), budget.dailyBudget)
            }
            if exceedInfo.exceeded {
                throw ClaudeAPIError.budgetExceeded(
                    spentToday: exceedInfo.spent,
                    dailyBudget: exceedInfo.cap,
                    estimated: estimate
                )
            }
        }

        var currentModel = model
        while true {
            do {
                let response = try await callWithRetry(
                    model: currentModel,
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    maxTokens: maxTokens
                )
                if let budget {
                    await MainActor.run {
                        budget.record(inputTokens: response.inputTokens, outputTokens: response.outputTokens)
                    }
                }
                return response
            } catch let error as ClaudeAPIError {
                guard allowFallback, let fallback = currentModel.fallback, Self.shouldFallback(error: error) else {
                    throw error
                }
                logger.warning("Falling back from \(currentModel.rawValue, privacy: .public) to \(fallback.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
                currentModel = fallback
            }
        }
    }

    private func callWithRetry(model: ClaudeModel,
                               systemPrompt: String,
                               userPrompt: String,
                               maxTokens: Int) async throws -> Response {
        var lastErrorDescription = "unknown"
        for attempt in 1...maxAttempts {
            do {
                return try await singleCall(
                    model: model,
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    maxTokens: maxTokens
                )
            } catch let error as ClaudeAPIError {
                lastErrorDescription = error.localizedDescription
                guard Self.isRetryable(error: error), attempt < maxAttempts else {
                    throw error
                }
                let delay = computeBackoff(attempt: attempt)
                logger.warning("Retry \(attempt, privacy: .public)/\(self.maxAttempts, privacy: .public) for \(model.rawValue, privacy: .public) after \(delay, privacy: .public)ms: \(error.localizedDescription, privacy: .public)")
                try? await Task.sleep(nanoseconds: delay * 1_000_000)
            }
        }
        throw ClaudeAPIError.allRetriesFailed(last: lastErrorDescription)
    }

    private func singleCall(model: ClaudeModel,
                            systemPrompt: String,
                            userPrompt: String,
                            maxTokens: Int) async throws -> Response {
        let apiKey: String
        do {
            apiKey = try KeychainService.shared.getApiKey()
        } catch {
            throw ClaudeAPIError.missingAPIKey
        }
        guard !apiKey.isEmpty else { throw ClaudeAPIError.missingAPIKey }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")

        let body = MessagesRequest(
            model: model.rawValue,
            maxTokens: maxTokens,
            system: systemPrompt,
            messages: [.init(role: "user", content: userPrompt)]
        )
        request.httpBody = try JSONEncoder().encode(body)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ClaudeAPIError.invalidResponse
            }
            guard (200...299).contains(http.statusCode) else {
                let bodyText = String(data: data, encoding: .utf8) ?? ""
                throw ClaudeAPIError.http(http.statusCode, bodyText)
            }
            do {
                let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
                let text = decoded.content.compactMap { $0.text }.joined(separator: "\n")
                let inTok = decoded.usage.inputTokens
                let outTok = decoded.usage.outputTokens
                logger.info("Claude \(model.rawValue, privacy: .public) tokens in=\(inTok, privacy: .public) out=\(outTok, privacy: .public)")
                return Response(text: text, inputTokens: inTok, outputTokens: outTok, modelUsed: model)
            } catch {
                throw ClaudeAPIError.decoding(error)
            }
        } catch let apiError as ClaudeAPIError {
            throw apiError
        } catch {
            throw ClaudeAPIError.transport(error)
        }
    }

    /// Exponential backoff with bounded jitter.
    /// delay = min(cap, base * 2^(attempt-1)) * (1 + rand[-jitter, +jitter])
    private func computeBackoff(attempt: Int) -> UInt64 {
        let exp = baseDelayMs << (attempt - 1)
        let bounded = min(exp, capDelayMs)
        let jitterPct = Double.random(in: -0.2...0.2)
        let jittered = Double(bounded) * (1.0 + jitterPct)
        return UInt64(max(50, jittered))
    }

    /// Identify retryable conditions: 429 (rate limit), 5xx (server), 529 (overloaded), transport.
    static func isRetryable(error: ClaudeAPIError) -> Bool {
        switch error {
        case .http(let code, _):
            return code == 429 || code == 529 || (500...599).contains(code)
        case .transport:
            return true
        default:
            return false
        }
    }

    /// Worth falling back to the smaller model: persistent overload or quota.
    static func shouldFallback(error: ClaudeAPIError) -> Bool {
        switch error {
        case .http(let code, _):
            return code == 429 || code == 529 || (500...599).contains(code)
        case .allRetriesFailed:
            return true
        default:
            return false
        }
    }

    /// Crude pre-call token estimate. ~4 chars/token rule + max_tokens for output.
    static func estimateTokens(systemPrompt: String, userPrompt: String, maxTokens: Int) -> Int {
        let inputChars = systemPrompt.count + userPrompt.count
        return (inputChars / 4) + maxTokens
    }

    /// Decodes a model's text output as JSON. Tolerates the common Claude
    /// quirk of wrapping JSON in a ```json ... ``` fence by stripping the
    /// fence before decoding. Throws ClaudeAPIError.decoding on syntax error.
    static func decodeJSON<T: Decodable>(_ text: String, as type: T.Type) throws -> T {
        let cleaned = stripCodeFence(from: text)
        guard let data = cleaned.data(using: .utf8) else {
            throw ClaudeAPIError.decoding(NSError(domain: "ClaudeAPIClient", code: -1,
                                                  userInfo: [NSLocalizedDescriptionKey: "Empty UTF-8 conversion"]))
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ClaudeAPIError.decoding(error)
        }
    }

    private static func stripCodeFence(from text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            if let firstNewline = s.firstIndex(of: "\n") {
                s = String(s[s.index(after: firstNewline)...])
            }
        }
        if s.hasSuffix("```") {
            s = String(s.dropLast(3))
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Configurable model identifiers. Adding a new model? Update `fallback`
/// to keep the resilience ladder coherent.
enum ClaudeModel: String, CaseIterable, Codable, Sendable {
    case opus47 = "claude-opus-4-7"
    case sonnet46 = "claude-sonnet-4-6"
    case haiku45 = "claude-haiku-4-5-20251001"

    var fallback: ClaudeModel? {
        switch self {
        case .opus47: return .sonnet46
        case .sonnet46: return .haiku45
        case .haiku45: return nil
        }
    }

    static func from(string: String) -> ClaudeModel {
        ClaudeModel(rawValue: string) ?? .sonnet46
    }
}

private struct MessagesRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String
    let messages: [Message]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
    }

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

private struct MessagesResponse: Decodable {
    let content: [ContentBlock]
    let usage: Usage

    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }

    struct Usage: Decodable {
        let inputTokens: Int
        let outputTokens: Int

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }
}
