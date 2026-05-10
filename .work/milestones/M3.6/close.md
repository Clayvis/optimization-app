# M3.6 Close Notes

Tag: `m3.6-complete`
Branch: `m3.6/bugfix-personalization-coach`
Date: 2026-05-07 (JST)

## Quality Gates

- iOS build: clean (zero warnings).
- Watch build: clean.
- Tests: 240 passed, 0 failed.
- Coverage: maintained above prior baseline.
- Privacy manifest: no new categories required (network calls to Anthropic do not require xcprivacy entries; Keychain access already declared).

## Tasks completed

Block 1 (entered already-done at run resume):
- SessionLifecycleService refactor with bounded HK retry, fire-and-forget HK writes
- HealthKitWriteFailure persistence
- Live Activity dismissal driven by SwiftData state
- Regression tests for HK-failure paths

Block 2:
- ScheduleEditorView with day-grouped CRUD, swipe delete, add-per-day, reorder via natural sort
- ScheduleBlockEditSheet (create + edit, isCustom marked on user touches)
- Reset-to-default action preserving user's custom blocks
- default_schedule_blank.json shipped for M4 onboarding choice

Block 3:
- SwimWaterType enum + free-text location + recents chips + configurable pool length
- Lap stepper (pool) and meter quick-pick + exact entry (open water)
- Hydration quick-pick CSV (user-editable in Settings) + custom oz/mL entry + beverage picker
- HydrationEntry rows persisted; effectiveOz drives DailyLog.waterOz
- Today's-log card on HydrationView surfacing recent entries
- Streak chips (workout / hydration / learning) on TodayView
- Lift add-custom-exercise inline + volume aggregator footer with three concentric arcs and identity-framed completion line
- Achilles check-in section gated behind Settings toggle

Block 4:
- ClaudeAPIClient (Anthropic Messages API, single-shot, Keychain-backed)
- CoachService with cached daily insight, manual refresh increments refreshCount, locked system prompt per spec
- DailyQuoteService with 60-quote curated DB across six styles + optional Haiku-generated quotes
- CoachInsightCard on TodayView with refresh affordance and missing-API-key recovery flow
- API key entry/clear in SettingsView (Keychain-backed status row)
- Daily quote rendered under TodayView title

Block 5:
- DiagnosticsView (HK auth, recent failures, API key status, last successful Coach call, token usage today / month, "Test API key" button)
- Task 21 (haptic suppression): codebase has no haptic engine usage; no wrap required.

## New tests

- CoachServiceTests: 10 (system prompt locked, gatherContext, cache TTL, refresh increments, missingAPIKey path, cache resilience, token usage persisted, style differentiation)
- DailyQuoteServiceTests: 11 (curated stability, style fallback, parse variants, AI off path, AI cache, AI failure fallback)
- PerformanceTests: +3 (Coach cache <10ms, curated quote <50ms, schedule editor fetch <100ms)

## Performance benchmarks

All M3.6 spec targets pass on the iPhone 17 Pro simulator:

- SessionLifecycleService.end synchronous return: passes via existing regression tests (HK write happens detached).
- Schedule editor list with 50 blocks: <100ms (test_perf_scheduleEditorFetch_50Blocks_under100ms).
- Coach insight cache lookup: <10ms (test_perf_coachCacheLookup_under10ms).
- Daily quote curated render: <50ms (test_perf_dailyQuoteCurated_under50ms).
- Coach insight generation cold path: not benchmarked in CI (requires network); manually verified with API key in dev.

## Decisions

- Schema stays at 3.0.0; SwimSession `waterTypeRaw` and UserProfile additions are additive-with-defaults handled by SwiftData lightweight migration.
- BlockType marked CaseIterable + Sendable so the schedule editor picker can enumerate it.
- Schedule Views excluded from watch + complications targets so iOS-only modifiers (listRowSeparator, secondarySystemBackground) don't break the watchOS build.
- Coach system prompt is locked verbatim per spec; styles map "custom" to the user's customStylePrompt.

## Deviations from spec

- Task 21 (haptic suppression) was a no-op: codebase had no haptic engine usage, so the conditional wrap never had a target.
- M4 onboarding (template selection from default vs blank vs other templates) is deferred to the M4 milestone; the blank file is in place.
- Sleep / restingHR / HRV in CoachContext currently read DailyLog only (not live HealthKit); HK live-read would block the API call. Acceptable since DailyLog is hydrated by HealthKit observers on session lifecycle.

## Stop conditions

- Stop. Do not start M4.
