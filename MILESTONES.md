# MILESTONES.md

Each milestone is a discrete unit of work with a Definition of Done. Each closes with a passing build, green tests, performance benchmarks met, PR to main, and `m<id>-complete` git tag.

Daily usable from M1 onward. No multi-milestone work in flight.

---

## M1: Scaffold + Schedule Engine + Watch Complication

**Goal**: User installs app, sees today's schedule on watch and phone, watch complication shows current block + next transition.

**Tasks**:

1. Create Xcode project with iOS and watchOS targets.
2. Add App Group entitlement and CloudKit container entitlement.
3. Create `PrivacyInfo.xcprivacy` with baseline declarations.
4. Define all 13 SwiftData @Model classes per DATA_MODELS.md (M6.5 ones can be stubbed).
5. Set up VersionedSchema (SchemaV1) for migration support from day one.
6. Bundle `Resources/default_schedule.json`. Write seeder running on first launch.
7. Build `Modules/Schedule/ScheduleService.swift` with: load template, today's blocks, current block, time until next transition.
8. Build `Views/TodayView.swift` for iPhone showing today's blocks with current block highlighted.
9. Build `Views/SettingsView.swift` (stub) with profile fields.
10. Build watchOS `ContentView` with vertical list of today's remaining blocks.
11. Build watchOS modular large complication (`Complications/CurrentBlockComplication.swift`): current block name + time remaining + next block.
12. Wire CloudKit sync via SwiftData ModelConfiguration. Verify data persists across simulator launches.
13. Implement `Logger+Categories.swift` with `os.Logger` extensions.
14. Implement `KeychainService.swift` (stub for now, populated at M5).
15. Build `Components/ErrorBanner.swift` for surfacing errors.
16. Implement JSON export/import (round-trips full ModelContext to/from JSON).
17. Write unit tests: schedule decoder, current-block resolver, time-until-next calculator, JSON export/import round-trip.

**Performance benchmarks**:
- iPhone cold start to TodayView: <1.5s (measured via Instruments).
- Watch cold start to current block visible: <2s.
- Schedule resolution `currentBlock(at: Date)`: <50ms.

**Definition of Done**:
- App launches on iPhone 16 Pro simulator.
- Watch app launches on Apple Watch Ultra 2 simulator.
- Today view on phone shows correct blocks for current weekday with current block highlighted.
- Watch complication renders current block name and time remaining.
- All 13 SwiftData models compile and persist correctly.
- CloudKit sync verified (modify on phone simulator, see change on watch simulator within 30 seconds).
- Profile data persists across launches.
- JSON export produces parseable file; JSON import round-trips without loss.
- Build succeeds with zero warnings on Xcode 16.
- All unit tests pass.
- Performance benchmarks met.
- PR merged to main, tag `m1-complete` pushed.

**Estimated effort**: 8-12 hours of agent execution.

---

## M2: Fasting + Hydration + Live Activities

**Goal**: User sees fast countdown on watch complication, logs water from watch quick-tap, receives hydration reminders, has Live Activity for active fast on Lock Screen and Dynamic Island.

**Tasks**:

1. Build `Modules/Fasting/FastingService.swift`:
   - Fast window computation per phased rollout (weeks 1-2 vs weeks 3+).
   - Current state: fasting / eating / transition.
   - Early-break logger with reason capture.
2. Build `Modules/Hydration/HydrationService.swift`:
   - Daily target by day-type (rest, lift, basketball, swim).
   - Current intake aggregation.
   - Bottle log with custom-amount option.
   - Electrolyte session log.
3. Build watch quick-log interface: tap-to-log 8/16/24/32 oz with optional electrolyte tag.
4. Build phone Hydration view with hourly breakdown vs target.
5. Build phone Fasting view with elapsed/remaining countdown.
6. Add fast countdown to watch complication (alternate face).
7. Build `PersonalOptimizationLiveActivity` extension target with:
   - `FastingLiveActivity.swift`: shows hours remaining, finishes when fast ends.
   - Lock screen, Dynamic Island compact, expanded, minimal presentations.
