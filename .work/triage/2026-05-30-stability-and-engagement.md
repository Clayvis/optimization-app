# Triage and targeted-refactor plan: stability + engagement

Date: 2026-05-30. Owner: Clay. Scope decision (confirmed): fix the crash now AND produce this plan in parallel; targeted hardening only (no architecture change); engagement stays within the locked Design Principles; crash discovered by static audit.

Source: full static audit of the main tree (iOS, Watch, Complications, Live Activity). Worktrees under `.claude/worktrees/` excluded. The codebase is disciplined: every `try?` carries its justification comment, no `print()`, no Combine, no `nonisolated(unsafe)`, no force-unwrap of optionals in live code, no TODO/FIXME/HACK. The risk is concentrated, not diffuse.

## 0. Shipped in this pass (crash fix)

The two launch `fatalError` sites are replaced with a non-destructive recovery ladder. See decision `012-modelcontainer-recovery-ladder.md`. Files: `PersistenceBootstrap.swift` (new), `PersistenceRecoveryView.swift` (new), `PersistenceBootstrapTests.swift` (new), `PersonalOptimizationApp.swift`, `PersonalOptimizationWatchApp.swift`, `RootView.swift`. Not yet built (no iOS toolchain in the agent sandbox); Quality Gate 1-3 are Clay's to run.

## 1. Severity-ranked findings

P0 = crash or data-loss risk. P1 = spec violation or broken feature. P2 = correctness/latent. P3 = polish.

| ID | Sev | Finding | Location | Status |
|----|-----|---------|----------|--------|
| C1 | P0 | `fatalError` on store-open failure (prime crash) | App.swift:131, WatchApp.swift:40 | FIXED this pass |
| R1 | P0 | Launch-path dedupe delete can drop a DailyLog row whose data was not fully merged | DailyLogStore.swift:75 (via App.swift launch) | Needs decision |
| R2 | P0 | `purgeStale` deletes ScheduleGenerationRun >30d on launch; retention violation if wired | ScheduleGenerationRun.swift:48-59 | Dormant (0 call sites) |
| C2 | P1 | CloudKit + NotificationCenter recompute storm contends on main-actor SwiftData context | HealthKitObserverService:150 -> ReactiveRecomputeService:38 + CharacterStateService:92 | Plan |
| W1 | P1 | Learning-reminder feature has ZERO call sites; never schedules | LearningReminderInstaller/Scheduler | Plan |
| W2 | P1 | Notifications built from device calendar, not `UserProfile.timezone`; wrong wall-clock hour off-JST | NotificationService.swift:206,224,263,283 | Plan |
| W3 | P1 | No cancel-before-schedule; duplicate pings can stack; violates "one nudge per behavior per day" | NotificationService.swift:198,216,255,275 | Plan |
| C3 | P1 | Internal event bus uses NotificationCenter where spec mandates AsyncStream | 7 sites (see section 3) | Plan |
| R3 | P2 | CoachMemory TTL prune runs on a read path (`active(asOf:)`) | CoachMemoryService.swift:93 | Needs decision |
| W4 | P2 | AdaptiveNotificationTiming implemented but unwired; "personalize after day 14" not applied | AdaptiveNotificationTiming.swift | Plan |
| W5 | P2 | Raw `±86400` date math breaks across DST (no impact on JST, breaks for travel/other users) | FastingService.swift:84,98,155 | Plan |
| W6 | P3 | Evening hydration check hardcodes `TimeZone.current`, ignoring passed timezone | CharacterStateService.swift:335-342 | Plan |
| R4 | P3 | CoachMemory key-dedupe delete on add (user-initiated, undocumented) | CoachMemoryService.swift:47 | Document |
| R5 | P3 | WeeklyReflection delete-on-regenerate (user-triggered, derived row) | WeeklyReflectionService.swift:44 | Document |
| E1 | P3 | `try?` justification comment slightly inaccurate (no swallow risk) | ArchiveBackgroundScheduler.swift:90,100 | Polish |

