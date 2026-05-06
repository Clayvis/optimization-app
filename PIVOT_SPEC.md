# PIVOT_SPEC.md

Mid-build pivot from the original v4 GSD package to a design-science-grounded engagement engine. Issued at: M3 substantially built, not yet tagged. Goal: keep every line of working code, layer the missing engagement primitives on top, ship a tighter v1.

---

## Current State (verified from .work/state.json + git log)

- **M1 complete**: tag `m1-complete`. Xcode project, 13 SwiftData models, schedule engine + seeder, RootView/TodayView/SettingsView, watch complication, JSON export/import, performance baselines.
- **M2 complete**: tag `m2-complete`. FastingService (16 tests), HydrationService (17 tests), NotificationService with suppression rules (15 tests), FastingView with live ring, HydrationView, watch quick-log, FastCountdownComplication, FastingLiveActivity.
- **M3 in flight, not tagged**: 9 commits covering Lift, Basketball, Swim, Learning streak calculator, HealthKit service, phone hubs, watch pages, Action Button App Intent, WorkoutLiveActivity. Effectively all the spec'd build work is done; close-out tasks remain.
- **HEAD**: `fd5f784 feat(M3): WorkoutLiveActivity for Lift, Basketball, Swim`.
- **state.json stale**: says active=M3, status=planning, last_task=M2.10. Update at M3 close.

## What Pivots, What Stays

### Stays (no changes to existing code)
Schedule engine, all M1 models, fast and hydration services, notification suppression, complications, Live Activities, Lift/Basketball/Swim/Learning modules, HealthKit abstraction, Action Button intents.

### Gets Closed Out (M3.20 series)
M3 Definition of Done audit, all-tests-green verification, zero-warning build, performance baselines for training and learning, M3 close notes, PR merged, tag `m3-complete` pushed.

### Gets Inserted (NEW M3.5)
The Engagement Engine. Layers seven evidence-based primitives on top of existing data:
1. StreakCounter with freeze inventory (2/month auto-grant)
2. Sick day toggle and Travel mode (preserves streaks without faking completion)
3. WorkoutEvent rollup entity (one row per workout day, `completed: Bool`, derived from existing LiftSession/BasketballSession/SwimSession)
4. CharacterStateService wired to genuine data state (precedence rules locked: urgent > achievement > proud > disappointed > tired > thirsty > fasting > neutral)
5. Adaptive notification timing engine (consumes 14-day completion history per behavior, suggests personalized notification times after day 14)
6. Identity-framed copy across all confirmation surfaces ("You showed up" not "Task complete")
7. Today's Protocol Adherence master metric on TodayView (single roll-up: "5/7 of today's protocol complete"); sub-metrics one tap away

### Gets Reshaped (NEW M4)
M4 was originally Learning + Pomodoro (now folded into M3 already). The replacement M4 is now **Notifications + Onboarding + Implementation Intentions + Weekly Reflection + Ship**.

### Gets Deferred to v1.5 (skipped in v1.0)
- Original M5 Biomarkers (entire module)
- Original M6 Widgets and Dashboard (defer all)
- Original M6.5 standalone Mascot milestone (mascot now lives inside M3.5)
- Original M7 Notifications hardening folds into new M4

---

## Design Science Principles (load-bearing)

Add these to CLAUDE.md under a new section "Design Principles for Engagement Decisions". Mandatory reading every session. Override any prior copy-design or notification-design choices that conflict.

1. **Implementation intentions beat reminders.** "When [trigger], I will [action]" has medium-to-large effect size on goal attainment (Gollwitzer meta-analysis, d=0.65, 94 studies). All scheduled notifications should anchor to event triggers (after coffee, after dinner, on schedule block start) not arbitrary clock times where possible.

2. **Streaks need mercy.** Duolingo's streak freeze increased DAU by 0.38% when added; doubling freeze inventory increased it more. Pure unbroken streaks produce hollow engagement (people tap to preserve streak, not to do the work). Travel mode and sick day must preserve streaks without faking completion.

3. **Notification minimum effective dose.** 50% of users disengage from a behavior change app at day 22 under fixed daily notification policy. Suppress nudges if user already engaged that day. Personalize timing from completion history. Max one nudge per behavior per day.

4. **Identity framing over task framing.** "You're someone who shows up" produces higher long-term adherence than "1 of 3 tasks complete." All confirmation copy reinforces identity.

5. **Friction reduction is the highest-leverage lever.** Tap-to-log on watch beats any motivational copy. Multi-step logging kills habits. Default everything; let user override later.

6. **One master metric.** Foreground a single daily roll-up. Sub-metrics one tap away. Never put a 15-tile dashboard on the home view.

7. **Mascot reflects state, never theater.** Character state derived from data layer with strict precedence. Sad mascot must mean a real miss. Achievement state must be rare. Scripted celebrations train users to ignore the mascot.

---

## Step 1: M3 Close-out

Drop this prompt into Claude Code as your next message.

```
Resume from .work/state.json, but note the file is stale (last_task references M2.10; HEAD is at fd5f784 with 9 M3 commits). Audit M3 against MILESTONES.md Definition of Done. For each DoD item:
- Confirm whether it is satisfied by existing code/tests.
- If not satisfied, list it as a remaining task with estimated effort.

Do NOT write code yet. Produce the audit as a single message. After I review, I will direct you to either close M3 or finish remaining tasks.

Update .work/state.json with current accurate values:
- last_task = "M3 audit in progress"
- last_commit = "fd5f784"
- status = "auditing"

Confirm and produce the audit.
```