8. `NotificationService.shared` registers fast start, fast end, hydration cadence.
9. Implement smart suppression:
   - No hydration pings during sleep window (22:00-07:00).
   - No pings pre-1000 if morning intake logged.
   - No pings during active basketball workout.
10. Write tests: fast window resolver across phase 1-2 vs 3+, hydration target lookup by day-of-week, suppression rules.

**Performance benchmarks**:
- Watch tap-to-log latency: <200ms from tap to confirmation haptic.
- Live Activity update frequency: budgeted by ActivityKit (max 4hr active state).

**Definition of Done**:
- Fast countdown visible on watch always-on complication.
- Water log on watch records to SwiftData and syncs to phone.
- Day-type-aware hydration target shown correctly.
- Notifications fire at scheduled times in simulator.
- Suppression rules verified by test scenarios.
- Phased rollout switch toggleable in Settings.
- Live Activity displays on Lock Screen during active fast.
- Dynamic Island compact and expanded presentations work.
- All unit tests pass.
- Performance benchmarks met.
- PR merged to main, tag `m2-complete` pushed.

**Estimated effort**: 12-16 hours.

---

## M3: Training (Lift, Basketball, Swim) + Learning (Japanese, Guitar)

**Goal**: User starts workout from watch Action Button, logs sets/reps for lift, captures basketball HR, logs swim laps, tracks Japanese and Guitar streaks.

**Tasks**:

1. Build `Modules/Training/Lift/`:
   - Template loader for Lift A and Lift B (bundled JSON).
   - Session recorder with HKWorkoutSession (.functionalStrengthTraining).
   - Watch UI for set/rep/weight/RPE entry.
   - Rest timer between sets with haptic at end.
2. Watch Action Button binding: when current block is `lift_a` or `lift_b`, button starts lift session. When `basketball`, starts basketball. When `swim`, starts swim.
3. Build `Modules/Training/Basketball/`:
   - HKWorkoutSession (.basketball).
   - 4-hour session tracking with HR zones.
   - Post-session Achilles check-in (1-10 scale).
   - In-session hydration prompt every 30 min.
4. Build `Modules/Training/Swim/`:
   - HKWorkoutSession (.swimming) with pool location.
   - Configurable pool length (default 25m).
   - Lap counter (auto from watch + manual override).
5. Build `Modules/Learning/Japanese/`:
   - Daily timer (target 30 min).
   - Pimsleur deep link launch with graceful fallback.
   - Streak counter.
6. Build `Modules/Learning/Guitar/`:
   - Daily timer (target 20 min).
   - Practice notes field.
   - Streak counter.
7. Wire workouts to HealthKit write so data appears in Apple Health.
8. Build Live Activity for active workout (`WorkoutLiveActivity.swift`).
9. Add reminders: 1600 weekday and 1900 weekend for guitar, per-day-specific times for Japanese.
10. Write tests: streak calculators (current, longest, milestone detection), lift volume aggregator, day-type training matcher, Pimsleur URL generation.

**Performance benchmarks**:
- HKWorkoutSession start latency: <500ms.
- Lift set logging: <200ms confirmation.
- Streak calculation: <20ms for 365-day window.

**Definition of Done**:
- Action Button starts correct workout type based on current block.
- Lift session records sets, reps, weight, RPE with rest timer.
- Basketball session captures HR, duration, calories.
- Swim session records laps and total meters.
- Japanese and Guitar minutes log to DailyLog, streaks compute correctly.
- Pimsleur deep link launches the app on iOS (no crash if Pimsleur not installed).
- HealthKit shows workouts after session ends.
- Achilles check-in surfaces post-basketball/post-lift, persists to DailyLog.
- Workout Live Activity active on Lock Screen during sessions.
- All unit tests pass.
- Performance benchmarks met.
- PR merged to main, tag `m3-complete` pushed.