Decision-doc 011 (CharacterStateLog prune) was verified NOT implemented: no source-row deletion exists. Retention of source-of-truth rows is currently intact except for R1.

## 2. Retention (decisions required before I touch these)

CLAUDE.md lists exactly four allowed deletion paths (ScheduleEditorView swipe, `ScheduleSeed.resetToDefault`, `JSONImportService.replaceAll`, `KeychainService.deleteApiKey`). The following run outside that list. Per CLAUDE.md these are load-bearing, so I will not change behavior without sign-off:

- R1 `DailyLogDedupeOnce` (DailyLogStore.swift:75): runs at launch, UserDefaults-gated one-shot, merges duplicate-day rows into a canonical row then deletes the duplicate. Risk: if `merge()` misses a field, or the user changed timezone between the rows being created, the deleted row carried data the survivor did not. Options: (a) keep, add a field-completeness assertion + log before delete; (b) convert to non-destructive (mark duplicates with a `supersededAt` flag, never delete, let analytics ignore them); (c) leave as-is. Recommendation: (b), it satisfies permanent-retention literally.
- R2 `purgeStale` (ScheduleGenerationRun.swift): dormant. Recommendation: delete the method, or convert to a flag, so a future caller cannot reintroduce a retention violation. The doc comment claims "called once per app launch" but no caller exists; the comment is a trap.
- R3 `CoachMemory.pruneExpired` (CoachMemoryService.swift:93): TTL prune on a read path. CoachMemory has an `expiresAt` by design but CLAUDE.md grants it no exception. Options: (a) add a documented fifth retention exception for TTL memory (like decision 011 proposes for CharacterStateLog); (b) stop deleting, filter expired rows at read time instead. Recommendation: (b).

## 3. Concurrency: NotificationCenter to AsyncStream (C2, C3)

CLAUDE.md Concurrency Model: "Use `AsyncStream` for HealthKit observation, never NotificationCenter wrappers." The cross-component event bus currently violates this:

- Posters: HealthKitObserverService:150, HealthKitSyncService:172, NotificationActionHandler:92, App.swift:102, WatchApp.swift:33, TodayView:265, RootView:56.
- Observers: CharacterStateService:92,97, ReactiveRecomputeService:38.

This is also the C2 crash/contention vector: a Garmin/Withings sample burst fans many `.dailyLogsRecomputed` posts to two main-actor observers that each run SwiftData fetches under a concurrent CloudKit merge. The 15s/60s throttles mitigate but do not serialize.

Targeted fix (no architecture change): introduce one `@MainActor` event-bus type exposing a single `AsyncStream<DomainEvent>` (replacing the named `Notification.Name` posts), with a coalescing/debounce on `.dailyLogsRecomputed` so a burst collapses to one recompute. This removes the NotificationCenter dependency, satisfies the spec, and serializes the recompute. The `WatchConnectivityService.lastEventStream` is already an AsyncStream, so this aligns the internal half with the external half.

## 4. Workflow fixes (W1-W6)

- W1 Learning reminders: wire `LearningReminderInstaller` into the launch sequence (now `runLaunchSequence`) behind the same durability gate. Without W3 first, wiring it will duplicate, so order W3 before W1.
- W2 timezone: every `schedule*` in NotificationService must build `DateComponents` with `UserProfile.timezone` (or device tz when `travelModeFollowsDevice`), not bare `Calendar.current`. This is rule 4.
- W3 dedupe IDs: switch notification identifiers from `timeIntervalSince1970` (per-instant, never matches) to a stable `behavior+localDay` key, and call `removePendingNotificationRequests(withIdentifiers:)` before `add`. Enforces "one nudge per behavior per day."
- W4 adaptive timing: feed `AdaptiveNotificationTiming` output into the scheduler once >=14 days of history exist (Design Principle 3).
- W5 fasting date math: replace `date.addingTimeInterval(±86400)` with `Calendar.date(byAdding: .day, value: ±1)`. Rule 4. Latent for JST, real for travel.
- W6 evening hydration: pass the resolved timezone into `hydrationFarBehindEvening` instead of `TimeZone.current`.

