# 011 — CharacterStateLog retention exception (proposed; awaits user approval)

Status: PROPOSED. **Requires user approval before merging the prune execution code.** Recorded against IMPROVEMENT_IMPLEMENTATION_PLAN.md Item 7.

## Context

CLAUDE.md's "Data Retention" section pins SwiftData retention as permanent. The full activity history is preserved forever in iCloud-backed private database. TrendAnalyticsService and CoachService v2 depend on this guarantee to produce year-plus historical context.

`CharacterStateLog` rows are inserted on every state transition (CharacterStateService.swift:113). Over a year of usage with 5-20 transitions per day, the table grows to thousands of rows. The rows are individually small but the unbounded growth is at odds with the existing per-day rollup pattern used by `ActivityArchive`.

`ActivityArchive.dominantMascotState` is already populated by `ActivityArchiveService.rollupDay` (verified: ScheduleConfig.swift earlier read; the archive captures the day's prevailing mascot state). So the prune-after-rollup pattern is supported by the existing rollup data flow.

## Proposed exception

`CharacterStateLog` rows older than **90 days** are pruned IFF the corresponding `ActivityArchive` row for that day exists and its `dominantMascotState` is non-empty.

Rationale:
- 90 days preserves the full ramp-up + first-stability window for the user.
- The `dominantMascotState` field is the user-visible rollup; once it's recorded, the per-transition log adds no analytic value the user can see.
- Source-of-truth `DailyLog` / `LiftSession` / `SwimSession` / `BasketballSession` / `WorkoutEvent` rows are **untouched** by this proposal — they continue to live forever.
- Skips the prune for any day whose archive row is missing or whose `dominantMascotState` is empty, so a pruning bug never deletes data not rolled-up.

## Allowed deletion contract (per CLAUDE.md)

CLAUDE.md currently lists four explicit user-action deletion paths:
- ScheduleEditorView swipe-to-delete
- ScheduleSeed.resetToDefault
- JSONImportService.replaceAll
- KeychainService.deleteApiKey

This proposal adds a fifth, system-triggered path:
- `ActivityArchiveService.pruneCharacterStateLog(olderThanDays:asOf:)` invoked from `ArchiveBackgroundScheduler.handle` after `backfillChunked`. Idempotent. Guarded by the rollup-row check.

## What is NOT in scope

- No pruning of `DailyLog`, session tables, biomarkers, lab draws, completion history, freeze applications, milestones, achievements.
- No TTL pruning of `CoachInsight`, `CoachMemory`, `LapseEvent` (these have their own retention semantics governed elsewhere).
- No remote opt-in/opt-out toggle — if the user wants to keep raw CharacterStateLog rows forever, they can disable the BG task entirely or the next PR can add a Settings toggle.

## Implementation sketch (NOT executed until approved)

```swift
// In ActivityArchiveService.swift
@discardableResult
func pruneCharacterStateLog(olderThanDays cutoffDays: Int = 90,
                             asOf: Date = Date()) throws -> Int {
    let cal = calendar()
    guard let cutoffDate = cal.date(byAdding: .day, value: -cutoffDays, to: cal.startOfDay(for: asOf)) else { return 0 }
    let oldLogs = (try? modelContext.fetch(
        FetchDescriptor<CharacterStateLog>(predicate: #Predicate { $0.timestamp < cutoffDate })
    )) ?? []
    guard !oldLogs.isEmpty else { return 0 }

    let grouped = Dictionary(grouping: oldLogs) { cal.startOfDay(for: $0.timestamp) }
    var deleted = 0
    for (day, logsForDay) in grouped {
        let archive = (try? modelContext.fetch(
            FetchDescriptor<ActivityArchive>(predicate: #Predicate { $0.date == day })
        ))?.first
        guard let archive, !archive.dominantMascotState.isEmpty else { continue }
        for log in logsForDay {
            modelContext.delete(log)
            deleted += 1
        }
    }
    try modelContext.save()
    return deleted
}
```

Wire into `ArchiveBackgroundScheduler.handle`'s `do` block immediately after `backfillChunked` succeeds:

```swift
let pruned = try service.pruneCharacterStateLog()
taskLog.summary = "wrote \(result.written) archive rows, pruned \(pruned) character logs"
```

## Decision needed from Clay

Approve the 90-day exception with the rollup-gate? If yes:
- Land the code in a follow-up commit.
- Update CLAUDE.md "Data Retention" to add this fifth allowed deletion path.

If no:
- Add a Settings toggle "Keep character-state log forever" instead, default on, that bypasses the prune.
- Or just leave CharacterStateLog growing unbounded (the storage cost is minimal — kilobytes per year).
