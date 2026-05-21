# 008 — Reward density in the day-30-to-90 window (deferred)

Status: DEFERRED. Recorded against HANDOFF_CLAUDE_CODE.md P3-3.

## Context

V1_OPPORTUNITIES.md Tier 1 item. The behavioral-economics research case: users who hit day 30 with no engineered reward density drop off at >40% by day 60. Habit formation studies suggest engineered milestones at days 30/45/60/75/90, mascot variants unlocking, variable-ratio celebrations on PRs.

M3.7a shipped the `MilestoneUnlock` + `Achievement` systems, plus the celebration sheet. The infrastructure is in place. What's missing is the *density* — currently milestones unlock at obvious thresholds (7d streak, 30d streak, 100 hydration logs), not in the day-30-to-90 retention dip specifically.

## Decision

Do not implement now. Land P0/P1 hardening (DR-005) first, ship to TestFlight, observe Clay's day-30-to-90 behavior with the existing milestone schedule. If a dip surfaces in the actual usage data, then engineer the additional rewards.

Reasoning:
- The retention research is general. Clay's specific drop-off curve may not match it (he's an unusual user — engineered the app himself, intrinsically motivated).
- Adding rewards we don't need would dilute the meaningful ones. The mascot variants and milestone-unlock surfaces should retain emotional weight.
- The infrastructure (`AchievementRegistry`, `MilestoneRegistry`, `MilestoneCelebrationSheet`) makes this a small-effort add once we know what to engineer.

## Pre-conditions for revisiting

- TestFlight v1.0 logs day-by-day engagement metrics for Clay + wife through day 90.
- If retention drops below 80% engagement on any single domain (workout / hydration / learning) during days 30-60, design the specific reward.
- Reward design must match `Design Principles for Engagement Decisions` rule 7 in CLAUDE.md: "Mascot reflects state, never theater. Sad mascot must mean a real miss. Achievement is rare and earned."

## Implementation sketch (not built)

- `EngagementMilestoneRegistry` adds entries: day-30 "First month rite", day-45 "Compound interest", day-60 "Habit owns you", day-75 "Body remembers", day-90 "v1 of you".
- Each unlocks a small UI cosmetic (mascot expression variant, journey badge).
- Variable-ratio: 1 in 3 PR notifications fires the celebration sheet; the other 2 get a quiet badge.
