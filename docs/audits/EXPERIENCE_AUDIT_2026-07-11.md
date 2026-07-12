# Experience Audit — 2026-07-11

Scope: current iPhone app, watch surfaces, onboarding, daily logging, and the
new Dojo navigation/widget work in PR #8.

## Shipped in PR #8

1. **Root navigation overload — fixed.** Eight root tabs triggered iOS's
   automatic More interface. Five stable tabs now keep daily actions one tap
   away and move lower-frequency modules into a themed Dojo hub.
2. **No iPhone mascot surface — fixed.** Small and medium Home Screen widgets
   now show mascot state, protocol completion, and streak.
3. **Widget return path — fixed.** Tapping the mascot widget routes to Today,
   even when the app was last left on another tab.
4. **No remote quality gate — fixed.** GitHub Actions now runs repository
   guards, the full unit suite, coverage, and a zero-warning check.

## Next priorities

### P1 — Reduce Today screen decision load

`TodayView` currently renders more than fifteen independent cards before the
schedule list. The information is useful, but the screen gives status,
partner, recovery, coaching, persona, schedule, reflection, and insight cards
nearly equal visual weight.

Recommended structure:

- Above the fold: mascot, master metric, next action, active session.
- "Today's plan": prescribed workout and schedule blocks.
- "Review": progress, recovery, partner, coach, and weekly cards in a
  collapsible section that remembers its state.
- Hide cards with no actionable content instead of rendering placeholders.

### P1 — Add UI smoke tests

The repository has strong service/model coverage but no UI-test target. Add a
small deterministic suite covering onboarding completion, each root tab, the
Dojo navigation path, hydration quick-log, and widget deep-link routing. This
will catch navigation regressions that unit tests cannot see.

### P1 — Make HealthKit state explicit

Today only shows Apple Health while synchronization is active. Add a compact
status surface for last successful sync, authorization gaps, and retryable
errors. Users should know whether "no activity" means no activity or no data.

### P2 — Shorten onboarding

The onboarding wizard combines identity, schedule, time anchors, permissions,
mascot, and optional AI configuration. Keep only the minimum required to reach
Today; defer advanced schedule and AI tuning to the Dojo with a completion
checklist.

### P2 — Finish partner mode or label it clearly

The current partner feature is a local scaffold; live cross-Apple-ID sharing
is deferred. TestFlight copy must not imply that pairing is fully functional.
Either finish the CloudKit shared-zone transport or mark it Preview and explain
what currently syncs.

### P2 — Accessibility regression coverage

Phone views contain useful VoiceOver labels, but watch workout controls remain
uneven. Add labels and hints to lift, basketball, swim, learning, and custom
activity controls, then include Accessibility Inspector in the release check.

## Release ordering

1. Merge CI/navigation/widget work.
2. Restructure Today without changing business logic.
3. Add the UI smoke-test target and critical navigation tests.
4. Add HealthKit status/error recovery.
5. Simplify onboarding.
6. Resolve partner-mode product truth before broader TestFlight distribution.
