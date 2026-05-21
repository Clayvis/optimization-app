# 005 — Pre-TestFlight P0/P1 hardening

Status: ACCEPTED. Implemented 2026-05-21 against HANDOFF_CLAUDE_CODE.md, layered on top of M4.1 (AI schedule optimizer) and M4.2 (Persona behavioral inference + cardio + music) work.

## Context

Three external reviews plus a direct code audit converged on four buckets of pre-TestFlight risk:

A. **Schema sprawl across CloudKit-shared targets** — iPhone, Watch, and Watch Complications declared different SwiftData schema versions. A CloudKit replication that reached the Watch with fields it doesn't know about could silently lose them on the Watch's next save back.

B. **HealthKit pipeline half-built** — the background-delivery entitlement was on, but no `enableBackgroundDelivery` or `HKObserverQuery` calls existed. Late-arriving samples (Garmin, Withings, Strava) never updated yesterday's streaks.

C. **30-second polling timers** — `CharacterStateService` and `TodayView` each ran 1/min CPU-spending recompute loops with unbounded `FetchDescriptor` fetches.

D. **AI/API resilience thin** — single-shot client, no retry, no daily budget cap, no model fallback.

The user is solo (Clay), about to ship to TestFlight (wife as second user). The cost of corrupting CloudKit data on first cross-device sync is high. The cost of fixing this before TestFlight is low.

## Decision

Land P0 and P1 in one pass before the TestFlight cut, on top of the existing M4.1/M4.2 work — preserving every M4.x feature while replacing the broken/fragile foundations.

### P0 (correctness — TestFlight blockers)

- **AppSchema as single source of truth.** Every production ModelContainer constructs its `Schema` via `AppSchema.schema()`. Bumping the schema version is one line in one file. SchemaV10 (P0/P1 pass) layered on top of M4.1's SchemaV9 (`ScheduleGenerationRun`) — additive only. New entities `TokenUsageEntry` + `BackgroundTaskLog`; new default-valued fields on `UserProfile` + `DailyLog`.
- **DailyLogStore + app-level uniqueness.** SwiftData prohibits `@Attribute(.unique)` on CloudKit-mirrored models, so the handoff's preferred approach is unavailable. Instead, every writer funnels through `DailyLogStore.upsert(for:)` which queries by the user-calendar `startOfDay` key before insert. A one-shot `DailyLogDedupeOnce` runs at first launch to repair any historical duplicates from inconsistent timezone logic. The richer M4.2 HealthKit-derived fields (respiratory rate, body fat, sleep, etc.) are preserved in the merge logic.
- **UserCalendar as the canonical time-zone resolver.** Reads `UserProfile.timezone`; falls back to device tz only when `travelModeFollowsDevice` is on. 76 hardcoded `Asia/Tokyo` references collapsed to 1 (the seed default).
- **AppGroupContainer for the shared store URL.** All three CloudKit-sharing targets open the same `default.store` URL in the App Group, so the Complications no longer lag the Watch app by a CloudKit cycle.
- **HealthKitObserverService + enhanced HealthKitSyncService.** Observer queries + `enableBackgroundDelivery(.immediate)` on weight, RHR, HRV, sleep, mindful, workouts. On fire, `syncRange(days: 7)` rebuilds DailyLog rows for the last week so late-arriving Garmin/Withings samples retroactively update yesterday's streaks and mascot state. Posts `Notification.Name.dailyLogsRecomputed` so downstream services rederive. The M4.2 single-day `syncToday()` is preserved; the new `sync(for:date)` and `syncRange(days:)` are layered on top.

### P1 (architecture hardening)

