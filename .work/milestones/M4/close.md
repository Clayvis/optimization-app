# M4 Close Notes

Tag: `m4-complete`, `v1.0.0-rc1`
Branch: `m3.7/coach-v2-trends-multimascot`
Date: 2026-05-07 (JST)

## Quality gates

- iOS build clean.
- watchOS build clean (PersonalOptimizationWatch + PersonalOptimizationWatchComplications).
- 316 tests pass on iOS (was 305 at M3.8 close; +11 new).
- Onboarding flow runs top-to-bottom on a fresh-install simulator.

## Tasks completed

Block 1 — Models + services:
- ImplementationIntention + WeeklyReflection @Models (SchemaV6, lightweight migration V5 → V6).
- ImplementationIntentionService (CRUD + 5 starter seeds).
- WeeklyReflectionService (currentOrGenerate + regenerate + composeCoachMessage).

Block 2 — Implementation Intentions UI:
- ImplementationIntentionsView (Settings → Schedule → Implementation intentions): empty state nudge, list with archive/edit, "Seed starter set" button.
- IntentionsStrip on TodayView under "WHEN YOU…" surfaces active plans; tap-to-record-completion.

Block 3 — Onboarding:
- 5-screen wizard gated behind UserProfile.onboardingCompleted: Welcome → Permissions (HK + notifications) → Goals → Mascot variant → Wrap-up.
- RootView routes to OnboardingView until completed; defaults seeded (custom activities + intention starters) on first appear.

Block 4 — Weekly reflection:
- WeeklyReflectionCard on TodayView (Sunday-only) with coach message + 3 metric chips.
- WeeklyReflectionDetailView with 6-tile metric grid + identity-framed coach line + free-text reflection note (saved live) + Regenerate.

Block 5 — Notification hardening:
- Existing NotificationService already implements quiet hours (default 22-07 JST), hydration cutoff, morning-intake bypass.
- Identity-framed copy already centralized in IdentityCopy.Notification.
- No new code needed at the V6 line.

Tests added (11):
- ImplementationIntentionServiceTests (6).
- WeeklyReflectionServiceTests (5).

## Deferred to user action / v1.0 sign-off

These M4 spec items require the user (no autonomous action possible):

1. **App Store screenshots** — six required per spec (TodayView with mascot, FastingView, HydrationView, Workout streak with mascot proud, Implementation Intentions builder, Weekly Reflection). Generated manually via simulator capture.
2. **TestFlight build** — requires a paid Apple Developer membership upgrade.
3. **App description copy + ASO keywords** — voice/positioning is the user's call.

## Deferred to v1.5+

- Configurable quiet hours UI (the values exist as defaults in NotificationService; UI wiring deferred).
- Time zone change handling test (Clay's US ↔ Okinawa scenario).
- DST transition tests.
- First-of-month freeze reset edge tests (the logic is in StreakService.resetMonthlyFreezes, untested at boundary edge).

## Ship readiness

The app reaches v1.0 release-candidate scope with:
- 316 tests, 0 failures.
- iOS + watchOS + complication extension all build clean.
- Zero third-party packages.
- Privacy manifest current (no new categories beyond M3.5).
- All seven CLAUDE.md design principles enforced through the codebase.
- 8 milestones (M1, M2, M3, M3.5, M3.6, M3.7, M3.8, M4) closed.

Tagging `v1.0.0-rc1` represents the codebase's first ship-ready candidate. Final `v1.0` waits on Clay running the 7-day usability test on real hardware (iPhone 16 Pro + Apple Watch Ultra 2) and the App Store / TestFlight steps above.
