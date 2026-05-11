# M4.2 Close Notes

Tag: `m4.2-complete` (push after merge)
Branch: pushed directly to `main` per workflow preference.
Date: 2026-05-11 (JST)

## Quality gates

- iOS build clean, zero warnings.
- watchOS build clean (PersonalOptimizationWatch + PersonalOptimizationWatchComplications).
- 409+ tests pass (M4.1 baseline 409; M4.2 added HealthKit sync coverage in T6, all passing).

## What landed

### Block 0 — Schedule fix (priority bug)
- Auto-seed gated on `UserProfile.onboardingCompleted`. Fresh installs no
  longer inherit Clay's `default_schedule.json` blocks before the user
  reaches onboarding's schedule step.
- `ScheduleIntake` now persists to `UserProfile.lastIntakeJSON` and hydrates
  on view appear. Backing out of the form preserves every answer.
- Onboarding "Continue" on the schedule step is disabled until the user
  explicitly picks a template OR applies an AI-generated schedule.
- `ScheduleDiffView` shows a "Nothing applied yet — tap Apply" banner so
  the proposal/apply distinction is obvious.

### Block 1 — "What are you optimizing?"
- New `OptimizationFocus` enum (language, music, strength, endurance,
  fasting, sleep_quality, deep_work, mobility, nutrition) plus custom
  labels via `custom:<label>` raw-value form.
- New `UserProfile.optimizationFocusesCSV` + `lastFocusPromptAt` fields.
- New `ScheduleIntake.optimizationFocusesCSV`. Hydrated from profile when
  the form opens; persisted back when the AI proposal is applied.
- Generation form: toggle-list of built-in focuses with descriptive footer.
- AI user prompt and `CoachPrompts.generateSchedule` system prompt both
  reference the focuses; each one is supposed to earn at least one weekly
  block.

### Block 2 — AI realism
- New REALISM section in the generation system prompt: density cap,
  cadence > density, recovery as a real block, friction reduction, 60-min
  weekday slack, honor focuses.
- `ScheduleIntake.availableTimeMinutesPerDay` (default 120, range 30-480)
  so the AI doesn't pile in 4 hours of training when the user has 90 min.

### Block 3 — HealthKit fetch surface
- `HealthKitServiceProtocol` gains 5 fetch methods:
  `fetchLatestQuantity`, `fetchSumQuantity`, `fetchSleepHours`,
  `fetchMindfulMinutes`, `fetchWorkouts`.
- `LiveHealthKitService` implements all five via `HKSampleQuery` +
  `HKStatisticsQuery`. Returns nil on empty/unauthorized rather than
  throwing.
- Authorized read scope: **12 → 28 types**. Adds respiratoryRate,
  oxygenSaturation, body composition, HR recovery, exercise + stand
  minutes, walking + running distance, walking speed, environmental +
  headphone audio, dietary macros, dietary caffeine, mindful sessions,
  stand hour, plus iOS-16 wrist temperature and iOS-17 daylight
  (availability-gated).
- `NSHealthShareUsageDescription` broadened to cover the new surface.
- `FakeHealthKitService` + `FailingHealthKitService` updated with stubs.

### Block 4 — DailyLog expansion
- 18 new optional fields on `DailyLog` covering everything fetched:
  respiratory rate, O2 sat, body comp, HR recovery, exercise/stand
  minutes, distance, ambient audio, wrist temp, mindful min, full macro
  stack, caffeine, time in daylight, step count, plus
  `healthKitSyncedAt`.
- New `HealthKitSyncService.syncToday()` — pure orchestrator. Walks the
  18 fields, calls the right fetch with the right unit, writes back to
  today's `DailyLog`. Idempotent. Individual fetch failures log a
  warning but don't abort the rest. Preserves existing user-entered
  values when HK returns nil.
- Wired into app launch via `Task` after onboarding-gate.

### Block 5 — iCloud-synced keychain
- `KeychainService.setApiKey` now writes with
  `kSecAttrAccessibleAfterFirstUnlock` + `kSecAttrSynchronizable=true`.
  The API key survives uninstall AND syncs to other Apple devices via
  iCloud Keychain.
- `migrateApiKeyToICloudSynced()`: probes for the legacy `ThisDeviceOnly`
  item, copies value to the new synchronizable item, then deletes the
  old. Safe sequence (copy-then-delete). Idempotent. Called once on app
  launch.
- `getApiKey` / `deleteApiKey` use `kSecAttrSynchronizableAny` to match
  both pre- and post-migration items.

### Block 6 — Tests
- `HealthKitSyncServiceTests`: 5 cases covering empty HK, populated HK,
  idempotency, partial data, preservation of existing values when HK is
  nil.
- Existing 409 tests still pass.

## Deferred to follow-up

- **Dedicated optimization-focuses onboarding step.** The generation
  form already captures focuses in the same flow, so wife/buddy testing
  isn't gated on this.
- **Routine "anything new you're sharpening?" Coach card.** Plumbing
  exists (`lastFocusPromptAt` on profile); UI surface deferred.
- **CoachContext + TrendAnalyticsService consumption of new DailyLog
  fields.** Data is now landing in the row; surfacing it in
  `summaryForPrompt` and 30-day aggregates is a small follow-on.
- **Settings → Data section** with "Export full history", "Verify iCloud
  sync", "Refresh from HealthKit". Plumbing exists; UI deferred.
- **CloudKit health-check diagnostic.** Container state probe + last-pulled
  timestamp.
- **SECURITY.md persistence guarantee doc.** Should explicitly list what
  survives uninstall after Block 5.

These are small, additive deltas. Marking them as carryover rather than
gating the live-test push.

## Notes on workflow

Five commits, all on `main`, no per-task branches:

1. `3b36b87` — Block 0: schedule sticks (priority bug fix).
2. `2ff841b` — Blocks 1 + 2: optimization focuses + AI realism.
3. `1d3afce` — Blocks 3 + 4 + 5: HealthKit depth + iCloud keychain.
4. (this commit) — Block 6: tests + close notes.

## Verification (manual smoke)

1. **Wife's flow on fresh sim.** Erase. Launch. Onboarding shows the
   schedule step; "Continue" is disabled until a template or AI proposal
   is applied.
2. **Intake persistence.** Open AI tile, fill 3 fields, dismiss. Re-open:
   fields preserved.
3. **API key survives uninstall.** Set key. Generate insight. Delete app.
   Reinstall (same iCloud). Key prompt does NOT appear.
4. **HealthKit pull.** Pre-populate sim Health app with synthetic data;
   launch app; observe DailyLog fields populated.
