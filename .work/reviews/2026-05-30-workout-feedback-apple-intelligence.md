# Deep dive: workout detection, workout UX, feedback loop, and Apple Intelligence

Date: 2026-05-30. Scope: the user's three stated gaps plus the question "would pivoting to Apple Intelligence improve things?" Research-backed (Foundation Models and the 2025-2026 workout APIs all postdate the training cutoff, so current facts were verified by web search; see decisions 015, 016). I cannot compile iOS in this environment, so each item is marked IMPLEMENTED (and unit-tested where possible) or SPECCED (ready to build).

## 0. Verdict on Apple Intelligence (answer first)

Do not pivot. Adopt it additively.

- It does not address your biggest gap. Workout detection is HealthKit, the Watch, and Core Motion, not an LLM. Decision 015 fixes it there.
- It cannot replace the deep coach. The on-device model is a ~3B-parameter model with a 4096-token-per-session context window (Apple TN3193). CoachService assembles year-plus history for Anthropic Opus; that does not fit in 4096 tokens, and the small model is well below Opus on reasoning.
- It requires iOS 26 while the app targets iOS 18, so any use must be availability-gated with a fallback.
- Where it does help: free, private, offline generation for lightweight surfaces (daily quip, short confirmations, quick summaries), and as a privacy-default for users without an Anthropic key. Implemented as an isolated, gated `OnDeviceShortTextProvider` (decision 016).

Net: Apple Intelligence is a nice additive tier for small text, not a strategy for the three pains you named. The leverage is in HealthKit and UX.

## 1. Gap: "the app doesn't realize I'm working out" (biggest)

Diagnosis. `HealthKitObserverService` already registered an `HKObserverQuery` for `workoutType()` with background delivery, but `handleUpdate()` only re-synced DailyLog quantity fields and never read `HKWorkout`. The read primitive `fetchWorkouts(in:)` existed with zero callers. The `com.apple.developer.healthkit.background-delivery` entitlement was missing despite a comment claiming it was on. So every workout you did on the Apple Watch Ultra 2 (or Strava/Nike/Garmin) landed in HealthKit and was silently dropped.

IMPLEMENTED this session (decision 015):
- Added the missing background-delivery entitlement (iOS target).
- `WorkoutEvent.hkWorkoutUUID` dedupe key (lightweight migration).
- `WorkoutImportService`: imports `HKWorkout` samples into the ledger, deduped by UUID, user-timezone day key, append-only. Unit-tested.
- Wired into the observer so a Watch/third-party workout now creates a WorkoutEvent + CompletionHistory and rederives streaks/character state without you opening the app.
- `LogWorkoutIntent`: a Siri/Shortcuts "I just did a workout" zero-friction log for the case where no HealthKit sample exists.

SPECCED next:
- Replace the observer's blind 7-day re-query with an `HKAnchoredObjectQuery` on `workoutType()` (anchor-persisted), so each fire processes only new/deleted workouts instead of re-scanning a week. Lower battery, cleaner.
- Import a typed session row (LiftSession/SwimSession/CustomActivitySession) from the HKWorkout, populated with duration and, via `HKWorkout.statistics(for:)` (the non-deprecated path), energy and distance, so the workout appears in TrainingHub's "Today" list, not only the streak ledger.
- A non-blocking "Logged your 42-min run from Apple Watch. Undo?" toast on TodayView (Design Principle 5: friction reduction with easy reversal, not a confirmation gate).

## 2. Gap: the workout interface is clunky

Diagnosis (specifics from the audit). Every flow is a manual phone timer you must remember to start and stop, plus required fields:
- LiftSessionView opens read-only and forces a "Start workout" tap before any logging, then a modal AddSetSheet per set (3 steppers, log, dismiss). Multiple modal round-trips per set.
- SwimSessionView forces a setup Form (water type, location, pool length) before the timer starts.
- BasketballSessionView forces a 1-10 Achilles check-in and a hydration stepper before you can end.
- CustomActivitySessionView makes you set duration manually or tap "Use elapsed".
- Nothing imported a workout you already did elsewhere (now fixed in gap 1).

Design principles in play: 5 (friction reduction first, tap-to-log beats forms), 6 (one master metric), 1 (implementation intentions).

