# Pending Xcode verification: watch tamagotchi + partner challenge (2026-06-12)

## Watch mascot (bug fix + feature)

- ROOT CAUSE: the 16 mascot PNGs shipped only in the iOS asset catalog; the
  watch home and MascotComplication rendered blank images. Moved them to
  `PersonalOptimization/MascotAssets.xcassets`, now a resource of iOS, Watch,
  and WatchComplications targets (project.yml). RUN `xcodegen generate`.
- IdleHomeWatchView: mascot now sits inside a live protocol-adherence ring
  (replaces the separate master-metric block), tap pokes it (haptic, bounce
  honoring Reduce Motion, caption flips reason <-> tally).
- MascotComplication: circular family gained a goal ring around the mascot;
  new accessoryRectangular (Smart Stack) family shows mascot + "N of M goals"
  + linear gauge. Entry now carries the ProtocolGoalSnapshot tally.

## Partner weekly challenge (seam-only, decision 007 addendum)

- Protocol-points scoring: ChallengeScoring walks the week through
  ProtocolGoalSnapshot; standing logic is pure. PartnerSharedRecord gained
  optional challengeWeekStart/Points (legacy payloads still decode; test
  covers it). PartnerService.challengeStanding() reads through the zone.
- PartnerChallengeCard on TodayView under PartnerStatusCard: You/Her point
  bars, leader line, daily points dots, days-left. Hidden until paired, so
  nothing changes in production until the CloudKit zone lands.
- Tests: PartnerChallengeTests.
- Decision 003 marked ENROLLED; decision 007 addendum records this scope.

## Verify

- `xcodegen generate`, then all four targets build (complications target
  newly compiles ProtocolGoalSnapshot usage in MascotComplication).
- Watch simulator: ninja renders on home + complication; tap bounces; ring
  fills as domains close. Add the rectangular Mascot widget to Smart Stack.
- iPhone: PartnerChallengeCard stays hidden (unpaired); preview shows the
  full card with a seeded MemoryPartnerSharedZone.

---

# Pending Xcode verification: Lift B leftovers (2026-06-11, third push)

The first rename only touched the iOS hub tile. This batch clears the
remaining "Lift B" surfaces:

- Watch Train list row is now My Workout; LiftWatchView resolves the custom
  template from UserProfile metadata (synced via CloudKit). Both files ride
  the existing SharedTraining/SharedModels source globs in project.yml.
- Bundled schedule JSONs (default, balanced, gym_focused, fasting_focused,
  References copy) renamed activity labels; `module: lift_b` keys unchanged.
- `LiftBRenameOnce` one-shot launch migration renames already-stored seeded
  blocks (non-custom, module lift_b) on the device. Update only, no deletes.
  Tests: `LiftBRenameOnceTests`.
- PrescribedWorkoutType.liftB displayName is "My Workout"; coach prompts note
  what lift_b means now.
- Kept on purpose: lift_templates.json "Lift B" entry (seed source + old
  drafts), session history rows, schedule module keys, watch handoff payloads.

NOTE: this and the previous batch add new source files. The pbxproj is
XcodeGen-generated; run `xcodegen generate` after pulling or the new files
will not be in any target.

---

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
