# 006 — On-device AI for Coach insights (deferred)

Status: DEFERRED. Recorded against HANDOFF_CLAUDE_CODE.md P3-1.

## Context

The Coach module currently sends health context (DailyLog summaries, streak counts, recent biomarker values, Persona) to Anthropic's API. For a private protocol app, an on-device 3B model produces meaningfully similar insight quality with zero data leakage.

iOS 18 ships with Apple's Foundation Models framework (private LLM access for apps from iOS 18.1+). Failing that, MLX or CoreML with a quantized Llama 3.2 3B fits in roughly 2GB and runs at acceptable latency on A16+ chips.

## Open questions before commitment

1. **Quality delta vs Claude Sonnet 4.6 + Persona injection.** Need a 20-prompt side-by-side eval on historical Coach prompts. M4.2's Persona system substantially raises the bar; an on-device model has to match the personalization too. Acceptance: within 80% of Sonnet+Persona quality on Clay's eyes-on rubric (specificity, accuracy of referenced data, actionability, tone match).
2. **App Store binary size impact.** Ship the model lazily via `BGProcessingTask`-driven download? On-device privacy story breaks if Anthropic hosts the download.
3. **Battery impact on iPhone 14 and below.** Clay's wife uses an older device; need watt-hour delta per Coach call.
4. **Sandbox + entitlement story for Foundation Models on iOS 18.1+.** Public availability of the framework in App Store builds (vs developer preview).

## Decision

Do not implement now. Land P0/P1 (record 005) and ship to TestFlight first. Add a `LocalCoachAPI` stub that returns curated insights so the user can opt into "Local mode" in Settings, with the actual on-device model deferred to v1.5+ unless one of the open questions surfaces a forcing function.

## Pre-conditions for revisiting

- TestFlight cohort > 1 user.
- Persona + Coach v2 prescriptive output validated against real users (M4.2 measurement window).
- Confirmed Foundation Models availability on a non-developer iCloud account.
