# Claude Code Handoff: PersonalOptimization App Improvements

Synthesized from three independent reviews (ChatGPT architecture review, Gemini follow-up review, and a direct code audit by Claude) plus a re-read of the repo at the current M3.7 state. Tasks are P0 to P3 by impact, with file paths, line numbers, acceptance criteria, and dependency order.

Ground rules:
- Each task lists the files to touch and an acceptance test.
- No new third-party dependencies. Apple frameworks only.
- Swift 6 strict concurrency. Decision records under `.work/decisions/<id>-<topic>.md` for any change that contradicts `ARCHITECTURE.md`.
- All migrations remain additive. No destructive schema changes.
- Run `xcodebuild test -scheme PersonalOptimization` after every task. Watch builds with `-scheme PersonalOptimizationWatch -destination 'platform=watchOS Simulator,name=Apple Watch Ultra 2 (49mm)'`.

---

## 0. Executive Summary

The repo is in a strong place architecturally. The mascot system, identity-framed copy, AI cost guardrails, watch parity, and zero-dependency stance are all working. Three buckets of issues are blocking it from being TestFlight-stable, and a fourth bucket is leaving retention leverage on the table.

**Bucket A: data integrity bombs.** The three targets that share the CloudKit container (iPhone, Watch, Watch Complications) declare three different SwiftData schemas. DailyLog rows are created from 8 different call sites with inconsistent timezone logic and no uniqueness constraint. Together these almost guarantee duplicate or corrupted rows after the first cross-device sync once the user travels or upgrades the watch app first.

**Bucket B: HealthKit pipeline is half-built.** Background delivery entitlement is on, but nothing in code calls `enableBackgroundDelivery` or installs an `HKObserverQuery`. Daily adherence and mascot state silently lag whatever the user last opened. Late-arriving samples (Garmin, Strava, Withings) retroactively change yesterday's score but nothing recomputes it.

**Bucket C: battery posture is fragile.** Two `Timer.scheduledTimer(withTimeInterval: 30, repeats: true)` instances drive recompute loops that issue multiple unbounded `FetchDescriptor` fetches each cycle. The Watch idle home has a tighter posture but still depends on a 30-second character-state recompute on the phone side.

**Bucket D: AI/API resilience is thin.** ClaudeAPIClient is single-shot with no retry, no token-budget cap, hardcoded model strings, and the API key lives in iCloud-synced keychain since M4.2 (so it now travels to every Apple device on the iCloud account including a stolen Mac).

The 22 retention opportunities in `V1_OPPORTUNITIES.md` are valid and well-researched. They should wait until the four buckets above are closed.

---

## P0: Critical Correctness Fixes

These must land before any new feature work or TestFlight build.

### P0-1. Unify schema version across all targets

**Problem.** Three targets that share the same CloudKit container declare three different schemas:

```
PersonalOptimization/PersonalOptimizationApp.swift:8          SchemaV9
PersonalOptimizationWatch/PersonalOptimizationWatchApp.swift:8 SchemaV3
PersonalOptimizationWatchComplications/*.swift               SchemaV8
PersonalOptimization/AppIntents/StartCurrentBlockWorkoutIntent.swift:39  SchemaV8
PersonalOptimization/Views/RootView.swift:59                  SchemaV9 (preview, OK)
PersonalOptimization/Modules/Fasting/Views/FastingView.swift:319   SchemaV8 (preview)
PersonalOptimization/Modules/Hydration/Views/HydrationView.swift:479 SchemaV8 (preview)
PersonalOptimization/Modules/Schedule/Views/ScheduleEditorView.swift:319 SchemaV8 (preview)
PersonalOptimization/Views/SettingsView.swift:575             SchemaV8 (preview)
PersonalOptimization/Views/TodayView.swift:557                SchemaV8 (preview)
```

The Watch is six schema versions behind the phone. Once CloudKit syncs a V9 record to the Watch, SwiftData has to decide what to do with fields the Watch's schema does not know about. In the best case those fields disappear when the watch saves the record back. In the worst case the merge fails silently.

**Fix.**
1. Create `PersonalOptimization/Models/AppSchema.swift`:

   ```swift
   import SwiftData
   enum AppSchema {
       static let current: any VersionedSchema.Type = SchemaV9.self
       static func schema() -> Schema { Schema(versionedSchema: current) }
   }
   ```

2. Replace every `Schema(versionedSchema: SchemaVN.self)` reference in non-preview code with `AppSchema.schema()`. Add a unit test that fails if any production target file references `SchemaV` directly outside the migration plan and the `AppSchema` file.

3. Add `PersonalOptimization/Models/AppSchema.swift` to the source paths for the Watch, Watch Complications, and App Intents targets in `project.yml`.

4. Regenerate the Xcode project with `xcodegen`.

