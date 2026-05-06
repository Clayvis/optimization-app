# M3 Plan: Training (Lift, Basketball, Swim) + Learning (Japanese, Guitar)

## Goal

User starts workout from watch Action Button, logs sets/reps for lift, captures basketball HR, logs swim laps, tracks Japanese and Guitar streaks.

## Phases

### M3.1 Lift module: templates, service, set logging, volume aggregator + tests
- `Resources/lift_templates.json` with Lift A (legs/push/pull) and Lift B exercise lists.
- `LiftService`: load templates, start session against template, log a set, compute totalVolumeLbs across exercises, end session.
- Tests: template decode, volume aggregator (5x225+3x245 = 1860 lbs), session lifecycle, session-by-date fetch.

### M3.2 Basketball module: service + tests
- `BasketballService`: start session, in-session hydration prompt cadence (every 30 min), post-session Achilles check-in writes to DailyLog and BasketballSession.achillesPostScore.
- Tests: HR-zone aggregator, prompt cadence boundary, post-session check-in write.

### M3.3 Swim module: service + tests
- `SwimService`: start session with configurable poolLengthMeters (default 25 from UserProfile? or hard-coded 25), log lap (auto OR manual), totalMeters = laps * poolLengthMeters.
- Tests: lap counter, totalMeters math at multiple pool lengths, location field.

### M3.4 Learning module: Japanese + Guitar services + streak calculator + tests
- `LearningService.logMinutes(module:date:minutes:)`: writes to DailyLog (japaneseMinutes / guitarMinutes), recomputes LearningStreak.
- `LearningStreakCalculator`: pure function over DailyLog history, considering target threshold (30 for japanese, 20 for guitar) and ISO weekday timezone.
- Tests: streak increment on consecutive days at threshold, streak reset on gap, streak preserved when minutes < threshold (no day counts), longestStreak update, 365-day window perf < 20ms.

### M3.5 HealthKit service abstraction
- `HealthKitServiceProtocol`: requestAuthorization, saveWorkout(.functionalStrengthTraining|.basketball|.swimming, start, end, calories?), fetchHRSummary, etc.
- `LiveHealthKitService`: production impl using HKHealthStore.
- `FakeHealthKitService`: test double per TESTING.md pattern.
- Wire into LiftService/BasketballService/SwimService end methods to write a workout summary to Health.

### M3.6 Phone Training views
- Lift session entry: list of exercises from template, set/rep/weight/RPE entry, rest timer between sets.
- Basketball summary view: post-session HR zones + Achilles check-in.
- Swim summary view: laps + totalMeters + duration.
- New "Training" tab in RootView.

### M3.7 Phone Learning views
- Japanese view: daily timer (target 30 min), Pimsleur deep link button, current streak.
- Guitar view: daily timer (target 20 min), notes field, current streak.
- New "Learn" tab.

### M3.8 Watch Training UI
- Start workout buttons (Lift A, Lift B, Basketball, Swim) on a watch page.
- Set logging row UI (weight, reps, RPE) for lift.
- Lap count tap-to-add for swim.
- Basketball monitor showing avg HR.

### M3.9 Watch Action Button intent
- App Intent `StartCurrentBlockWorkoutIntent` reads current ScheduleBlock.module.
- Maps `lift_a|lift_b` → start lift, `basketball` → start basketball, `swim` → start swim.
- Bound to the watch Action Button via Donations/Shortcuts.

### M3.10 WorkoutLiveActivity in PersonalOptimizationLiveActivity extension
- Second ActivityAttributes (`WorkoutActivityAttributes`) covering active workout type, start, current HR/duration.
- Lock Screen + Dynamic Island regions.

### M3.11 Notification reminders
- Japanese: per-day-specific times pulled from default_schedule.json blocks where module=="japanese".
- Guitar: 1600 weekday and 1900 weekend per spec.
- Wire into existing NotificationService.

### M3.12 Pimsleur deep link helper + tests
- `PimsleurURLBuilder`: returns URL for `pimsleur://` deep link when applicable, falls back to App Store URL.
- Tests: deep link format, fallback path.

### M3.13 M3 close (quality gates, tag m3-complete)

## Surfaced unknowns (resolving with spec-aligned defaults)

1. **HealthKit authorization timing**: request on first start of a workout, not at app launch. Reduces pre-workout friction.
2. **Lift template content**: spec doesn't enumerate exercises. Pick reasonable defaults for an athletic 31yo male marine vet (Lift A: Squat/Bench/Row/OHP/RDL; Lift B: Front Squat/Incline Bench/Pull-up/Push Press/Hip Thrust). User can edit via Settings later (post-M3 polish).
3. **Pimsleur URL scheme**: `pimsleur://` is not officially documented. Try opening it; on failure fall back to App Store deep link.
4. **HealthKit on free dev team**: workouts can be written to Health app fine. Background delivery (sleep autobackground) defers to paid team.
5. **Lap counter auto-detection**: HKLiveWorkoutBuilder auto-detects laps in pool. Manual override is a "+1 lap" button.
6. **Action Button intent**: WatchOS App Intents framework. Requires watchOS 10+. Use AppShortcutsProvider for system-level discoverability.

## Estimated work

16-20 hours per MILESTONES.md.
