# 022: Repeat meals and native articulated companion

2026-09-26. User requested both features and a resumable Claude handoff.

- Use existing SavedMeal/SavedMealItem models; no migration or third-party dependency.
- Whole-meal repeats/copies use immutable macro and portion snapshots, including when the original catalog food disappears. Cached food and meal usage counters update in the same local transaction as copied entries; HealthKit receives fresh entries after commit using the established ordered write queue.
- Home Quick add defaults to Recent. Logging a recent whole meal takes two taps and a saved meal three; manual entry remains available.
- Copying a previous day/meal has a review sheet and an explicit confirm. A failed validation must not partially append a meal. Duplicate taps are gated until the sheet dismisses.
- Saved meals gain optional backup DTOs with their complete snapshots. Old backups leave saved meals intact. This does not fix the pre-existing absence of the full nutrition ledger from generic JSON export.
- The built-in vector ninja gains shoulder, hip, head, blink and breathing motion. Default animated mode uses this drawing. Original PNG artwork is still selectable in mascot settings. The style is a per-device presentation preference (AppStorage), not a new synced model field.
- Timelines exist only while visible/active and both Reduce Motion flags are off. One celebration sequence settles to idle motion; no animation mutates rewards or logged activity.

- Completion pass (Claude, same day): repeated and copied meals keep the order their foods were logged in; copied items step back one second each from the slot time, never before the day start.

See docs/planning/NUTRITION_PHASE2_AND_ANIMATION_HANDOFF.md for verified checks and remaining work.