5. Add a smoke test that opens a ModelContainer with each target's expected schema and confirms `currentVersion == SchemaV9.versionIdentifier`.

**Acceptance.**
- `grep -rn "SchemaV[0-9]" --include="*.swift" PersonalOptimization PersonalOptimizationWatch PersonalOptimizationWatchComplications PersonalOptimizationLiveActivity | grep -v -e "Models/Schema" -e "Models/AppSchema" -e "#Preview" -e "previewContainer"` returns nothing.
- All targets compile.
- App launches on phone and watch simulators against a fresh CloudKit container without crashing.

### P0-2. DailyLog uniqueness and a single writer

**Problem.** Eight call sites create `DailyLog` rows:

```
PersonalOptimization/AppIntents/QuickLogIntents.swift:156
PersonalOptimization/Modules/Fasting/FastingService.swift:273
PersonalOptimization/Modules/Learning/LearningService.swift:77
PersonalOptimization/Modules/Training/Basketball/BasketballService.swift:53
PersonalOptimization/Modules/Hydration/HydrationService.swift:191
PersonalOptimization/Services/HealthKitSyncService.swift:143
PersonalOptimization/Services/JSONImportService.swift:206
PersonalOptimizationWatch/Views/LearningWatchView.swift:103
```

`DailyLog.date` has no `@Attribute(.unique)`. The `init(date:)` uses `Calendar.current.startOfDay(for:)` which respects the device timezone. Many writers explicitly set the timezone to `Asia/Tokyo`. `HealthKitSyncService.ensureLog` uses `.current` (line 137). When Clay leaves OKA for the US, two different writers can create two different `DailyLog` rows for the same calendar day, one keyed to JST midnight and one to PST midnight. CloudKit will faithfully replicate both.

**Fix.**

1. Add a uniqueness constraint to `DailyLog.date`:

   ```swift
   @Model
   final class DailyLog {
       @Attribute(.unique) var date: Date = Date.distantPast
       // ...
   }
   ```

   Note: SwiftData unique attributes interact with CloudKit. Test that this still syncs (it does in iOS 18+; CloudKit dedupes on the unique attribute).

2. Create `PersonalOptimization/Services/DailyLogStore.swift`:

   ```swift
   @MainActor
   final class DailyLogStore {
       private let modelContext: ModelContext
       private let calendar: Calendar
       init(modelContext: ModelContext, calendar: Calendar) {
           self.modelContext = modelContext
           self.calendar = calendar
       }
       /// Returns the unique DailyLog row for the calendar day containing `date`.
       /// Creates the row if needed. Idempotent across writers and timezones.
       func upsert(for date: Date) -> DailyLog {
           let day = calendar.startOfDay(for: date)
           let descriptor = FetchDescriptor<DailyLog>(
               predicate: #Predicate<DailyLog> { $0.date == day }
           )
           if let existing = (try? modelContext.fetch(descriptor))?.first { return existing }
           let new = DailyLog(date: day, calendar: calendar)
           modelContext.insert(new)
           return new
       }
   }
   ```

3. Update `DailyLog.init` to take a calendar parameter:

   ```swift
   init(date: Date, calendar: Calendar = .current) {
       self.date = calendar.startOfDay(for: date)
   }
   ```

4. Replace every `DailyLog(date: ...)` call site with `DailyLogStore(...).upsert(for: ...)`. Each module that holds a `timezone` should construct a `Calendar` once and pass it in.

5. Write a one-shot dedupe migration that runs at app launch after the schema migration. For each calendar day that has more than one DailyLog row, merge them (favor non-nil fields, sum numeric counters, max of streak-like fields) and delete the duplicates. Run it once per device, gated by a UserDefaults flag.

**Acceptance.**
- `grep -rn "DailyLog(date:" --include="*.swift" | grep -v "DailyLog.swift" | grep -v Tests` returns nothing.
- Unit test that creates the same calendar day from `.current` and `Asia/Tokyo` calendars returns the same DailyLog row.
- Unit test of the dedupe migration on a fixture with two same-day rows results in one merged row.

### P0-3. Single source of truth for the user's calendar

**Problem.** 76 hardcoded references to `"Asia/Tokyo"` across the codebase. The `UserProfile.timezone` field exists but is mostly ignored. Some services use the device's `.current` timezone, some use a hardcoded JST, some accept a constructor parameter and most callers default to JST.

When Clay flies to LAX, the schedule view (TodayView line 511), the streak boundary (HydrationService line 16), and the HealthKit sync (HealthKitSyncService line 137) will all disagree about when "today" started.

