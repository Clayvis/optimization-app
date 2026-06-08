# 017 - Engagement & retention build sheet: gap closure decisions

Date: 2026-06-08
Status: implemented (pending user review)
Context: the M3.7 "Engagement and Retention Build Sheet" was re-issued. A gap
analysis against the current v1.0.0-rc1 code found most mechanics already built
(streaks, freezes, partner pairing seam, achievements, recovery gate, AI coach,
HealthKit background delivery, CloudKit parity). This records the two judgment
calls made while closing the genuine gaps.

## Decision 1: forgiveness auto-apply is honest mercy, not faked completion

The build sheet (section 2, Gap 2 fix) wants the grace-day pool to AUTO-protect
the streak on a miss, citing Duolingo's Streak Freeze (cut churn 21%). The
project's own PIVOT_SPEC design principle 2 says "Never fake completion to
preserve a streak; preserve it via explicit pause."

Resolution: these are reconcilable. Auto-grace does NOT fake a completion. It
spends a token from the finite monthly freeze pool (2/month) and records a real
`FreezeApplication` (or `WorkoutEvent` source=.freeze) on the missed day, which
the streak engine already treats as a distinct grace source. It is transparent
(the freeze count visibly drops, and TodayView shows "Grace day auto-applied")
and bounded (it only fires when it actually saves a LIVE chain, never on a zero
streak or a multi-day lapse).

Implementation: `StreakService.autoApplyGraceIfNeeded(domain:asOf:)`, run once at
launch alongside `resetMonthlyFreezes()`. Default domain is protocolAdherence
(the headline streak). The manual "Protect today" button is preserved.

Reversibility: high. Deleting the two launch calls reverts to manual-only.

## Decision 2: the spouse dyad ships as seam-level logic, transport deferred

The build sheet (section 3) wants a joint streak (continues only if both log),
shared visibility, and nudge-a-partner. Section 5 itself notes the CloudKit
shared zone gates this, and decision 007 already defers the live zone to a paid
Apple Developer account.

Resolution: build the full LOGIC and UI against the existing `PartnerSharedZone`
seam, tested with `MemoryPartnerSharedZone`, so the live zone is one PR away. The
joint-streak computation (`PartnerService.jointStatus`, min of both chains),
`sendNudge`/`pendingNudge`, and `PartnerStatusCard` are all wired. In v1.0 the
default `NoopPartnerSharedZone` returns nil, so the card stays hidden until the
account lands. The instrumentation joint-streak indicator consumes the same
computation.

Do NOT implement `CloudKitPartnerSharedZone` now: it needs the paid account,
entitlement changes, and a CKShare spike (out of scope, irreversible infra).

## What was built (all tested, build clean, zero warnings)

- Section 6 instrumentation: `EngagementMetricsService` (6 leading indicators) +
  a Diagnostics "Test instrumentation" section.
- Gap 1 durability handoff: `DurabilityHeadlineService` + TodayView headline
  shift after a 30-day bootstrap window.
- Gap 3 readiness transparency: `RecoveryGate.evaluateDetailed` + `RecoveryCard`.
- Goal-gradient: "one more to close" nudge + per-bar final-stretch emphasis.
- Watch complication: `ProtocolGoalComplication` renders the daily goal as a
  4-track ring with the master streak at center (the goal IS the visual), using
  device-timezone day boundaries to match the streak engine.
- Forgiveness auto-apply (decision 1) + monthly reset wired at launch.
- Spouse dyad (decision 2).
- Import safeguard: JSONImportService.restore now runs the non-destructive
  DailyLog dedupe so an import file with same-day duplicate rows cannot corrupt
  the imported streak counts.
- Baseline fixes: CT3 retention-aware assertion; PersistenceBootstrap directory
  pre-flight so an impossible store path degrades to recovery instead of the
  SIGABRT ModelContainer raises on iOS 26.

## Not built (documented gaps)

- DailyGoal Live Activity rendering the goal-as-shape: the lock-screen surface
  is partly covered by the new watch complication; a Live Activity is additive.
- iOS Home Screen widget extension: a whole new target; deferred.
- `MilestoneType.appUsageDays`: left as-is. On inspection it is computed from
  DailyLog row count (days WITH a log), not raw app-opens, and no milestone
  definition awards it, so it is not a trivial-badge violation.
