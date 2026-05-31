# 016 - Apple Foundation Models as an additive, flag-gated provider (not a pivot)

Status: PROPOSED. Reference provider implemented and isolated; requires user approval and a build verification before wiring into any surface. Answers the user's question: "would pivoting to Apple Intelligence improve things?"

## The question

The user asked whether to pivot the app to Apple Intelligence. Researched the current state (May 2026) before answering.

## Findings (verified, not from training data)

- Foundation Models framework (WWDC25, iOS 26) exposes Apple's on-device ~3B-parameter LLM via Swift: `LanguageModelSession`, `respond`/`streamResponse`, guided generation, tool calling. Free, private, offline, no API key.
- Device support: iPhone 16 (all), iPhone 15 Pro/Pro Max, M1+ iPad/Mac, with Apple Intelligence enabled in a supported region. The user's iPhone 16 Pro qualifies.
- Context window: 4096 tokens per session (Apple TN3193). Exceeding it throws `.exceededContextWindowSize`; you must start a new session. iOS 26.4 added `SystemLanguageModel.contextSize` and `tokenCount(for:)`.
- Deployment: the app targets iOS 18. Foundation Models needs iOS 26, so any use must be `@available(iOS 26.0, *)` and `#if canImport(FoundationModels)` gated, with a fallback for iOS 18-25 and unsupported devices.

## Decision: additive, not a pivot

A pivot is the wrong frame for three reasons.

1. It does not touch the biggest gap. Apple Intelligence does not detect workouts (decision 015 fixes that with HealthKit).
2. It cannot replace the deep coach. CoachService/CoachContextV2 assemble year-plus history into a single prompt for Anthropic Opus. A 4096-token on-device session cannot hold that, and the ~3B model is well below Opus on multi-step reasoning. Routing the coach on-device would be a capability downgrade.
3. The locked architecture and CLAUDE.md gate new dependencies; ripping out the Anthropic path would also remove the existing opt-in, BYO-key design the app already has.

Where Foundation Models genuinely helps, additively:

- Lightweight, low-stakes generation that benefits from being free/offline/private: the daily quip (DailyQuoteService), one-line identity-framed confirmations, short "why" explanations, quick summaries. These fit comfortably in 4096 tokens.
- A privacy-default for users who have not added an Anthropic key: today those surfaces fall back to curated static copy; on a supported device they could fall back to on-device generation instead.

## Implementation (reference, isolated)

`OnDeviceShortTextProvider` (`Services/OnDeviceShortTextProvider.swift`) behind a `ShortTextGenerating` protocol. Triple-gated: `#if canImport(FoundationModels)`, `@available(iOS 26.0, *)`, and a runtime `SystemLanguageModel.default.availability == .available` check. Returns nil on any unavailability or error so every caller transparently falls back. Not yet wired into any surface.

Suggested first adoption: DailyQuoteService, as a new tier in its existing fallback chain (AI key -> on-device -> curated static), since it is already optional and low-stakes.

## Build verification (the one risk)

This is the only file that uses a framework I could not compile in the agent sandbox (no iOS toolchain). The API usage matches the documented surface, but verify it against the iOS 26 SDK in Xcode before relying on it. It is isolated to one file and wired into nothing, so a signature mismatch is contained and trivially fixable, and cannot break the existing build paths.

## Decision needed from Clay

1. Approve adding the FoundationModels-backed provider as an additive tier (keep Anthropic Opus for the deep coach).
2. Approve the first adoption surface (recommend DailyQuoteService).
3. Build-verify `OnDeviceShortTextProvider` against the iOS 26 SDK.
