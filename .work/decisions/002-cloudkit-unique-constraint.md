# Decision 002: Remove SwiftData .unique constraints for CloudKit compatibility

**Status**: APPLIED 2026-05-06 (forced by CloudKit, no realistic alternative)
**Date**: 2026-05-06
**Milestone**: M1, Phase 3
**Related**: Decision 001 (CloudKit wired now per option A)

## Context

DATA_MODELS.md declares `@Attribute(.unique)` on three entities:

- `DailyLog.date`
- `LabDraw.date`
- `LearningStreak.module`

CloudKit-mirrored SwiftData stores reject unique constraints. Boot-time error:

> CloudKit integration does not support unique constraints. The following entities are constrained: ...

The ModelContainer fails to load and the app crashes on launch.

## Constraint already noted by spec

DATA_MODELS.md note 4 reads:

> `DailyLog.date`, `LabDraw.date`, and `LearningStreak.module` are uniqued. Inserting duplicates is a programmer error.

The spec frames uniqueness as a programmer contract, not a hard storage guarantee. The `.unique` decoration was an attempt to enforce it at the SwiftData level. CloudKit makes that impossible.

## Decision

Remove `@Attribute(.unique)` from the three fields. Enforce uniqueness in the service layer:

- `DailyLog`: `DailyLogRepository.upsert(forDate:)` fetches by date, updates if exists, inserts otherwise.
- `LabDraw`: `BiomarkerService.saveDraw(date:values:)` same upsert pattern (M5).
- `LearningStreak`: `LearningStreakService.streak(for module: String)` upserts by module (M3).

Each service must also expose a single canonical fetch path so callers cannot end-run around the upsert.

## Alternatives considered

### B. Drop CloudKit for M1 (option B from earlier framing)

Use `cloudKitDatabase: .none`. Re-enable when paid Apple Developer team is in place pre-M7. This would let `.unique` stay.

Rejected: user picked option A. Wiring CloudKit now and accepting its constraints keeps the diff small at upgrade time. The data integrity loss is negligible for a single-user app where all writes flow through service classes.

### C. Composite primary key

Not supported by CloudKit either. Rejected.

## Trade-offs accepted

- Loss of storage-layer uniqueness guarantee. If a service forgets to upsert, two `DailyLog` rows for the same day can exist. Mitigation: every write goes through a service method documented to upsert.
- Test fixtures need to use date-of-day at consistent times to avoid accidental duplicates during multi-test runs against the same in-memory container (current tests reset per-test so this is fine).

## Impact

- Code removed: three `@Attribute(.unique)` declarations.
- Code added: upsert logic in services as each is built (M1 for DailyLog if needed; M3 for LearningStreak; M5 for LabDraw).
- DATA_MODELS.md: not edited (it's locked seed doc); this decision record captures the deviation.