**Fix.**
1. Add `PersonalOptimization/Services/UserCalendar.swift`:

   ```swift
   @MainActor
   enum UserCalendar {
       /// Resolves the calendar from the user's profile (or .current as a last resort).
       static func current(modelContext: ModelContext) -> Calendar {
           let profile = (try? modelContext.fetch(FetchDescriptor<UserProfile>()))?.first
           var cal = Calendar(identifier: .gregorian)
           cal.timeZone = TimeZone(identifier: profile?.timezone ?? "")
               ?? TimeZone.current
           return cal
       }
       static func timezone(modelContext: ModelContext) -> TimeZone {
           current(modelContext: modelContext).timeZone
       }
   }
   ```

2. Replace every `TimeZone(identifier: "Asia/Tokyo") ?? .current` with `UserCalendar.timezone(modelContext: modelContext)`. Same for `Calendar.current` where it is being used for app logic (not display formatting).

3. Add a "Travel mode" Settings toggle that, when on, uses `TimeZone.current` so Clay can choose either pinned-JST behavior or auto-follow-device. Default off (auto-follow).

4. Migration: backfill `UserProfile.timezone` from `TimeZone.current.identifier` if the existing value is `"Asia/Tokyo"` and the device is not currently in JST. Prompt the user once via a one-time alert: "We noticed you are not in Japan right now. Should the app follow your device timezone?"

**Acceptance.**
- `grep -rn "Asia/Tokyo" --include="*.swift" | grep -v Tests | wc -l` returns under 5 (only the default seed value plus comments).
- Test: set device timezone to PST, set profile timezone to JST, confirm DailyLog day-boundary aligns with profile (not device).
- Test: enable travel mode, confirm boundaries shift to device.

### P0-4. App Group container path for SwiftData

**Problem.** The phone, watch, and complications all share `iCloud.com.rawlins.PersonalOptimization` as the CloudKit container but each writes to its own local SwiftData store URL. The Live Activity target has the App Group entitlement but no ModelContainer at all (acceptable since it uses ActivityKit attributes, not SwiftData). However, the watch complications opening a separate SwiftData URL means they get whatever CloudKit has replicated locally, not what the watch app has just written. The complication is therefore always one CloudKit cycle behind the watch app.

**Fix.**

1. Add an App Group URL helper:

   ```swift
   // PersonalOptimization/Services/AppGroupContainer.swift
   enum AppGroupContainer {
       static let identifier = "group.com.rawlins.PersonalOptimization"
       static func storeURL() -> URL? {
           FileManager.default
               .containerURL(forSecurityApplicationGroupIdentifier: identifier)?
               .appendingPathComponent("default.store")
       }
   }
   ```

2. Update all three production ModelContainer construction sites to use the same URL:

   ```swift
   let config = ModelConfiguration(
       schema: schema,
       url: AppGroupContainer.storeURL() ?? URL.applicationSupportDirectory.appending(path: "default.store"),
       cloudKitDatabase: .private("iCloud.com.rawlins.PersonalOptimization")
   )
   ```

3. Decide explicitly: phone is the source of truth for heavy aggregations. The watch reads from its local store (which CloudKit syncs from the phone). Complications read from the App Group URL so they pick up watch-app writes without waiting for CloudKit.

**Acceptance.**
- All targets boot and produce non-nil store URLs in their respective sandbox containers.
- Logging confirms the same path is used on watch and complications.

### P0-5. HealthKit background delivery is entitled but not wired

**Problem.** The entitlement `com.apple.developer.healthkit.background-delivery` is on for both phone and watch targets. `grep` for `HKObserverQuery` and `enableBackgroundDelivery` returns zero hits. The app does not actually react to new HealthKit samples in the background, it only pulls when the user opens the app (`PersonalOptimizationApp.swift:50`).

**Fix.**
1. Add `HealthKitObserverService` that registers observer queries for the high-frequency types and calls `enableBackgroundDelivery`:

   ```swift
   // PersonalOptimization/Services/HealthKitObserverService.swift
   @MainActor
   final class HealthKitObserverService {
       private let store: HKHealthStore
       private let sync: HealthKitSyncService
       private var queries: [HKObserverQuery] = []
       
       init(store: HKHealthStore, sync: HealthKitSyncService) {
           self.store = store
           self.sync = sync
       }
       
       func startObserving() async {
           let types: [HKSampleType] = [
               HKQuantityType(.bodyMass),
               HKCategoryType(.sleepAnalysis),
               HKCategoryType(.mindfulSession),
               HKObjectType.workoutType()
           ]
           for type in types {
               do {
                   try await store.enableBackgroundDelivery(for: type, frequency: .immediate)
               } catch {
                   Logger.healthkit.warning("enableBackgroundDelivery failed for \(type.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
               }
               let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
                   Task { @MainActor in
                       defer { completion() }
                       guard error == nil else { return }
                       await self?.sync.syncToday()
                       await self?.recomputeRecent(daysBack: 7)
                   }
               }
               store.execute(query)
               queries.append(query)
           }
       }
       
       func stopObserving() {
           for q in queries { store.stop(q) }
           queries.removeAll()
       }
       
       private func recomputeRecent(daysBack: Int) async {
           // For each of the last `daysBack` days, re-run HealthKitSyncService
           // and the dependent scorers (StreakService, CharacterState, Trends).
       }
   }
   ```