**Estimated effort**: 16-20 hours.

---

## M3.5: Engagement Engine

Goal: Layer Duolingo-style streak retention, mascot emotional signaling, identity copy, master metric, and adaptive notifications on top of M1-M3. This is the design-science core. Mascot integration moved here from former M6.5.

Pre-flight checklist (must complete before starting M3.5):
1. M3 closed and tagged m3-complete.
2. User has run gemini_workflow.md to generate 8 mascot PNG files.
3. PNG files placed in PersonalOptimization/Assets.xcassets/Mascot/ as Image Sets:
   MascotNeutral, MascotThirsty, MascotFasting, MascotUrgent, MascotProud,
   MascotDisappointed, MascotTired, MascotAchievement.
4. Each Image Set has 1x, 2x, 3x variants (1024x1024 base, scaled).
5. Wife has approved the character look.

If pre-flight items not complete, agent stops and prompts user.

Tasks:

1. SwiftData migrations (additive, non-destructive):
   - Add StreakCounter @Model: domain (workout|fasting|hydration|learning|protocol),
     currentStreak: Int, longestStreak: Int, lastCompletedDate: Date?,
     freezesAvailable: Int (default 2), freezesUsedThisMonth: Int.
   - Add WorkoutEvent @Model: date: Date, completed: Bool, source: String
     ("lift"|"basketball"|"swim"|"manual_skip"|"sick_day"|"travel"|"freeze"),
     sourceID: UUID? (FK to LiftSession/BasketballSession/SwimSession when applicable).
   - Add fields to UserProfile: sickDayActiveUntil: Date?, travelModeActiveUntil: Date?,
     mascotEnabled: Bool (default true).
   - Bump SchemaV1 -> SchemaV2 with VersionedSchema migration plan.
   - Implement CharacterStateLog per existing DATA_MODELS.md spec (it's already defined; just hadn't been built yet).

2. StreakService:
   - recompute(domain:) -> StreakCounter for any domain.
   - applyFreeze(domain:) -> uses one freeze, marks today as completed, decrements freezesAvailable.
   - resetMonthlyFreezes() -> Timer at month rollover.
   - Travel mode: when active, all domains record completed via "travel" source.
   - Sick day: same, source "sick_day".
   - Tests: 12 minimum, including freeze exhaustion, travel mode boundary, monthly reset.

3. CharacterStateService (port from existing DATA_MODELS.md spec):
   - @Observable singleton.
   - recompute() runs every 30 seconds via Timer + on relevant SwiftData writes
     (workout completion, hydration log, fast end, streak change).
   - Queries data layer, produces (CharacterState, reason) candidates.
   - Resolves precedence: urgent, achievement, proud, disappointed, tired, thirsty, fasting, neutral.
   - Writes CharacterStateLog row on every transition.
   - Exposes currentState and triggerReason properties.
   - Tests: 8 scenarios, one per state, plus 3 precedence-conflict cases.

4. CharacterView (M6.5 spec from MILESTONES.md, ported):
   - SwiftUI view rendering current state.assetName as Image (200x200 on Today; face crop on watch complication).
   - Cross-fade transition: .transition(.opacity).
   - Breathing animation: .scaleEffect(breathing ? 1.02 : 1.0) with .easeInOut(duration: 3).repeatForever(autoreverses: true).
   - Alert pulse on .urgent and .achievement entry: brief .scaleEffect(1.1).
   - @Environment(\.accessibilityReduceMotion) disables breathing and pulse.

5. Wire mascot to TodayView header (200x200pt) and watch CircularComplication.

6. Master metric: Today's Protocol Adherence:
   - Computed property on a new DailySummaryService.
   - Numerator = count of completed protocol items today (workout if scheduled, fasting if active, hydration if target hit, learning streak if logged).
   - Denominator = count of scheduled items today.
   - Display: "{n}/{m} of today's protocol complete" prominent on TodayView.
   - Sub-metrics (per-domain) accessible via tap.

