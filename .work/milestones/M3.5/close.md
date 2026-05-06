# M3.5 Engagement Engine — Close Notes

## Status

DoD satisfied. All 11 tasks shipped. Build green, 207 tests pass, zero warnings on Xcode 16. Closing as `m3.5-complete`.

## Quality Gate Results (run 2026-05-06)

| Gate | Result | Evidence |
|------|--------|----------|
| iOS build (iPhone 17 Pro, iOS 26.4.1) | PASS | `xcodebuild -scheme PersonalOptimization build` -> BUILD SUCCEEDED |
| Watch build (Apple Watch Ultra 3, watchOS 26.4) | PASS | `xcodebuild -scheme PersonalOptimizationWatch build` -> BUILD SUCCEEDED |
| Zero warnings | PASS | grep filter on full build log returned no `warning:` or `error:` |
| Unit tests | PASS | 207 tests, 0 failures, 0 unexpected (≈7s) |
| Performance: CharacterStateService.gatherInputs <30ms | PASS | `test_perf_recompute_under30msWithModerateData` baseline ≈15ms median |
| Performance: schedule resolution <50ms | PASS | preserved from M1 |
| Performance: streak calc 365-day <20ms | PASS | preserved from M3 |
| Mascot asset memory <8MB | PASS | `test_mascotAssets_totalBackingMemoryUnder8MB` |
| All 8 mascot PNGs load | PASS | `test_allMascotAssets_loadFromMainBundle` |
| PrivacyInfo.xcprivacy unchanged (no new HK/CK/network usage) | PASS | only additive SwiftData entities |

## Task-by-task DoD audit

| # | Task | Result |
|---|------|--------|
| 1 | SchemaV2 + migration | StreakCounter, WorkoutEvent, CompletionHistory, FreezeApplication; SchemaV2 + AppMigrationPlan with lightweight stage; iOS, Watch, AppIntents, complications containers all on V2; on-disk V1->V2 migration test passes |
| 2 | StreakService | recompute, applyFreeze, resetMonthlyFreezes, activateSickDay/TravelMode, recordWorkoutLedger; 15 tests |
| 3 | CharacterStateService | @Observable singleton, 30s timer + write-driven recompute, 8-state precedence resolver, transition logging; 16 tests |
| 4 | CharacterView | breathing, alert pulse on urgent/achievement, reduce-motion aware, transition |
| 5 | Wire mascot to TodayView + watch | 200pt header gated on profile.mascotEnabled; new MascotComplication for circular/inline/corner |
| 6 | DailySummaryService master metric | ProtocolAdherenceTally with displayText "n/m of today's protocol complete"; sub-metrics in ProtocolDetailView; 6 tests |
| 7 | Adaptive notification timing | AdaptiveNotificationTiming pure resolver activates at 14 days; CompletionHistoryWriter wired into Fasting/Hydration/Learning/Lift/Basketball/Swim end paths; 6 tests |
| 8 | IdentityCopy refactor | enum centralizes confirmations, banners, notification copy; NotificationService and TodayView use it |
| 9 | Sick day + Travel mode UI | Settings "Streak grace" section, sick toggle, travel stepper + activate, end-travel button; banners on TodayView |
| 10 | Mascot enabled toggle | already-bound profile.mascotEnabled now drives CharacterView visibility on TodayView |
| 11 | Tests + perf benchmarks | 56 new tests (43 service-level + 4 integration + 8 schema + 1 streak edge); perf measure inside CharacterStateServiceTests |

## Architectural deviations (documented for trail)

1. **Dropped `@Attribute(.unique)` on StreakCounter.domain**. CloudKit doesn't support unique constraints; uniqueness enforced at the service layer (`StreakService.upsertCounter`). Same pattern is used elsewhere (DailyLog, LearningStreak).

2. **Added FreezeApplication entity** (5th new @Model) beyond the 4 the PIVOT_SPEC named. Necessary because `WorkoutEvent` only covers workouts, and freezes can apply to any of the 5 streak domains. Cleaner than overloading `WorkoutEvent.source`.

3. **`StreakDomain.protocolAdherence` rather than `protocol`**. Swift `protocol` is reserved; rawValue stays `"protocol"` so on-disk values match the spec.

4. **Travel/Sick activation writes WorkoutEvent + FreezeApplication ledger entries** rather than relying solely on profile flags. This is more honest (no "today still counts via flag" magic) and lets the streak walker preserve historical streaks correctly.

## Commits in M3.5 (since `m3-complete`)

```
7b05ab3 test(M3.5): integration tests for engagement engine + asset memory check
50c982d feat(M3.5): Sick day + Travel mode + Mascot toggle UI in Settings
e240595 feat(M3.5): IdentityCopy enum centralizes identity-framed strings
4f16d86 feat(M3.5): adaptive notification timing + completion ledger writes
9330dc4 feat(M3.5): DailySummaryService master metric on TodayView
572c0fd feat(M3.5): wire mascot to TodayView header and watch CircularComplication
8f610b7 feat(M3.5): CharacterView with breathing, alert pulse, reduce-motion aware
80e3537 feat(M3.5): CharacterStateService with 8-state precedence resolver
1601353 feat(M3.5): StreakService with freezes, travel/sick grace, and monthly reset
dc675d5 feat(M3.5): SchemaV2 with engagement-engine entities and migration
```

## Closing Action

Tag `m3.5-complete` on this commit. Stop. Per the overnight runbook do NOT advance to M4.
