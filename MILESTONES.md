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

## M4: Coursework (Pomodoro) + Admin

**Goal**: User runs Pomodoro sessions during study blocks. Admin module surfaces SSDI, VR&E, and micro-SaaS tasks during 1500-1600 Mon/Fri admin block.

**Tasks**:

1. Build `Modules/Coursework/PomodoroService.swift`:
   - Configurable work/break (25/5 or 50/10).
   - Course tag.
   - Cycle counter.
   - Session log to PomodoroSession entity.
2. Build watch Pomodoro view: start/pause/skip with current cycle indicator and haptic transitions.
3. Build phone Coursework view: daily and weekly minute totals, per-course breakdown via Swift Charts.
4. Build `Modules/Admin/`:
   - Task list (title, category, due date, completed).
   - Pre-seed tasks: VA Form 20-10206 retrieval, VSO follow-up with Jeffery C. Hanscom, VR&E counselor follow-up, micro-SaaS launch checklist.
5. Trigger admin module surface on watch during 1500-1600 Mon/Fri blocks (gentle haptic + glance presentation).
6. Add App Intents for Pomodoro start/pause (Siri: "Hey Siri, start Pomodoro").
7. Write tests: Pomodoro state machine, admin task filtering by category and completion, App Intent invocation.

**Performance benchmarks**:
- App Intent invocation: <300ms cold start to action.

**Definition of Done**:
- Pomodoro on watch runs through full cycles with haptic transitions.
- Coursework minutes log to DailyLog, daily total visible on phone.
- Admin tasks list editable from phone, glanceable from watch during admin blocks.
- Siri Pomodoro start works.
- All unit tests pass.
- Performance benchmarks met.
- PR merged to main, tag `m4-complete` pushed.

**Estimated effort**: 8-10 hours.

---

## M5: Biomarkers + Lab PDF Parser

**Goal**: User uploads lab PDF on phone, sees biomarkers extracted to structured form, saves draw, views dashboard with flagged markers, trend charts, PhenoAge.

**Tasks**:

1. Port `BIOMARKERS` catalog from `References/biomarker-tracker.html` to `Resources/biomarker_catalog.json` and `Modules/Biomarkers/BiomarkerCatalog.swift`.
2. Port `BIOMARKER_ALIASES` to `Resources/biomarker_aliases.json` and `BiomarkerAliases.swift`.
3. Build `Modules/Biomarkers/PDFParser.swift`:
   - PDFKit primary text extraction.
   - Vision OCR fallback for scanned PDFs (when text yields <50 lines).
   - DOD MTF detection via "Laboratory" sentinel count.
   - Generic format fallback (Quest, LabCorp).
   - Direct port of HTML `parseLines()` algorithm.
4. Build `Modules/Biomarkers/PhenoAge.swift`: direct port of HTML `calculatePhenoAge()`.
5. Build `Modules/Biomarkers/PatternDetection.swift`: direct port of HTML `detectPatterns()` with all 12 rules.
6. Build `Modules/Biomarkers/AnalysisGenerator.swift` for local rule-based summary.
7. Build `Services/ClaudeAPIClient.swift`:
   - URLSession-based actor.
   - System prompt for live analysis.
   - System prompt for live PDF parsing (matches HTML version).
   - Error handling with user-readable messages.
8. Build phone biomarker views: Dashboard, Add Draw (with PDF upload), Trends (with wearable overlay), Analysis, Protocols.
9. Hook HealthKit pull for wearable metrics (RHR, HRV, sleep) to power overlays.
10. Build Settings section for Anthropic API key (Keychain) and model selection.
11. **Regression test**: parse `References/sample_lab_dod.pdf` through code, assert 25 of 25 markers extracted matching `sample_lab_dod.json`.
12. Update `PrivacyInfo.xcprivacy` for network usage (Anthropic API).
13. Write tests: parser (DOD format, generic format, OCR path), PhenoAge formula (validated against known test vectors), all 12 pattern detection rules, alias resolver.

**Performance benchmarks**:
- PDF parse end-to-end: <30s for 2-page DOD PDF.
- PhenoAge calculation: <10ms.
- Pattern detection: <50ms across 12 rules.

**Definition of Done**:
- DOD lab PDF uploads, parses, populates form with 25/25 markers correctly.
- Synthetic Quest-format fixture extracts ≥80% of common markers.
- PhenoAge computes correctly when 9 required markers present.
- All 12 pattern detection rules trigger appropriately.
- Trend charts render with optimal/normal range overlays.
- Wearable overlay on biomarker chart works.
- Local analysis generator produces structured text summary.
- Live Claude analysis works when API key in Keychain.
- PrivacyInfo.xcprivacy updated.
- All unit tests pass.
- Performance benchmarks met.
- PR merged to main, tag `m5-complete` pushed.

**Estimated effort**: 20-28 hours. Largest milestone.

---

## M6: Analytics + Weekly Review + Widgets

**Goal**: Sunday auto-generated weekly review. iOS home screen widgets for hydration, fast countdown, schedule.

**Tasks**:

