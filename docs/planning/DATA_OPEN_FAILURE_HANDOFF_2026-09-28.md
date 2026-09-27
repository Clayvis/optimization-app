# Data-open failure and completion verification

Date: 2026-09-28. Base: `1184d54` on main. Checkout: `/Users/phantom/Developer/optimization-app`.

User: verify Claude's completed Nutrition Phase 2 and animations; repair "Couldn't open your data" despite app/phone restarts. User confirms this appeared after the recent update, exact installed build still unknown. Standing request: always leave a handoff for future tasks, now recorded in CLAUDE.md.

## Result

Reproduced and repaired an upgrade failure matching the report. The InBody commit `d90e45a` added three LiftExercise progression fields and LiftSet RIR, but historical schemas referenced those same live classes. Their model checksums changed, leaving real released databases unrecognized by staged migration.

An independent database made with frozen pre-InBody workout declarations from `dbb4644` fails on the original code with **NSCocoaErrorDomain 134504: Cannot use staged migration with an unknown model version**. This is confirmed locally, not from the user's phone. No device was connected (`xcrun devicectl list devices`).

## Changes

- `Models/SchemaV11.swift`: frozen pre-InBody LiftSession/LiftExercise/LiftSet declarations. `SchemaV1.swift` and `SchemaV2.swift` use that historical graph, inherited by V3 through V11.
- `Models/SchemaV12.swift`: explicitly replaces the historical workout graph with current types. Current persisted fields/version remain unchanged, preserving recognition of already-released V12 stores across phone, Watch, and complications.
- `PersonalOptimizationTests/Fixtures/ReleasedNutritionSchema.swift`: independent frozen workout graphs from pre-InBody and released InBody commits; V10/V11/V12 fixtures.
- `PersonalOptimizationTests/Services/ReleasedStoreMigrationTests.swift`: old-store upgrade, relationship/data preservation, new-field defaults, post-upgrade save/reopen, and current-store compatibility. Verifies food snapshots, saved-meal relationships, usage counts, targets, and HealthKit sample IDs remain intact.
- `Services/PersistenceBootstrap.swift`, `PersonalOptimizationApp.swift`, `Views/RootView.swift`, `Views/PersistenceRecoveryView.swift`: pass an optional startup report to the recovery screen. Report contains app/OS/schema and error domains/codes, not database records, paths, or NSError description/userInfo contents. ShareLink is user-controlled. Recovery copy advises an in-place update rather than repeated restarts. No reset/delete action.
- `PersistenceBootstrapTests.swift`: diagnostic privacy and recovery report assertions. Regenerated checked-in Xcode project for new test sources.
- `CLAUDE.md`: standing handoff instruction. `.work/state.json` points here (ignored local state).

## Verified

- Baseline reproduction: `/tmp/released-store-reproduction.xcresult`, `.work/logs/released-store-reproduction.log`.
- First successful V11 preservation/reopen regression: `/tmp/released-store-fix-1.xcresult`.
- **872 unit tests + 11 UI tests passed**, zero failures. `/tmp/data-open-full-suite.xcresult`, `.work/logs/data-open-full-suite.log`.
- All three independent migration regression cases passed: V10 upgrade, V11 upgrade, already-released V12 reopen. Old workout graph/defaults and nutrition data survived. Existing migration tests passed too.
- UI checks confirm two-tap recent whole meals, three-tap saved meals, save/copy preview cancel/confirm, InBody entry, and companion preview behavior.
- Reviewed all four rendered animation frames (idle/training/recovery/celebration), visibility/scene gating, Reduce Motion, and celebration settling. Claude's requested implementation is present; no additional defect found in those flows.
- **Unsigned generic-iOS Release archive passed**, zero non-exempt warnings. `/tmp/data-open-fix.xcarchive`, `.work/logs/data-open-release.log`. Confirmed embedded Watch app, Watch complications, and Live Activity extension.
- Schema parity guard, asset guard, git diff whitespace check passed. Prior Claude commit CI independently confirmed successful: https://github.com/Clayvis/optimization-app/actions/runs/36241335844.

Commands (choose fresh result/archive paths for a rerun):

```sh
xcodegen generate
bash scripts/check_schema_parity.sh
bash scripts/check_assets.sh
xcodebuild test -project PersonalOptimization.xcodeproj -scheme PersonalOptimization -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/optimization-phase2-dd -resultBundlePath /tmp/data-open-full-suite.xcresult -parallel-testing-enabled NO -jobs 3 COMPILER_INDEX_STORE_ENABLE=NO
xcodebuild archive -project PersonalOptimization.xcodeproj -scheme PersonalOptimization -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /tmp/optimization-current-release -archivePath /tmp/data-open-fix.xcarchive CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO -jobs 3
```

## Device follow-through and remaining limits

1. Publish/install a signed build containing this repair over the existing installation. This task produced an unsigned archive, not a signed TestFlight upload. Do not uninstall, reset, delete the store, or overwrite it with a backup.
2. Verify on the user's phone that launch reaches Home and existing workouts, nutrition, profiles, and scans are present. Verify iCloud/Watch synchronization after local recovery. Do not claim phone recovery before this is observed.
3. If recovery persists, use **Share startup report**, capture the exact installed build, and collect device console logs if necessary. SwiftData sometimes hides the underlying Core Data error in its thrown wrapper. Inspect the actual failing store/version before changing migration behavior again.
4. Existing non-blocking feature limitation: general JSON backup omits Phase 1 foods/entries/targets. Saved meals back up correctly. This repair preserves the ledger in place; it does not fix that backup gap.
5. Legacy models other than the workout graph still use shared global declarations. Future persisted model edits must freeze released shapes and add independent upgrade fixtures. Building an "old" store from modified live classes hides real upgrade bugs.

Repository note: no Localizable.xcstrings currently exists despite the documented convention. Recovery text uses SwiftUI localizable literals / String(localized:) consistent with existing code.
