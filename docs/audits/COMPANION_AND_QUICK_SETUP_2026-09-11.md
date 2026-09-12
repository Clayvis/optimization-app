# Companion and quick first-launch setup

The nutrition reliability fixes were pushed to `main` as `2e08330`. This pass
adds companion behavior and replaces the six-screen onboarding flow.

## Companion

- Four contextual states: training, recovery day, welcome back, and daily win.
  Existing state raw values remain readable in retained history.
- Training follows started/resumed phone sessions and Watch presence. A saved
  workout can celebrate; skips, freezes, unfinished sessions, and future rows
  cannot earn a celebration. Stale live-workout signals expire.
- Rest days, sick days, and reported pain receive a calm recovery response.
  A break receives a welcome-back response. No XP or workout history changes.
- The service belongs to the tab root, fixing stale state after leaving Today.
  It refreshes on workout events, tab changes, and foregrounding.
- Native breathing, training rhythm, gentle sway, and brief tap/state reactions
  reuse the installed ninja artwork. Both system Reduce Motion and the app's
  reduced-motion preference stop the animated rendering path. Motion also stops
  when the view disappears or the app becomes inactive.
- Dojo > Meet your companion previews the four reactions without changing live
  state, rewards, or history. The same preview is available in mascot settings.
- Watch home uses the same state resolver. Widgets retain the matching static
  artwork; the vector fallback understands the new reaction names.

This is native motion around the existing illustrations, not a skeletal or
frame-by-frame character rig. No new raster assets or dependencies were added.

## Quick setup

- Step 1: optional name, height, weight, and imperial/metric units. Measurements
  start empty; validated input replaces the old prefilled body defaults.
  Full-width measurement inputs fix missed taps on the old label/value rows.
  Unit conversion carries rounded inches into feet at the next-foot boundary.
- Step 2: goal, workout days per week, 5/10/20-minute session target, equipment,
  and companion choice. The selected targets drive Today and are also stored
  in profile metadata for other devices.
- Profile completion uses a transaction. Invalid input cannot mark setup done;
  a returning user's completed profile cannot be overwritten by another finish.
- Existing users continue directly into the app. Detailed body info, schedules,
  nutrition targets, and permissions remain available in their relevant screens.
- New quick-setup profiles do not receive the old personal schedule on the next
  launch. Notification authorization is requested from the explicit Settings
  action, rather than automatically before the profile screen.

No SwiftData schema changes, automatic data deletion, or new dependencies.

## Verification

Verified September 11-12, 2026 with Xcode 26.6 (17F113), iPhone 17 Pro simulator
running iOS 26.5. No schema changes or third-party packages were required.

| Check | Result | Local artifact |
| --- | --- | --- |
| Full unit suite | 827 passed, zero skipped | `/private/tmp/optimization-xcode-local/QuickProfileVerified.xcresult` (unit bundle) |
| Final profile regression run | 9 passed, including rounding across a foot boundary | `/private/tmp/optimization-xcode-local/QuickProfileBoundary.xcresult` |
| Mascot, navigation, nutrition, water, workout and rest UI flows | 6 passed | `/private/tmp/optimization-xcode-local/CompanionFinalUI.xcresult` |
| Final first-launch setup flow | 1 passed, selected 20-minute target appears on Today | `/private/tmp/optimization-xcode-local/QuickSetupFinal.xcresult` |
| Release build, generic iOS destination | Passed with zero warnings; iPhone, Watch, complications and Live Activity targets | `.work/logs/companion-profile-release.log` |
| Schema parity, asset checks and whitespace checks | Passed | `scripts/check_schema_parity.sh`, `scripts/check_assets.sh`, `git diff --check` |

The older combined result bundles retain the onboarding input-focus failure
found during review. It is resolved by the final first-launch run above.
Across these runs, all 834 distinct tests pass (827 unit tests and 7 UI tests);
the 9 profile retests are not counted again.

Reviewed screenshots of both setup steps and all four companion reactions.
The first profile screen fits all fields and its primary action at the tested
default text size. Companion choices fit in a two-column grid, with a single
column at accessibility text sizes. Pose changes no longer blend old artwork
through a long idle animation.

Local review images are in
`/private/tmp/optimization-xcode-local/companion-review/`.
Simulator tests use an in-memory profile. Release verification used
`CODE_SIGNING_ALLOWED=NO`; no device installation or TestFlight release was
performed. Real-device battery, Health permissions and cross-device iCloud
sync were not measured by these checks.
