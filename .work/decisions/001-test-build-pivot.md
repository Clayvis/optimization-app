# 001 — M3.7a test-build pivot

Status: ACCEPTED. Recorded retroactively against M3_7a_TEST_BUILD_SPEC.md execution.

## Context

M3_7_SPEC.md bundled four workstreams (long-term log persistence, trend analytics, prescriptive Coach v2, multi-mascot rename + onboarding polish) into one milestone. Audit surfaced four problems:

1. Scope: 25-36h estimate unrealistic; realistic was 60-90h.
2. Coach v2 prescriptive output is an unvalidated product hypothesis. M3.6 commentary insight has not been used long enough to know whether the user reads it, ignores it, or modifies behavior because of it.
3. Cost projections for Coach v2 understated: 1500-3000 input tokens per call, $4-7 / user / month average, $10-15 heavy. The proposed $5 cap leaves no margin.
4. MascotNeutral.imageset → NinjaMale_Neutral.imageset rename is high blast radius (mascot is core UX), low feature value (rename ships nothing), and unnecessary (female assets can be added alongside).

## Decision

Replace M3.7 with M3.7a (test-build), defer prescriptive Coach v2 / ActivityArchive rollups / TrendAnalyticsService / DetectedPatterns to M3.7b or M3.7c, gated by 30-day usage data from Clay + wife on TestFlight.

## What's IN (M3.7a, what shipped)

- Wife onboarding readiness: mascot variant system (additive), goals capture in Settings, schedule template chooser, first-launch onboarding stub.
- Long-term log persistence (lite): SwiftData retention audit + CLAUDE.md "Data Retention" section. JSON export/import round-trip test.
- TestFlight distribution path (Clay actions, gated on paid Apple Developer enrollment).
- Feedback capture: in-app mailto shortcut, CoachInsight.userInteraction field + thumbs-up/thumbs-down on Today coach card.

## What's OUT (deferred to M3.7b or M3.7c)

- CoachService.prescribeTodaysWorkout
- CoachService.suggestScheduleOptimizations + ScheduleSuggestion entity
- CoachService.generateWeeklyProgrammingPass + WeeklyProgram entity
- ActivityArchive entity + daily rollup BGAppRefreshTask
- TrendAnalyticsService
- DetectedPattern entity + 6 pattern rules
- Mascot asset rename
- CloudKit sync verification UI in Settings

## Status note (recorded 2026-05-08)

By the time this decision record was written, several "deferred" items had already shipped under separate M3.x milestones (ActivityArchive shipped under M3.7 line, ScheduleSuggestion + WeeklyProgram shipped under follow-on engagement work). The pivot's intent was preserved: ship a tight test-build, gate prescriptive Coach output on 30-day data. The deferred-list above reflects the spec as written, not current reality.

## Success criteria for deciding next milestone (per spec)

Day-30 review reads:
- Daily insight engagement data (Task 11 + 12 logging).
  - ≥40% interaction rate AND ≥3:1 helpful-to-unhelpful ratio → M3.7b prescriptive Coach is worth building.
  - Below either threshold → design M3.7c (different reinforcement loop).
- Wife's qualitative feedback (top 3 liked / disliked / wanted-but-missing).
- Bug + stability data (>1% crash rate gates new features).
- Cost data (>$4 / user / month gates new API calls).

Findings written to `.work/reviews/m3.7a-day30-review.md`.