When the audit comes back:
- If gaps exist (likely just close-out tasks: build with zero warnings, all-tests-green verification, performance baselines for training, M3 close notes), tell agent: "Close the gaps task by task per CLAUDE.md execution loop. After each passing test, commit. When DoD is satisfied, open PR, run Quality Gates, merge to main, tag m3-complete, push tag."
- If audit shows M3 is already DoD-complete, tell agent: "M3 is DoD-complete. Open close-out PR with M3 close notes, merge to main, tag m3-complete, push tag."

Wait for `m3-complete` tag to land before proceeding to Step 2.

---

## Step 2: M3.5 Engagement Engine (new milestone)

Insert this block into MILESTONES.md after the M3 section.

```
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
```

---

## Step 3: M4 Reshape (Notifications + Onboarding + Implementation Intentions + Weekly Reflection + Ship)

Replace the original M4 in MILESTONES.md with this block.

```
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
```

---

## Step 4: Defer Original M5, M6, M6.5, M7

Replace those sections in MILESTONES.md with a single block.

```
## Deferred to v1.5+

The following modules from the original v4 spec are deferred to post-launch versions. Not built in v1.0.

- Biomarker module (was M5): lab PDF parsing, PhenoAge, AI interpretation. Reference logic preserved in References/biomarker-tracker.html. Reintroduce as v1.5 standalone module.
- Widgets and Dashboard (was M6): home screen widgets, Smart Stack, Control Center, dashboard view. Reintroduce as v1.5.
- Standalone Mascot milestone (was M6.5): folded into M3.5. Already shipped.
- Notifications hardening (was M7): folded into M4.

Decision criterion for v1.5: ship v1.0 to App Store, run for 60 days, measure user retention (Clay + wife daily-active rate, week-1 to week-8). If both >70% DAU at week 8, prioritize biomarker module. If <70%, prioritize whatever the friction-reduction wins are based on actual usage patterns.
```

---

## SwiftData Migration: SchemaV1 -> SchemaV2 (additive)

Insert into DATA_MODELS.md before "Schema Versioning" section.

```
## SchemaV2 (M3.5)

VersionedSchema migration. All changes are additive; no deletions, no field renames. Migration plan: lightweight, no custom migration logic required.

New @Model entities:
- StreakCounter
- WorkoutEvent
- CharacterStateLog (already spec'd; finally implemented at M3.5)
- CompletionHistory

New @Model entities (M4):
- ImplementationIntention
- WeeklyReflection

New fields on existing models:
- UserProfile: sickDayActiveUntil: Date?, travelModeActiveUntil: Date?, mascotEnabled: Bool, onboardingCompleted: Bool

Migration test: load a SchemaV1 store, open with SchemaV2 model container, verify all M1-M3 data is intact, verify new fields default correctly.
```

---

## CLAUDE.md Addendum

Append this section at the bottom of CLAUDE.md.

```
## Design Principles for Engagement Decisions (load-bearing from M3.5 onward)

These principles override any prior copy-design or notification choice when in conflict. Source: 2024-2025 systematic reviews on habit formation app design (see PIVOT_SPEC.md for citations).

1. Implementation intentions over reminders. Anchor every notification and prompt to a trigger event (after coffee, after dinner, on block start), not a clock time, when feasible.
2. Streaks need mercy. Always honor freezes, sick day, and travel mode. Never fake completion to preserve a streak; preserve it via explicit pause.
3. Notification minimum effective dose. One nudge per behavior per day max. Suppress if logged. Personalize timing from history after day 14.
4. Identity framing over task framing. Confirmation copy reinforces who the user is, not what task is done.
5. Friction reduction first. Tap-to-log beats motivational copy. Multi-step logging kills habits.
6. One master metric. Foreground today's protocol adherence as a single number. Sub-metrics one tap away.
7. Mascot reflects state, never theater. Sad mascot must mean a real miss. Achievement is rare and earned.

Apply these principles to every UI/copy/notification decision from M3.5 forward. When in doubt, choose the option that respects the user's autonomy and reduces friction.
```

---

## Final Step: Bootstrap the Pivot in Claude Code

After you have copied this PIVOT_SPEC.md into your project root, paste this into Claude Code:

```
Read PIVOT_SPEC.md in this directory. Confirm understanding by stating:
1. The current state per the PIVOT_SPEC's "Current State" section.
2. The three new milestones (M3 close, M3.5 Engagement Engine, M4 reshape).
3. The seven design principles to be appended to CLAUDE.md.
4. The SchemaV1 -> SchemaV2 migration scope.

After confirming, integrate the pivot:
1. Append the design principles section to CLAUDE.md.
2. Insert M3.5 milestone block into MILESTONES.md after the existing M3 section.
3. Replace any existing M4-M7 content in MILESTONES.md with the new M4 block + the Deferred section.
4. Append the SchemaV2 section to DATA_MODELS.md.
5. Update .work/state.json: active_milestone="M3", status="closing", last_task="M3 close-out audit pending".
6. Commit with message "docs: pivot spec integrated, M3.5 + reshaped M4 inserted, M5-M7 deferred per PIVOT_SPEC".

Then audit M3 against its DoD per Step 1 of PIVOT_SPEC. Produce the audit as a single message. Do not write code yet. Wait for my approval before closing M3 or starting M3.5.
```

The agent will integrate the pivot doc, audit M3, and produce a clean handoff to the engagement engine.
