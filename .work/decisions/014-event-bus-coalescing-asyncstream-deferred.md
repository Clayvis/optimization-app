# 014 - Recompute coalescing done, AsyncStream bus migration deferred

Status: C2 IMPLEMENTED in code; C3 DEFERRED (out of scope for the chosen refactor depth). Part of the 2026-05-30 stability pass.

## Context

CLAUDE.md Concurrency Model: "Use AsyncStream for HealthKit observation, never NotificationCenter wrappers." The app's cross-component event bus is built on `NotificationCenter` (`userStateChanged`, `dailyLogsRecomputed`), which deviates from that rule and also created a main-actor contention vector (C2): a single Garmin/Withings sync delivers a burst of `dailyLogsRecomputed` posts, and CharacterStateService recomputed on every one via `force: true`, hammering the main context under a concurrent CloudKit merge.

The user chose the "targeted hardening, no architecture change" refactor depth.

## Decision

Two parts, split by the refactor-depth constraint.

C2 (done, hardening): CharacterStateService now routes `dailyLogsRecomputed` through its existing 60s cache (`force: false`) instead of forcing a recompute on every post. The first post in a burst recomputes; the rest are cache hits; the storm collapses to one recompute. `userStateChanged` (a rare user action) stays `force: true` for instant mascot feedback. ReactiveRecomputeService already coalesces via its 15s leading-edge throttle and is left as-is (its test asserts that timing). Mascot state is daily-granularity, so the up-to-60s staleness on late HK samples is irrelevant.

C3 (deferred, structural): migrating the whole `NotificationCenter` event bus to a single `@MainActor` `AsyncStream<DomainEvent>` is a structural change to cross-component messaging across ~10 files (HealthKitObserverService, HealthKitSyncService, NotificationActionHandler, ReactiveRecomputeService, CharacterStateService, both app entries, RootView, TodayView). That exceeds "targeted hardening, no architecture change." It is recorded here as the next item if the user opts into a structural-refactor pass.

## Why this is safe under the chosen scope

C2 removes the actual contention with a one-region change inside the existing pattern, no new concurrency primitives, and no test breakage (there is no CharacterStateService timing test). C3, the spec-conformance migration, carries real blast radius and is correctly gated behind an explicit depth decision rather than smuggled into a hardening pass.

## Decision needed from Clay

When ready, approve a structural-refactor pass to land C3 (NotificationCenter -> AsyncStream bus). Until then the bus stays on NotificationCenter, now without the recompute storm.
