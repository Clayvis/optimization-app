# M1 CloudKit Live-Sync Verification: Deferred

**Status**: DEFERRED to paid Apple Developer Program upgrade pre-M7
**Decided in**: Decision 001 (project generation tool) and option A confirmation
**Milestone**: M1, Phase 7

## What is wired now

- `iCloud.com.rawlins.PersonalOptimization` declared on iOS app, watch app, and widget extension entitlements (`com.apple.developer.icloud-container-identifiers`).
- `CloudKit` declared in `com.apple.developer.icloud-services`.
- App Group `group.com.rawlins.PersonalOptimization` shared across all three targets.
- `ModelConfiguration(... cloudKitDatabase: .private("iCloud.com.rawlins.PersonalOptimization"))` set in:
  - `PersonalOptimizationApp.container`
  - `PersonalOptimizationWatchApp.container`
  - `CurrentBlockTimelineProvider.sharedContainer()`

## What is NOT verified at M1 close

The MILESTONES.md M1 Definition of Done line:

> CloudKit sync verified (modify on phone simulator, see change on watch simulator within 30 seconds).

This requires:

1. A paid Apple Developer Program account ($99/year). Container provisioning for `iCloud.com.<container>` is rejected for free personal teams when CloudKit dashboard creation is required.
2. A signed-in iCloud account on both simulators that share the same Apple ID.
3. CloudKit container schema deployed (which requires the paid account too).

Per BOOTSTRAP.md, the user is on a free personal team for M1-M3, switching to paid pre-M7. Live cross-simulator CloudKit sync verification is therefore not achievable inside M1.

## Local-store behavior at M1

- The iOS app launches successfully with the ModelContainer initialized. SwiftData backs the local store.
- The watch app launches with its own local SwiftData store.
- CloudKit sync silently fails to initialize at runtime with `CKAccountStatusNoAccount` (visible in console only). No data is sent to Apple.
- All in-app reads and writes complete locally. The Phase 3 `SchemaV1Tests` verified the container loads, profiles persist, and lift cascade-deletes work.

## Re-enable plan (pre-M7)

When the user upgrades to a paid team:

1. Replace `DEVELOPMENT_TEAM` in `project.yml` (currently `""`) with the new Team ID.
2. Run `xcodegen generate` to update the project.
3. In Apple Developer portal: provision the App Group, the iCloud container, and the bundle IDs under the new team.
4. In Xcode: enable iCloud + CloudKit capability on each target (or let Xcode auto-resolve from the entitlements files which already declare the container).
5. Push the SwiftData schema to CloudKit dashboard. Apple's tooling: deploy CloudKit schema from Xcode (Edit > Provisioning Profiles > CloudKit Schema).
6. Run the cross-simulator manual test: open iOS sim, sign into iCloud, modify UserProfile.name, observe watch sim reflect within 30s.
7. Update this file to status: VERIFIED with date and the test transcript.

## Code differences vs. the spec

None of the M1 code reads or writes anything CloudKit-specific that would need to change at upgrade time. The `cloudKitDatabase: .private(...)` argument is the only switch, and it stays the same after upgrade. Decision 002 (removed `.unique` constraints) and the optional `[LiftExercise]?` to-many relationships in LiftSession also stay; they are CloudKit-required regardless of paid vs. free team.

## What this defers from M1 Quality Gates

| DoD line | Status at M1 close |
|---|---|
| App launches on iPhone 16 Pro simulator (we use 17 Pro) | PASS |
| Watch app launches on Apple Watch Ultra 2 simulator (we use Ultra 3) | PASS |
| Today view on phone shows correct blocks for current weekday with current block highlighted | PASS |
| Watch complication renders current block name and time remaining | PASS |
| All 13 SwiftData models compile and persist correctly | PASS (15 @Model classes) |
| **CloudKit sync verified across simulators within 30 seconds** | **DEFERRED to paid-team upgrade** |
| Profile data persists across launches | PASS (local SwiftData) |
| JSON export/import round-trip without loss | PENDING Phase 8 |
| Build succeeds with zero warnings | PASS |
| All unit tests pass | PASS |
| Performance benchmarks met | PENDING Phase 9 |
| PR merged to main, tag `m1-complete` pushed | PENDING Phase 10 |
