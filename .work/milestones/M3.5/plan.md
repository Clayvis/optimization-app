# M3.5 Engagement Engine: Plan

## Pre-flight (verified)
- All 8 mascot PNGs present at 1024x1024 RGBA in `Assets.xcassets/Mascot/`
- M3 closed and tagged `m3-complete`
- SchemaV2 doc already inserted into DATA_MODELS.md, design principles in CLAUDE.md, M3.5 + reshaped M4 in MILESTONES.md

## Architectural decisions

### Data layer (SchemaV2)
Lightweight additive migration, no field renames. New entities:
- `StreakCounter` (one per domain, includes `currentStreak`, `longestStreak`, `lastCompletedDate`, `freezesAvailable`, `freezesUsedThisMonth`, `freezeMonthAnchor`)
- `WorkoutEvent` (per-day workout rollup; `source` enum covers `lift|basketball|swim|manual_skip|sick_day|travel|freeze`)
- `CompletionHistory` (every behavior log writes a row; powers adaptive timing)
- `FreezeApplication` (cross-domain freeze ledger; needed because `WorkoutEvent` only covers workouts and other domains need a freeze record)

`StreakDomain` enum: `workout, fasting, hydration, learning, protocolAdherence` (note `protocolAdherence` to dodge Swift `protocol` keyword).

UserProfile additions: `sickDayActiveUntil: Date?`, `travelModeActiveUntil: Date?`. `mascotEnabled` already in V1. `onboardingCompleted` deferred to M4.

`MigrationPlan` enum with `.lightweight(SchemaV1 -> SchemaV2)`.

### Service layer
- `Modules/Engagement/StreakService` (12+ tests): per-domain recompute walking back from today, freeze/sick/travel honors, monthly freeze reset.
- `Modules/Engagement/DailySummaryService` (6+ tests): "Today's Protocol Adherence" tally over scheduled domains.
- `Modules/Engagement/AdaptiveNotificationTiming` (4+ tests): pure function over CompletionHistory; activates at day 14.
- `Modules/Engagement/IdentityCopy`: central enum of identity-framed copy strings.
- `Modules/Character/CharacterStateService` (11 tests): @Observable, timer + write-driven recompute, precedence resolver, transition logging.
- `Modules/Character/CharacterView`: 200pt image, breathing, alert pulse, reduce-motion aware.

### View wiring
- `TodayView` adds: `CharacterView` header (200x200 mascot), master metric card under it, sick/travel banner when active.
- `SettingsView`: sick day toggle, travel mode toggle (with day count stepper), mascot toggle (already-existing field finally surfaced).
- `PersonalOptimizationWatchComplications`: new `MascotComplication` (CircularSmall, face crop).

### Adaptive timing wiring
- Inject CompletionHistory writes into `FastingService.logScheduledFastEnd/logEarlyBreak`, `HydrationService.logBottle`, `LearningService.logMinutes`, and workout end paths.
- `NotificationService.scheduleHydrationReminder` etc. consult `AdaptiveNotificationTiming.estimatePreferredTime` when ≥14 days of history exist.

### Identity copy targets
Search-and-replace generic confirmations in existing views:
- "Logged", "Saved", "Complete" -> domain-specific identity strings via `IdentityCopy`.

## Execution order
1. Models + SchemaV2 + MigrationPlan + container update on iOS and Watch apps (commit).
2. StreakService + tests (commit).
3. CharacterStateService + tests (commit).
4. CharacterView (commit).
5. Wire mascot to TodayView and watch complication (commit).
6. DailySummaryService + master metric on TodayView + tests (commit).
7. CompletionHistory wiring + AdaptiveNotificationTiming + tests (commit).
8. IdentityCopy refactor (commit).
9. Sick day + Travel mode UI (commit).
10. Mascot toggle wiring (commit).
11. Tests/performance polish (commit).
12. Quality gates + close notes + tag m3.5-complete (commit).

## Performance targets (verified at close)
- `CharacterStateService.recompute`: <30ms with 365 days of data
- Mascot asset memory: <8MB total (8 × 1024x1024 RGBA decompresses to ~32MB; rely on UIImage cache demand-loading + downscale)
- 60fps render with breathing
- Watch complication battery delta: <1%/12hr (timeline entries kept sparse)
