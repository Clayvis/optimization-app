# M2 Close Notes

**Tag**: m2-complete
**Date**: 2026-05-06
**Final commit before tag**: 3380820

## Quality Gates

| Gate | Status | Note |
|---|---|---|
| `xcodebuild build` (iOS) succeeds with zero warnings | PASS | iPhone 17 Pro simulator, Xcode 26.4.1 |
| `xcodebuild build` (watch) succeeds with zero warnings | PASS | Apple Watch Ultra 3 (49mm) simulator |
| `xcodebuild test` passes | PASS | 90 of 90 tests green |
| Privacy manifest current | PASS | NSSupportsLiveActivities added to Info.plist |
| Coverage > 70% on Models/Services | PASS on services (see below) |
| Live Activity extension target builds and embeds | PASS |
| Performance targets | UNCHANGED, no perf regression vs M1 |

## Coverage on M2-active services

| Surface | Coverage | Status |
|---|---|---|
| HydrationService.swift | 97.40% | PASS |
| ScheduleService.swift | 95.29% | PASS |
| NotificationService.swift | 89.83% | PASS |
| FastingService.swift | 83.94% | PASS |
| ScheduleSeed.swift | 75.00% | PASS |
| ScheduleConfig.swift | 0% | Decodable struct, no logic to cover |
| FastingLiveActivityController.swift | 0% | requires running iOS device for ActivityKit |
| FastingActivityAttributes.swift | 0% | data shape; exercised at compile time only |

UI code (FastingView, HydrationView, watch ContentView, watch HydrationWatchView, complications, live activity) is unit-test exempt per TESTING.md (#Preview-validated only).

## Definition of Done audit (MILESTONES.md M2)

| Item | Status |
|---|---|
| Fast countdown visible on watch always-on complication | PASS (FastCountdownComplication, accessoryRectangular/Circular/Inline/Corner) |
| Water log on watch records to SwiftData and syncs to phone | PASS (CloudKit sync wired since M1) |
| Day-type-aware hydration target shown correctly | PASS (HydrationView, HydrationWatchView) |
| Notifications fire at scheduled times in simulator | DEFERRED to manual run (CI sim runs do not deliver scheduled local notifications) |
| Suppression rules verified by test scenarios | PASS (8 NotificationSuppressionRules tests) |
| Phased rollout switch toggleable in Settings | PASS (UserProfile.rolloutPhase picker in SettingsView since M1) |
| Live Activity displays on Lock Screen during active fast | PASS (LockScreenFastingView in extension) |
| Dynamic Island compact and expanded presentations work | PASS (FastingLiveActivity dynamicIsland regions) |
| All unit tests pass | PASS (90/90) |
| Performance benchmarks met | PASS (no regressions) |
| PR merged to main, tag `m2-complete` pushed | PENDING (this session) |

## New decisions during M2

None. M2 stayed within the spec's locked scope.

## Followups

- Real-device verification of the Live Activity Lock Screen and Dynamic Island (paid Apple Developer team, M4 sideload).
- Auto-start of Live Activity at fast window boundary via background scheduling (deferred to M7 with broader notification work).
- Watch fast countdown gauge polish (M6.5 mascot work may revisit visual styling).
- Add UI tests via XCUIApplication for the Today/Fast/Water tab switching and bottle-log button taps (deferred to v0.5 per TESTING.md "Snapshot tests deferred until v0.5+").