2. Call `startObserving()` from `PersonalOptimizationApp.swift` after authorization is granted.

3. Add a "Catching up with Apple Health..." inline status to TodayView that surfaces when `HealthKitSyncService` is running and there is no cached value yet. Use `@Observable` state on the sync service.

**Acceptance.**
- `enableBackgroundDelivery` is called once per type per process.
- HK observer queries are registered. A unit test that injects a fake HKHealthStore confirms `execute` is called for each type.
- TodayView shows a spinner when sync is mid-flight.

### P0-6. Late-arriving HealthKit data triggers retroactive recompute

**Problem.** Garmin, Strava, Withings, and Apple Watch sometimes deliver samples hours or days late. The current `HealthKitSyncService.syncToday()` only touches today's `DailyLog`. Yesterday's adherence score, mascot trigger, and streak status freeze whatever they were when the user last opened the app.

This is the "Idempotent Pipeline" point in the Gemini review. The right fix is to treat scoring as a pure function of the data.

**Fix.**
1. Extend `HealthKitSyncService` with:

   ```swift
   func sync(date: Date) async -> DailyLog { ... }
   func syncRange(days: Int = 7) async {
       let cal = UserCalendar.current(modelContext: modelContext)
       let today = cal.startOfDay(for: Date())
       for offset in 0..<days {
           guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
           _ = await sync(date: d)
       }
   }
   ```

2. When `HealthKitObserverService` fires, call `syncRange(days: 7)`, then post a notification `Notification.Name.dailyLogsRecomputed`.

3. `StreakService`, `CharacterStateService`, and `TrendAnalyticsService` listen for `dailyLogsRecomputed` and re-derive their cached values from the underlying DailyLog rows.

4. Mascot state should always be a pure function of DailyLog + StreakCounter + UserProfile + clock, never persisted as a baked field. (It already is. Confirm and add a regression test.)

**Acceptance.**
- New test: insert a 2-day-old workout into HealthKit, run sync, confirm that day's DailyLog updates and the streak counter recomputes.
- No code path writes the mascot state to a persistent "yesterday's mascot" field.

---

## P1: Architecture Hardening

### P1-1. Stop the schema version sprawl

**Problem.** Nine schema versions in roughly six milestones. SchemaV9 adds one new entity. Each version is a separate file. Lightweight migrations chain through all 8 stages, and each new field added (today via `DailyLog` for example) requires a new schema version.

The Gemini review flagged this as "Schema Version Hell". They are right.

**Fix.**
1. Adopt the "metadata blob" pattern for non-relational evolving fields:

   ```swift
   @Model
   final class DailyLog {
       // ... relational fields ...
       
       /// JSON blob for additive, non-queried fields (AI configs, experimental
       /// metrics, mascot state hints). Add fields without bumping the schema
       /// version. Decode lazily; never query by these fields.
       var metadataBlob: Data?
       
       func metadata<T: Decodable>(_ key: String, as type: T.Type) -> T? {
           guard let blob = metadataBlob,
                 let dict = try? JSONSerialization.jsonObject(with: blob) as? [String: Any],
                 let raw = dict[key] else { return nil }
           let data = try? JSONSerialization.data(withJSONObject: raw)
           return data.flatMap { try? JSONDecoder().decode(T.self, from: $0) }
       }
       
       func setMetadata<T: Encodable>(_ key: String, value: T?) {
           // ... merge into blob ...
       }
   }
   ```

2. Reserve new versioned schemas for actual entity changes (new model classes, new relationships, type changes). Document the rule in `ARCHITECTURE.md`.

3. Migrate existing low-traffic fields (`musicMinutes`, `wristTemperatureCelsius`, etc.) into the metadata blob over the next two milestones. The next time a schema bump is required, kill 3-4 V9 fields by promoting them to metadata.

**Acceptance.**
- `metadataBlob` exists on DailyLog, UserProfile, and PrescribedWorkout.
- One unit test that round-trips a custom struct through `setMetadata`/`metadata`.
- ARCHITECTURE.md updated with "metadata blob first, schema bump only for entity changes".

### P1-2. CharacterStateService: stop polling, react to events

**Problem.** `CharacterStateService.swift:70` runs a 30-second polling timer. Each tick re-fetches every DailyLog, StreakCounter, LiftSession, and SwimSession in the database (`gatherInputs`, lines 185-267, has unbounded fetches). On a phone with 6 months of data this is a substantial main-thread workload every 30 seconds.

