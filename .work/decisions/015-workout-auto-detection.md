# 015 - Automatic workout detection via HealthKit observation

Status: IMPLEMENTED in code, awaits build + PR review. Closes the user's reported biggest gap: "the app doesn't realize I'm working out."

## Context

Root cause (audit 2026-05-30): `HealthKitObserverService` already registers an `HKObserverQuery` for `HKObjectType.workoutType()` with background delivery requested, but `handleUpdate()` only called `HealthKitSyncService.syncRange(7)`, which pulls quantity/category samples into DailyLog and never reads `HKWorkout`. A workout the user recorded on the Apple Watch (or Strava/Nike/Garmin) landed in HealthKit as an `HKWorkout` and was dropped. The read primitive `LiveHealthKitService.fetchWorkouts(in:)` existed with zero call sites. The entitlement `com.apple.developer.healthkit.background-delivery` was missing despite a code comment claiming it was on, so background delivery silently no-opped.

Apple Intelligence is irrelevant here: the on-device LLM does not detect workouts. This is a HealthKit wiring fix.

## Decision

1. Entitlement: add `com.apple.developer.healthkit.background-delivery = true` to the iOS target (project.yml + PersonalOptimization.entitlements). Required for the existing observer to wake in the background.
2. Model: add `WorkoutEvent.hkWorkoutUUID: UUID?` (optional, nil default; lightweight in-place migration on the current schema, same pattern as DailyLog.supersededAt). It is the dedupe key.
3. Service: new `WorkoutImportService`. Pure, testable `importWorkouts([ImportedWorkout])` that, for each workout not already in the ledger (deduped by HealthKit UUID, both against the store and within the batch), inserts a completed `WorkoutEvent` keyed to the user-timezone day and records a `.workout` CompletionHistory row. Append-only, never deletes.
4. Mapping: `ImportedWorkout(hkWorkout:)` converts an `HKWorkout` using only stable, non-deprecated properties (uuid, workoutActivityType, startDate, endDate). `WorkoutEventSource.from(HKWorkoutActivityType)` maps strength -> .lift, basketball -> .basketball, swimming -> .swim, everything else -> .custom.
5. Wiring: `HealthKitObserverService.handleUpdate()` now also fetches the last 7 days of `HKWorkout`, imports the new ones, and posts `.dailyLogsRecomputed` when any landed so streaks and character state rederive.

## Why dedupe is essential

The app's own Watch sessions and `LiveHealthKitService.saveWorkout` write `HKWorkout` samples. Without the UUID guard, observing `workoutType()` would re-import every workout the app itself logged, double-counting the streak. The `hkWorkoutUUID` guard makes the in-app log and the HealthKit sample reconcile to one ledger day.

## Retention

Import is additive only. No deletes. Consistent with the permanent-retention rule.

## Tested

`WorkoutImportServiceTests`: create + CompletionHistory, dedupe across calls, dedupe within a batch, skip when the ledger already has the UUID, user-timezone day key, and the activity-type source mapping.

## Not in this change (specced in the deep-dive review)

- Replacing the observer's blind 7-day re-query with an `HKAnchoredObjectQuery` (anchor-based, only new/deleted workouts).
- Importing a typed session row (LiftSession/SwimSession/CustomActivitySession) from the HKWorkout so the workout shows in TrainingHub's "Today" list, not just the streak ledger.
- A "logged your Apple Watch workout" confirm/undo surface on TodayView (friction-reducing, Design Principle 5).

## Decision needed from Clay

Confirm auto-import with no confirmation gate (workouts auto-log and the streak reflects reality), versus a confirm/undo surface. Recommendation: auto-import now, add a non-blocking "logged from Apple Watch, undo" toast next.
