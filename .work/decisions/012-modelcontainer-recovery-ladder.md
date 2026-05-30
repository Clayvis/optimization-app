# 012 - ModelContainer recovery ladder (replace launch fatalError)

Status: IMPLEMENTED in code, awaits build + PR review per Quality Gates (the sandbox has no iOS toolchain; `xcodebuild` runs on Clay's Mac). Recorded against the stability-and-engagement triage (`.work/triage/2026-05-30-stability-and-engagement.md`).

## Context

`PersonalOptimizationApp.swift:131` and `PersonalOptimizationWatchApp.swift:40` wrapped `ModelContainer` init in `do/catch` and called `fatalError` on any failure. This is the highest-probability cause of the reported occasional launch crashes.

The store is a single App Group SwiftData store, opened across four targets (iOS app, Watch app, Watch complications, extensions), carrying a ten-version migration chain (`SchemaV1`...`SchemaV10` via `AppMigrationPlan`), feeding a CloudKit private database. Every one of these can fail intermittently in the field:

- A migration stage throwing on a specific stored-data shape.
- A CloudKit schema-deploy lag or record-type mismatch (CloudKit replicates fields a target does not yet know).
- Store corruption after a hard kill mid-write.
- A momentarily missing App Group entitlement (`AppGroupContainer.storeURL()` returns nil, already handled with a sandbox fallback, but the open can still fail).

With `fatalError`, any of these is a 100% crash on launch until the store is wiped, and a wipe destroys data, violating the permanent-retention rule. "Occasional" fits exactly: the crash fires only when one of these transient conditions is present.

## Decision

Introduce `PersistenceBootstrap` (`PersonalOptimization/Services/PersistenceBootstrap.swift`): a non-destructive recovery ladder shared by both app entry points. Each rung is tried only if the previous one threw.

1. App Group store + migration + CloudKit private DB. Success -> `PersistenceMode.full`.
2. Same on-disk store + migration, `cloudKitDatabase: .none`. Success -> `.localOnly`. Isolates a CloudKit failure from a local one: if the bytes on disk are fine and only CloudKit is unhappy, the app stays fully usable locally and resumes sync on the next clean launch.
3. Throwaway in-memory store, on-disk store left untouched. Success -> `.recovery`. The app launches to a recovery screen instead of crashing.

`PersistenceMode.isDurable` gates the launch side-effect sequence (seed, HealthKit sync, notification + CloudKit + observer wiring). In `.recovery` the store is in-memory, so those side effects are skipped (writing to a throwaway store would mask the failure).

UI surfacing:
- `.localOnly`: dismissible `ErrorBanner` over `RootView`, copy "iCloud sync is paused. Your data is saved on this device...".
- `.recovery`: blocking `PersistenceRecoveryView`, copy steering the user to force-quit and relaunch, explicitly stating data is unchanged. No reset/delete/wipe action is offered.

## Retention safety (per CLAUDE.md)

This change adds NO deletion path. The ladder never calls `modelContext.delete`, never removes the store file, never wipes CloudKit. Rung 3 opens a separate in-memory store and leaves the on-disk store and its iCloud copy intact for a future launch to recover. The four allowed deletion paths in CLAUDE.md are unchanged.

## Remaining fatalError

One `fatalError` remains, in `PersistenceBootstrap.inMemory(schema:logger:)`, reachable only if the compiled `Schema` is structurally invalid. With no disk IO, CloudKit, or migration in play at that rung there is no runtime or data failure mode, so this is a build-time programmer error that fails in dev/CI and cannot occur on a shipped build that has launched before. Crashing there is the honest signal. This narrows the launch-crash surface from "any migration/CloudKit/corruption/entitlement failure" to "compiled schema is invalid".

## Test

`PersonalOptimizationTests/Services/PersistenceBootstrapTests.swift`:
- `testDurabilityMapping`: mode -> isDurable mapping.
- `testInMemoryContainerRoundTrips`: in-memory rung inserts and fetches a `UserProfile`.
- `testUnopenableStoreDegradesToRecoveryWithoutCrashing`: a store URL under `/dev/null` forces both disk rungs to throw; asserts the ladder lands on `.recovery` and returns a launchable container (no crash).

The ladder relies on `ModelContainer` surfacing open failures as thrown errors, which is its documented behavior.

## Decision needed from Clay

1. Confirm the three-rung degradation and copy are acceptable.
2. Confirm `.localOnly` should reuse the red `ErrorBanner` or get a softer warning style (follow-up, low effort).
3. Build on hardware/simulator and run the new test (no iOS toolchain in the agent sandbox). On green, this closes as ACCEPTED.

## Files

- Added: `PersonalOptimization/Services/PersistenceBootstrap.swift`
- Added: `PersonalOptimization/Views/PersistenceRecoveryView.swift`
- Added: `PersonalOptimizationTests/Services/PersistenceBootstrapTests.swift`
- Changed: `PersonalOptimization/PersonalOptimizationApp.swift` (init + gated `runLaunchSequence`)
- Changed: `PersonalOptimizationWatch/PersonalOptimizationWatchApp.swift` (init + gated seed)
- Changed: `PersonalOptimization/Views/RootView.swift` (persistenceMode param, banner, recovery branch)
