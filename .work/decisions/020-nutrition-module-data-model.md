# 020 — Nutrition module: data model and integration choices

Date: 2026-09-09
Status: accepted (Phase 1)
Source spec: docs/planning/NUTRITION_MODULE_HANDOFF.md

## Context

The nutrition handoff specifies FoodEntry as a relationship off DailyLog and
FoodItem, SavedMeal/Recipe as relationship trees, and a set of P0
prerequisites (DailyLog uniqueness, hardcoded timezones, schema parity,
HealthKit background delivery). At the current tree those prerequisites are
already closed: AppSchema + scripts/check_schema_parity.sh unify the schema,
DailyLogStore is the single day-keyed writer (duplicates are merged and
superseded, never deleted), UserCalendar follows the device timezone, and
HealthKitObserverService already lands activeEnergyBurned in DailyLog.

## Decisions

1. **FoodEntry is day-keyed, not a DailyLog relationship.** `FoodEntry.date`
   is the user-calendar start of day (same convention as WorkoutEvent and
   HydrationEntry). DailyLog duplicates are merged and marked superseded, so a
   relationship could strand entries on a tombstone row. Day sums are a
   single-table predicate fetch.
2. **FoodEntry snapshots the food's per-serving macros at log time** and keeps
   `foodID` as a soft link to FoodItem. Editing or deleting a food later never
   rewrites history, the day summary needs no join, and an entry that arrives
   through CloudKit before its FoodItem still renders. Same for SavedMealItem.
3. **SavedMeal → SavedMealItem uses the LiftSession relationship pattern**
   (`@Relationship(deleteRule: .cascade, inverse:)`, optional array with a
   default) because it is the one relationship shape already proven against
   CloudKit in this codebase.
4. **Recipe is deferred to Phase 4** as its own additive schema bump. Shipping
   an unused entity in Phase 1 adds CloudKit surface with no test coverage.
5. **Enums store as String raw values** (WorkoutEvent convention). No
   `@Attribute(.unique)` anywhere (CloudKit forbids it).
6. **NutritionTargets keeps history** by `effectiveFrom` (start of day). The
   row in force for a day is the latest `effectiveFrom <= day`. Saving targets
   on a day that already has a row updates it in place; otherwise a new row
   starts that day so past days keep the targets that applied then.
7. **HealthKit writes are dispatched off the logging path** exactly like
   SessionLifecycleService.dispatchHealthKitWorkout: detached task, three
   attempts with backoff, exhausted failures persisted as HealthKitWriteFailure
   (activityTypeRaw 0, errorDescription prefixed "Nutrition") so the existing
   Today health card surfaces them. Samples are grouped in an HKCorrelation
   (.food) and tagged with HKMetadataKeyExternalUUID = entry id; edit and delete
   remove by that tag and by the stored sample UUIDs before rewriting.
8. **Nutrition authorization is a separate request** (dietary share + read,
   activeEnergyBurned and bodyMass read) made on first open of the nutrition
   day view, not at launch and not folded into the workout "Connect" request.
   The Health mirror runs only while sharing is authorized; unanswered or
   refused access leaves entries local (healthKitSyncedAt nil) with no
   failure row, so a refusal never becomes a "sync needs attention" nag.
   Backfilling unsynced entries after a later grant is a Phase 2 item.
9. **Placement.** The tab bar is full (5 tabs; a 6th would push iOS into a
   "More" tab). Nutrition gets a compact Today card (protein remaining
   headline, calories remaining) and a Dojo hub tile; both push
   NutritionDayView. Ordering on Today: the daily workout card alone fills
   the iPhone 17 Pro viewport (688 of 874 pt in the UI-test snapshot), so a
   card below it fails the spec's "visible without scrolling" criterion.
   Setting nutrition targets is the opt-in signal: once any NutritionTargets
   row exists the nutrition card leads Today; until then the workout card
   keeps the top and the "log your first meal" card follows it.
10. **Retention.** Deleting a FoodEntry is an explicit user action (allowed
    list). No timer, background, or sync path deletes nutrition rows.

## Consequences

- SchemaV11 adds FoodItem, FoodEntry, SavedMeal, SavedMealItem,
  NutritionTargets. Lightweight migration from V10.
- HealthKitServiceProtocol gains nutrition methods with protocol-extension
  defaults so existing fakes stay source-compatible.
- Phase 2 (recents, frequents, saved meals, copy day) needs no schema change.
