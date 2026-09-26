# Nutrition Phase 2 and articulated companion handoff

User authorized both features on 2026-09-26 and requested a resumable Claude handoff.
Repository: /Users/phantom/Developer/optimization-app. Base: f9098cc. Do not work in the empty Desktop `optimization-app 2` directory.

## Scope and decisions

- Recent foods (14 local calendar days), frequent foods (stored useCount, exclude photo estimates), saved meals, recent whole-meal repeats, copy previous day or selected meal/date.
- Home Quick add → Recent meal Log is two taps. Saved tab → Log is three. Keep inline meal-slot add and manual food creation.
- Batch logging validates first, saves all entries together, then mirrors each entry to HealthKit using the existing ordered retry pipeline. Preserve snapshot nutrition and servings when copying meals; never reuse Health sample IDs.
- Reuse SavedMeal/SavedMealItem already in SchemaV11/V12. No schema migration expected.
- Native articulated ninja uses the existing vector art, separate shoulder/hip/head transforms and blinking. Four sequences: idle, training, recovery, celebration. Existing PNG illustrations remain a style choice. No third-party SDK or new image assets.
- Motion must stop when hidden/inactive or either Reduce Motion preference is enabled. Previews never change state, rewards or logs. Celebrate on state/tap trigger, then settle; do not loop earned-win celebration indefinitely.

## Checkpoint (update as work progresses)

Status: complete and verified in the simulator; committed and pushed to `main` on 2026-09-26. Codex implemented it; Claude finished the open checks.

Verified 2026-09-26 on Xcode 26.6 (iPhone 17 simulator unless noted):

| Check | Result |
|---|---|
| Unit tests | 868 passed, 0 failed |
| UI tests | 11 of 11, including recent meal from Home in two taps, saved meal in three, and save/copy with Cancel then Confirm |
| Unsigned App Store archive (generic iOS) | succeeded, 0 non-exempt warnings; Watch app and Live Activity extension embedded |
| Schema parity and asset guards | passed |
| Motion visual review | four sequences, both palettes, 260 pt and 48 pt: celebration hands stay visible beside the head, no clipping, blink and breathing read clearly |
| Screen review | Recent, Saved meals and Copy day screenshots from the UI run |

Completion-pass changes (Claude): recent meals list their foods in the order they were logged, and copied items keep that order in the day list (each item steps back one second from the slot time, never before the start of the day; the last item lands on the slot time). Test added: `test_repeatedMealKeepsTheOrderItWasLoggedIn`. Indentation fix in `MascotView.art`.

CI note: GitHub CI run #37 (commit 6fd696f) failed only `test_saveMealAndCopyPreviewCancelThenConfirm`, waiting for the "Meal saved for next time." banner, which lasts 1.8 seconds and can vanish before a slow runner looks. The three Phase 2 UI tests now assert durable results instead: the save sheet closes, the saved meal is listed under Quick add, Saved meals, and Home shows "140 g protein left" after a repeat. Avoid asserting on the confirmation banner in new UI tests.

History: the first build found shared Watch compilation issues (MealSlot.defaultHour moved to FoodEntry.swift; the missing-date constant captured outside the SwiftData #Predicate). A test-fixture container lifetime error was fixed by retaining the in-memory containers. The celebration arm angles were adjusted after visual review.

Important existing limitation: general JSON export still does not export the Phase 1 food catalog, entry and target tables. Saved meals are exported with full snapshots, so they stay loggable after restore without the catalog. Do not claim the whole nutrition backup is complete.

Remaining checks that need a phone (not verifiable in the simulator):
1. Log a saved meal from Home, then confirm each food appears once in Apple Health under Nutrition, with no duplicate samples after copying the same meal twice.
2. Copy yesterday on a day that already has entries; confirm nothing existing is replaced and totals add up.
3. Watch the companion on Today and in the Dojo for a minute: blink, breathing, a training squat, and a celebration that settles. Turn on Reduce Motion and confirm a still pose. Lock and unlock: motion resumes, no stutter.
4. Mascot settings: turning off Articulated companion brings back the illustrated artwork.

Next engineering items: add the Phase 1 nutrition ledger (foods, entries, targets) to JSON backup; Nutrition Phase 3 (barcode scan and database lookup) per docs/planning/NUTRITION_MODULE_HANDOFF.md.

### Code map

- `Modules/Nutrition/NutritionService.swift`: recentFoods/frequentFoods/recentMeals/savedMeals, saveMeal/logSavedMeal/copyEntries; private atomic batch.
- `Modules/Nutrition/NutritionPortion.swift`: copy/backup snapshot values and SavedNutritionMealDTO.
- `Modules/Nutrition/Views/AddFoodSheet.swift`: repeat meals + food lists, portions, duplicate-tap guard.
- `NutritionTodayCard.swift`: visible Home Quick add; `NutritionMealActionsSheet.swift`: review/save/copy; `NutritionDayView.swift`: per-slot menus.
- `Modules/Character/MascotIllustration.swift`: Motion.sample and joint transforms; `MascotView.swift`: active/visible animation timeline; `MascotVariantPickerView.swift`: style preference and five preview states (including idle and comeback).
- Tests: NutritionPhase2Tests, MascotMotionTests, and two new Home repeat-meal UI cases. Existing companion preview UI test captures four states.

Service-level calendar dates are injected. No new hardcoded production zones. Shared MealSlot.defaultHour moved from the phone-only NutritionDayView to the shared FoodEntry model file for Watch builds.

## Verification / handoff requirements

- Tests: snapshot/portion preservation, atomic validation, fresh Health IDs/writes for each copied item, JST dates, Recent cutoff/order, Frequent photo exclusion, saved meal counters, no source mutations.
- UI: save a meal then log it from Home in ≤3 taps; copy preview/cancel/confirm; repeat navigation and duplicate-tap protection.
- Motion: deterministic pose tests; inspect four sequences at small and large sizes; both variants; reduced motion/offscreen; no artwork clipping.
- Commands: `bash scripts/check_schema_parity.sh`, `bash scripts/check_assets.sh`, `xcodegen generate`, `xcodebuild test -project PersonalOptimization.xcodeproj -scheme PersonalOptimization -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO`, generic iOS Release with CODE_SIGNING_ALLOWED=NO.
- Do not claim real-device HealthKit, CloudKit production sync or TestFlight distribution without actually verifying them.
- User's InBody records remain git-excluded under `.work/private/`; never stage them.
