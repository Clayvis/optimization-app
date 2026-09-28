# Train suggestions and logging

Date: 2026-09-28. Base: aa10de2 on main. Checkout: /Users/phantom/Developer/optimization-app.

## Request and scope

User wants to work on Train suggestions and logging next. Preference question sent: both / suggestions / logging. No response received yet; proceeding with both suggestions-to-session and logging. First slice is strength suggestions becoming real logged workouts, with faster, correctable set entry. Keep this handoff current.

## Initial findings

- Train and Today both show PrescribedWorkoutCard. Accept currently only changes status; it does not start or link a session. Detail renders raw template JSON rather than an executable exercise plan.
- Lift session logging resets every new set to 135 lb and 5 reps, with no previous-set prefill or logged-set editing.
- LiftService.startSession ignores template targets when filling existing progression fields. The active screen can show template targets and conflicting default progression targets.
- LiftService.logSet finds exercises by name, which can target the wrong exercise when duplicate names exist. Inputs need validation at the service boundary.
- Initial logging-only focused LiftService tests passed. Broader implementation now in progress, not yet fully verified. Database upgrade repair from prior task is pushed as aa10de2; user phone recovery still requires updated installed build.

## Next steps

1. Inspect prescription payload and session routing; define bounded first slice using user's preference.
2. Implement useful suggestion-to-session flow and reliable set logging using existing models.
3. Add regression tests for targets, identity, input validation, and durable set logging. Verify related UI flow.
4. Build/test, document exact outcomes and remaining work here. Do not label unverified work complete.

## Implementation in progress

- Lift logging uses exact exercise identity, validates inputs, prefills last set/completed workout/plan, preserves decimal weights, and offers in-place set corrections. Template progression fields now match actual plan targets.
- Suggested lift JSON validated before use; Review opens readable plan, explicit Start creates actual exercises without any fabricated performed sets. Existing-key-free saved suggestions remain viewable.
- Proper durable linking needs stable session identity. Added **SchemaV13**, optional LiftSession.id assigned only to newly created sessions. Froze the entire V12 workout graph before introducing it, retaining prior V10/V11/V12 fixtures. No metadata/notes workaround. JSON backup includes the optional ID and reads older backups.
- Start/resume idempotently uses PrescribedWorkout.sessionUUID. End updates its status only after finishing the actual session, and repeated End no longer creates duplicate workout credit. Missing cloud-linked session blocks duplicate creation.
- Train's resume banner routes the exact draft, including custom AI plan names and prior-day drafts.
- Coach generation guards against replacing a linked active plan, including after the asynchronous API response; completed linked plans are retained when generating a new suggestion.
- Raw JSON and manually editable completion status removed from suggestion details.

Active compile/test: session 93316, `.work/logs/train-flow-focused-1.log`, `/tmp/train-flow-focused-1.xcresult`. New additional tests were written after this run started and need a subsequent run. Continue by checking compile, testing prescription linking/backup/editing and UI flow, running historical migrations, full suite and Release archive. User phone recovery from prior task is still unconfirmed; do not uninstall/reset.

## Completion pass (Claude, 2026-09-28)

Picked up from Codex's in-progress run (`train-flow-focused-1`), which had failed to compile.

- Compile fix: `SchemaV12.swift` imports Foundation (the frozen V12 classes use `Date`).
- Renamed the new optional `LiftSession.id` to `LiftSession.sessionID` (model, service, JSON DTO/import, tests). An optional `id` replaced the persistentModelID-based Identifiable conformance, so every pre-V13 row would share the nil identity in any `ForEach(sessions)`, and existing `.id` uses silently changed meaning. V13 had not shipped, so the rename is free.
- Verified the frozen `SchemaV12` workout classes match the released V12 declarations field for field (diff against `aa10de2:LiftSession.swift`).
- Suggestion card navigation: SwiftUI does not support `navigationDestination` inside a lazy container, and Today shows the card inside a List. The card now takes `onOpenWorkout`; Today hosts `navigationDestination(item:)` on the List and passes the tapped suggestion. Train (ScrollView/VStack) keeps the card's own destination. Shared destination view: `SuggestedWorkoutDestination`.
- Upgrade tests extended to V13 (`ReleasedStoreMigrationTests`): V10, V11 and released V12 stores upgrade with data intact, old sessions have nil `sessionID`, new sessions get one, and the upgraded store reopens with the ID preserved.
- UI fixture `--ui-testing-suggested-lift` (valid two-exercise plan for today). UI tests: `test_suggestedLiftReviewStartsWorkoutWithPrefilledSet` (Train: Review shows the plan, Start opens the workout, the first set prefills the coach's 40 lb, Log set lists an editable set) and `test_suggestedLiftOpensFromToday` (Review from inside Today's List opens the plan).

- Flaky test fixed: `test_duplicateExerciseNamesLogToExactExercise` asserted on `session.exercises?.first`, but SwiftData to-many arrays are unordered, so `first` was sometimes the added duplicate (failed once in a 899-test run with 1 vs 0). The test now holds the template's own Back Squat by identity. The service never relied on that order (it matches by identity; views sort by `orderIndex`). After the fix, LiftServiceTests ran 20 consecutive iterations (21 tests each, 420 runs) with 0 failures.
- Coach guard completed: `CoachService.existingPrescription(for:)` now returns the day's newest prescription (sorted by `generatedAt`, the same row the card shows). Codex's change keeps a completed suggestion's row and adds a new one beside it when the plan is regenerated, so a day can hold several rows; with an unsorted fetch the started-plan guard could inspect the finished row and let a started replacement be overwritten. Test: `CoachServiceV2Tests.test_prescribeTodaysWorkout_keepsFinishedPlanAndProtectsStartedReplacement`.

First pass (Xcode 26.6, iPhone 17 simulator, `train-full-1`): 880 unit tests passed, including the three upgrade tests and all LiftServiceTests. `test_suggestedLiftOpensFromToday` passed. The Train UI test reached the prefilled 40 lb and then could not find Log set (bottom of the form, not yet created); the test now scrolls to it.

Final results (shared verification pass with Nutrition Phase 3; full table and commands in NUTRITION_PHASE3_BARCODE_HANDOFF_2026-09-28.md): 900 unit tests passed with 0 failures, including V10/V11/V12 to V13 upgrades, all 21 LiftServiceTests (also 20 consecutive iterations with 0 failures) and the new coach test, which fails without its fix. 15 of 15 UI tests passed, including `test_suggestedLiftReviewStartsWorkoutWithPrefilledSet` and `test_suggestedLiftOpensFromToday`. Unsigned Release archive succeeded with 0 non-exempt warnings.

Device-only checks: start a coach suggestion on the phone, log sets, finish, and confirm the card shows Completed and the workout counts once; confirm existing workouts are intact after installing the V13 build over the V12 build.

