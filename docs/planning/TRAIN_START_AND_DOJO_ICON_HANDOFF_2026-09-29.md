# Train session start and Dojo tab icon

Date: 2026-09-29. Base: c2d2d66 on main. Checkout: /Users/phantom/Developer/optimization-app.

## Request

User, with screenshots of the Train tab: "these two tabs, make no sense, they have fixed titles when you click into them, my workouts change and vary" (the "Lift A · legs, push, pull" and "My Workout · your custom lift" tiles open fixed exercise lists). "and dojo does not have a icon".

## Findings

- The Dojo tab uses `systemImage: "torii.gate"`, which is not an SF Symbol (absent from the system symbol list), so no icon renders. The Dojo header fallback uses the same name.
- Train's lift tiles open the bundled "Lift A" template and the single editable "My Workout" template. Today's `lift_a`/`lift_b` schedule blocks open the same two. The Watch lists them too.
- `LiftService.startSession(template:)` rejects an empty exercise list, so there is no way to start a workout and build it as you go.

## Scope

- Dojo: a torii-gate template image asset for the tab and the header fallback.
- Train: replace the two fixed tiles with "New workout" (start empty, add exercises with quick picks from your own exercise history, optional name) and a tile for the most recent completed workout under its real name, which repeats it (same exercises and set counts; weights prefill from last time through the existing prefill). The New workout screen also lists recent workouts to repeat.
- Today: lift schedule blocks open the New workout screen instead of the fixed templates.
- Out of scope: the Watch's fixed list (unchanged; noted for the user). The custom-template editor stays for the Watch.

## Status

Implemented 2026-09-29 by Claude; pushed as 38deb3a with GitHub CI green (run 36598987796). Not yet observed on the phone.

## Implementation

- `Assets.xcassets/ToriiGate.imageset`: a torii-gate vector drawn for this app (template rendering, 25 pt), used by the Dojo tab (`Label("Dojo", image: "ToriiGate")`) and the Dojo header's no-mascot fallback. Checked in simulator screenshots: tints with the other tab icons, red when selected.
- `LiftService`: `startFreestyleSession(name:)` (no exercises; blank name becomes "Workout"), `recentWorkouts(limit:before:)` (finished, with exercises, newest first, one per title and exercise list), `recentExerciseNames(limit:excluding:)` (exercises with logged sets in finished workouts, most trained first), `template(repeating:)` (same exercises in order, sets performed and most common reps, last rest; no sets copied). `addCustomExercise` now reuses the history spelling and targets of the last finished workout with that exercise, so prefill and progression stay linked.
- `NewLiftWorkoutView` (new): today's open coach lift plan, an optional name with Start empty workout, and Repeat a recent workout.
- `LiftSessionView`: `freestyle` and `repeatOf` modes. Freestyle starts at once; the add-exercise section offers quick picks from exercise history and says so; no CUSTOM badges in a built-as-you-go workout. Repeat shows "Last time: N sets, top W lb × R" per exercise. Preview rows are keyed by position (a repeat can list an exercise twice). Add-exercise errors now show instead of being swallowed.
- `TrainingHubView`: "New workout" tile and, once a workout is finished, a tile titled with that workout's own name and exercises that repeats it. The fixed "Lift A" and "My Workout" tiles are gone.
- `TodayView`: `lift_a` and `lift_b` schedule blocks open New workout.
- `PrescribedWorkoutType.displayName`: lift plans without a coach title show "Strength" instead of "Lift A" / "My Workout".
- Unchanged: the Watch still lists Lift A and My Workout (`TrainingWatchView`), and the custom-template editor remains for it.

## Results

Same verification run as the InBody photo change; see INBODY_PHOTO_IMPORT_HANDOFF_2026-09-29.md for the shared table (919 unit tests, 17 of 17 UI tests from a clean install, Release archive with 0 non-exempt warnings, guards).

- New LiftServiceTests: freestyle start and naming, history spelling and targets for added exercises, recent workouts (finished, distinct, newest first), quick-pick ranking and exclusion, repeat plan (performed shape, no sets copied, loads prefill from last time). All 26 LiftServiceTests passed.
- UI: `test_newWorkoutBuildsAsYouGoAndBecomesTheRepeatTile` names a new workout, adds an exercise, logs a set, finishes, and finds the repeat tile under that name with "Last time" in its preview. Passed in both full UI runs.
- Screenshots from the simulator (not committed): the Dojo tab shows the torii icon, black when idle and red when selected, and the Dojo header fallback uses it; the Train grid shows "New workout" in place of the fixed tiles; New workout lists today's coach plan, the name field and Start empty workout.

## Device-only checks

- Tab bar icon on the phone in light and dark mode.
- Start a new workout, add exercises from the quick picks, log sets, finish; the Repeat tile then shows that workout's name.