1. Build `Modules/Analytics/WeeklyReviewService.swift`:
   - Aggregates DailyLog, training sessions, learning streaks, biomarker draws, HealthKit metrics.
   - Computes adherence percentages per pillar.
   - Detects PRs and milestone hits.
2. Build phone WeeklyReview view: pillar adherence, weight trend, sleep trend, training volume PRs, missed sessions table, week-ahead schedule.
3. Schedule local notification every Sunday 1800 to surface review.
4. Build PDF/markdown export for weekly review (sharable).
5. Build `PersonalOptimizationWidgets` extension target:
   - `HydrationWidget.swift`: progress vs daily target. Sizes: small, medium, lock screen rectangular.
   - `FastingWidget.swift`: countdown. Sizes: small, lock screen circular and rectangular.
   - `ScheduleWidget.swift`: today's blocks. Sizes: medium, large.
   - `StreakWidget.swift`: current streaks. Sizes: small, lock screen circular.
6. Implement TimelineProvider for each widget with relevance scoring for Smart Stack.
7. Add Control Center widgets (iOS 18+) for quick actions: log water 16oz, end fast.
8. Write tests: adherence calculator, missed-session detector, trend aggregator, widget timeline generation.

**Performance benchmarks**:
- Weekly review generation: <500ms for full week of data.
- Widget timeline refresh: <200ms.

**Definition of Done**:
- Sunday 1800 notification fires with summary preview.
- Weekly review view renders with all sections from real data.
- PDF/markdown export works.
- All 4 home screen widgets render correctly at all sizes.
- Lock screen widgets render correctly.
- Smart Stack ranking works (relevance scores update by time of day).
- Control Center widgets work.
- All unit tests pass.
- Performance benchmarks met.
- PR merged to main, tag `m6-complete` pushed.

**Estimated effort**: 10-14 hours.

---

## M6.5: Mascot System (PNG-based)

**Goal**: A persistent character (cute Japanese ninja aesthetic) lives on the Today screen and watch. Character emotional state tied to user behavior. Static PNG assets generated via Gemini web. Subtle SwiftUI animations for breathing, transitions, alert pulse.

**Pre-flight checklist (must complete before starting M6.5)**:

1. User has used `References/gemini_workflow.md` to generate 8 character PNG files via Gemini web.
2. PNG files placed in `PersonalOptimization/Assets.xcassets/Mascot/` as Image Sets:
   - MascotNeutral.imageset
   - MascotThirsty.imageset
   - MascotFasting.imageset
   - MascotUrgent.imageset
   - MascotProud.imageset
   - MascotDisappointed.imageset
   - MascotTired.imageset
   - MascotAchievement.imageset
3. Each Image Set has 1x, 2x, 3x variants (1024x1024 base, scaled).
4. Wife has approved the character look.

If pre-flight items not complete, agent stops and prompts user to complete them.

**Tasks**:

1. Verify all 8 mascot PNG assets present in Asset Catalog with correct names. Fail fast if missing.
2. Implement `CharacterStateLog` SwiftData model (already in DATA_MODELS.md).
3. Implement `CharacterState` enum and `CharacterStateService` per DATA_MODELS.md.
4. Wire state computation: re-evaluate every 30 seconds via Timer plus on relevant SwiftData writes (DailyLog updates, hydration log, streak change, schedule block transition).
5. Implement state rules with proper precedence per DATA_MODELS.md.
6. Build `Modules/Character/CharacterView.swift`:
   - SwiftUI view rendering current `CharacterState.assetName` as `Image`.
   - Cross-fade transition between states using `.transition(.opacity)`.
   - Subtle breathing animation: `.scaleEffect(breathing ? 1.02 : 1.0)` with `.easeInOut(duration: 3).repeatForever(autoreverses: true)`.
   - Alert pulse: when transitioning to .urgent or .achievement, brief `.scaleEffect(1.1)` then back to normal.
   - Respect `@Environment(\.accessibilityReduceMotion)`: skip breathing and pulse when on.
7. Place CharacterView at top of TodayView (200x200pt frame).
8. Build watchOS `CharacterComplication.swift` for circular complication family (face only, no breathing).
9. Build Settings toggle: "Show mascot" on/off (default on, persists to UserProfile.mascotEnabled).
10. Add Settings section showing mascot acquisition date and version (for future Rive upgrade tracking).
11. Write tests:
    - State resolution scenarios (each of 8 states triggers correctly).
    - Precedence resolution with overlapping conditions (urgent + tired + thirsty all true → urgent wins).
    - State transition logging.
    - mascotEnabled toggle hides/shows CharacterView cleanly.

**Performance benchmarks**:
- CharacterStateService.recompute(): <30ms with full data.
- CharacterView rendering: 60fps maintained with breathing animation active.
- Memory footprint of 8 PNG assets: <8 MB total in app bundle.
- Watch battery impact of complication: <1%/12hr.

