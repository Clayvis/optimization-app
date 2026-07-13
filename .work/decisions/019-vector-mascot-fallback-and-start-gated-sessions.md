# 019 — Vector mascot fallback, start-gated sessions, body-info capture

Date: 2026-07-13
Status: accepted

## Context

Three user-reported gaps on the 2026-07-13 pass:

1. The Dojo tab rendered no image. Investigation: the mascot PNG catalog
   (`MascotAssets.xcassets`, 16 imagesets, generated 2026-06-13 via the Gemini
   workflow) exists and is valid, but the Dojo hub itself never rendered the
   character; only Today did. Additionally, every render site did a blind
   `Image(assetName)` with no fallback, so any missing/renamed asset renders
   as blank space silently (the original "no image" failure mode).
2. Training tiles auto-started workouts on tap (`autoStart: true` on
   Lift/Swim; Basketball and Custom started in `.task` on appear). No
   HealthKit data surfaced during or after sessions.
3. Nothing asked for body info. `UserProfile` has carried `dob/sex/
   heightInches/weightLbs` since M1, with fields buried in Settings and
   onboarding never asking. `dob` still held the `.distantPast` sentinel.

## Decisions

1. **`MascotIllustration` vector fallback.** A dependency-free Canvas
   rendering of the chibi ninja (8 states, 2 palettes) that any target can
   compile (no UIKit/SwiftData/Theme). `MascotView` resolves PNG-first,
   vector-second. The widget extension compiles the illustration directly so
   a Home Screen widget can never render blank. PNG art remains the primary
   path per the M6.5 brief; the vector is resilience, not replacement.
2. **Start-gated sessions.** Every Training tile opens a prep screen with an
   explicit "Start session" affordance. Resume paths (in-progress banner,
   active-session adoption on appear) keep their immediate behavior.
   Friction-reduction principle 5 stays intact: starting is still two taps
   from the hub, but accidental session rows are gone.
3. **HealthKit in-session metrics.** `LiveWorkoutMetrics` polls interval
   statistics (active energy, activity-appropriate distance, latest HR)
   every 20s during a session. On end, measured energy wins; otherwise a MET
   estimate from `UserProfile.weightLbs` (Compendium values in
   `WorkoutMetrics`). Hub tiles show the last completed HKWorkout recap per
   activity. Custom activities now dispatch HKWorkouts (name-mapped activity
   type), which also feeds the recaps.
4. **Body-info capture.** New onboarding step (prefilled from HealthKit
   characteristics: DOB, biological sex, latest bodyMass/height), a Settings
   "Body" section with explicit save-weight-to-Health, and a one-time Today
   prompt for pre-existing profiles (`dob == .distantPast` sentinel).

## Bugs fixed in passing

- `LiveHealthKitService.saveWorkout` wrote every distance sample as
  `distanceSwimming`; now mapped per activity type.
- Workout energy/distance samples were never authorized for share, so
  `HKWorkoutBuilder.addSamples` failed silently; write set expanded.
- Basketball session view hung on a spinner forever if `startSession` threw.
- Mascot variant picker hard-blocked switching when PNGs were missing; now
  informational (vector fallback always renders).

## Alternatives considered

- Generating placeholder PNGs at build time: worse quality than vector,
  another build step, and the real art already exists.
- Persisting HK stats onto session rows: requires a schema version bump for
  data HealthKit already stores; recaps read HKWorkouts instead.
