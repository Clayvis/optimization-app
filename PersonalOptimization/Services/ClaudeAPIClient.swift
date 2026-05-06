import Foundation
import os

enum ClaudeAPIError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case http(Int, String)
    case decoding(Error)
    case transport(Error)

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
        }
    }
}

/// Minimal Anthropic Messages API client. Single-shot prompts; no streaming.
/// Uses the user's stored API key from Keychain at call time. Logs token usage to
/// the "api" logger category for cost tracking.
struct ClaudeAPIClient: Sendable {
    struct Response: Sendable {
        let text: String
        let inputTokens: Int
        let outputTokens: Int
        var totalTokens: Int { inputTokens + outputTokens }
    }

    static let shared = ClaudeAPIClient()

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let anthropicVersion = "2023-06-01"
    private let session: URLSession
    private let logger = Logger.api

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Single-shot completion. Throws on missing API key, transport error, or non-2xx.
    func complete(model: String,
                  systemPrompt: String,
                  userPrompt: String,
                  maxTokens: Int = 256) async throws -> Response {
        let apiKey: String
        do {
            apiKey = try KeychainService.shared.getApiKey()
        } catch {
            throw ClaudeAPIError.missingAPIKey
        }
        guard !apiKey.isEmpty else { throw ClaudeAPIError.missingAPIKey }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")

        let body = MessagesRequest(
            model: model,
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
                logger.info("Claude \(model, privacy: .public) tokens in=\(inTok, privacy: .public) out=\(outTok, privacy: .public)")
                return Response(text: text, inputTokens: inTok, outputTokens: outTok)
            } catch {
                throw ClaudeAPIError.decoding(error)
            }
        } catch let apiError as ClaudeAPIError {
            throw apiError
        } catch {
            throw ClaudeAPIError.transport(error)
        }
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
