# M3.7a_TEST_BUILD_SPEC.md

Scoped pivot from M3_7_SPEC.md. Replaces M3.7 as the next milestone. Goal: ship a tight, useful build that Clay and his wife can both run on their personal iPhones for 30 days, then decide what to build next based on real usage data instead of speculation.

This spec supersedes M3_7_SPEC.md until further notice. The original M3.7 work (prescriptive Coach v2, ActivityArchive rollups, multi-mascot asset rename, weekly programming pass) is split into M3.7b and M3.7c, deferred until the 30-day test produces evidence those features are worth building.

---

## Why this pivot

Reviewing M3_7_SPEC.md against the rest of the project documents surfaced four problems:

1. M3.7 bundles four separate workstreams (long-term log persistence, trend analytics, prescriptive Coach v2, multi-mascot variant + onboarding polish) into one milestone. Every prior milestone scoped one thing. The estimate of 25-36 hours is unrealistic given the scope. Realistic estimate is 60-90 hours.
2. Coach Mode v2 prescriptive output is a product hypothesis that has not been validated. M3.6 daily insight commentary has not been used long enough to know whether the user reads it, ignores it, or modifies behavior because of it. Building prescriptive output before validating commentary is over-engineering.
3. Cost projections in M3_7_SPEC.md assume a "compact 500 token historical context." Realistic CoachContextV2 with 365 days of trend data, full goals, equipment, weather, and schedule density will be 1500 to 3000 input tokens per call. Per-user monthly cost is closer to 4 to 7 dollars average and 10 to 15 dollars heavy. The proposed 5 dollar tier cap leaves no margin.
4. The MascotNeutral.imageset to NinjaMale_Neutral.imageset rename is high blast radius (mascot is core UX), low feature value (the rename itself ships nothing), and unnecessary. Female assets can be added alongside without renaming the existing ones.

The 30-day Clay-plus-wife test resolves all four problems. We get real usage data on whether M3.6 features are useful before extending them, we get wife onboarding shipped which is the most valuable thing in the original M3.7 anyway, and we keep the build simple enough to actually finish in one milestone.

---

## Scope: what's IN

### Wife onboarding readiness (the headline feature)

The single most valuable thing in original M3.7 is making the app installable and usable for wife. Everything else can wait. This requires:

1. **Mascot variant system, additive only.** Add mascotVariant field to UserProfile, default "ninja_male" for existing user. CharacterState.assetName(for variant:) helper returns existing asset names for ninja_male and new NinjaFemale_* names for ninja_female. Do NOT rename existing MascotNeutral.imageset etc. Existing PNGs stay where they are. Female PNGs go into new NinjaFemale_*.imageset folders.

2. **Goals capture in Settings.** Add fields to UserProfile: primaryGoal (free text), secondaryGoals (string array, 3-5 entries), equipmentAccess (picker: gym, home_full, home_minimal, bodyweight, outdoor), weeklyTrainingTargetSessions (stepper, default 5), restrictions (free text). Settings -> Goals view to enter and edit these. SchemaV3 migration.

3. **Schedule template chooser.** Settings -> Schedule -> "Start fresh from template" with 5 options: gym-focused, language-focused, fasting-focused, balanced, blank slate. Replaces current schedule with chosen template. Wife picks balanced or language-focused on first launch.

4. **First-launch onboarding stub.** Minimal flow on a fresh install: pick mascot variant, enter primary goal, choose schedule template. Three screens, no animations, just functional. M4 will build the polished version. This is the foundation.

5. **Per-user data isolation verification.** Confirm and document that wife's UserProfile, sessions, fasts, etc. on her iPhone are NOT visible on Clay's iPhone. They will be different iCloud accounts so this should already be true via CloudKit, but verify and write a test that runs a fresh install scenario.

### Long-term log persistence (lite version)

The original M3.7 plan for ActivityArchive rollup table plus daily background job is deferred. For a 30-day test with 2 users producing maybe 30-60 sessions each, no rollup is needed. The existing SwiftData session rows are queried directly, fast enough.

What we DO need:

6. **Audit and document SwiftData retention.** Confirm no auto-delete code exists anywhere. Write findings to CLAUDE.md under a "Data Retention" section. Add an explicit code comment to any cleanup-adjacent code (cache eviction, log truncation) documenting that session data is never deleted.

7. **Export and import round-trip test.** Settings -> Data -> Export full history as JSON (already exists for some entities from M1). Extend to cover all current entities. Round-trip test: export, wipe DB on a clean simulator, import, assert all sessions and configuration restored. This is the bulletproof backup before we hand the app to wife.

### TestFlight distribution

8. **Paid Apple Developer Program enrollment.** PROJECT_BRIEF.md defers this decision to M7. Pull it forward. Paid account is required for TestFlight, which is the only sensible way to get a 30-day build onto wife's phone. Free personal team gives 7-day signing which means Clay re-installs the app on wife's phone every week. That breaks the test.

