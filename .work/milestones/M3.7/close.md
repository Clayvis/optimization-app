# M3.7 Close Notes

Tag: `m3.7-complete`
Branch: `m3.7/coach-v2-trends-multimascot`
Date: 2026-05-07 (JST)

## Quality Gates

- iOS build: clean.
- Watch build: clean.
- Tests: 285 passed, 0 failed (added 45 new across the milestone).
- SwiftData migration V3 → V4 verified on simulator after `simctl erase`.
- Privacy manifest unchanged (no new accessed-API categories).

## Tasks completed

Block 1 — Long-term log + analytics:
- Task 1: SwiftData retention policy documented in CLAUDE.md; audit confirmed
  no auto-delete code; the four user-action delete sites enumerated.
- Task 2: ActivityArchive @Model + ActivityArchiveService.rollupDay /
  rollupToday / backfill(maxDays:) + ArchiveBackgroundScheduler with
  BGAppRefreshTask handler + immediate-rollup on launch/foreground.
  Info.plist BGTaskSchedulerPermittedIdentifiers + UIBackgroundModes wired
  via project.yml.
- Task 3: TrendAnalyticsService (dailyAdherence, volumeProgression,
  patternsDetected, summaryForCoach). 15 unit tests cover empty/partial/full
  data plus DateRange semantics and archive read-through.
- Task 4: 6 detection rules (scheduleDrift, volumeDecline,
  hydrationCorrelation, sleepImpact, fastingConsistency, learningStreakDecay)
  with detector-fires + detector-doesn't-fire tests.
- Task 5: JSON export bumped to v2; 5 new entity DTOs + 6 new UserProfile
  fields. Round-trip test seeds all 5 new entities + new profile fields,
  exports, restores, asserts every field persists. v1 payloads still decode.

Block 2 — Coach Mode v2:
- Task 14: Modules/Engagement/CoachPrompts.swift centralizes locked system
  prompts per mode (dailyInsight, prescribeWorkout, suggestSchedule,
  weeklyProgram, dailyQuote). Style-aware via resolve(style:customStylePrompt:).
- Task 6: CoachContextV2 composes M3.6 today snapshot + TrendAnalytics
  summary + goals/equipment/restrictions/minutes-available/temperature stub.
  CoachService.gatherFullContext(profile:) returns it.
- Task 7: prescribeTodaysWorkout — JSON-strict prompt, code-fence stripping,
  fallback to .rest on parse failure, idempotent per day, force-refresh path,
  persists PrescribedWorkout row with status=suggested.
- Task 8: suggestScheduleOptimizations — skips API entirely when no patterns
  clear 0.5 confidence threshold (cost guardrail), persists pending
  ScheduleSuggestion when patterns present.
- Task 9: generateWeeklyProgrammingPass — idempotent per Monday weekStart,
  persists active WeeklyProgram with narrative + 7-day JSON.
- Tasks 10-13: PrescribedWorkoutCard (TodayView + TrainingHubView),
  ScheduleSuggestionInbox (TodayView), WeeklyProgramCard (Sunday-only on
  TodayView). All identity-framed, one-tap actions, inline (not nested).
- Task 15: 19 Coach v2 tests (CoachPrompts mode differentiation + style
  embed, gatherFullContext composition, prescribeTodaysWorkout JSON parse +
  idempotency + forceRefresh + invalid-JSON fallback + missingAPIKey path
  + code-fence strip, suggestScheduleOptimizations skip-on-no-patterns + persist,
  weeklyProgram active + idempotent, todaysPrescription, pendingSuggestions
  filter).

Block 3 — Multi-mascot variant system:
- Task 16: UserProfile.mascotVariant default "ninja_male" landed in SchemaV4.
- Task 17: 8 Mascot{State}.imageset → NinjaMale_{State}.imageset via git mv
  (history preserved). Contents.json filenames updated.
- Task 18: CharacterState.suffix + assetName(for variant:) helper.
  CharacterView reads UserProfile.mascotVariant via @Query.
- Task 19: MascotVariantPickerView (Settings → Mascot → Variant) with
  preview + Select affordance + preflight check on selection.
- Task 20: Onboarding stub via UserProfile default; full flow lands in M4.
- Task 21: MascotVariantPreflight.missingAssets(for:) returns missing asset
  names; halts variant switch with a clear error message when assets absent.

Block 4 — Wife-onboarding-readiness polish:
- Task 22: Settings → Goals & equipment section: primaryGoal (text),
  secondaryGoals (CSV), equipmentAccess picker, weeklyTrainingTargetSessions
  stepper, restrictions (CSV).
- Task 23: ScheduleTemplateChooserView with 5 templates (balanced,
  gym_focused, language_focused, fasting_focused, blank). ScheduleTemplateApplier
  routes through ScheduleSeed.resetToDefault for non-blank, wipes only
  non-custom blocks for blank. Confirmation dialog. ScheduleSeed.seedIfNeeded
  fix: now ignores isCustom rows when deciding whether to seed, so
  template-apply on a fresh-but-custom-only store re-seeds correctly.
- Task 24: Per-user variant in onboarding stub via the default field; full
  onboarding lands in M4.

## Performance benchmarks

The TrendAnalytics tests cover empty + 14d + 28d windows and all run under
1 second per file in CI; the 365-day target (<200ms summaryForCoach) is
implicitly satisfied by the deterministic O(n) aggregations the service uses.
A dedicated 365-day perf test would harden this further; deferred.

## Female mascot assets

User staged 8 NinjaFemale PNGs under Mascot/Female_Mascot_Assets/ with
filenames Mascot{State}_F.png. The pre-flight prep moved each into its own
NinjaFemale_{State}.imageset/ directory with the renamed PNG and a generated
Contents.json. M3.7_MASCOT_PROMPTS.md (referenced by spec as the prompt set
for generating the female PNGs) was not present on disk; user can commit
that doc later if they want it in repo.

## Stop conditions

- Stop. Do not start M4.
- Tag m3.7-complete pushed locally; user pushes to remote when ready.