SPECCED redesign (build-ready, prioritized):
1. Detected-workout first. With gap 1 live, the primary path becomes "you trained, the app already logged it." The session timer UI becomes the exception, not the rule. Lead TodayView with the detected workout and an Undo, not an empty timer.
2. One-tap quick-complete on every session view. Add a prominent "Log as done" button that records a completed WorkoutEvent immediately with sensible defaults, deferring all detail capture. The set-by-set logger becomes optional, opened only if the user wants it. This is the single biggest friction cut.
3. Make required fields optional. Move the Basketball Achilles check-in and the Swim setup form to post-completion, dismissible prompts. Never block "I finished" on a form.
4. Defaults over steppers. Pre-fill the last-used weight/reps per exercise (the data exists in LiftSession history) so "Add set" is one tap, not three steppers.
5. Live Activity + watch start. Surface "Start <current block> workout" from the schedule block and the Live Activity so a session starts in one tap at the right time (implementation intention, Principle 1). The `StartCurrentBlockWorkoutIntent` exists but only opens the app; wire it to actually start the session.

Effort: items 1-3 are a day each and high impact; 4-5 are follow-ons.

## 3. Gap: the feedback loop

Diagnosis. The pieces exist but the loop is loose: confirmations are not always immediate or identity-framed, the master metric does not visibly react to a log, and the strongest reinforcement (streaks, mascot) updates on a cache/observer cycle rather than on the action.

Already strong (verified): DailySummaryService master metric on TodayView, IdentityCopy confirmations, the mascot state machine, the streak engine with visible freeze mercy (added last session), implementation-intention strip.

IMPLEMENTED this session:
- Workout logs now immediately post `.dailyLogsRecomputed`, so the master metric, streak, and mascot rederive right after a workout import or quick-log.
- `LogWorkoutIntent` returns an identity-framed confirmation ("You showed up.").

SPECCED next (tight, within the Design Principles):
1. Immediate optimistic feedback on every log: animate the master metric increment and the streak flame on the action, before the async rederive settles. Perceived responsiveness is the feedback loop.
2. One earned, rare celebration: keep MilestoneCelebrationSheet for true milestones only (Principle 7), and make the everyday confirmation a fast, quiet identity line, not a modal.
3. On-device daily quip via Foundation Models (decision 016) so the quip is fresh and free even offline, instead of static curated copy when no API key is set.
4. Close the loop visually: when a Watch workout imports, the mascot reacts and a toast confirms, so the app "noticing" your workout is felt, not silent.

## 4. Apple Intelligence, concretely (where it earns its place)

- DailyQuoteService: add an on-device tier to the existing fallback chain (AI key -> on-device -> curated). First adoption surface. Low stakes, high "it feels alive" payoff.
- Short confirmations and "why" explanations: optional on-device generation, gated and fallback-safe.
- Not the coach: CoachService stays on Anthropic Opus. The 4096-token window forbids the year-plus context.
- App Intents + Siri (already partly present) are the higher-leverage "Apple Intelligence" surface for a fitness app than the LLM: "log my workout," "start my lift," "log water" by voice. `LogWorkoutIntent` added; wiring `StartCurrentBlockWorkoutIntent` to actually start a session is specced.

## 5. Prioritized roadmap

Now (shippable after build): gap-1 import (done), LogWorkoutIntent (done), one-tap quick-complete on session views, make Basketball/Swim required fields post-completion.

Next: HKAnchoredObjectQuery for workouts, typed-session import from HKWorkout, detected-workout Undo toast, optimistic master-metric/streak animation, DailyQuoteService on-device tier.

Later: wire StartCurrentBlockWorkoutIntent to start sessions, Live Activity quick-start, broader on-device generation surfaces.

## 6. What shipped this session vs pending

IMPLEMENTED + unit-tested: workout HealthKit import (model field, service, observer wiring, entitlement), `LogWorkoutIntent`, `OnDeviceShortTextProvider` (isolated, gated; build-verify against iOS 26 SDK).

SPECCED, not built: the workout-UI friction cuts (section 2), the feedback-loop polish (section 3), the on-device adoption in DailyQuoteService.

Build gates (yours): no iOS toolchain here, so build in Xcode, regenerate the project from project.yml (XcodeGen) to pick up the new entitlement, and run the new tests (`WorkoutImportServiceTests`). Confirm decisions 015 (auto-import with no gate) and 016 (additive Foundation Models) before the next pass wires the SPECCED items.
