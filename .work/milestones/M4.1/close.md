# M4.1 Close Notes

Tag: `m4.1-complete` (to push after merge)
Branch: pushed directly to `main` per project workflow preference (no per-task branches).
Date: 2026-05-11 (JST)

## Quality gates

- iOS build clean, zero warnings.
- watchOS build clean (PersonalOptimizationWatch + PersonalOptimizationWatchComplications).
- 409 tests pass on iOS (M3.8 baseline was 400; +9 from M4.1).
- ScheduleValidator performance budget enforced via test: < 5ms for a 14-block week.

## Tasks completed (18/18)

Block 1 — Schema + foundation:
- T1: SchemaV9 with lightweight V8→V9 migration; threaded through `PersonalOptimizationApp`, `RootView`, `InMemoryContainer`.
- T2: `ScheduleBlock.anchorEvent` + `anchorOffsetMinutes` (additive, default nil; display-only at v1).
- T3: `UserProfile.anchorEventsCSV` + `lastGeneratedAt` + `anchorEvents` computed property.
- T4: `ScheduleGenerationRun` model with `purgeStale` (30-day rolling window).
- T5: `ScheduleValidator` — pure-Swift, 8 error classes (overlap, sleep, volume, module, anchor, weekday, time format, range inverted), sleep-window wrap-aware. 21 unit tests.

Block 2 — Generation pipeline:
- T6: `ScheduleIntake`, `ScheduleBlockDraft`, `GenerationProposal` DTOs; shape-compatible with the validator.
- T7: `CoachPrompts.generateSchedule` locked system prompt with hard constraints, soft prefs, identity framing, rejected-proposal block injection point.
- T8: `ScheduleAIService.generate` end-to-end: prompt → API → fence-strip → decode → validate → retry-on-failure → persist run.
- T9: `ClaudeAPIClient.decodeJSON` shared helper (markdown fence strip + outer-brace narrowing). Lives on the existing client; available to all future structured-output callers.
- T10: `ScheduleSeed.applyDrafts` wipes non-custom non-override blocks, inserts drafts, stamps `lastGeneratedAt` + `anchorEventsCSV`.

Block 3 — Views + UX:
- T11: `ScheduleGenerationView` — SwiftUI Form for the intake. Hydrates defaults from `UserProfile`. Push to diff view on success.
- T12: `ScheduleDiffView` — stacked Current vs Proposed week. Per-block change tags (Added/Changed/Same). Apply / Discard footer actions. Anchor labels render as "30 min after kid dropoff".
- T13: `OnboardingView` schedule step — "Build me a schedule (AI)" tile at top of the templates list, presented as a sheet (paged TabView, not NavigationStack).
- T14: `SettingsView` Schedule section — "Generate with AI" is the first link, with friendly relative `lastGeneratedAt` timestamp.

Block 4 — Adaptation extensions + tests:
- T15: `ScheduleSuggestionInbox` dismiss writes a `CoachMemory` row keyed by SHA256 of the change signature, importance=2, 60-day expiry.
- T16: `CoachService.suggestScheduleOptimizations` injects active rejected-proposal memory into the user prompt under `=== Previously rejected ===`. `CoachPrompts.suggestSchedule` system prompt extended with explicit "do not re-suggest" rule.
- T17: Inbox row gains "Why this?" disclosure that exposes `rationaleData` as human-readable bullets. Header gains a summary line ("3 suggestions ready").
- T18: `ScheduleAIServiceTests` covers happy path, fence stripping, validation retry, rejection memory injection, apply preserving custom blocks, rejection key dedup. 9 new tests.

## Tests added (30 net)

- `ScheduleValidatorTests`: 21 cases including a 5ms performance budget assertion.
- `ScheduleAIServiceTests`: 9 cases including markdown-fence stripping, retry path, rejection memory injection, apply preserving custom rows.

## Deferred to v1.5+

- Anthropic Structured Outputs (`output_config.format` with JSON Schema). The current implementation uses prompt-based JSON instruction + fence-strip + retry. Constrained decoding would shift the safety net earlier and reduce token waste on malformed responses; switching is a localized change in `ClaudeAPIClient`.
- Per-block manual edit in `ScheduleDiffView`. M4.1 ships Apply All / Discard. Inline edits are an obvious follow-on.
- Conversational generation (multi-turn refinement). The intake form is structured. v1.5+ could add a chat refinement layer over the same DTOs.
- Memory of rejected *generations* (vs rejected adaptation suggestions). T15-T16 cover the adaptation loop. Generation discards write a `ScheduleGenerationRun` with status=.discarded but the prompt does not yet feed those back. Low priority since regeneration is rare.
- Per-template seeds for `gym_focused`, `language_focused`, `fasting_focused` (already shipped in the prior commit).

## Carryover for v1.5+

- Wire the dismissed-generation feedback loop (above) so multiple discards refine future intakes automatically.
- Mascot reaction to generation events (currently silent; v1.5 could surface "let me know if this fits").
- Watch surface for the diff view (currently iOS-only; watch reads CloudKit-synced applied schedule).

## Notes on workflow

Pushed five commits directly to `main` (no per-task branches), per the explicit memorized preference:

1. `ae97a4f` — docs(M4.1): SPEC + PLAN drafted
2. `4915354` — block 1: schema + foundation + validator
3. `02b6d8d` — block 2: generation pipeline
4. `1dd2518` — block 3: views + onboarding tile + settings entry
5. (this commit) — block 4: adaptation extensions + close notes