**Definition of Done**:
- All 8 PNG assets present and load without error.
- Today screen shows animated character at 200x200pt.
- Watch complication shows character face on circular family.
- Character changes state when triggering data changes (verified by 8 test scenarios, one per state).
- State precedence rules verified by unit tests with overlapping conditions.
- Settings toggle disables character cleanly.
- Breathing animation runs at 60fps.
- Reduced motion setting disables breathing and pulse.
- Battery impact <2% additional drain over 24 hrs (measure with Energy Log on device).
- All unit tests pass.
- Performance benchmarks met.
- PR merged to main, tag `m6.5-complete` pushed.

**Estimated effort**: 8-12 hours of agent execution. Plus 1-2 hours user time for Gemini PNG generation.

**Future v1.5+ option**: Replace static PNGs with Rive `.riv` file containing state machine. The `CharacterState` enum and `CharacterStateService` stay identical; only `CharacterView` swaps from `Image(state.assetName)` to a Rive renderer. This keeps M6.5 cheap and fast while leaving a clean upgrade path.

---

## M7: Notifications Hardening + Edge Cases + Onboarding

**Goal**: All notification triggers from spec wired with smart suppression. All edge cases handled. First-launch onboarding. App is production-ready for daily use.

**Tasks**:

1. Audit and complete every notification trigger:
   - Block start (-5 min)
   - Fast transitions (start, end)
   - Hydration cadence (default 90 min, suppression rules)
   - Pickup prep (16:30 daily)
   - Guitar reminder (1600 weekday, 1900 weekend)
   - Japanese reminder (per-day-specific times)
   - Energy check-in (15:00 daily, banner with 1-10 picker)
   - Achilles check-in (post-basketball, post-lift)
   - Sunday weekly review (1800)
2. Implement notification bundling preference: morning summary at 0900 vs individual alerts.
3. Implement Sick Day Mode: pause reminders, do not break streaks.
4. Implement Travel Mode: collapse to fast + water + 1 learning session, suppress training reminders.
5. Implement Family Event Override: shift blocks for one day without breaking streak.
6. Implement Achilles Flare Protection: if score >=6 logged, suggest rest day insertion next basketball day.
7. Implement Seasonal Pool Change prompt: October 1 trigger to switch Wed swim to Hansen 0500-0700 OR replace with third lift.
8. Implement Watch Off-Wrist graceful degradation for basketball/swim.
9. Build first-launch onboarding flow:
   - Welcome screen.
   - Profile setup (name, DOB, sex, height, weight).
   - HealthKit permission request with rationale.
   - Notification permission request with rationale.
   - Schedule preview (today's blocks).
   - Optional: paste Anthropic API key.
10. Build "What's New" sheet for major updates.
11. Verify JSON export/import round-trips all data without loss after every prior milestone added new entities.
12. Add MetricKit subscription for crash data (`MXMetricManager.shared.add(self)`).
13. Implement App Intents for all major actions: log water, end fast, start lift, log Japanese minutes.
14. **End-to-end test**: 7-day adherence run on simulator with manual time advancement. No crashes, no data loss, no missed schedule blocks.
15. Update PrivacyInfo.xcprivacy with all final entries.
16. Generate and add app icon (1024x1024 base, all required sizes).
17. Write App Store Connect metadata (description, keywords, screenshots) even if not shipping publicly.

**Performance benchmarks**:
- Onboarding cold-flow completion: <60s for typical user.
- 7-day simulator run: zero crashes, zero missed scheduled notifications.
- Memory growth across 7-day run: <10 MB above baseline.

**Definition of Done**:
- All notification triggers verified firing on schedule.
- Suppression rules verified.
- All four mode toggles work (normal, sick, travel, family event).
- Achilles flare suggestion fires on next basketball day after flare logged.
- October pool prompt surfaces on October 1.
- Watch off-wrist scenario does not crash; manual log fallback works.
- JSON export and re-import round-trips all data.
- Onboarding flow runs cleanly on first launch.
- App Intents work via Siri and Spotlight.
- MetricKit reports collected.
- 7-day simulator run completes successfully.
- App icon present at all required sizes.
- All unit tests pass.
- Performance benchmarks met.
- PR merged to main, tag `v1.0` pushed.

**Estimated effort**: 14-18 hours.

---

## Summary

| ID | Module | Effort | Daily-usable after |
|----|--------|--------|--------------------|
| M1 | Schedule + Complication | 8-12h | yes |
| M2 | Fasting + Hydration + Live Activities | 12-16h | yes |
| M3 | Training + Learning | 16-20h | yes |
| M4 | Coursework + Admin | 8-10h | yes |
| M5 | Biomarkers + Lab Parser | 20-28h | yes |
| M6 | Analytics + Weekly Review + Widgets | 10-14h | yes |
| M6.5 | Mascot (PNG-based) | 8-12h | yes |
| M7 | Notifications + Onboarding + Edge Cases | 14-18h | yes (v1.0) |

**Total: 96-130 hours of Claude Code execution.**

Calendar time depends on cadence. Typical pace: 1 milestone per 1-2 weeks for a part-time builder. Full v1.0 in ~10-16 weeks at that cadence.
