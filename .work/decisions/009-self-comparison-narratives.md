# 009 — Self-comparison narratives in Coach output (deferred)

Status: DEFERRED. Recorded against HANDOFF_CLAUDE_CODE.md P3-4.

## Context

Handoff's framing: "You ran 3.2 miles today. Six months ago your average was 1.8." Coach should reference specific prior wins by name, surfacing the user's own historical baseline as the comparison target rather than a generic external benchmark.

M3.7 shipped `TrendAnalyticsService` which already computes per-domain trends (weekly volume, rolling averages, biomarker deltas). M4.2 added `CoachContextV2` which packages this data for Coach prompts. Both are in place.

The gap: the Coach *prompts* (in `CoachPrompts.swift`) don't currently include the historical baseline data structured as "you vs your 6-month-ago self." They include current data and recent trends; not the explicit then/now contrast.

## Decision

Do not implement now. Land P0/P1 hardening (DR-005) first. The change is a prompt-engineering update + a small `TrendAnalyticsService.compareToBaseline(months: 6)` helper. Doing it without TestFlight data risks tuning prompts to Clay's specific style rather than what works generally — and risks burning eval cycles to validate the change in isolation.

## Pre-conditions for revisiting

- TestFlight v1.0 has at least 6 months of DailyLog data for one user (Clay's existing data may seed this; wife's account starts fresh).
- M4.2 Persona system has stabilized — self-comparison phrasing needs to match the user's motivation style ("disciplinarian" vs "encourager" handle "you used to suck" differently).
- Eval rubric for Coach insight quality (CLAUDE.md M3.7c gating) explicitly scores "references prior data" as a dimension.

## Implementation sketch (not built)

- `TrendAnalyticsService.compareToBaseline(domain: StreakDomain, monthsAgo: Int) -> (current: Double, baseline: Double, deltaPct: Double)?`
- `CoachPrompts.contextPrompt` adds a `historicalBaselines` section when the user has >= 90 days of data.
- Persona-aware phrasing: disciplinarian style ("Six months ago this was 1.8 mi. Today 3.2. The work shows.") vs encourager ("Look how far you've come — 1.8 → 3.2.").
