# Workout experience changes, September 8, 2026

Today now leads with a workout win, three activity rings, a short session, and a useful coach message. The working hypothesis is that an achievable action and reliable automatic credit make returning more worthwhile than a multi-domain checklist. This is based on a source audit; retention improvement has not been measured with the user's wife.

## Experience implemented

- Move: Apple Health exercise minutes or completed local session minutes, whichever is higher. Overlapping local sessions are merged and clipped to the elapsed calendar day.
- Workout: a completed workout today. Imported Apple Health workouts count.
- Week: distinct workout days, Monday to Sunday. Default target is three, adjustable from one to seven.
- One daily workout earns 50 XP; every 250 XP advances a level. XP is derived from distinct recorded workout days, so duplicate events, repeat opens, and changing the movement goal cannot farm XP. Missed days and rest do not subtract XP.
- Choose a 5-, 10-, or 20-minute movement goal and an existing activity. Start opens a running session directly; Finish & save uses elapsed time. Distance, intensity, notes, and duration corrections are optional.
- Local daily coaching handles first use, a completed workout, a return after missed days, and recovery. It needs no API key. A voluntary rest day uses the existing DailyLog metadata, not a fake workout.
- Schedule, full protocol progress, quotes, advanced coaching, fasting, water, and learning remain accessible. The schedule and habits panels remember expansion state.
- Existing recovery signals can suggest a shorter day or rest. Historical sleep averages no longer masquerade as last night's sleep.

## Bugs addressed

1. Custom session completion used the template's full default duration, even after a short timer. It now defaults to elapsed time and freezes that duration when Finish is tapped.
2. Repeated starts could create orphan timers; repeated finishes could create duplicate workout/history/Health entries. Starts resume an unfinished same-day activity and completion is idempotent.
3. Custom session, workout credit, and completion history were separate saves. They now commit in one transaction with an error path that allows retry.
4. Start/save failures were swallowed on phone and Watch. Both now show actionable errors; finish buttons disable while saving. Watch retries retain the finished metrics.
5. Foreground/manual Health sync updated totals without importing workouts. It now imports them and notifies downstream progress consumers.
6. UUID-only import dedupe could re-import the phone's own Health export. Own-phone exports are excluded. Own-watch exports are skipped when a matching local completion exists, while Watch workouts arriving before CloudKit still receive credit. Rewards additionally dedupe at the calendar-day level.
7. A failed Health sync updated its successful-sync timestamp. Failure now preserves the prior timestamp.
8. Today could show yesterday's state after foregrounding, and milestone celebrations waited for reopening. Date refresh now follows foreground/log/sync events and milestones are evaluated after a confirmed log.
9. Today read HealthKit authorization synchronously while rendering. A stalled Health daemon could leave the launch screen visible. Authorization now refreshes off the main thread and caches its result for the view.
10. SwiftUI's automatic List button behavior triggered both Start and Rest from the workout card. Explicit borderless button styling keeps these actions independent. The card's parent accessibility identifier also masked the controls' identifiers and has been removed.
11. Finish performed another Health query before saving the workout. Saving now uses the latest collected metrics so a slow Health response cannot block local completion.

## Xcode setup and project location

- Installed Xcode 26.6 (17F113), its first-launch components, and iOS/watchOS 26.5 simulator runtimes. Command Line Tools now select `/Applications/Xcode.app/Contents/Developer`; macOS developer permissions are enabled.
- Xcode stalled in file coordination when opening the iCloud-managed Desktop project. After downloading the repository fully, moved it to `/Users/phantom/Developer/optimization-app` with the user's approval. `/Users/phantom/Desktop/projects2026/optimization-app` is a symbolic link to that active copy. Git history and local changes were preserved; repository connectivity validation passed.
- The shared scheme supplies `--unit-testing` only for Test actions. The app recognizes that argument and XCTest environment markers to use an in-memory store and skip launch side effects. Normal Run and Release behavior retain durable persistence.

## Validation

- Passed: 18 portable Swift regression scenarios, executed from the exact DailyWorkoutProgressTests scenario bodies using `bash scripts/check_workout_progress.sh`.
- Passed: Swift syntax parsing of all modified/new Swift files, schema parity, asset opacity (32 icons), project plist validation, and `git diff --check`.
- Added to the native XCTest suite: repeated start/finish, committed persistence, own-export dedupe, Watch-before-CloudKit ordering, invalid imports, foreground workout fetch, failed-sync timestamps, and historical sleep regression coverage.
- Added UI smoke coverage for Today → start session → Finish & save → earned daily win.
- Updated the checked-in Xcode project so Release builds include the new source files and tests. No new dependencies or SwiftData schema changes.

Native verification continued after installing Xcode:

- The iPhone and embedded Watch/extension Debug simulator build passed. The current source also passed a Release build for generic iOS devices with zero warnings (`.work/logs/release-build.log`). Device code signing was disabled for this compilation check.
- The native unit suite on the final source: 769 tests, zero failures, no skipped tests with the ad-hoc signed simulator host (2026-09-09 08:40 JST, repeated at 09:41 JST on the same Xcode 26.6 / iOS 26.5 setup). Zero non-exempt warnings. The earlier unsigned run skipped five Keychain tests.
- All four UI smoke tests passed on the relocated project: primary navigation, quick water logging, workout start/save/reward, and rest without starting a workout (08:40 and 09:32 JST). They include regression assertions for the List button issue.
- Release build for generic iOS devices on the final source (09:33 JST): zero warnings; app, Live Activity, Watch app, and Watch complications all linked. Device code signing was disabled for this compilation check.
- The intermittent unit-test-host launch failure was an environment flake, not a code fault. xcodebuild occasionally launched the host with no arguments and no XCTest environment (`launchctl procinfo` on the host reported `argument count = 1`, and no XCTest images were loaded). An unsigned host then crashed on the production launch path (the `signal trap before establishing connection` error); a signed host idled until xcodebuild gave up. Shutting the simulator down and rerunning cleared it. TESTING.md documents the check and the workaround.
- Xcode's UI-test metadata extraction reports a missing AppIntents dependency warning in the test bundle. Application Release compilation has no warnings.

Physical-device HealthKit/CloudKit behavior, VoiceOver, and actual retention still need acceptance testing. Nothing has been installed on a physical device or distributed.

## Device acceptance checks

1. Open Today with Health denied and no API key. A useful coach message and a workout action must remain available.
2. Pick five minutes, start Walking, and finish after a shorter elapsed interval. Confirm duration reflects elapsed time, one workout is saved, and exactly 50 XP is earned for the day. Reopen without gaining more XP.
3. Record a workout in Apple Workouts, then foreground this app. Verify automatic workout credit, including when CloudKit is delayed.
4. Choose rest, relaunch, and confirm that plan remains for today without a fake workout or XP award. Check tomorrow resets the rest choice.
5. Check small iPhone layouts, accessibility text sizes, VoiceOver labels, and reduced motion. Verify the start action is easy to reach.
6. Test the next local midnight and a timezone change on both devices. Existing Watch widgets still show the legacy protocol metric; the new workout rings and XP currently lead on iPhone Today.

The useful outcome to evaluate next is how easily she can choose, finish, and feel credited for a workout, along with whether she finds the daily coach helpful. More app opens alone would not establish that this experience is better.