The same service (with the same timer) is referenced from the Watch idle home through `recomputeMascot()`.

**Fix.**
1. Replace the timer with two triggers:
   - Time-of-day boundary changes via `TimelineView.Schedule` in the consuming views.
   - Data-change notifications. Each service that mutates DailyLog or StreakCounter posts a `Notification.Name.userStateChanged`. CharacterStateService subscribes and recomputes.

2. Narrow the fetches. Today's DailyLog is one row, fetch with predicate. Lift PR check should fetch today's sessions + max prior volume via two scoped fetches, not full unbounded fetches of every LiftSession ever.

3. On the watch, drop the imported timer-based recompute. Move character state computation to a `TimelineProvider` cadence (the OS picks the cadence; aim for 15 minutes default, immediate refresh on data change events).

4. Cache the resolved state for 60 seconds. Repeated `recompute()` calls within 60s return the cached value unless `Notification.userStateChanged` was posted in between.

**Acceptance.**
- No `Timer.scheduledTimer` in `CharacterStateService.swift`.
- `gatherInputs` uses predicates, no unbounded `FetchDescriptor<>()` fetches.
- Phone idle (app foreground, no user action) shows zero CPU from character state for at least 60 seconds at a time in Instruments.

### P1-3. Drop the 30-second TodayView timer

**Problem.** `TodayView.swift:525` runs a 30-second `Timer.scheduledTimer` purely to update the "now" display. SwiftUI has `TimelineView` exactly for this.

**Fix.**

Replace:

```swift
private func startTicking() {
    tickTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
        Task { @MainActor in self.now = Date() }
    }
}
```

With:

```swift
TimelineView(.periodic(from: .now, by: 60)) { context in
    todayContent(now: context.date)
}
```

The OS pauses the timeline when the view is off screen and resumes it when it comes back. No manual lifecycle.

**Acceptance.**
- `startTicking`, `stopTicking`, `tickTimer` removed.
- TodayView still updates within 60s of the minute rolling over.

### P1-4. ClaudeAPIClient: retry, timeouts, budget cap

**Problem.** Single-shot fetch (`ClaudeAPIClient.swift:77`). No retry on 5xx, 429, or 529 (overloaded). No daily token cap. Model strings hardcoded. The user-visible action (Coach insight, prescription) fails on the first transient error.

**Fix.**
1. Add exponential backoff with jitter for 5xx, 429, 529. Max 3 attempts, base 500ms, cap 8s. Surface the final error if all attempts fail.

2. Make models configurable:

   ```swift
   enum ClaudeModel: String, CaseIterable, Codable {
       case opus47 = "claude-opus-4-7"
       case sonnet46 = "claude-sonnet-4-6"
       case haiku45 = "claude-haiku-4-5-20251001"
       
       var fallback: ClaudeModel? {
           switch self {
           case .opus47: return .sonnet46
           case .sonnet46: return .haiku45
           case .haiku45: return nil
           }
       }
   }
   ```

   On a 5xx after retry exhaustion, fall through to the fallback model once.

3. Add `TokenBudgetService`:

   ```swift
   @MainActor
   final class TokenBudgetService {
       /// Daily token cap. Reads from UserProfile.
       var dailyCap: Int { profile?.dailyTokenCap ?? 50_000 }
       /// Returns true if the requested call would exceed today's cap.
       func wouldExceed(estimatedTokens: Int) -> Bool { ... }
       /// Record actual usage post-call.
       func record(inputTokens: Int, outputTokens: Int) { ... }
       /// Today's spent count (for Settings UI).
       func spentToday() -> Int { ... }
   }
   ```

   Persist daily spend in a small `TokenUsageEntry` SwiftData model keyed by date.

4. Surface usage in Settings: "Today: 12,400 / 50,000 tokens". Let the user adjust the cap.

5. Add a kill-switch for AI features: if `dailyCap == 0`, all Claude calls are skipped silently and Coach falls back to curated quotes / canned insights.

**Acceptance.**
- Test: simulate a 503, then a 200. Client succeeds with 1 retry.
- Test: estimated tokens exceed `dailyCap`. Client throws `budgetExceeded`.
- Settings shows today's token usage. Slider changes the cap.

### P1-5. Reconsider iCloud-synced API key

**Problem.** `KeychainService.swift:90-91` now stores the Anthropic API key with `kSecAttrSynchronizable = true` and `kSecAttrAccessibleAfterFirstUnlock`. The M4.2 migration moves legacy `ThisDeviceOnly` items to the synced item.

This means the API key now syncs to every Apple device on the iCloud account. If Clay's MacBook gets compromised (malware, lost in a coffee shop, family member borrowing it), the key is exfiltrable from the iCloud Keychain on that machine. The previous `ThisDeviceOnly` posture was stronger.

