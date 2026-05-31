#if canImport(FoundationModels)
import FoundationModels
#endif
import Foundation
import os

/// Abstraction over a short-form text generator so the app can swap providers
/// (on-device Apple Foundation Models, or the existing Anthropic client) behind
/// a single call site. Intended for SHORT, low-stakes generations only.
protocol ShortTextGenerating: Sendable {
    /// Generate a short response to `prompt` under `instructions`, or nil if the
    /// provider is unavailable so the caller can fall back. Keep prompts small:
    /// the on-device model has a 4096-token session limit.
    func generate(instructions: String, prompt: String) async -> String?
}

/// On-device generator backed by Apple's Foundation Models (iOS 26+). Free,
/// private, offline. Returns nil when the framework is unavailable, Apple
/// Intelligence is off, the device is unsupported, or generation fails, so the
/// caller transparently falls back to its existing path.
///
/// Scope (decision 016): lightweight surfaces only (daily quip, one-line
/// confirmations, short summaries). NOT the deep CoachService: a 4096-token
/// session cannot hold the year-plus CoachContextV2 history, and the ~3B
/// on-device model is well below Opus on multi-step reasoning.
///
/// Build note: the FoundationModels block requires the iOS 26 SDK. It is gated
/// by `#if canImport(FoundationModels)` and `@available(iOS 26.0, *)`, so the
/// iOS 18 deployment target and older devices are unaffected (the call returns
/// nil and the caller falls back). This is the one file to build-verify first.
struct OnDeviceShortTextProvider: ShortTextGenerating {
    private let logger = Logger.api

    func generate(instructions: String, prompt: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else {
                return nil
            }
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: prompt)
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            } catch {
                logger.warning("On-device generation failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        } else {
            return nil
        }
        #else
        return nil
        #endif
    }
}