7. Adaptive notification timing:
   - Add CompletionHistory @Model: domain: String, timestamp: Date.
   - On every behavior log, write a CompletionHistory row.
   - After 14 days, NotificationService can call estimatePreferredTime(domain:)
     -> returns median completion time (or fallback to schedule block time).
   - Scheduled notifications fire at preferredTime - 30 minutes (configurable).
   - Suppression rules already in NotificationService extend: do not notify if behavior already logged today.

8. Identity-framed copy refactor:
   - Replace generic confirmation strings ("Logged", "Complete", "Saved") with identity-reinforcing variants ("You showed up.", "That's who you are now.", "Streak alive.").
   - Centralize in IdentityCopy enum so future tone changes are one-edit wide.

9. Sick day and Travel mode UI:
   - Settings has two toggles. Sick day = today only. Travel mode = 7 days, configurable.
   - When active, prominent banner on TodayView confirms streak preserved.
   - Mascot enters .neutral or .tired with reason "user marked travel/sick".

10. Settings: Mascot enabled toggle (persists to UserProfile.mascotEnabled). When off, CharacterView hides cleanly.

11. Tests:
    - StreakService 12 tests minimum.
    - CharacterStateService 11 tests (8 states + 3 precedence).
    - DailySummaryService 6 tests (varying schedule + completion combinations).
    - Adaptive timing 4 tests (cold start, day 14 transition, suppression, fallback).
    - UI tests: sick day toggle, travel mode toggle, mascot disable.

Performance benchmarks:
- CharacterStateService.recompute(): <30ms with full data.
- CharacterView rendering: 60fps with breathing.
- Mascot asset memory: <8MB total.
- Watch complication battery delta: <1%/12hr.

Definition of Done:
- All 8 PNG assets present and load.
- Today screen shows mascot at 200x200pt, master metric below name.
- Watch circular complication shows mascot face.
- Mascot transitions verified by 8 test scenarios.
- Sick day and Travel mode preserve streak without faking workout completion.
- Streak freeze exhaustion handled gracefully.
- Adaptive timing engine activates at day 14.
- All identity-framed copy in place.
- All unit tests pass.
- Performance benchmarks met.
- PR merged to main, tag m3.5-complete pushed.

Estimated effort: 22-28 hours of agent execution.

---

## M4: Notifications, Onboarding, Implementation Intentions, Weekly Reflection, Ship

Goal: Wrap v1 with high-quality first-run experience, the implementation intentions habit-stack builder, weekly reflection, and App Store submission readiness.

Tasks:

1. SwiftData additions:
   - ImplementationIntention @Model: id: UUID, scheduleBlockID: UUID? (optional FK),
     trigger: String (description, e.g., "After morning coffee"),
     triggerType: String (time|after_event|location|after_block),
     action: String, createdAt: Date, lastCompletedAt: Date?, active: Bool.
   - WeeklyReflection @Model: weekStartDate: Date, adherencePercent: Double,
     bestDomain: String, weakestDomain: String, userNote: String?.

2. Implementation Intentions Builder:
   - In-app screen accessible from Settings and Schedule.
   - User can add an if-then plan, link to existing schedule block or freestanding.
   - Active plans reveal in TodayView under "When you... I will remind you to..." section.

3. Onboarding wizard (first-launch only):
   - Screen 1: Welcome + privacy statement (no servers, no accounts).
   - Screen 2: Notification permission ask + HealthKit permission ask.
   - Screen 3: Capture 5-7 implementation intentions for user's domains
     (training, fasting, hydration, language, optional). Pre-fill with smart defaults from default_schedule.json.
   - Screen 4: Mascot reveal (assumes M3.5 done). User sees their mascot for the first time.
   - Screen 5: Apple Watch pairing reminder + complication setup tip.
   - State stored in UserProfile.onboardingCompleted: Bool.