The convenience win (key survives uninstall + reinstall, watch picks it up automatically) is real. The threat-model claim in the comment ("no threat-model change vs. SwiftData CloudKit") is wrong: the SwiftData CloudKit container holds personal logs, not a billable secret.

**Fix.** Offer the user a choice, default to ThisDeviceOnly.

1. Add a Settings toggle "Sync API key across my Apple devices (less secure)". Default off.
2. When off, store with `ThisDeviceOnly`. When on, store synchronizable. Toggling re-writes.
3. Watch app gets a "Set API key from companion phone" flow that uses WatchConnectivity `sendMessage` to one-shot the key over (encrypted by the OS transport; key never persists on the watch outside Keychain).
4. Show the user a one-line summary in Settings: "Stored on this device only" vs "Synced via iCloud Keychain".

**Acceptance.**
- Default install: keychain item written with `ThisDeviceOnly`. Confirm via SecItem query in test.
- Toggle on: re-write succeeds; subsequent read returns the same value.

### P1-6. Concurrent target builds: shared model files are at risk

**Problem.** `project.yml:128` and following list `PersonalOptimization/Models` as a source path for the Watch app, the Complications, and the Live Activity targets. Every file in `Models/` is compiled into every target. The Watch target then declares its own (different) schema. The compiler does not catch this because the schema enum just lists which models to include, not which versions of fields.

**Fix.**
1. Move shared types into a Swift Package (`Packages/PersonalOptimizationCore`) and depend on it from each target. The package becomes the single source of truth for `@Model` classes, `AppSchema`, `AppMigrationPlan`, `UserCalendar`, `AppGroupContainer`.

2. The package compiles once and is linked into all targets. No way to disagree about model field shapes.

3. Defer this if it adds too much project churn now. Minimum: add a CI script that diffs the field counts of each `@Model` class versus the source file in `PersonalOptimization/Models` and fails the build if any target overrides them.

**Acceptance (if Swift Package approach).**
- `swift build` succeeds on the package alone.
- `xcodegen` regenerates without errors.
- All targets compile.

---

## P2: Reliability and Observability

### P2-1. Wire up the WatchConnectivity event stream

**Problem.** `WatchConnectivityService.lastEventStream` (lines 25-37) is exposed but I see no consumer reading from it in production code. The watch sends events on workout/water/fast lifecycle, but the phone's CharacterStateService doesn't react. The pattern is half built.

**Fix.**
1. Subscribe from `PersonalOptimizationApp.init`:

   ```swift
   Task { @MainActor in
       for await event in WatchConnectivityService.shared.lastEventStream {
           switch event.kind {
           case .workoutStarted, .workoutEnded, .waterLogged, .fastStarted, .fastEnded, .learningLogged:
               NotificationCenter.default.post(name: .userStateChanged, object: nil)
               await HealthKitSyncService(modelContext: container.mainContext).syncToday()
           }
       }
   }
   ```

2. Have the watch app subscribe too, mirroring on the opposite direction.

**Acceptance.**
- Test: post a `waterLogged` event into the stream. Confirm a `userStateChanged` notification fires within 100ms.

### P2-2. Observable HealthKit sync state

**Problem.** `HealthKitSyncService` has no observable state. TodayView cannot show a spinner while sync is mid-flight.

**Fix.** Make it `@Observable`:

```swift
@Observable
@MainActor
final class HealthKitSyncService {
    private(set) var isSyncing: Bool = false
    private(set) var lastSyncedAt: Date?
    private(set) var lastSyncDurationMs: Int?
    // ...
}
```

Inject as `.environment(\.healthKitSync, ...)` into RootView. Bind from TodayView and SettingsView.

**Acceptance.**
- TodayView shows "Syncing Apple Health..." when `isSyncing == true`.
- Settings shows "Last synced: 3 min ago" derived from `lastSyncedAt`.

### P2-3. Notification suppression rule defaults are JST-anchored

**Problem.** `NotificationService.swift:34-43` hardcodes the sleep window as 22:00 to 07:00 with no respect for the user's profile or their actual sleep window. If Clay's wife uses the app and sleeps 23:00 to 06:00, or Clay shifts his schedule during a study crunch, the suppression rule misses.

**Fix.**
1. Add `UserProfile.sleepWindowStartTime` and `sleepWindowEndTime` (strings "HH:mm").
2. Default to "22:00" and "07:00" on new install.
3. Pass to `NotificationSuppressionRules.shouldSuppressHydration` as parameters.
4. Settings UI for editing.

**Acceptance.**
- Test: set sleep window 23:00 to 06:00, confirm hydration ping at 22:30 is not suppressed.

### P2-4. Surface BG task failures to the user