9. **TestFlight internal testing setup.** Configure App Store Connect with internal testers (Clay, wife). Build, sign, upload via Xcode Organizer or xcodebuild + altool. Verify wife receives TestFlight invite, installs, opens the app, completes onboarding.

### Feedback capture during the 30-day test

10. **In-app feedback shortcut.** Settings -> "Send feedback" opens a pre-populated mailto: link with subject "PersonalOptimization feedback YYYY-MM-DD" and body containing app version, build number, current mascot variant, and a "What's working / What's broken / What's missing" template. Both Clay and wife use this throughout the 30 days. Captures structured feedback without building any infrastructure.

11. **Daily insight engagement logging.** Add a single field to the existing CoachInsight entity: userInteraction (enum: ignored, viewed, dismissed, acted_on, marked_helpful, marked_unhelpful). On the TodayView Coach card, add two small buttons: thumbs up and thumbs down. Tap logs the interaction. After 30 days, query: of N daily insights generated, how many got user interaction, how many marked helpful, how many marked unhelpful. This is the data that decides whether M3.7b prescriptive Coach is worth building.

---

## Scope: what's OUT

These are explicitly deferred until after the 30-day test results are reviewed.

- **CoachService.prescribeTodaysWorkout** and the entire prescriptive workout output pipeline. M3.6 daily insight stays as the only Coach output.
- **CoachService.suggestScheduleOptimizations** and ScheduleSuggestion entity.
- **CoachService.generateWeeklyProgrammingPass** and WeeklyProgram entity.
- **ActivityArchive entity and daily rollup BGAppRefreshTask.** Not needed at 60 sessions per user. Re-evaluate when one user has more than 1000 sessions logged.
- **TrendAnalyticsService.** Same reason. Pattern detection across 365 days of data is solving a problem that does not exist yet at month one.
- **DetectedPattern entity and 6 pattern rules.** Same reason.
- **Mascot asset rename from MascotNeutral.imageset to NinjaMale_Neutral.imageset.** Additive approach only.
- **CloudKit sync verification UI in Settings.** OS-level CloudKit status is sufficient for the 30-day window.

---

## Decision records to write before starting code

Per ARCHITECTURE.md rules. Write these to .work/decisions/ first, get them committed, then write code.

- **001-test-build-pivot.md**: this entire pivot. Why M3.7 is being split, what's deferred, success criteria for deciding next milestone.
- **002-additive-mascot-variants.md**: rationale for not renaming existing mascot assets. Includes the namespace convention (legacy MascotX names continue working for ninja_male, NinjaFemale_X names for the new variant).
- **003-paid-developer-account.md**: pulling the paid Apple Developer Program decision forward from M7 to now. Includes cost ($99/year), benefits (TestFlight, HealthKit background delivery, eventual App Store submission), and account ownership (Clay's personal Apple ID).
- **004-coach-feedback-as-validation-gate.md**: defines the "M3.7b is built only if X" criterion based on insight interaction data captured during the 30-day test. Specific threshold: at least 40 percent of generated insights receive an interaction (any of the 4 affirmative states), AND helpful-to-unhelpful ratio is at least 3:1. Below either threshold, M3.7b is not built; instead, M3.7c (different reinforcement loop) is designed.

---

## Tasks

### Block 1: Onboarding foundations (4-6 hours)

**Task 1**: SchemaV3 migration. Add to UserProfile: mascotVariant (String, default "ninja_male"), primaryGoal (String?), secondaryGoals ([String], default []), equipmentAccess (String, default "home_full"), weeklyTrainingTargetSessions (Int, default 5), restrictions (String?).

**Task 2**: CharacterState.assetName(for variant:) helper. Update CharacterView and any other consumer to read userProfile.mascotVariant and pass it. Existing asset names continue to work for ninja_male.

**Task 3**: NinjaFemale asset placeholder. Create empty NinjaFemale_*.imageset folders for all 8 states. Add a pre-flight check at app launch: if userProfile.mascotVariant == "ninja_female" and assets are missing or empty, log a warning and fall back to ninja_male temporarily. This lets us ship the variant infrastructure before the PNGs are generated.

**Task 4**: Settings -> Goals view. Form-style screen with all 5 goal fields. Saves to UserProfile.

**Task 5**: Settings -> Schedule -> Start fresh from template. 5 templates as JSON files in Resources/. Tapping a template shows a confirmation dialog ("This replaces your current schedule"), then loads the template.

**Task 6**: First-launch onboarding stub. 3-screen flow: variant picker, primary goal, template chooser. Triggers when UserProfile.primaryGoal == nil on launch. Skippable but encouraged.

### Block 2: Test infrastructure (3-4 hours)

**Task 7**: Audit data retention. grep for any cleanup, deleteAll, prune, expire, evict patterns in the codebase. Document findings in CLAUDE.md. Add inline comments to anything that touches user data.

**Task 8**: Extend JSON export/import to cover all current entities. Round-trip test: PersonalOptimizationTests/DataExportImportTests.swift. Test cases: empty DB, single user with 7 days of data, single user with 30 days of data, schema version mismatch handling.

**Task 9**: In-app feedback mailto shortcut in Settings. Pre-populated subject and body template.

**Task 10**: CoachInsight.userInteraction field (SchemaV3, same migration as Task 1). Default ignored. Update existing rows to ignored on migration.

**Task 11**: TodayView Coach card thumbs-up / thumbs-down buttons. On tap, set userInteraction to marked_helpful or marked_unhelpful and persist. Subtle visual confirmation, no modal.

**Task 12**: TodayView Coach card view tracking. When the card scrolls into view for more than 1.5 seconds, set userInteraction to viewed (only if currently ignored, do not overwrite a stronger signal).

### Block 3: TestFlight distribution (2-3 hours, mostly waiting)

**Task 13**: Paid Apple Developer Program enrollment. This is a Clay action, not a Claude Code action. Document status in .work/decisions/003-paid-developer-account.md when complete. Claude Code halts on this until done.

**Task 14**: App Store Connect record creation. Bundle ID com.rawlins.PersonalOptimization. App name "Optimization." Privacy nutrition label filled out (no data collected, no tracking, no third-party SDKs).

**Task 15**: TestFlight internal testing group with two testers (Clay, wife). Build, archive, upload. Verify TestFlight build appears, both testers receive invites.

**Task 16**: Wife device install validation. Wife installs from TestFlight, completes onboarding, verifies mascot variant renders correctly, confirms her data does not appear on Clay's iPhone (different iCloud accounts).

### Block 4: Polish and pre-flight (2-3 hours)

**Task 17**: Settings -> About screen showing app version, build number, current schema version, days since first launch, total sessions logged. Useful for both users to self-diagnose during testing.

**Task 18**: Crash and hang resilience pass. Run app for 1 hour straight on simulator with rotation, backgrounding, low-memory simulation. Fix anything that breaks.

**Task 19**: Tests passing, build clean, zero warnings.

**Task 20**: Tag m3.7a-test-build in git. Push.

---

## Definition of Done

- All 20 tasks complete.
- 4 decision records written and committed.
- TestFlight build available, both Clay and wife have it installed and have completed onboarding.
- Wife's first 24 hours of usage produces zero crashes, zero data loss, no missing functionality on her primary intended use cases (open app, view today's schedule, log a workout, log hydration, see mascot in correct variant).
- M3_7_SPEC.md is moved to .work/archive/M3_7_ORIGINAL_SPEC.md with a header note pointing at this file.
- README.md and MILESTONES.md updated to reflect the M3.7a / M3.7b / M3.7c split.
- 30-day usage period begins. Calendar reminder set for day 30 review.