4. Weekly Reflection (Sunday view):
   - On Sundays, TodayView surfaces a "Weekly Reflection" card.
   - Card shows: this week's adherence %, best day, weakest domain.
   - Tap opens full reflection screen: graph of 7-day adherence, mascot delivers identity-framed message ("You showed up 6 of 7 days. That's the standard."), free-text note input.
   - Notes persist as WeeklyReflection rows for trend.

5. Notification Hardening:
   - Audit all NotificationService schedules: ensure suppression-if-logged-today is universal.
   - Adaptive timing (from M3.5) wired into all notifications.
   - Quiet hours: configurable (default 22:00-07:00 JST).
   - Notification copy revised per identity framing (M3.5).

6. Edge cases:
   - Time zone change handling (Clay travels US <-> Okinawa).
   - DST transitions.
   - First-of-month freeze reset.
   - Schedule block edits: existing intentions and historical data unaffected.

7. App Store prep:
   - Privacy manifest review (PrivacyInfo.xcprivacy already shipped at M1).
   - App Store screenshots (six required: TodayView with mascot, FastingView, HydrationView, Workout streak with mascot proud, Implementation Intentions builder, Weekly Reflection).
   - App description copy.
   - Keywords for ASO (longevity, biomarker tracker stays out for v1).
   - TestFlight build (requires paid Apple Developer; user upgrades here).

8. Tests:
   - Implementation intention CRUD 6 tests.
   - Weekly Reflection generation 4 tests.
   - Onboarding state machine 5 tests.
   - Edge case tests for time zone change, DST, monthly reset.

Performance benchmarks:
- Onboarding cold start to first interactive: <2s.
- Weekly Reflection generation: <100ms with 90 days of data.

Definition of Done:
- Onboarding flows top to bottom on fresh install simulator.
- 5-7 implementation intentions captured and surface in TodayView.
- Sunday Weekly Reflection card appears and opens correctly.
- Time zone and DST tests pass.
- App Store screenshots generated.
- TestFlight build uploaded (assuming paid Apple Dev membership active).
- All unit tests pass.
- Performance benchmarks met.
- PR merged to main, tag m4-complete pushed.
- Tag v1.0.0-rc1 pushed.

Estimated effort: 16-22 hours of agent execution.

---

## Deferred to v1.5+

The following modules from the original v4 spec are deferred to post-launch versions. Not built in v1.0.

- Biomarker module (was M5): lab PDF parsing, PhenoAge, AI interpretation. Reference logic preserved in References/biomarker-tracker.html. Reintroduce as v1.5 standalone module.
- Widgets and Dashboard (was M6): home screen widgets, Smart Stack, Control Center, dashboard view. Reintroduce as v1.5.
- Standalone Mascot milestone (was M6.5): folded into M3.5. Already shipped.
- Notifications hardening (was M7): folded into M4.

Decision criterion for v1.5: ship v1.0 to App Store, run for 60 days, measure user retention (Clay + wife daily-active rate, week-1 to week-8). If both >70% DAU at week 8, prioritize biomarker module. If <70%, prioritize whatever the friction-reduction wins are based on actual usage patterns.

---

## Summary

| ID | Module | Effort | Daily-usable after |
|----|--------|--------|--------------------|
| M1 | Schedule + Complication | 8-12h | yes |
| M2 | Fasting + Hydration + Live Activities | 12-16h | yes |
| M3 | Training + Learning | 16-20h | yes |
| M3.5 | Engagement Engine (streaks, mascot, master metric, adaptive notifications) | 22-28h | yes |
| M4 | Notifications + Onboarding + Implementation Intentions + Weekly Reflection + Ship | 16-22h | yes (v1.0) |

Deferred to v1.5+: Biomarkers (was M5), Widgets/Dashboard (was M6), standalone Mascot (was M6.5; folded into M3.5), Notifications hardening (was M7; folded into M4).

**Total v1.0: ~74-98 hours of Claude Code execution.**

Calendar time depends on cadence. Typical pace: 1 milestone per 1-2 weeks for a part-time builder.