**Problem.** `ArchiveBackgroundScheduler.swift:67` logs errors but never tells the user. If background archive rollups silently die for a week, the user finds out only when their Journey tab is stale.

**Fix.**
1. Persist a `BackgroundTaskLog` SwiftData model with `taskId`, `startedAt`, `endedAt`, `status`, `error`.
2. Surface "Background sync: 3 failures in the last week" in Settings > Diagnostics.
3. Add a "Run rollup now" button in Diagnostics.

**Acceptance.**
- Run a BG task that fails, confirm the row appears in Diagnostics.

### P2-5. Diagnostics view

**Problem.** No central place to see: HealthKit auth state, CloudKit account status, last sync times, token usage, background task history, schema version, error counts by category.

**Fix.** Add Settings > Diagnostics with:
- HealthKit authorization status per type.
- CloudKit account status + last successful sync.
- HealthKitSyncService last run + duration.
- Token usage today/this month.
- Background task log (P2-4).
- Schema version + database row counts.
- "Export logs" button (writes OSLog entries from `os_log` to a temp file via OSLogStore and shares via UIActivityViewController).

**Acceptance.**
- Diagnostics view loads in under 200ms.
- Export logs produces a file containing the last 24h of `subsystem == "com.rawlins.PersonalOptimization"` entries.

---

## P3: Strategic Improvements

These are higher-effort changes that need decision records before starting.

### P3-1. On-device AI for Coach insights

The Gemini review's "Radical Privacy: On-Device AI Architecture" point is correct. The Coach module today ships health context to Anthropic's API. For a private protocol app, an on-device 3B model produces meaningfully similar insight quality with zero data leakage.

iOS 18 ships with Apple's Foundation Models framework (private LLM access for apps starting iOS 18.1+, but check current SDK availability). Failing that, MLX or CoreML with a quantized Llama 3.2 3B fits in roughly 2GB and runs at acceptable latency on A16+ chips.

Decision record required before starting. Open questions:
- Quality delta versus Claude Sonnet 4.6. Run side-by-side eval on 20 historical prompts.
- App Store binary size impact. Ship the model lazily via `BGProcessingTask` downloading?
- Battery impact on iPhone 14 and below.

Not a P0. Mention in `ARCHITECTURE.md` as a future direction. Keep ClaudeAPIClient as the primary path. Add a stub `LocalCoachAPI` that returns curated insights and let the user opt in for "Local mode" in Settings.

### P3-2. Partner mode (the V1_OPPORTUNITIES.md top item)

The retention research case is strong. Clay's wife is the obvious partner. The CloudKit container architecture is there. The implementation cost is roughly two weeks.

This belongs after P0/P1 are closed. Pre-TestFlight target.

### P3-3. Reward density in the day-30-to-90 window

`V1_OPPORTUNITIES.md` Tier 1 item. Engineered milestones at days 30, 45, 60, 75, 90. Mascot variants unlocking. Variable-ratio celebrations on PRs.

### P3-4. Self-comparison narratives

"You ran 3.2 miles today. Six months ago your average was 1.8." Coach should reference specific prior wins by name.

### P3-5. Lapse recovery proactive flow

`LapseDetectionService.swift` exists. Use it. When the user opens the app after a 5+ day lapse, route through a "welcome back" screen instead of TodayView.

---

## Task Ordering and Dependencies

Linear order. Each task's branch should be small and atomic. Run the full test suite after each.

```
1. P0-1 (unify schema)            [no dependencies]
2. P0-2 (DailyLog uniqueness)      [depends on P0-1]
3. P0-3 (UserCalendar)             [depends on P0-2]
4. P0-4 (App Group store URL)      [depends on P0-1]
5. P0-5 (HK background delivery)   [depends on P0-3]
6. P0-6 (retroactive recompute)    [depends on P0-5]

7. P1-2 (CharacterState reactive)  [depends on P0-3, P0-6]
8. P1-3 (drop TodayView timer)     [no deps]
9. P1-4 (Claude API resilience)    [no deps]
10. P1-5 (API key sync choice)     [no deps]
11. P1-1 (metadata blob)           [no deps; introduce in DailyLog first]
12. P1-6 (Swift Package extraction) [depends on P0-1; can defer to V1.1]

13. P2-1 (WC event stream wiring)  [depends on P0-6]
14. P2-2 (Observable HK sync)      [depends on P0-5]
15. P2-3 (sleep window in profile) [no deps]
16. P2-4 (BG task log)             [no deps]
17. P2-5 (Diagnostics view)        [depends on P2-2, P2-4, P1-4]

P3 items: separate decision records first.
```

P0 is the TestFlight-blocking set. Once P0 is closed, ship to TestFlight for Clay's wife to test partner-mode-less first. P1 and P2 land over the next two milestones in parallel with P3 decision records.