- **CharacterStateService reactive, not polling.** Subscribes to `userStateChanged` + `dailyLogsRecomputed`. 60-second cache for repeated calls within the window. `gatherInputs` rewritten to use predicate-bound fetches (today's DailyLog by date equality, lift/swim PR check uses `fetchLimit = 1` on a sorted descriptor). No more full-table scans every 30 seconds.
- **TodayView TimelineView-style ticker.** Replaced `Timer.scheduledTimer` with a `.task` modifier that sleeps in a loop. The OS pauses the task off-screen; no manual lifecycle.
- **ClaudeAPIClient resilience.** Exponential backoff with jitter for 429/5xx/529. Model fallback ladder (Opus → Sonnet → Haiku). `TokenBudgetService` enforces a daily cap (default 50k, slider 0–500k; 0 disables AI entirely). The legacy `complete(model: String, ...)` overload is preserved so M4.2's `CoachService` and `DiagnosticsView` keep compiling unchanged.
- **Keychain dual posture.** M4.2 explicitly switched to iCloud-synced default and shipped a migration; we preserve that as the new default but add an opt-out toggle in Settings. `UserProfile.apiKeyICloudSync` controls the posture; toggling re-writes the keychain item to match.
- **Metadata blob on DailyLog + UserProfile.** Additive JSON bag for low-traffic experimental fields. The rule: schema bump only for new entities or new relationships; metadata blob for new scalar attributes.

### P2 (reliability)

- **WatchConnectivity event consumer wired.** App `init` subscribes to `WatchConnectivityService.lastEventStream` and fans each event into `userStateChanged` (for mascot + UI) and (for workout events) `HealthKitSyncService.syncToday()`.
- **HealthKitSyncService is `@Observable`.** `isSyncing`, `lastSyncedAt`, `lastSyncDurationMs`, `lastSyncError` are public; UI can show a "catching up..." spinner.
- **Sleep window read from UserProfile.** `NotificationSuppressionRules.shouldSuppressHydration` accepts `sleepStartHHMM` + `sleepEndHHMM` and handles cross-midnight windows.
- **BackgroundTaskLog persistence.** Each BG run writes a row; Diagnostics surfaces a count of failed runs and the most recent five.
- **Diagnostics view expanded** — schema version row, token usage with progress bar against the daily cap, BG task history, API key storage posture (device-only vs iCloud-synced).

## Why we deviated from the handoff

- **Did NOT default Keychain to ThisDeviceOnly.** M4.2 explicitly chose iCloud sync for the convenience win (user reinstalls, survives device migrations, watch picks up the key). Reverting that default would undo a deliberate product decision and break the M4.2 migration path. Instead, we added a Settings opt-out so security-minded users can choose ThisDeviceOnly.
- **Did NOT add `@Attribute(.unique)` on DailyLog.date.** Apple's docs forbid it on CloudKit-mirrored models. App-level upsert + dedupe migration gives the same end-state.
- **Replaced ensureLog inline pattern in HealthKitSyncService with DailyLogStore.** M4.2's `ensureLog` did its own fetch-or-create with `.current` calendar; routing through DailyLogStore.forUser ensures it uses the user's pinned timezone like every other writer.
- **Bumped to SchemaV10 not V9.** Remote main already had SchemaV9 for M4.1's `ScheduleGenerationRun`. SchemaV10 is the additive layer for P0/P1.

## Acceptance evidence

- `grep -rn "SchemaV[0-9]" --include="*.swift" ... | grep -v -e "Models/Schema" -e "Models/AppSchema" -e "#Preview" -e "previewContainer"` → empty.
- `grep -rn "DailyLog(date:" --include="*.swift" | grep -v "DailyLog.swift" | grep -v Tests` → 2 sanctioned sites (JSONImportService, DailyLogStore).
- `grep -rn "Asia/Tokyo" --include="*.swift" | grep -v Tests | wc -l` → 1 (UserProfile.timezone seed default).
- `grep -rn 'Timer.scheduledTimer' --include="*.swift" PersonalOptimization` → 1 (LiveWorkoutSessionService 1Hz workout ticker, allowed by spec).
- Cross-cutting tests CT-1 through CT-5 added in `PersonalOptimizationTests/HandoffCorrectnessTests.swift`.

## What was NOT done (deferred)

- **Swift Package extraction (P1-6).** Project churn cost > immediate value when xcodegen already includes the shared sources in every target. Decision 008 if it becomes load-bearing.
- **On-device AI (P3-1).** Decision record 006: not implemented. Quality eval against Sonnet 4.6 + binary size impact need to be measured.
- **Partner mode (P3-2).** Decision record 007: deferred to v1.1.
- **Reward density, self-comparison narratives, lapse recovery proactive flow (P3-3/4/5).** V1_OPPORTUNITIES.md backlog post-TestFlight.