---

## Performance and quality gates

Inherit all PERFORMANCE.md targets. Specifically verify on the test build before TestFlight upload:

- iPhone cold start to TodayView render under 1.5s.
- Schedule resolution under 50ms.
- Mascot variant switch (Settings change) renders new asset within one frame.
- JSON export of 30 days of data under 5s.
- TestFlight build size under 50 MB.

---

## API cost ceiling for the 30-day test

Combined hard cap: 30 dollars across both users for the full 30 days. M3.6 daily insight at 0.02 to 0.04 per call, twice daily max (Clay + wife), 30 days = 1.20 to 2.40 per user per month. Add daily quote (Haiku) at 0.005 = 0.30 per user. Total expected: under 6 dollars combined. The 30 dollar cap leaves enormous margin and absorbs any retry storms.

If actual spend tracks higher than 6 dollars by day 10, halt and investigate.

---

## After day 30: decision framework for next milestone

Review session at day 30. Look at:

1. **Daily insight engagement data** (from Task 11 and 12 logging).
   - At least 40 percent interaction rate AND 3:1 helpful-to-unhelpful ratio: M3.7b prescriptive Coach is worth building.
   - Below either threshold: do NOT build M3.7b. Instead, design M3.7c which is a different feedback / reinforcement mechanism. Most likely candidates: a streak-recovery prompt, a weekend reflection nudge, or a goal-progress dashboard. Decide based on what the feedback emails actually said.

2. **Wife's qualitative feedback.** Top 3 things she liked. Top 3 things she did not like. Top 3 things she wanted that did not exist. This drives the next 2 milestones regardless of insight data.

3. **Bug and stability data.** Crash rate, hang rate, sync issues, data loss reports. Anything above 1 percent crash rate gets fixed before any new features.

4. **Cost data.** Actual API spend over 30 days, projected forward. If average per-user-month is over 4 dollars before any prescriptive features are added, redesign cost model before adding more API calls.

Write findings to .work/reviews/m3.7a-day30-review.md. That document drives the M3.7b vs M3.7c vs other decision.

---

## Estimated effort

11 to 16 hours of agent execution, plus Clay's enrollment time for the paid Apple Developer Program (24 to 48 hours of waiting on Apple). Total calendar time from spec acceptance to TestFlight build in wife's hands: 4 to 7 days.

This is roughly one third of the original M3.7 estimate, scoped to the highest-value subset, and explicitly designed to produce data that informs what to build next.
