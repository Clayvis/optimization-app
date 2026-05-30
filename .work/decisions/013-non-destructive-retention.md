# 013 - Non-destructive retention (remove non-user deletes)

Status: IMPLEMENTED in code, awaits build + PR review. Part of the 2026-05-30 stability pass (`.work/triage/2026-05-30-stability-and-engagement.md`, findings R1/R2/R3/R4).

## Context

The audit found three deletes on non-user paths, violating the CLAUDE.md permanent-retention rule, plus one user-action delete that was undocumented.

- R1 `DailyLogDedupeOnce` (launch path): merged duplicate-day rows into a canonical row, then deleted the duplicate. Data-loss risk if `merge` missed a field or the calendar shifted between runs.
- R2 `ScheduleGenerationRun.purgeStale`: deleted rows older than 30 days; its doc claimed "called once per app launch" but it had zero call sites (a dormant trap).
- R3 `CoachMemoryService.pruneExpired`: deleted expired CoachMemory rows on a read path (`active(asOf:)`). The same method already filters expired rows at read, so the delete was redundant.
- R4 `CoachMemoryService.add` key-dedupe: deletes a prior row sharing the same key when the user saves a new keyed note. User-action, but undocumented.

## Decision

- R1: dedupe is now non-destructive. It merges each duplicate into the canonical row, then marks the duplicate `supersededAt` (new optional field on DailyLog, lightweight in-place migration on the current schema) and neutralizes its measurement fields. The retained tombstone contributes zero to any aggregate even for readers that do not filter superseded rows. `DailyLogStore.upsert` filters `supersededAt == nil` so the writer never returns a tombstone. No row is deleted.
- R2: `purgeStale` deleted outright. `ScheduleGenerationRun` rows are retained permanently; the class doc updated.
- R3: `pruneExpired` removed. `active(asOf:)` already filters `expiresAt > date`, so expired rows are simply not surfaced to the Coach. They are retained.
- R4: the `add` key-dedupe is documented in CLAUDE.md as the fifth allowed user-action delete path. It runs only on the user's explicit save of a keyed note.

Net: no non-user-action `modelContext.delete` remains in the codebase.

## Why neutralize instead of just a flag

DailyLog has ~30 reader sites (TrendAnalyticsService, StreakService, ActivityArchiveService, etc.). Relying on every reader to add a `supersededAt == nil` filter would be a wide, error-prone change where one miss double-counts. Neutralizing the tombstone's fields makes aggregates correct without touching any reader. `neutralize` must stay in sync with `merge` when a DailyLog field is added; both are co-located in DailyLogStore with a comment to that effect.

## Retention safety

This change strictly increases retention. The only remaining deletes are the five explicit user-action paths in CLAUDE.md. The merged data lives in the canonical row; the tombstone is an inert retained record.

## Test

`PersonalOptimizationTests/Services/DailyLogStoreDedupeTests.swift`: inserts two same-day rows with disjoint data, runs dedupe, asserts (1) one non-superseded row remains with merged data, (2) the duplicate is retained with `supersededAt` set and zeroed fields, (3) totals are unchanged when summing all rows (tombstone contributes zero), (4) re-running dedupe is a no-op.

## Files

- Changed: `Models/DailyLog.swift` (supersededAt), `Services/DailyLogStore.swift` (merge+supersede+neutralize, upsert filter), `Models/ScheduleGenerationRun.swift` (purgeStale removed), `Modules/Engagement/CoachMemoryService.swift` (pruneExpired removed), `CLAUDE.md` (retention section).
- Added: `PersonalOptimizationTests/Services/DailyLogStoreDedupeTests.swift`.

## Decision needed from Clay

Confirm the neutralize-tombstone approach over a reader-side filter. If you would rather delete-after-merge (the row truly gone), that is a one-line revert in `dedupe`, but it reintroduces a launch-path delete and the future-field merge risk.
