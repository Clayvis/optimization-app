# 010 — Proactive lapse-recovery flow (deferred)

Status: DEFERRED. Recorded against HANDOFF_CLAUDE_CODE.md P3-5.

## Context

`LapseDetectionService` already exists (added during V1 opportunities pass). It detects when the user has been away ≥ 5 days based on the most recent DailyLog activity. `WelcomeBackCard` exists and is shown on TodayView when a lapse is active.

The handoff asks for more: when the user opens the app after a 5+ day lapse, **route through a dedicated "welcome back" screen** instead of TodayView. This is a behavioral nudge — full-screen acknowledgment of the gap, soft re-onboarding, suggested first action, before they see the regular dashboard.

## Decision

Do not implement now. Land P0/P1 hardening (DR-005) first. The shipped `WelcomeBackCard` is a soft version of the proactive flow; upgrade to a full-screen sheet later when we have evidence the card isn't strong enough.

Reasoning:
- The behavioral case is real but the strength of a full-screen interrupt depends on user style. For some users it'd feel patronizing.
- TestFlight signal (does Clay actually return after a real 5-day lapse?) will tell us whether the existing card is enough or whether we need the proactive sheet.
- M4.2 Persona system gives us a way to gate the strength of the flow per user style (disciplinarian gets the full screen; encourager gets the card).

## Pre-conditions for revisiting

- TestFlight v1.0 logs at least one real lapse-and-return event for Clay or wife.
- Compare time-on-app and re-engagement rate when the card is shown vs control.
- Persona-aware variant designed (disciplinarian: full-screen, encourager: card).

## Implementation sketch (not built)

- `RootView` checks `LapseDetectionService.lastLapseDays(asOf:)` on launch.
- If >= 5 and the user hasn't dismissed today's welcome-back, route to `WelcomeBackSheet` (full-screen, modal).
- Sheet contains: identity-framed message ("you're back, this is who you are"), one-tap "log today's first thing" CTA, optional "I was sick / traveling" toggle (sets `sickDayActiveUntil` / `travelModeActiveUntil`).
- Dismiss writes `lastLapseAcknowledgedAt` to UserProfile so the sheet doesn't re-fire on the same lapse.