## 5. Engagement, within the locked Design Principles ("more addicting", ethically)

The highest-leverage engagement work is not new hooks. It is finishing and wiring the ethical-engagement machinery already designed and half-built. Mapping to the seven principles:

1. Implementation intentions over reminders (Principle 1): `ImplementationIntentionService` exists. Wire `LearningReminderInstaller` (W1) and anchor nudges to trigger events (after coffee, on block start) rather than clock times. This is the single biggest adherence lever in the habit-formation literature cited in PIVOT_SPEC.
2. Streak mercy made visible (Principle 2): `StreakService` already honors freeze/sick/travel/rest-day and never fake-completes (verified). Surface "freeze available" and "streak protected" affordances so the user feels safe; fear of a broken streak is the top churn driver, and mercy that the user cannot see does not reduce it.
3. Notification minimum effective dose (Principle 3): land W2+W3+W4 so nudges fire at the right local time, never duplicate, and personalize after day 14.
4. Identity framing (Principle 4): `IdentityCopy` centralizes copy. Audit every confirmation/notification string to route through it ("You are someone who shows up" not "Task done").
5. Friction reduction (Principle 5): hydration already has lock-screen quick actions. Extend one-tap logging to fasting start/stop and learning start from the widget/complication; remove any multi-step log paths.
6. One master metric (Principle 6): `DailySummaryService` computes a single adherence number. Confirm `TodayView` foregrounds exactly that one number, sub-metrics one tap away.
7. Rewards rare and earned (Principle 7): `MilestoneRegistry` + `AchievementRegistry` exist; decision 008 (reward density day 30-90) and 009 (self-comparison narratives) and 010 (lapse-recovery proactive flow) are already on file. Finish/wire these. Keep the mascot reflecting real state only (verified clean today). Reward density should ramp, not saturate.

Net: the ethical, in-spec path to "more addicting" is to wire the dormant learning reminders, adaptive timing, implementation intentions, and the already-designed reward-density / self-comparison / lapse-recovery flows, and to make existing streak mercy visible. No variable-ratio dark patterns, no manufactured urgency, no mascot theater. This respects autonomy and the literature you already cited.

## 6. Proposed sequence (targeted hardening, no architecture change)

Phase A (stability, P0): land the crash fix (done, awaiting build); decide and apply R1/R2/R3 retention fixes.
Phase B (notifications, P1): W3 (dedupe) -> W2 (timezone) -> W1 (wire learning reminders) -> W4 (adaptive timing).
Phase C (concurrency, P1): C2/C3 event-bus to AsyncStream with coalescing.
Phase D (correctness, P2-P3): W5, W6, R4/R5 documentation, E1.
Phase E (engagement, in-spec): section 5 items, sequenced after B so nudges are correct before they are amplified.

Each phase closes with the standard Quality Gates (build zero-warning, tests, watch build, coverage >70% on Models/Services). Each behavior-changing retention item gets its own `.work/decisions/` entry like 012.

## 7. Explicitly OUT of scope (targeted hardening only)

No architecture change: SwiftData/CloudKit/WatchConnectivity/HealthKit stack stays. No new third-party dependency. No re-layout of modules. No rewrite of services. No new persistence model beyond additive flags if R1/R3 choose the non-destructive option. No Rive, no server, no multi-user (per CLAUDE.md "What NOT to Build").

## 8. Approvals needed from Clay

1. R1: pick (a) assert+log, (b) non-destructive supersede flag [recommended], or (c) leave.
2. R2: delete `purgeStale` [recommended] or convert to flag.
3. R3: (a) documented TTL exception or (b) filter-at-read [recommended].
4. Confirm Phase B ordering (W3 before W1 to avoid duplicate scheduling).
5. Confirm the section 5 engagement scope is the intended reading of "more addicting".
6. Build the crash fix and run `PersistenceBootstrapTests`; report green to close decision 012 as ACCEPTED.
