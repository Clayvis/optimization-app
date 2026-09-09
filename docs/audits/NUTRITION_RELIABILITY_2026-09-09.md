# Nutrition reliability review, September 9, 2026

Reviewed pushed commit `9dc45e2` after fetching `origin`. This pass preserves the
new nutrition screens, targets, workout rings, and daily coach. It changes no
SwiftData schema and adds no dependencies.

## Reproduced bugs and fixes

1. **Edits could lose to an older Health write.** A controlled test paused the
   first write, changed servings in a separate service instance, then released
   the old write. Health ended with 165 kcal instead of the edited 330 kcal.
   Operations now run in order per entry across service instances. Different
   entries can still sync independently.
2. **A deleted entry could reappear in Health.** Deleting while that entry's
   first write was paused removed the local entry, but the late write recreated
   its Health data. Deletion now waits for earlier operations on the entry.
   A completed write also checks the current entry snapshot before marking it
   synced, so an older version cannot acknowledge a newer edit.
3. **Logging still performed synchronous Health IPC on the main thread.** The
   permission check happened before launching the background write. Both that
   check and the nutrition screen's authorization-status reads now run off the
   main thread. Local saves do not wait for Health authorization queries.
4. **Invalid nutrition values could crash display or reach HealthKit.** Food,
   target, and serving writes now reject non-finite values and overflowing
   serving totals before mutating saved data. Nutrition formatting no longer
   converts unbounded Double values to Int. Invalid synced values display as
   unavailable and do not fill progress bars.

## Validation

The three initial Health regressions failed against the pushed implementation,
including assertions for stale calories and food remaining after deletion.
Added coverage also checks rejected inputs preserve stored entries, overflow,
safe formatting, invalid Health totals, and authorization reads off the main
thread.

- Full native suite: **817 passed, 0 failed, 0 skipped** (812 unit tests and
  5 UI tests), using Xcode 26.6 on the iPhone 17 simulator with iOS 26.5.
  The UI suite includes food logging plus the existing workout and rest-day
  flows. Simulator targets use local signing.
- Release build for a generic iOS device, including the embedded watch app
  and extensions: **succeeded with zero compiler/build warnings**. Distribution
  signing was disabled for this compile check.
- Schema parity, direct DailyLog creation, timezone, polling timer, model
  parity, and app icon guards passed. `git diff --check` passed.
- Local test result bundle:
  `/private/tmp/optimization-xcode-local/NutritionVerified.xcresult`.
  Build and test logs are in `.work/logs/nutrition-verified.log` and
  `.work/logs/release-nutrition.log`. The failing-before regression result is
  `/private/tmp/optimization-xcode-local/NutritionRegressionBefore.xcresult`.

## Remaining device checks

Verify create, rapid edit, and delete against Apple Health on a signed physical
device, including interrupted connectivity and permission changes. The queue
orders operations within a running app; a durable retry queue and backfilling
unsynced entries after app termination remain future work from the nutrition
handoff. This pass does not measure retention or change nutrition targets.
