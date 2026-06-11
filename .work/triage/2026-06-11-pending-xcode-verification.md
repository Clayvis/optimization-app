# Pending Xcode verification: training fix batch (2026-06-11, second push)

Five fixes on top of the merged revamp. Authored remotely, unverified by Xcode.

## Changed in this batch

1. Auto-start: Training tiles start the session on tap. `LiftSessionView` and
   `SwimSessionView` gained `autoStart` (default false, so schedule-block taps
   from TodayView still show the preview). Swim auto-start prefills water
   type, pool length, and location from the most recent session. Resume
   banner lift rows auto-resume.
2. "My Workout" replaces the Lift B tile. Template lives in
   `UserProfile.metadataBlob` (key `customLiftTemplate`), seeded from bundled
   Lift B on first open, edited via the pencil toolbar button in the session
   view (`CustomLiftEditorSheet`). Sessions record `template == "My Workout"`.
   `lift_b` schedule blocks in TodayView route to it. Bundled "Lift B" JSON
   kept for old drafts and history. New tests:
   `CustomLiftTemplateStoreTests`.
3. Custom train hours: `TimeOfDayPreference.custom` + a "Training starts"
   DatePicker in onboarding anchors and Settings anchor editor. Planner
   resolves `.custom` from `UserProfile.trainingWindowStartHHMM` (field
   existed, was never read). Re-apply template after saving anchors to see
   blocks move. New tests in `SchedulePlannerTests`.
4. Faster Move refresh: observer now watches activeEnergyBurned,
   appleExerciseTime, stepCount on a debounced (60s) today-only sync path,
   plus a foreground `scenePhase` sync in the App. Observer tests updated to
   `allObservedTypes`.
5. Daily goal milestones: quarter ticks on DailyProgressBars, "halfway" label
   at 50 percent ("almost" moved 80 to 75 to align), one haptic per milestone
   crossing, baseline-on-appear so opening the screen is silent.

## Verify

- Build + tests (`CustomLiftTemplateStoreTests`, `SchedulePlannerTests`,
  `HealthKitObserverServiceTests` changed).
- Simulator: tile tap goes straight to live session; pencil edits My Workout;
  anchors editor shows the time picker when Custom is selected; Move bar
  updates on foreground.

---

# Pending Xcode verification: Training + Learning tab revamps

Branch: `claude/training-tab-redesign-tnqr3y`
Authored in a remote Linux container (no Xcode). Symbols and initializers were
verified against the codebase by inspection; nothing on this branch has been
compiled or run.

## Changed files

- `PersonalOptimization/Modules/Training/Views/TrainingHubView.swift` (rewrite)
- `PersonalOptimization/Modules/Learning/Views/LearningHubView.swift` (rewrite)
- `PersonalOptimization/Modules/Learning/Views/LearningTimerView.swift` (rewrite)
- `PersonalOptimization/Modules/Learning/LearningModule.swift` (added `iconName`)
- `PersonalOptimization/Components/DojoComponents.swift` (added `DojoPressStyle`)

## Verify at the workstation

1. ~~`xcodebuild -scheme PersonalOptimization build` with zero warnings~~
   DONE 2026-06-11 at merge: iOS + watch + complications all build, 0 warnings.
2. ~~`xcodebuild test -scheme PersonalOptimizationTests`~~
   DONE 2026-06-11 at merge: 704 tests, 0 failures.
3. Open the four `#Preview`s (TrainingHubView, LearningHubView,
   LearningTimerView, DojoComponents) and confirm they render with seeded data.
4. Simulator pass, both color schemes:
   - Training: week dot strip marks today, tiles navigate, resume banner
     appears when a lift is left with `durationMinutes == 0`, custom activity
     sessions appear in Today's log.
   - Learning: hero ring percent matches per-module capped math, live ring
     advances while the stopwatch runs, quick-log chips write through
     `LearningService.logMinutes`, Pimsleur deep link still opens.

## Known behavior notes (intentional, not regressions)

- Learning stopwatch state (`startedAt`) is still view-local `@State`; leaving
  the screen mid-session drops the running timer, same as before the revamp.
- Week-at-a-glance counts completed sessions only (lift `durationMinutes > 0`,
  basketball `endTime > startTime`, swim `durationMinutes > 0`). No targets
  invented; dots show days with at least one completed session.
- Training "Today" card now excludes in-progress lifts (the old list counted a
  zero-duration lift as a completed session).