---

## Cross-Cutting Acceptance Tests

These tests should be added in addition to the per-task acceptance criteria above and run on every CI build.

### CT-1. Cross-target schema parity

```swift
func testAllProductionTargetsUseCurrentSchema() {
    // Walk the source tree, grep for `Schema(versionedSchema:`
    // outside Models/Schema*.swift, Tests, and #Preview blocks.
    // Assert the only allowed reference is `AppSchema.schema()`.
}
```

### CT-2. DailyLog uniqueness invariant

```swift
func testDailyLogUniquePerCalendarDay() async throws {
    let store = DailyLogStore(modelContext: ctx, calendar: jst)
    let a = store.upsert(for: jstDate(2026, 5, 20, 6, 0))
    let b = store.upsert(for: jstDate(2026, 5, 20, 23, 0))
    XCTAssertIdentical(a, b)
    let all = try ctx.fetch(FetchDescriptor<DailyLog>())
    XCTAssertEqual(all.count, 1)
}
```

### CT-3. Timezone change does not duplicate today

```swift
func testTimezoneChangeDoesNotSplitToday() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    let jstStore = DailyLogStore(modelContext: ctx, calendar: cal)
    _ = jstStore.upsert(for: Date())
    
    cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    let pstStore = DailyLogStore(modelContext: ctx, calendar: cal)
    _ = pstStore.upsert(for: Date())
    
    // The user's profile timezone is the source of truth. Both stores
    // were given the same calendar instance configured at write time;
    // production code routes through UserCalendar which reads from
    // UserProfile.timezone, so the day key stays stable.
    let all = try! ctx.fetch(FetchDescriptor<DailyLog>())
    XCTAssertLessThanOrEqual(all.count, 2)
    // Note: if the user enabled travel mode mid-flight, two rows is
    // acceptable. Without travel mode, the count must be 1.
}
```

### CT-4. Late-arriving HK sample triggers recompute

```swift
func testLateArrivingWorkoutUpdatesYesterdayStreak() async {
    // Set today as day N. Streak at end-of-day-N-1 was at 0 (broken).
    // Insert a HealthKit workout dated day N-1 at 14:00.
    // Run syncRange(days: 7).
    // Assert streak counter recomputes to 1, mascot state reflects it.
}
```

### CT-5. No 30-second polling timers in production

```swift
func testNoPollingTimersInProductionCode() {
    let badPatterns = ["Timer.scheduledTimer(withTimeInterval: 30"]
    // Walk PersonalOptimization, PersonalOptimizationWatch sources.
    // Allowed: LiveWorkoutSessionService (1Hz UI ticker during active workout).
    // Disallowed: everything else.
}
```

---

## Open Questions for Clay

These need a one-liner answer before implementation:

1. **Travel mode default.** Should the app follow the device timezone by default, or pin to `UserProfile.timezone`? My recommendation: follow device by default, with a toggle to pin.

2. **API key sync default.** Sync via iCloud Keychain (convenience) or ThisDeviceOnly (security)? My recommendation: ThisDeviceOnly default, opt-in to sync with a clear warning.

3. **Daily token cap default.** What ceiling for unattended runs? My recommendation: 50,000 tokens/day default, slider 0 to 500,000.

4. **Partner mode timeline.** P0/P1 fixes plus partner mode pre-TestFlight, or partner mode after first TestFlight cohort with just Clay? My recommendation: ship P0/P1 first to TestFlight solo, partner mode in v1.1.

5. **Swift Package extraction (P1-6).** Take the project churn now or defer to v1.1? My recommendation: defer. The CI guard script is enough for now.

---

## Out-of-Scope (for this handoff)

- The 22 retention opportunities in `V1_OPPORTUNITIES.md`. Those are post-TestFlight feature work.
- Widgets for iPhone home screen. Scheduled for M6 per `ARCHITECTURE.md`.
- Mac Catalyst, visionOS. Explicitly excluded.
- Localizations beyond en-US. Excluded for v1.
- Snapshot tests. Deferred until v0.5+ per `TESTING.md`.

---

## Definition of Done for this handoff

- All P0 tasks merged with acceptance tests green.
- All P1 tasks either merged or have an open PR with the decision record committed.
- P2 tasks tracked as issues with owner and target milestone.
- P3 tasks have decision records under `.work/decisions/`.
- Cross-cutting tests CT-1 through CT-5 are part of the CI run on push to main.
- `xcodebuild test -scheme PersonalOptimization` passes on iPhone 16 Pro simulator.
- `xcodebuild build -scheme PersonalOptimizationWatch -destination 'platform=watchOS Simulator,name=Apple Watch Ultra 2 (49mm)'` passes.
- App launches on a paired iPhone + Apple Watch Ultra 2 against an empty CloudKit container without crashing.
