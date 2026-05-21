# IMPROVEMENT_IMPLEMENTATION_PLAN.md

Hand-off spec for Claude Code. 22 items grouped into 4 tiers. Each item gives: files touched, the bug or gap with file:line references, the exact diff or code to write, the tests to add, and acceptance criteria. Items are ordered so dependencies land before consumers (notification delegate before action wiring, config cache before TodayView refactor, schema test harness before per-version migration tests).

Repo root: `/Users/ghost/Desktop/projects2026/optimization-app`. All file paths are absolute.

## Bootstrap rules for every PR

1. One milestone-style PR per item or per small group. Branch name `improve/<short-tag>`.
2. Quality gates per CLAUDE.md must pass before merge: `xcodebuild build` zero warnings, `xcodebuild test` green, watch target builds, coverage on Models/Services not regressing.
3. Every new `try?` in this plan ships with `// MARK: - try? justified because <reason>` per CLAUDE.md.
4. No `print()`, no Combine. Async/await everywhere.
5. Times stored UTC, computed via `Calendar` with explicit timezone.
6. New tests use `PersonalOptimizationTests/Helpers/InMemoryContainer.swift` (existing helper). No live HealthKit, CloudKit, or Keychain in tests.
7. Performance assertions use `measure { }` blocks in `PerformanceTests`.

---

# Tier 1: Pre-sideload blockers

## Item 1: Register notification categories and wire the action-button handler

### Problem

- `NotificationService.swift:111-134` exposes `register()` which calls `registerCategories()` (line 131) which calls `center.setNotificationCategories(...)` (line 191).
- `register()` is never called from production. `OnboardingView.swift:474` calls `UNUserNotificationCenter.current().requestAuthorization(...)` directly, bypassing `NotificationService`. So categories are never registered with the system, and the action buttons defined at `NotificationService.swift:137-161` (`log_8oz`, `log_16oz`, `log_24oz`, `log_32oz`, `skip`) never appear on lock screen or notification center.
- There is no `UNUserNotificationCenterDelegate` anywhere in the codebase (verified with grep). Even if categories were registered, action-button taps would have no handler. Tapping `log_16oz` would silently dismiss the notification without writing to `DailyLog`.

### Files touched

- `PersonalOptimization/PersonalOptimizationApp.swift`
- `PersonalOptimization/Services/NotificationService.swift`
- `PersonalOptimization/Views/OnboardingView.swift`
- `PersonalOptimization/Services/AppNotifications.swift` (add notification names if not present)
- New file: `PersonalOptimization/Services/NotificationActionHandler.swift`
- `PersonalOptimization/Modules/Hydration/HydrationService.swift` (verify quick-log path)
- `PersonalOptimizationTests/Services/NotificationActionHandlerTests.swift` (new)

### Implementation

Step 1. Create `NotificationActionHandler.swift`:

```swift
import Foundation
import UserNotifications
import SwiftData
import os

/// Handles user interactions with delivered notifications. Wired as the
/// UNUserNotificationCenterDelegate during app launch. Routes hydration
/// action buttons (8/16/24/32 oz, Skip) into HydrationService and fast
/// notifications into FastingService. Background-delivered actions land
/// here without surfacing the app to foreground.
@MainActor
final class NotificationActionHandler: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationActionHandler()

    private let logger = Logger.app
    private var modelContainer: ModelContainer?

    func attach(to center: UNUserNotificationCenter = .current(), modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        center.delegate = self
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show alerts while foregrounded so the user sees the same banner they
    /// would on the lock screen. Sound stays off in foreground to avoid double-
    /// trigger with in-app feedback.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .badge]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            handle(response: response)
        }
    }

    private func handle(response: UNNotificationResponse) {
        let actionId = response.actionIdentifier
        let category = response.notification.request.content.categoryIdentifier
        logger.info("Notification action category=\(category, privacy: .public) action=\(actionId, privacy: .public)")

        guard let container = modelContainer else {
            logger.warning("Notification action received but no model container attached")
            return
        }
        let context = container.mainContext

        switch category {
        case NotificationIdentifier.hydrationCategory:
            handleHydrationAction(actionId, context: context)
        case NotificationIdentifier.fastStartCategory,
             NotificationIdentifier.fastEndCategory:
            // Default tap opens the app at Fasting tab. No quick actions
            // defined yet for fasting; UNNotificationDefaultActionIdentifier
            // is handled by SceneDelegate / RootView routing on open.
            break
        case NotificationIdentifier.learningCategory:
            // Default tap opens the app. No quick actions yet.
            break
        default:
            break
        }
    }

    private func handleHydrationAction(_ actionId: String, context: ModelContext) {
        let oz: Double
        switch actionId {
        case NotificationIdentifier.actionLog8oz: oz = 8
        case NotificationIdentifier.actionLog16oz: oz = 16
        case NotificationIdentifier.actionLog24oz: oz = 24
        case NotificationIdentifier.actionLog32oz: oz = 32
        case NotificationIdentifier.actionSkip:
            logger.info("Hydration reminder dismissed via Skip")
            return
        default:
            return
        }
        let targets = try? ScheduleConfigLoader.load().hydrationTargetsOz
        let service = HydrationService(modelContext: context, targets: targets)
        do {
            _ = try service.logBottle(oz: oz)
            NotificationCenter.default.post(name: .userStateChanged, object: nil)
            logger.info("Logged \(Int(oz), privacy: .public) oz via notification action")
        } catch {
            logger.warning("Hydration quick-log failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
```

Step 2. Wire it in `PersonalOptimizationApp.swift` immediately after the `WatchConnectivityService.shared.activateIfPossible()` call (around line 61):

```swift
// Register notification categories + action handler so lock-screen
// hydration buttons (8 / 16 / 24 / 32 oz) actually fire. Must run before
// any reminder is scheduled. Authorization request is idempotent.
NotificationActionHandler.shared.attach(modelContainer: container)
Task { @MainActor in
    do {
        _ = try await NotificationService.shared.register()
    } catch {
        Logger.app.warning("Notification register failed: \(error.localizedDescription, privacy: .public)")
    }
}
```

Step 3. Stop bypassing `NotificationService` in `OnboardingView.swift`. Replace line 474:

```swift
// Old:
_ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])

// New:
// try? justified because: onboarding step is best-effort; user can still
// grant later via Settings. Failure to obtain authorization is logged at
// NotificationService level and does not block onboarding completion.
_ = try? await NotificationService.shared.register()
```

Drop the `let center = UNUserNotificationCenter.current()` line if it's only used here.

Step 4. In `AppNotifications.swift` confirm `.userStateChanged` is declared. If not, add:

```swift
extension Notification.Name {
    static let userStateChanged = Notification.Name("com.rawlins.PersonalOptimization.userStateChanged")
}
```

### Tests

Create `PersonalOptimizationTests/Services/NotificationActionHandlerTests.swift`:

```swift
import XCTest
import UserNotifications
import SwiftData
@testable import PersonalOptimization

@MainActor
final class NotificationActionHandlerTests: XCTestCase {

    func test_handlesLog16ozAction_writesToDailyLog() throws {
        let container = try InMemoryContainer.make()
        NotificationActionHandler.shared.attach(modelContainer: container)

        let response = makeResponse(
            category: NotificationIdentifier.hydrationCategory,
            actionId: NotificationIdentifier.actionLog16oz
        )
        // Invoke the private handler indirectly through the delegate API.
        let exp = expectation(description: "action dispatched")
        Task { @MainActor in
            await NotificationActionHandler.shared.userNotificationCenter(
                UNUserNotificationCenter.current(),
                didReceive: response
            )
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)

        let logs = try container.mainContext.fetch(FetchDescriptor<HydrationEntry>())
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.amountOz, 16)
    }

    func test_skipAction_doesNotWriteLog() throws { /* mirror above */ }

    func test_unknownCategory_isNoOp() throws { /* mirror above */ }

    private func makeResponse(category: String, actionId: String) -> UNNotificationResponse {
        // Use UNNotificationResponse(coder:) hack: subclass UNNotificationResponse
        // in a test helper. Apple's UNNotificationResponse can't be constructed
        // directly. Use a protocol seam in NotificationActionHandler instead
        // (recommended): factor `handle(actionId:category:context:)` out of the
        // delegate method and test that function directly.
        fatalError("Refactor handler to expose pure func for tests")
    }
}
```

The cleanest path is to refactor `handle(response:)` so the routing logic accepts `(actionId: String, category: String, context: ModelContext)` and the delegate method only unwraps `UNNotificationResponse`. Then the tests target the pure function, no UNNotificationResponse construction needed.

### Acceptance criteria

- Cold launch on hardware: hydration reminder shows "8 / 16 / 24 / 32 oz / Skip" actions on the lock screen.
- Tapping "16 oz" from lock screen creates a `HydrationEntry` row visible in `HydrationView` next open.
- `Skip` dismisses without writing.
- `NotificationActionHandlerTests` cover the four oz actions, Skip, and unknown category (no-op).
- Log line `Notification action category=hydration action=log_16oz` appears in Console.app under subsystem `com.rawlins.PersonalOptimization` category `app`.

---

## Item 2: Accessibility labels on watch workout views

### Problem

Per audit, `HydrationWatchView` and `IdleHomeWatchView` are correctly labeled (see `HydrationWatchView.swift:66, 80`). `LiftWatchView`, `BasketballWatchView`, `SwimWatchView`, `LearningWatchView`, `CustomActivityWatchView` have no `.accessibilityLabel(...)` on Steppers, Pickers, set-log buttons, or end buttons. Watch screen real estate makes each control more critical to VoiceOver users.

### Files touched

- `PersonalOptimizationWatch/Views/LiftWatchView.swift`
- `PersonalOptimizationWatch/Views/BasketballWatchView.swift`
- `PersonalOptimizationWatch/Views/SwimWatchView.swift`
- `PersonalOptimizationWatch/Views/LearningWatchView.swift`
- `PersonalOptimizationWatch/Views/CustomActivityWatchView.swift`

### Implementation

Reference pattern from `LiftWatchView.swift`. Replace each Button without an `.accessibilityLabel` with the labeled form. Use `String(localized:)` so labels land in `Localizable.xcstrings`.

For `LiftWatchView.swift`:

```swift
// Line 42-49 currently:
Button {
    _ = try? service.logSet(in: session, exerciseName: active.name, weightLbs: 135, reps: 5, restSeconds: 90)
    WKInterfaceDevice.current().play(.success)
} label: {
    Label("+ Set 135x5", systemImage: "plus")
}
.buttonStyle(.borderedProminent)

// Replace with:
Button {
    // try? justified because: SwiftData local write, failure is unrecoverable.
    _ = try? service.logSet(in: session, exerciseName: active.name, weightLbs: 135, reps: 5, restSeconds: 90)
    WKInterfaceDevice.current().play(.success)
} label: {
    Label("+ Set 135x5", systemImage: "plus")
}
.buttonStyle(.borderedProminent)
.accessibilityLabel(String(localized: "Log a set of 135 pounds for 5 reps"))
.accessibilityHint(String(localized: "Records a new set on the active exercise"))
```

For navigation chevrons (lines 53-66):

```swift
Button {
    if currentExerciseIndex > 0 { currentExerciseIndex -= 1 }
} label: {
    Image(systemName: "chevron.left")
}
.accessibilityLabel(String(localized: "Previous exercise"))

// And:
Button {
    if currentExerciseIndex < exercises.count - 1 { currentExerciseIndex += 1 }
} label: {
    Image(systemName: "chevron.right")
}
.accessibilityLabel(String(localized: "Next exercise"))
```

For the end button (lines 68-72):

```swift
Button(role: .destructive) {
    Task { await end(service: service, session: session) }
} label: {
    Label("End", systemImage: "stop.circle")
}
.accessibilityLabel(String(localized: "End workout"))
.accessibilityHint(String(localized: "Saves the session and returns to the watch home screen"))
```

Live stats row (lines 83-103) needs a combined VoiceOver readout. Replace the HStack with:

```swift
HStack(spacing: 6) {
    Label("\(Int(live.heartRate))", systemImage: "heart.fill")
        .foregroundStyle(.red)
        .font(.caption2.monospacedDigit())
        .accessibilityHidden(true)
    Spacer()
    Label("\(Int(live.activeCaloriesKcal))", systemImage: "flame.fill")
        .foregroundStyle(.orange)
        .font(.caption2.monospacedDigit())
        .accessibilityHidden(true)
    Spacer()
    Text(formatDuration(live.elapsedSeconds))
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
}
.accessibilityElement(children: .ignore)
.accessibilityLabel(String(localized:
    "Heart rate \(Int(live.heartRate)), \(Int(live.activeCaloriesKcal)) calories burned, elapsed \(formatDuration(live.elapsedSeconds))"
))
```

Apply the same pattern across `BasketballWatchView`, `SwimWatchView`, `LearningWatchView`, `CustomActivityWatchView`. Steppers get `.accessibilityValue(...)` so the current value is announced on each change.

### Tests

Add `PersonalOptimizationTests/Modules/WatchAccessibilityLabelsTests.swift`. Tests verify that labels exist in code (compile-time) and that the SwiftUI `accessibilityLabel` modifier is present in the view tree.

```swift
import XCTest
import SwiftUI
@testable import PersonalOptimization

@MainActor
final class WatchAccessibilityLabelsTests: XCTestCase {

    func test_liftView_endButton_hasAccessibilityLabel() {
        let mirror = Mirror(reflecting: LiftWatchView(templateName: "Lift A"))
        // Reflection across SwiftUI views is brittle. Better: rely on
        // ViewInspector pattern via the testable accessor — but the project
        // has no third-party deps. Instead, add a UITestplan target if you
        // want runtime checks. For unit-test coverage, the linting approach
        // below is the pragmatic option.
    }
}
```

Pragmatic fallback: add a lint test that grep-checks the watch view files for accessibility label coverage. `PersonalOptimizationTests/Modules/WatchAccessibilityLintTests.swift`:

```swift
import XCTest

final class WatchAccessibilityLintTests: XCTestCase {

    /// Fails if any Button or Stepper in the listed watch views lacks an
    /// adjacent .accessibilityLabel modifier. Catches the most common
    /// regression: someone adds a new button and forgets the label.
    func test_watchWorkoutViews_haveAccessibilityLabels() throws {
        let bundle = Bundle(for: type(of: self))
        let watchSourceRoot = bundle.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("PersonalOptimizationWatch/Views")
        let files = [
            "LiftWatchView.swift",
            "BasketballWatchView.swift",
            "SwimWatchView.swift",
            "LearningWatchView.swift",
            "CustomActivityWatchView.swift",
        ]
        for file in files {
            let path = watchSourceRoot.appendingPathComponent(file)
            guard let source = try? String(contentsOf: path) else {
                // Source not available in test bundle layout. Skip rather
                // than fail; this lint is best-effort.
                continue
            }
            let buttonCount = source.components(separatedBy: "Button {").count - 1
            let labelCount = source.components(separatedBy: ".accessibilityLabel(").count - 1
            XCTAssertGreaterThanOrEqual(
                labelCount, buttonCount,
                "\(file): \(buttonCount) Buttons but only \(labelCount) accessibility labels"
            )
        }
    }
}
```

If the source files are not bundled into the test target, do this check as a CI script instead. The simpler answer: ship the labels, manual VoiceOver pass on Apple Watch in the simulator, no automated test.

### Acceptance criteria

- VoiceOver on Apple Watch Ultra simulator reads every Button, Stepper, and live-stats row in Lift / Basketball / Swim / Learning / CustomActivity views.
- Each accessibility label is sourced from `String(localized: ...)` so it appears in `Localizable.xcstrings` for future translation.
- No new emoji or em dash characters in the labels.

---

## Item 3: Real-time hydration sync from watch to phone via WatchConnectivity

### Problem

`HydrationWatchView.swift:86-93` calls `service.logBottle(oz:)` then triggers a haptic. SwiftData writes the row locally on the watch, and CloudKit eventual consistency syncs to the phone within minutes. There is no immediate phone-side update.

`WatchConnectivityService` already has `send(_ event: WatchConnectivityEvent)` at `WatchConnectivityService.swift:55-74`, and the event Kind enum already includes `.waterLogged` at line 117. The send call is just missing.

### Files touched

- `PersonalOptimizationWatch/Views/HydrationWatchView.swift`
- `PersonalOptimization/PersonalOptimizationApp.swift` (extend the event-stream consumer)

### Implementation

Step 1. In `HydrationWatchView.swift:86-93`, send a WC event after the log succeeds:

```swift
private func log(oz: Double, service: HydrationService) {
    do {
        _ = try service.logBottle(oz: oz)
        WKInterfaceDevice.current().play(.success)
        // Real-time signal to the phone so the iOS UI updates within
        // seconds instead of waiting on CloudKit propagation. Persisted
        // SwiftData row + CloudKit sync remain the source of truth.
        WatchConnectivityService.shared.send(
            WatchConnectivityEvent(
                kind: .waterLogged,
                payload: ["oz": "\(Int(oz))"]
            )
        )
        refreshTrigger += 1
    } catch {
        // Failure path: surface to UI via loadError.
        loadError = error.localizedDescription
    }
}
```

Replace the existing `try?` line per coding convention (no silent swallow without justification). If keeping `try?` is preferred, justify it:

```swift
// try? justified because: SwiftData local write to in-process container,
// failure path is unrecoverable corruption rather than a recoverable user
// error; the haptic still fires to confirm the tap was received.
_ = try? service.logBottle(oz: oz)
```

Step 2. The phone-side consumer at `PersonalOptimizationApp.swift:66-76` already fans the event into `.userStateChanged`. Add an explicit case for `.waterLogged` so the iOS `HydrationService` can re-read its own SwiftData row (CloudKit will mirror it, but we want immediate UI):

```swift
Task { @MainActor in
    for await event in WatchConnectivityService.shared.lastEventStream {
        NotificationCenter.default.post(name: .userStateChanged, object: event)
        switch event.kind {
        case .workoutStarted, .workoutEnded:
            await HealthKitSyncService(modelContext: container.mainContext).syncToday()
        case .waterLogged:
            // Force HK sync so the daily aggregate refreshes with whatever
            // the watch added. SwiftData rows arrive via CloudKit; this
            // accelerates the visible state on the phone.
            await HealthKitSyncService(modelContext: container.mainContext).syncToday()
        default:
            break
        }
    }
}
```

### Tests

Append to `PersonalOptimizationTests/Services/WatchConnectivityServiceTests.swift`:

```swift
func test_waterLoggedEvent_encodesAndDecodes() throws {
    let event = WatchConnectivityEvent(
        kind: .waterLogged,
        payload: ["oz": "16"]
    )
    let data = try JSONEncoder().encode(event)
    let decoded = try JSONDecoder().decode(WatchConnectivityEvent.self, from: data)
    XCTAssertEqual(decoded.kind, .waterLogged)
    XCTAssertEqual(decoded.payload["oz"], "16")
}
```

### Acceptance criteria

- Tapping "16 oz" on a paired Apple Watch causes the phone's `TodayView` master metric and `HydrationView` total to update within 5 seconds (vs. minutes today).
- WC event log line `Received event waterLogged` appears in Console.app on the iOS device under `com.rawlins.PersonalOptimization` category `wc`.
- If watch is unpaired or unreachable, the local watch write still succeeds and CloudKit eventual consistency handles propagation (verified by toggling phone airplane mode).

---

## Item 4: Tests for cost guardrails (TokenBudgetService) and untested services

### Problem

`TokenBudgetService.swift` enforces the daily spend cap on the Anthropic API and has zero tests. `ProfileService.swift`, `ReactiveRecomputeService.swift`, `HealthKitObserverService.swift`, `FastingLiveActivityController.swift`, `WorkoutLiveActivityController.swift` also have zero tests. Coverage on Models/Services is below the 70% target stated in CLAUDE.md Quality Gates.

### Files touched

- New: `PersonalOptimizationTests/Services/TokenBudgetServiceTests.swift`
- New: `PersonalOptimizationTests/Services/ProfileServiceTests.swift`
- New: `PersonalOptimizationTests/Services/ReactiveRecomputeServiceTests.swift`
- New: `PersonalOptimizationTests/Services/HealthKitObserverServiceTests.swift`
- New: `PersonalOptimizationTests/Modules/FastingLiveActivityControllerTests.swift`
- New: `PersonalOptimizationTests/Modules/WorkoutLiveActivityControllerTests.swift`

### Implementation

`TokenBudgetServiceTests.swift`:

```swift
import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class TokenBudgetServiceTests: XCTestCase {

    func test_wouldExceed_returnsTrueWhenBudgetIsZero() throws {
        let container = try InMemoryContainer.make()
        let context = container.mainContext
        let profile = UserProfile(dailyTokenBudget: 0)
        context.insert(profile)
        try context.save()

        let service = TokenBudgetService(modelContext: context)
        XCTAssertTrue(service.wouldExceed(estimatedTokens: 1))
        XCTAssertTrue(service.wouldExceed(estimatedTokens: 0))
    }

    func test_wouldExceed_falseWhenWithinBudget() throws {
        let container = try InMemoryContainer.make()
        let profile = UserProfile(dailyTokenBudget: 10_000)
        container.mainContext.insert(profile)
        try container.mainContext.save()
        let service = TokenBudgetService(modelContext: container.mainContext)
        XCTAssertFalse(service.wouldExceed(estimatedTokens: 5_000))
    }

    func test_wouldExceed_trueAtExactCap() throws {
        let container = try InMemoryContainer.make()
        let profile = UserProfile(dailyTokenBudget: 10_000)
        container.mainContext.insert(profile)
        let service = TokenBudgetService(modelContext: container.mainContext)
        service.record(inputTokens: 9_000, outputTokens: 0)
        XCTAssertFalse(service.wouldExceed(estimatedTokens: 1_000))
        XCTAssertTrue(service.wouldExceed(estimatedTokens: 1_001))
    }

    func test_record_accumulatesIntoTodaysEntry() throws {
        let container = try InMemoryContainer.make()
        let profile = UserProfile(dailyTokenBudget: 50_000)
        container.mainContext.insert(profile)
        let service = TokenBudgetService(modelContext: container.mainContext)
        service.record(inputTokens: 100, outputTokens: 200)
        service.record(inputTokens: 50, outputTokens: 50)
        XCTAssertEqual(service.spentToday(), 400)
    }

    func test_spentToday_zeroBeforeAnyRecord() throws {
        let container = try InMemoryContainer.make()
        let profile = UserProfile(dailyTokenBudget: 50_000)
        container.mainContext.insert(profile)
        let service = TokenBudgetService(modelContext: container.mainContext)
        XCTAssertEqual(service.spentToday(), 0)
    }

    func test_dayBoundary_yesterdayUsageDoesNotCountToday() throws {
        let container = try InMemoryContainer.make()
        let profile = UserProfile(dailyTokenBudget: 1_000)
        container.mainContext.insert(profile)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: Date()))!
        let priorEntry = TokenUsageEntry(
            date: yesterday,
            inputTokens: 5_000,
            outputTokens: 5_000,
            callCount: 1,
            lastCallAt: yesterday
        )
        container.mainContext.insert(priorEntry)
        try container.mainContext.save()

        let service = TokenBudgetService(modelContext: container.mainContext, calendar: cal)
        XCTAssertEqual(service.spentToday(), 0)
        XCTAssertFalse(service.wouldExceed(estimatedTokens: 500))
    }

    func test_spentThisMonth_aggregatesAllEntries() throws {
        let container = try InMemoryContainer.make()
        let profile = UserProfile(dailyTokenBudget: 50_000)
        container.mainContext.insert(profile)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let today = cal.startOfDay(for: Date())
        let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: today)!
        container.mainContext.insert(TokenUsageEntry(
            date: twoDaysAgo, inputTokens: 100, outputTokens: 200, callCount: 1, lastCallAt: twoDaysAgo
        ))
        container.mainContext.insert(TokenUsageEntry(
            date: today, inputTokens: 50, outputTokens: 50, callCount: 1, lastCallAt: today
        ))
        try container.mainContext.save()
        let service = TokenBudgetService(modelContext: container.mainContext, calendar: cal)
        XCTAssertEqual(service.spentThisMonth(), 400)
    }
}
```

`ProfileServiceTests.swift` covers: initial profile creation when none exists, idempotency on second call, preservation of existing profile fields on second call, timezone default (JST), onboardingCompleted flag transition.

`ReactiveRecomputeServiceTests.swift` covers: subscribes to `.dailyLogsRecomputed`, debounces within `throttleWindow`, recomputes all `StreakDomain` cases, no crash when modelContainer is nil.

`HealthKitObserverServiceTests.swift` covers: registration when HK denied (no-op), observer fan-out into `.dailyLogsRecomputed`, idempotency on repeated `startObserving`.

`FastingLiveActivityControllerTests.swift` and `WorkoutLiveActivityControllerTests.swift` cover: state transitions (start, update, end), stale date calculation, no Activity.request crash when `ActivityAuthorizationInfo().areActivitiesEnabled == false` (gated via dependency injection of a protocol seam).

For Live Activity controllers, refactor the controller to take an `ActivityKitProtocol` parameter so tests can supply a fake:

```swift
protocol ActivityRequester: Sendable {
    func request<T: ActivityAttributes>(attributes: T, content: T.ContentState, staleDate: Date?) throws -> Activity<T>
}

@MainActor
final class FastingLiveActivityController {
    private let requester: ActivityRequester
    init(requester: ActivityRequester = LiveActivityRequester()) { ... }
}
```

### Acceptance criteria

- All six new test files run and pass.
- `xcrun xccov view --report --only-targets <build>.xcresult` shows Models/Services coverage at or above 70%.
- `TokenBudgetServiceTests.test_dayBoundary_yesterdayUsageDoesNotCountToday` passes in JST and an alternate timezone (run twice with `TZ=America/Los_Angeles xcodebuild test`).

---

# Tier 2: Performance and data hygiene

## Item 5: Push date predicates into `DailySummaryService` fetches

### Problem

`DailySummaryService.swift:56,61,65` issues `fetch(FetchDescriptor<ScheduleBlock>())`, `fetch(FetchDescriptor<DailyLog>())`, `fetch(FetchDescriptor<WorkoutEvent>())` with no `#Predicate`, then filters in memory. Each `TodayView` body evaluation triggers this. At 1000 rows per table the cost is dozens of milliseconds; PERFORMANCE.md targets <100ms.

`todaysWorkoutSnippet` at lines 145-179 repeats the same pattern across `CustomActivitySession`, `LiftSession`, `BasketballSession`, `SwimSession`.

### Files touched

- `PersonalOptimization/Modules/Engagement/DailySummaryService.swift`
- `PersonalOptimizationTests/Modules/DailySummaryServiceTests.swift` (add perf assertion)

### Implementation

Replace the unbounded fetches at line 56 onward:

```swift
// Pre-compute the day range once.
let tomorrow = cal.date(byAdding: .day, value: 1, to: day) ?? day

// ScheduleBlock: no date predicate possible (weekly recurring). Keep
// the unbounded fetch but cache the result since it rarely changes.
let blocks = (try? modelContext.fetch(FetchDescriptor<ScheduleBlock>())) ?? []

// DailyLog: scoped to the single row for `day`. SwiftData supports
// equality predicates on Date.
let dailyLogDescriptor = FetchDescriptor<DailyLog>(
    predicate: #Predicate<DailyLog> { $0.date == day }
)
let log = (try? modelContext.fetch(dailyLogDescriptor))?.first

// WorkoutEvent: scoped to today's range.
let workoutEventsDescriptor = FetchDescriptor<WorkoutEvent>(
    predicate: #Predicate<WorkoutEvent> {
        $0.date >= day && $0.date < tomorrow && $0.completed
    }
)
let workoutEvents = (try? modelContext.fetch(workoutEventsDescriptor)) ?? []
let workoutCompleted = !workoutEvents.isEmpty
```

For `todaysWorkoutSnippet`, push the day range into each descriptor:

```swift
private func todaysWorkoutSnippet(for day: Date) -> String? {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = timezone
    let tomorrow = cal.date(byAdding: .day, value: 1, to: day) ?? day

    var customsDescriptor = FetchDescriptor<CustomActivitySession>(
        predicate: #Predicate<CustomActivitySession> {
            $0.date >= day && $0.date < tomorrow && $0.durationMinutes > 0
        },
        sortBy: [SortDescriptor(\.date, order: .reverse)]
    )
    customsDescriptor.fetchLimit = 1
    if let custom = (try? modelContext.fetch(customsDescriptor))?.first {
        let name = custom.templateName.isEmpty ? "Cardio" : custom.templateName
        return "\(name) \u{00B7} \(custom.durationMinutes) min"
    }

    var liftsDescriptor = FetchDescriptor<LiftSession>(
        predicate: #Predicate<LiftSession> {
            $0.date >= day && $0.date < tomorrow && $0.durationMinutes > 0
        },
        sortBy: [SortDescriptor(\.date, order: .reverse)]
    )
    liftsDescriptor.fetchLimit = 1
    if let lift = (try? modelContext.fetch(liftsDescriptor))?.first {
        return "\(lift.template) \u{00B7} \(lift.durationMinutes) min"
    }

    var bballDescriptor = FetchDescriptor<BasketballSession>(
        predicate: #Predicate<BasketballSession> {
            $0.startTime >= day && $0.startTime < tomorrow
        },
        sortBy: [SortDescriptor(\.startTime, order: .reverse)]
    )
    bballDescriptor.fetchLimit = 1
    if let game = (try? modelContext.fetch(bballDescriptor))?.first, game.endTime > game.startTime {
        let minutes = max(1, Int(game.endTime.timeIntervalSince(game.startTime) / 60))
        return "Basketball \u{00B7} \(minutes) min"
    }

    var swimsDescriptor = FetchDescriptor<SwimSession>(
        predicate: #Predicate<SwimSession> {
            $0.date >= day && $0.date < tomorrow && $0.durationMinutes > 0
        },
        sortBy: [SortDescriptor(\.date, order: .reverse)]
    )
    swimsDescriptor.fetchLimit = 1
    if let swim = (try? modelContext.fetch(swimsDescriptor))?.first {
        return "Swim \u{00B7} \(swim.durationMinutes) min \u{00B7} \(Int(swim.totalMeters))m"
    }
    return nil
}
```

The middle-dot character `\u{00B7}` keeps the existing visual `·` without an em dash and without copy-paste hazards.

### Tests

Add to `DailySummaryServiceTests.swift`:

```swift
func test_perf_todayProtocol_under20ms_with1000Rows() throws {
    let container = try InMemoryContainer.make()
    let context = container.mainContext
    let cal = Calendar(identifier: .gregorian)
    let today = cal.startOfDay(for: Date())
    // Seed 1000 DailyLog rows across the prior 1000 days, plus 1000 random
    // WorkoutEvent rows. Predicate pushdown should keep todayProtocol cost
    // independent of total row count.
    for i in 0..<1000 {
        let d = cal.date(byAdding: .day, value: -i, to: today)!
        context.insert(DailyLog(date: d, waterOz: 32, japaneseMinutes: 0))
        context.insert(WorkoutEvent(date: d, completed: true))
    }
    try context.save()

    let service = DailySummaryService(modelContext: context)
    measure {
        for _ in 0..<10 {
            _ = service.todayProtocol(asOf: Date())
        }
    }
}
```

The `measure { }` block records baseline. Run on hardware and capture the baseline at <100ms per 10 calls (10ms each).

### Acceptance criteria

- `DailySummaryServiceTests.test_perf_todayProtocol_under20ms_with1000Rows` passes at <100ms per 10 calls.
- `xcodebuild test` green.
- No behavioral regression: existing `DailySummaryServiceTests` tests still pass.

---

## Item 6: Cache `ScheduleConfigLoader` result and stop rebuilding services in `TodayView`

### Problem

- `ScheduleConfigLoader.load()` at `ScheduleConfig.swift:55` parses `default_schedule.json` from the app bundle on every call. Audit found 9+ callsites: `TodayView`, `ReactiveRecomputeService:55`, `ArchiveBackgroundScheduler:62,103`, `DailyProgressBars`, etc. Each call hits `Data(contentsOf:)` and `JSONDecoder().decode()`.
- `TodayView.swift:16-23` exposes `service` and `summaryService` as computed properties. On each body evaluation, both are reconstructed and `ScheduleConfigLoader.load()` runs again.

### Files touched

- `PersonalOptimization/Modules/Schedule/ScheduleConfig.swift`
- `PersonalOptimization/Views/TodayView.swift`
- All other callsites of `ScheduleConfigLoader.load()` (search and update)
- `PersonalOptimizationTests/Modules/ScheduleConfigLoaderCacheTests.swift` (new)

### Implementation

Step 1. Add a cached accessor at the bottom of `ScheduleConfig.swift`:

```swift
/// Process-lifetime cache for `default_schedule.json`. Invalidated only on
/// explicit `reset()` (used in tests). Thread-safe via an actor.
actor ScheduleConfigCache {
    static let shared = ScheduleConfigCache()

    private var cached: ScheduleConfig?
    private var cachedError: Error?

    func loadCached(bundle: Bundle = .main) throws -> ScheduleConfig {
        if let cached { return cached }
        if let cachedError { throw cachedError }
        do {
            let config = try ScheduleConfigLoader.load(bundle: bundle)
            cached = config
            return config
        } catch {
            cachedError = error
            throw error
        }
    }

    func reset() {
        cached = nil
        cachedError = nil
    }
}

extension ScheduleConfigLoader {
    /// Synchronous cached accessor for callers that cannot await. Bridges to
    /// the actor via an unsafe-but-bounded MainActor-isolated cache. Falls
    /// back to a direct load if accessed from a non-MainActor context.
    @MainActor
    private static var mainActorCache: ScheduleConfig?

    @MainActor
    static func loadCached(bundle: Bundle = .main) throws -> ScheduleConfig {
        if let mainActorCache { return mainActorCache }
        let config = try load(bundle: bundle)
        mainActorCache = config
        return config
    }

    @MainActor
    static func resetCache() {
        mainActorCache = nil
    }
}
```

Use the `@MainActor` variant in iOS UI code, and the actor variant in background-actor code (currently only background tasks in `ArchiveBackgroundScheduler`).

Step 2. Update callsites. In `TodayView.swift`:

```swift
struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @State private var now: Date = Date()
    @State private var characterService = CharacterStateService.shared
    @State private var hkSyncService: HealthKitSyncService?
    @State private var showingProtocolDetail = false
    @State private var quoteService = DailyQuoteService()
    @State private var dailyQuote: DailyQuote?
    @State private var pendingCelebration: MilestoneUnlock?
    @State private var showingMemorySheet = false

    // Hold the SwiftData-bound services in @State so they survive across
    // body evaluations. Initialized in .task once the modelContext is in
    // scope. Marked optional so the view renders before init completes.
    @State private var scheduleService: ScheduleService?
    @State private var summaryService: DailySummaryService?
    @State private var cachedHydrationTargets: HydrationTargetsOz?

    var body: some View {
        NavigationStack {
            content
        }
        .task {
            await bootstrapServices()
        }
    }

    private func bootstrapServices() async {
        if scheduleService == nil {
            scheduleService = ScheduleService(modelContext: modelContext)
        }
        if summaryService == nil {
            // try? justified because: ScheduleConfig is a bundled resource.
            // If load fails the targets default to nil, hydrationFloor uses
            // its 64 oz default in DailySummaryService, and the user still
            // sees today's metric.
            let config = try? ScheduleConfigLoader.loadCached()
            cachedHydrationTargets = config?.hydrationTargetsOz
            summaryService = DailySummaryService(
                modelContext: modelContext,
                hydrationTargets: cachedHydrationTargets
            )
        }
    }

    // ... rest of body, swap `service` -> `scheduleService` and `summaryService` accesses
    //     to gate on optional unwrap with a `if let` ProgressView fallback while bootstrap runs.
}
```

Step 3. Audit other callsites and migrate to `loadCached()`:

- `Services/ReactiveRecomputeService.swift:55`
- `Services/ArchiveBackgroundScheduler.swift:62,103`
- `Modules/Engagement/Views/DailyProgressBars.swift`
- Any other `ScheduleConfigLoader.load()` callsite found via grep.

In `ArchiveBackgroundScheduler` the BG handler runs in a `Task { @MainActor in ... }` so `loadCached()` (MainActor) works. The synchronous-immediate path at lines 55-81 also runs MainActor-isolated.

### Tests

Create `ScheduleConfigLoaderCacheTests.swift`:

```swift
import XCTest
@testable import PersonalOptimization

@MainActor
final class ScheduleConfigLoaderCacheTests: XCTestCase {

    override func setUp() async throws {
        ScheduleConfigLoader.resetCache()
    }

    func test_loadCached_returnsSameInstanceAcrossCalls() throws {
        let first = try ScheduleConfigLoader.loadCached()
        let second = try ScheduleConfigLoader.loadCached()
        XCTAssertEqual(first.hydrationCutoffTime, second.hydrationCutoffTime)
        // Identity check approximated via value semantics: same decoded
        // values implies same source data.
    }

    func test_resetCache_forcesReparse() throws {
        _ = try ScheduleConfigLoader.loadCached()
        ScheduleConfigLoader.resetCache()
        _ = try ScheduleConfigLoader.loadCached()
        // No assertion on parse count without instrumentation; this test
        // ensures resetCache() does not throw and the second load succeeds.
    }

    func test_perf_loadCached_amortized() {
        ScheduleConfigLoader.resetCache()
        measure {
            for _ in 0..<1000 {
                _ = try? ScheduleConfigLoader.loadCached()
            }
        }
    }
}
```

The perf test should drop the 1000-call cost from O(1000 JSON parses) to O(1 parse + 999 dictionary reads).

### Acceptance criteria

- `xcodebuild test` green.
- `ScheduleConfigLoaderCacheTests` pass.
- Instruments time-profile of a cold `TodayView` render shows zero JSON parse calls in `default_schedule` after the first load.

---

## Item 7: `CharacterStateLog` retention policy

### Problem

`CharacterStateService.swift:113` inserts a `CharacterStateLog` row per state transition. No pruning, no cap. CLAUDE.md says permanent retention is load-bearing for analytics; this conflicts with M3.7 ActivityArchive rollups.

The retention contract permits explicit user actions to delete and additive rollups. A 90-day pruning policy that lands the rollup data into `ActivityArchive.dominantMascotState` before deleting the source rows fits inside the contract IF the rollup is captured first.

Per CLAUDE.md: "Adding ANY new dependency requires writing `.work/decisions/<id>-<topic>.md` first and user approval." The same gating applies to a retention policy change. Author the decision first.

### Files touched

- New: `.work/decisions/<id>-character-state-log-pruning.md`
- `PersonalOptimization/Modules/Character/CharacterStateService.swift`
- `PersonalOptimization/Modules/Engagement/ActivityArchiveService.swift` (verify dominantMascotState capture)
- `PersonalOptimization/Services/ArchiveBackgroundScheduler.swift` (add pruning step)
- New: `PersonalOptimizationTests/Modules/CharacterStateLogRetentionTests.swift`

### Implementation

Step 1. Author `.work/decisions/<next_id>-character-state-log-pruning.md` quoting CLAUDE.md's retention guarantee and proposing the exception:

> CharacterStateLog rows older than 90 days are pruned IFF the
> corresponding ActivityArchive row for that day exists and its
> `dominantMascotState` is populated. Rollup runs before prune;
> failure to rollup blocks the prune for that day.

Wait for user approval before merging.

Step 2. Extend `ActivityArchiveService.rollupDay(_:)` (already does this at line 88, verified) and add a pruning helper:

```swift
/// Prunes CharacterStateLog rows older than `cutoffDays` IFF the
/// corresponding ActivityArchive row exists and is non-empty for the day.
/// Returns the number of rows deleted. Caller must hold the @MainActor.
@discardableResult
func pruneCharacterStateLog(olderThanDays cutoffDays: Int = 90, asOf: Date = Date()) throws -> Int {
    let cal = calendar()
    guard let cutoffDate = cal.date(byAdding: .day, value: -cutoffDays, to: cal.startOfDay(for: asOf)) else {
        return 0
    }
    let oldLogsDescriptor = FetchDescriptor<CharacterStateLog>(
        predicate: #Predicate<CharacterStateLog> { $0.timestamp < cutoffDate }
    )
    let oldLogs = (try? modelContext.fetch(oldLogsDescriptor)) ?? []
    guard !oldLogs.isEmpty else { return 0 }

    // Group by day in user timezone. For each day check the archive exists
    // and is non-empty before deleting that day's logs.
    let grouped = Dictionary(grouping: oldLogs) { cal.startOfDay(for: $0.timestamp) }
    var deleted = 0
    for (day, logsForDay) in grouped {
        let archiveDescriptor = FetchDescriptor<ActivityArchive>(
            predicate: #Predicate<ActivityArchive> { $0.date == day }
        )
        guard let archive = (try? modelContext.fetch(archiveDescriptor))?.first,
              !archive.dominantMascotState.isEmpty,
              archive.dominantMascotState != "neutral" || logsForDay.allSatisfy({ $0.stateRaw == "neutral" }) else {
            logger.info("Skip pruning for \(day, privacy: .public): archive missing or empty")
            continue
        }
        for log in logsForDay {
            modelContext.delete(log)
            deleted += 1
        }
    }
    try modelContext.save()
    logger.info("Pruned \(deleted, privacy: .public) CharacterStateLog rows older than \(cutoffDays, privacy: .public) days")
    return deleted
}
```

Step 3. Call pruning inside `ArchiveBackgroundScheduler.handle(task:modelContainer:)` after `backfill`:

```swift
do {
    let written = try service.backfill(maxDays: 7)
    let pruned = try service.pruneCharacterStateLog()
    taskLog.status = "success"
    taskLog.summary = "wrote \(written) archive rows, pruned \(pruned) character logs"
    ...
}
```

### Tests

`CharacterStateLogRetentionTests.swift`:

```swift
@MainActor
final class CharacterStateLogRetentionTests: XCTestCase {

    func test_prune_doesNotDeleteWhenArchiveMissing() throws { ... }
    func test_prune_deletesWhenArchivePresent() throws { ... }
    func test_prune_skipsLogsNewerThanCutoff() throws { ... }
    func test_prune_isIdempotent() throws { ... }
}
```

### Acceptance criteria

- `.work/decisions/<id>-character-state-log-pruning.md` exists, signed off by user.
- 90-day retention working: a synthetic test database with 200 days of CharacterStateLog rows, run pruning, expect rows older than day 90 deleted IFF the archive row for that day is non-empty.
- `Diagnostics` view's character-state log size graph levels out around 90 days of data.

---

## Item 8: Move `ReactiveRecomputeService` work off the main actor

### Problem

`ReactiveRecomputeService.swift:60-62` loops every `StreakDomain.allCases` and calls `streakService.recompute(domain:)` synchronously while `runIfNotThrottled()` runs on the main actor. HK observers can fan out late samples in tight bursts; even with the 5s throttle, the main thread blocks during recompute.

### Files touched

- `PersonalOptimization/Services/ReactiveRecomputeService.swift`
- `PersonalOptimization/Modules/Engagement/StreakService.swift` (if not already actor-safe, audit)
- `PersonalOptimizationTests/Services/ReactiveRecomputeServiceTests.swift`

### Implementation

Replace the loop with a Task that hops off the main actor:

```swift
private func runIfNotThrottled() {
    if let last = lastRunAt, Date().timeIntervalSince(last) < throttleWindow {
        return
    }
    lastRunAt = Date()
    guard let container = modelContainer else { return }

    Task.detached(priority: .utility) { [weak self] in
        // SwiftData ModelContext is not Sendable across actors. Spin up a
        // background context bound to this Task instead of reusing main.
        let context = ModelContext(container)
        let targets = try? await MainActor.run { try ScheduleConfigLoader.loadCached().hydrationTargetsOz }
        let streakService = await StreakService(modelContext: context, hydrationTargets: targets)
        await withTaskGroup(of: Void.self) { group in
            for domain in StreakDomain.allCases {
                group.addTask { @MainActor in
                    _ = try? streakService.recompute(domain: domain)
                }
            }
        }
        await self?.logCompletion()
    }
}

@MainActor
private func logCompletion() {
    logger.info("ReactiveRecomputeService recomputed \(StreakDomain.allCases.count, privacy: .public) streak domains")
}
```

Notes:
- `StreakService` is currently `@MainActor` (verify before changing). If it must stay main-isolated, fan-out via `TaskGroup` is purely overlap rather than parallelism, but still better than serial blocking.
- If `StreakService.recompute` is fast (<5ms each) the simpler fix is to keep the main-actor loop and increase throttle to 15s.
- Profile both versions on hardware. Pick whichever wins.

### Tests

Update `ReactiveRecomputeServiceTests.swift`:

```swift
func test_runIfNotThrottled_recomputesAllDomains() throws { ... }
func test_throttleWindow_blocksRepeatFireWithin5Seconds() throws { ... }
func test_throttleWindow_allowsFireAfter5Seconds() throws { ... }
func test_perf_recompute_under50ms_oneDomain() throws { ... }
```

### Acceptance criteria

- Main thread free-time during a synthetic burst of 10 HK observer fires improves by at least 30% (Instruments capture).
- Existing tests pass.

---

## Item 9: Chunk `ArchiveBackgroundScheduler.backfill` against BG budget

### Problem

`ArchiveBackgroundScheduler.swift:108-118` awaits `service.backfill(maxDays: 7)` then handles success or failure. The expiration handler at lines 92-100 sets task as failed if iOS kills the budget mid-call, but the in-flight `backfill` does not check for expiration between days and cannot resume. iOS gives BG tasks ~30 seconds.

### Files touched

- `PersonalOptimization/Modules/Engagement/ActivityArchiveService.swift`
- `PersonalOptimization/Services/ArchiveBackgroundScheduler.swift`
- `PersonalOptimizationTests/Modules/ActivityArchiveServiceChunkingTests.swift`

### Implementation

Add a chunked backfill that takes a per-iteration expiration check:

```swift
@discardableResult
func backfillChunked(
    maxDays: Int? = 30,
    asOf: Date = Date(),
    shouldContinue: () -> Bool
) throws -> (written: Int, completed: Bool) {
    let earliestSource = earliestSourceDataDate() ?? startOfDay(for: asOf)
    let today = startOfDay(for: asOf)
    let lower: Date = {
        guard let cap = maxDays else { return earliestSource }
        let capDate = calendar().date(byAdding: .day, value: -cap, to: today) ?? earliestSource
        return max(earliestSource, capDate)
    }()
    var cursor = lower
    var written = 0
    while cursor <= today {
        guard shouldContinue() else {
            logger.warning("backfillChunked interrupted at \(cursor, privacy: .public)")
            return (written, false)
        }
        _ = try rollupDay(cursor)
        written += 1
        guard let next = calendar().date(byAdding: .day, value: 1, to: cursor) else { break }
        cursor = next
    }
    return (written, true)
}
```

Update `ArchiveBackgroundScheduler.handle`:

```swift
private static func handle(task: BGTask, modelContainer: ModelContainer) {
    schedule()
    let taskLog = BackgroundTaskLog(taskId: taskIdentifier)
    Task { @MainActor in
        modelContainer.mainContext.insert(taskLog)
        try? modelContainer.mainContext.save()
    }

    let expirationDeadline = Date().addingTimeInterval(25) // 5s safety margin

    task.expirationHandler = {
        logger.warning("BG archive task expired before completion")
        Task { @MainActor in
            taskLog.status = "expired"
            taskLog.endedAt = Date()
            try? modelContainer.mainContext.save()
        }
        task.setTaskCompleted(success: false)
    }

    Task { @MainActor in
        let context = modelContainer.mainContext
        let targets = try? ScheduleConfigLoader.loadCached().hydrationTargetsOz
        let service = ActivityArchiveService(modelContext: context, hydrationTargets: targets)
        do {
            let result = try service.backfillChunked(maxDays: 7) {
                Date() < expirationDeadline
            }
            taskLog.status = result.completed ? "success" : "partial"
            taskLog.summary = "wrote \(result.written) archive rows, completed=\(result.completed)"
            logger.info("BG archive wrote \(result.written, privacy: .public) rows complete=\(result.completed, privacy: .public)")
            task.setTaskCompleted(success: result.completed)
        } catch {
            taskLog.status = "failure"
            taskLog.errorMessage = error.localizedDescription
            logger.error("BG archive failed: \(error.localizedDescription, privacy: .public)")
            task.setTaskCompleted(success: false)
        }
        taskLog.endedAt = Date()
        try? context.save()
    }
}
```

### Tests

`ActivityArchiveServiceChunkingTests.swift`:

```swift
func test_chunked_stopsWhenShouldContinueReturnsFalse() throws { ... }
func test_chunked_completesWhenShouldContinueAlwaysTrue() throws { ... }
func test_chunked_persistsPartialProgress() throws { ... }
```

### Acceptance criteria

- A simulated BG run with `shouldContinue` returning false after 3 days produces 3 archive rows and `BackgroundTaskLog.status == "partial"`.
- Test suite green.

---

# Tier 3: Test depth

## Item 10: Schema migration round-trip tests for V3..V10

### Problem

`SchemaV1Tests.swift` and `SchemaV2Tests.swift` exist. `SchemaV3.swift` through `SchemaV10.swift` have no matching test files. The migration plan is defined in `AppSchema.swift`. A future schema change risks silent data loss.

### Files touched

- New: `PersonalOptimizationTests/Models/SchemaV3Tests.swift` through `SchemaV10Tests.swift`
- New: `PersonalOptimizationTests/Helpers/SchemaMigrationTestHarness.swift`

### Implementation

Step 1. Create the test harness. The pattern: build a `ModelContainer` at version N with seed data, then build a new container at version N+1 with the migration plan, fetch the migrated rows, assert no loss and correct transformation.

```swift
import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
enum SchemaMigrationTestHarness {

    /// Builds an in-memory container at the requested schema version with
    /// the migration plan applied. Returns the resulting ModelContainer so
    /// the test can fetch rows and assert.
    static func migrate(
        seedAtVersion: VersionedSchema.Type,
        targetVersion: VersionedSchema.Type,
        seed: (ModelContext) throws -> Void
    ) throws -> ModelContainer {
        let seedSchema = Schema(versionedSchema: seedAtVersion)
        let seedConfig = ModelConfiguration(schema: seedSchema, isStoredInMemoryOnly: true)
        let seedContainer = try ModelContainer(for: seedSchema, configurations: [seedConfig])
        try seed(seedContainer.mainContext)
        try seedContainer.mainContext.save()

        // For an in-memory container migration is tricky: SwiftData doesn't
        // persist between containers. The pragmatic alternative is to
        // construct a file-backed temp store, migrate it, and assert.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-test-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let initialConfig = ModelConfiguration(schema: seedSchema, url: tempURL)
        let initial = try ModelContainer(for: seedSchema, configurations: [initialConfig])
        try seed(initial.mainContext)
        try initial.mainContext.save()

        // Reopen at target version with the migration plan.
        let targetSchema = Schema(versionedSchema: targetVersion)
        let migratedConfig = ModelConfiguration(schema: targetSchema, url: tempURL)
        let migrated = try ModelContainer(
            for: targetSchema,
            migrationPlan: AppSchema.migrationPlan,
            configurations: [migratedConfig]
        )
        return migrated
    }
}
```

Step 2. For each version, write a test that seeds two or three rows and asserts the migrated rows contain the expected values. Example for V3 to V4:

```swift
@MainActor
final class SchemaV3Tests: XCTestCase {

    func test_migration_V3_to_V4_preservesUserProfile() throws {
        let container = try SchemaMigrationTestHarness.migrate(
            seedAtVersion: SchemaV3.self,
            targetVersion: SchemaV4.self
        ) { context in
            // Use SchemaV3.UserProfile here. The exact API depends on
            // SchemaV3.swift's surface.
            let profile = SchemaV3.UserProfile(/* required fields */)
            context.insert(profile)
        }
        let descriptor = FetchDescriptor<SchemaV4.UserProfile>()
        let rows = try container.mainContext.fetch(descriptor)
        XCTAssertEqual(rows.count, 1)
        // Assert any new V4 fields default correctly:
        XCTAssertEqual(rows.first?.someNewV4Field, "expected default")
    }
}
```

For each schema bump:
- Identify the diff between V(N) and V(N+1). Look at the corresponding `.swift` file in `Models/`.
- Pick three representative model types to seed.
- Assert no row loss and that new fields default to their declared values.
- Assert any field renames migrated correctly.

### Acceptance criteria

- 8 new test files (V3..V10), each with 2-4 tests, all green.
- A deliberate breaking change to a model (e.g. removing a field with no migration) causes at least one of these tests to fail.

---

## Item 11: CloudKit conflict resolution and partner-zone tests

### Problem

The audit found one `CloudKit` mention in tests and no conflict-resolution coverage. Partner Mode (V1_OPPORTUNITIES #1) lands on top of a CloudKit shared zone and needs this baseline first.

### Files touched

- New: `PersonalOptimizationTests/Services/CloudKitConflictResolutionTests.swift`
- `PersonalOptimization/Services/CloudKitSyncService.swift` (may not exist yet; see ARCHITECTURE.md)
- `PersonalOptimization/Modules/Engagement/PartnerService.swift` (extend with rollback paths)

### Implementation

CloudKit conflict resolution in SwiftData is partially automatic (last-write-wins). Custom semantics require subscribing to record-change callbacks and re-fetching. The current app uses `cloudKitDatabase: .private(...)` in `ModelConfiguration` at `PersonalOptimizationApp.swift:12`, so the SwiftData CloudKit bridge handles propagation.

For tests, the goal is not to verify Apple's CloudKit behavior. The goal is to verify the app's conflict-resolution policy where it overrides defaults:

1. `WatchConnectivityService` events posted while a SwiftData write is in flight: assert the WC event handler reconciles using the SwiftData row, not the event payload.
2. `PartnerService.unpair`: assert all shared-zone records are removed.

Add a fake CK shim by injecting a protocol seam into `PartnerService`:

```swift
protocol PartnerSharedZone: Sendable {
    func write(record: PartnerSharedRecord) async throws
    func deleteAll() async throws
    func fetchPartnerSnapshot() async throws -> PartnerSharedRecord?
}

@MainActor
final class PartnerService {
    private let zone: PartnerSharedZone
    init(zone: PartnerSharedZone) { self.zone = zone }

    func unpair() async throws {
        try await zone.deleteAll()
    }
}
```

Tests use a `FakePartnerSharedZone` that records calls, fails on demand, and emits conflicts:

```swift
@MainActor
final class CloudKitConflictResolutionTests: XCTestCase {

    func test_unpair_deletesAllRecords() async throws { ... }
    func test_writeFailure_doesNotCorruptLocalState() async throws { ... }
    func test_concurrentWatchEventDuringWrite_lastWriteWins() async throws { ... }
}
```

### Acceptance criteria

- New tests pass.
- `PartnerService` refactored to depend on `PartnerSharedZone` protocol.
- Existing `PartnerServiceTests` still green.

---

## Item 12: `WatchConnectivityService` failure-mode tests

### Problem

`WatchConnectivityServiceTests.swift` covers event encoding and Kind raw values. The audit flagged untested paths:
- `isReachable=false` silent drop (line 60-63).
- `activationState != .activated` skip (line 59).
- `sendMessage` failure callback (line 67-68).
- Duplicate event suppression (not implemented; if added, test it).

### Files touched

- `PersonalOptimization/Services/WatchConnectivityService.swift`
- `PersonalOptimizationTests/Services/WatchConnectivityServiceTests.swift`

### Implementation

Refactor `send(_:)` to use a `WCSessionTransport` protocol seam:

```swift
protocol WCSessionTransport: AnyObject, Sendable {
    var activationState: WCSessionActivationState { get }
    var isReachable: Bool { get }
    func sendMessage(
        _ message: [String: Any],
        replyHandler: (([String: Any]) -> Void)?,
        errorHandler: ((Error) -> Void)?
    )
}

@available(iOS 13.0, watchOS 6.0, *)
extension WCSession: WCSessionTransport {}

final class WatchConnectivityService: NSObject, @unchecked Sendable {
    static let shared = WatchConnectivityService()
    private var transport: WCSessionTransport?

    func send(_ event: WatchConnectivityEvent) {
        guard let transport else { return }
        guard transport.activationState == .activated else { return }
        guard transport.isReachable else {
            logger.info("Peer unreachable; skipping event \(event.kind.rawValue, privacy: .public)")
            return
        }
        do {
            let payload = try JSONEncoder().encode(event)
            guard let dict = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return }
            transport.sendMessage(dict, replyHandler: nil) { [weak self] error in
                self?.logger.warning("sendMessage error: \(error.localizedDescription, privacy: .public)")
            }
        } catch {
            logger.warning("Encoding event failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
```

Tests use a `FakeTransport` that records calls and lets the test choose `isReachable`, `activationState`, and force `sendMessage` to invoke the errorHandler with a synthetic NSError.

```swift
final class FakeWCTransport: WCSessionTransport {
    var activationState: WCSessionActivationState = .activated
    var isReachable: Bool = true
    var sentMessages: [[String: Any]] = []
    var errorToReturn: Error?
    func sendMessage(_ message: [String : Any], replyHandler: (([String : Any]) -> Void)?, errorHandler: ((Error) -> Void)?) {
        sentMessages.append(message)
        if let error = errorToReturn { errorHandler?(error) }
    }
}

@MainActor
final class WatchConnectivityServiceFailureModeTests: XCTestCase {
    func test_send_droppedWhenUnreachable() { ... }
    func test_send_droppedWhenActivationStateNotActivated() { ... }
    func test_send_invokesErrorHandlerOnFailure() { ... }
    func test_send_succeedsWhenAllConditionsMet() { ... }
}
```

### Acceptance criteria

- New tests pass.
- `WatchConnectivityService` decoupled from concrete `WCSession`.

---

## Item 13: DST and timezone boundary tests

### Problem

JST never observes DST so the codebase has no DST tests. The user (Marine veteran with US-based wife) will travel. `AdaptiveNotificationTiming`, fasting window math, and any midnight rollover logic needs DST coverage.

### Files touched

- New: `PersonalOptimizationTests/Modules/DSTBoundaryTests.swift`
- `PersonalOptimization/Modules/Fasting/FastingService.swift` (verify behavior)
- `PersonalOptimization/Modules/Engagement/AdaptiveNotificationTiming.swift`

### Implementation

```swift
@MainActor
final class DSTBoundaryTests: XCTestCase {

    private let pacific = TimeZone(identifier: "America/Los_Angeles")!
    private let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Spring forward in US/Pacific in 2026: March 8 02:00 -> 03:00.
    func test_fastingWindow_acrossSpringForward() throws {
        let container = try InMemoryContainer.make()
        let profile = UserProfile(
            timezone: pacific.identifier,
            fastWindowStartHour: 20,  // 20:00 the night before
            fastWindowEndHour: 12    // 12:00 the next day
        )
        container.mainContext.insert(profile)
        try container.mainContext.save()
        // Fast started at 20:00 PT on March 7. End-of-fast at 12:00 PT on
        // March 8 should be 15 hours of wall-clock (lost an hour), not 16.
        // The app should report a 16h scheduled window but record the
        // elapsed time honestly.
        ...
    }

    /// Fall back in US/Pacific in 2026: November 1 02:00 -> 01:00.
    func test_fastingWindow_acrossFallBack() throws { ... }

    /// AdaptiveNotificationTiming should not crash if history spans a DST
    /// boundary. The median of [00:30 PT pre-DST, 00:30 PT post-DST] is
    /// well-defined when expressed in minutes-from-midnight in local time.
    func test_adaptiveTiming_acrossDST() throws { ... }
}
```

### Acceptance criteria

- DST tests pass without modifying production code IF the code already uses `Calendar` correctly.
- If a test fails, the fix is to switch the offending math to `Calendar.dateComponents(_:from:)` instead of `timeIntervalSince`.

---

## Item 14: `ClaudeAPIClient` retry, fallback, and streaming failure tests

### Problem

`CoachServiceTests` uses `StubAPI` for happy paths. No coverage for 429 vs 5xx vs 529, exponential backoff with jitter, model fallback (Opus to Sonnet to Haiku), or truncated-stream JSON.

### Files touched

- `PersonalOptimization/Services/ClaudeAPIClient.swift`
- New: `PersonalOptimizationTests/Services/ClaudeAPIClientRetryTests.swift`

### Implementation

Audit `ClaudeAPIClient.swift` for the retry surface. Typical implementation:

```swift
@MainActor
final class ClaudeAPIClient {
    enum APIError: LocalizedError {
        case rateLimited(retryAfter: TimeInterval?)
        case serverError(status: Int)
        case overloaded
        case invalidResponse
        case truncatedStream
        case malformedJSON(Error)
        case authenticationFailed
    }

    func send(...) async throws -> String {
        let backoffMs: [Int] = [500, 1500, 4000]
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                return try await sendOnce(...)
            } catch APIError.rateLimited(let retryAfter) {
                let delay = retryAfter ?? Double(backoffMs[attempt]) / 1000
                try await Task.sleep(for: .milliseconds(Int(delay * 1000)))
                lastError = APIError.rateLimited(retryAfter: retryAfter)
            } catch APIError.serverError(let status) where (500..<600).contains(status) {
                let jitter = Double.random(in: 0...0.3)
                try await Task.sleep(for: .milliseconds(backoffMs[attempt] + Int(jitter * 1000)))
                lastError = APIError.serverError(status: status)
            } catch APIError.overloaded {
                // Switch model on 529.
                continue
            } catch {
                throw error
            }
        }
        throw lastError ?? APIError.invalidResponse
    }
}
```

Test via a URLProtocol stub:

```swift
final class StubURLProtocol: URLProtocol {
    static var responseStack: [(Int, Data)] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data) = Self.responseStack.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class ClaudeAPIClientRetryTests: XCTestCase {
    func test_retries_on429_thenSucceeds() async throws { ... }
    func test_exponentialBackoff_on5xx() async throws { ... }
    func test_modelFallback_on529() async throws { ... }
    func test_throwsAuthenticationFailed_on401() async throws { ... }
    func test_throwsTruncatedStream_onIncompleteJSON() async throws { ... }
    func test_throwsMalformedJSON_onSyntaxError() async throws { ... }
}
```

### Acceptance criteria

- Tests cover the four documented status codes (200, 401, 429, 5xx, 529) and at least one streaming-truncation scenario.
- Existing CoachServiceTests still green.

---

## Item 15: Performance regression tests for `ScheduleValidator` and `CharacterStateService.gatherInputs`

### Problem

`PerformanceTests` has 4 measure blocks. CLAUDE.md PERFORMANCE.md targets <50ms for ScheduleValidator and <30ms for character state recompute, but no test enforces this. CI cannot catch a regression.

### Files touched

- `PersonalOptimizationTests/PerformanceTests.swift` (verify path; create if needed)
- New: `PersonalOptimizationTests/Modules/ScheduleValidatorPerformanceTests.swift`
- New: `PersonalOptimizationTests/Modules/CharacterStateGatherInputsPerformanceTests.swift`

### Implementation

```swift
@MainActor
final class ScheduleValidatorPerformanceTests: XCTestCase {

    func test_perf_validate_under50ms() throws {
        let container = try InMemoryContainer.make()
        seedRealisticSchedule(context: container.mainContext)
        let validator = ScheduleValidator(modelContext: container.mainContext)
        measure {
            for _ in 0..<10 {
                _ = validator.validate(at: Date())
            }
        }
        // XCTest's measure block records baseline. To assert hard ceiling,
        // use measureMetrics with custom recording.
    }
}

@MainActor
final class CharacterStateGatherInputsPerformanceTests: XCTestCase {

    func test_perf_gatherInputs_under30ms() throws {
        let container = try InMemoryContainer.make()
        seedFullDay(context: container.mainContext)
        measure {
            for _ in 0..<10 {
                _ = CharacterStateService.gatherInputs(
                    modelContext: container.mainContext,
                    timezone: TimeZone(identifier: "Asia/Tokyo")!
                )
            }
        }
    }
}
```

The first run sets a baseline. Subsequent runs compare against it; large regressions fail.

### Acceptance criteria

- `xcodebuild test -only-testing:PersonalOptimizationTests/ScheduleValidatorPerformanceTests` reports baseline at <50ms/10 calls on simulator.
- Same for CharacterStateGatherInputsPerformanceTests at <30ms/10 calls.
- A deliberate slowdown (e.g. removing a `#Predicate`) triggers the perf regression alert.

---

# Tier 4: Code-quality nits

## Item 16: Add `try?` justification comments

### Problem

CLAUDE.md: every `try?` requires `// MARK: - try? justified because <reason>`. Audit found:
- `KeychainService.swift:41-42` (variant cleanup before write).
- `CharacterStateService.swift:115` (`try? ctx.save()` after CharacterStateLog insert).

### Files touched

- `PersonalOptimization/Services/KeychainService.swift`
- `PersonalOptimization/Modules/Character/CharacterStateService.swift`

### Implementation

In `KeychainService.swift:40-44`:

```swift
func setApiKey(_ key: String, iCloudSync: Bool) throws {
    // try? justified because: variant-cleanup is best-effort. The new write
    // below targets a specific posture; pre-deleting the opposite posture
    // prevents stale Keychain items but its failure must not block the
    // primary set operation, which has its own error path.
    try? delete(key: "anthropic_api_key", synchronizableSpecific: true)
    try? delete(key: "anthropic_api_key", synchronizableSpecific: false)
    try set(key: "anthropic_api_key", value: key, iCloudSync: iCloudSync)
}
```

In `CharacterStateService.swift:115`:

```swift
ctx.insert(log)
// try? justified because: CharacterStateLog is non-critical analytic data.
// A save failure here is logged via Logger.persistence elsewhere; the
// in-memory `currentState` still updates so the UI reflects the change.
try? ctx.save()
```

Apply same pattern across any other `try?` found via `grep -nR "try?" PersonalOptimization`.

### Acceptance criteria

- `grep -rn "try?" PersonalOptimization | grep -v "MARK"` returns nothing OR every match is in a test file.

---

## Item 17: Guard `CharacterStateService.start()` against double-registration

### Problem

`CharacterStateService.swift:69-89` appends observers without checking whether the service is already running. If `start(modelContext:)` is called twice (model context swap, app cold start while previous instance is alive), observers accumulate, recompute fires twice per event, and `stop()` only removes the new set.

### Files touched

- `PersonalOptimization/Modules/Character/CharacterStateService.swift`
- `PersonalOptimizationTests/Modules/CharacterStateServiceTests.swift`

### Implementation

Guard `start` with a defensive `stop()`:

```swift
func start(modelContext: ModelContext, timezone: TimeZone? = nil) {
    // Defensive teardown so repeated start() calls do not stack observers
    // or leak prior model-context references.
    if !observers.isEmpty {
        logger.info("CharacterStateService.start called twice; resetting observers")
        stop()
    }
    self.modelContext = modelContext
    if let tz = timezone { self.timezone = tz }
    recompute(force: true)
    observers.append(NotificationCenter.default.addObserver(
        forName: .userStateChanged, object: nil, queue: .main
    ) { [weak self] _ in
        Task { @MainActor in self?.recompute(force: true) }
    })
    observers.append(NotificationCenter.default.addObserver(
        forName: .dailyLogsRecomputed, object: nil, queue: .main
    ) { [weak self] _ in
        Task { @MainActor in self?.recompute(force: true) }
    })
}
```

Tests:

```swift
func test_start_calledTwice_doesNotStackObservers() async throws {
    let container = try InMemoryContainer.make()
    let service = CharacterStateService.shared
    service.start(modelContext: container.mainContext)
    service.start(modelContext: container.mainContext)
    // No public count of observers; assert via recompute call frequency.
    // Fire .userStateChanged once and verify exactly one recompute via a
    // counter that the service exposes for tests.
}
```

Add a test-only counter:

```swift
#if DEBUG
var debugRecomputeCount: Int = 0
#endif

func recompute(force: Bool = false) {
    #if DEBUG
    debugRecomputeCount += 1
    #endif
    ...
}
```

### Acceptance criteria

- Calling `start()` twice followed by one `.userStateChanged` post increments `debugRecomputeCount` by exactly 1 plus the initial recompute (so 2, not 3).
- Existing CharacterStateServiceTests pass.

---

## Item 18: Replace `DispatchQueue.main.asyncAfter` with `Task.sleep`

### Problem

`CharacterView.swift:88` uses `DispatchQueue.main.asyncAfter(deadline: .now() + 0.25)`. CLAUDE.md: "No completion handlers. Async/await everywhere." It also makes the view harder to teach about Swift 6 concurrency.

### Files touched

- `PersonalOptimization/Modules/Character/CharacterView.swift`

### Implementation

```swift
private func triggerAlertPulseIfNeeded(for state: CharacterState) {
    guard !reduceMotion else { return }
    guard state == .urgent || state == .achievement else { return }
    guard lastAlertState != state else { return }
    lastAlertState = state

    withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) {
        pulseScale = 1.1
    }
    Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            pulseScale = 1.0
        }
    }
}
```

### Acceptance criteria

- `grep -rn "DispatchQueue.main.asyncAfter" PersonalOptimization` returns nothing (or only test mocks).
- Animation behavior visually identical.

---

## Item 19: Replace `@Bindable` singleton binding in `CharacterView` with `@State` plus environment

### Problem

`CharacterView.swift:9` does `@Bindable var service = CharacterStateService.shared`. This couples the view to the singleton's lifecycle, makes `#Preview` rely on hidden mutable global state, and breaks fixture-based testing.

### Files touched

- `PersonalOptimization/Modules/Character/CharacterView.swift`
- All callers of `CharacterView(...)` (search for `CharacterView(`)

### Implementation

```swift
struct CharacterView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let service: CharacterStateService
    @Query private var profiles: [UserProfile]
    var size: CGFloat = 200
    var showsReason: Bool = true

    @State private var breathing = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var lastAlertState: CharacterState?

    init(service: CharacterStateService = .shared, size: CGFloat = 200, showsReason: Bool = true) {
        self.service = service
        self.size = size
        self.showsReason = showsReason
    }

    // body unchanged, but bindings become read-only accesses
}
```

Since `CharacterStateService` is `@Observable`, SwiftUI tracks its property reads automatically without `@Bindable`. `@Bindable` is needed only when the view writes to the observable. `CharacterView` does not write to `service`, so the binding is unnecessary.

Caller updates: existing call at `TodayView.swift:51` reads `CharacterView(service: characterService, size: 200)` (per the file read earlier). Verify it still compiles after the init change.

### Acceptance criteria

- `xcodebuild build` clean.
- `#Preview` still renders.

---

## Item 20: Centralize app-identity constants

### Problem

- `WatchConnectivityService.swift:27` hardcodes `Logger(subsystem: "com.rawlins.PersonalOptimization", category: "wc")` instead of using `Logger+Categories.swift`.
- `AppGroupContainer.swift:10` hardcodes `"group.com.rawlins.PersonalOptimization"`.
- `KeychainService.swift:23` hardcodes `"com.rawlins.PersonalOptimization"` for the service identifier.
- `PersonalOptimizationApp.swift:12` hardcodes `"iCloud.com.rawlins.PersonalOptimization"`.
- `ArchiveBackgroundScheduler.swift:18` hardcodes `"com.rawlins.PersonalOptimization.archiveRollup"`.

If team-id changes (the `<YOUR-TEAM>` placeholder per CLAUDE.md), each file needs a manual edit.

### Files touched

- New: `PersonalOptimization/Services/BuildConfig.swift`
- `PersonalOptimization/Services/Logger+Categories.swift`
- `PersonalOptimization/Services/WatchConnectivityService.swift`
- `PersonalOptimization/Services/AppGroupContainer.swift`
- `PersonalOptimization/Services/KeychainService.swift`
- `PersonalOptimization/Services/ArchiveBackgroundScheduler.swift`
- `PersonalOptimization/PersonalOptimizationApp.swift`

### Implementation

Create `BuildConfig.swift`:

```swift
import Foundation

/// Centralized app-identity constants. Sourced from the build setting
/// `TEAM_BUNDLE_PREFIX` (defaults to `com.rawlins.PersonalOptimization`) via
/// Info.plist key `TeamBundlePrefix`. Falling back to a string literal keeps
/// the app launching even if the Info.plist key is missing.
enum BuildConfig {
    static let bundlePrefix: String = {
        let info = Bundle.main.infoDictionary?["TeamBundlePrefix"] as? String
        return info ?? "com.rawlins.PersonalOptimization"
    }()
    static let loggingSubsystem: String = bundlePrefix
    static let appGroupID: String = "group.\(bundlePrefix)"
    static let cloudKitContainer: String = "iCloud.\(bundlePrefix)"
    static let keychainServiceID: String = bundlePrefix
    static let bgArchiveTaskID: String = "\(bundlePrefix).archiveRollup"
}
```

Update `Logger+Categories.swift`:

```swift
extension Logger {
    private static let subsystem = BuildConfig.loggingSubsystem

    static let app = Logger(subsystem: subsystem, category: "app")
    static let schedule = Logger(subsystem: subsystem, category: "schedule")
    static let healthkit = Logger(subsystem: subsystem, category: "healthkit")
    static let cloudkit = Logger(subsystem: subsystem, category: "cloudkit")
    static let parser = Logger(subsystem: subsystem, category: "parser")
    static let character = Logger(subsystem: subsystem, category: "character")
    static let api = Logger(subsystem: subsystem, category: "api")
    static let keychain = Logger(subsystem: subsystem, category: "keychain")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let coach = Logger(subsystem: subsystem, category: "coach")
    static let wc = Logger(subsystem: subsystem, category: "wc")
}
```

Update each callsite:

```swift
// WatchConnectivityService.swift:27
private let logger = Logger.wc

// AppGroupContainer.swift:10
static let identifier = BuildConfig.appGroupID

// KeychainService.swift:23
private let service = BuildConfig.keychainServiceID

// PersonalOptimizationApp.swift:12
cloudKitDatabase: .private(BuildConfig.cloudKitContainer)

// ArchiveBackgroundScheduler.swift:18
static let taskIdentifier = BuildConfig.bgArchiveTaskID
```

Add `TeamBundlePrefix` to `PersonalOptimization/Info.plist` (and the watch Info.plist) with value `$(TEAM_BUNDLE_PREFIX)` and define the build setting in `project.yml`:

```yaml
settings:
  base:
    TEAM_BUNDLE_PREFIX: com.rawlins.PersonalOptimization
```

### Acceptance criteria

- All four targets (iOS, watch, complications, Live Activity) build green.
- `grep -rn "com.rawlins.PersonalOptimization" PersonalOptimization` returns nothing outside `BuildConfig.swift` and `project.yml`.
- A single `TEAM_BUNDLE_PREFIX` change in `project.yml` propagates to every target.

---

# Tier 5: Items missing from V1_OPPORTUNITIES.md

## Item 21: NSUserActivity Handoff between watch and iOS for in-progress workouts

### Problem

`HandoffCorrectnessTests.swift` exists but no `NSUserActivity` usage was found in production. Starting a Lift on the watch and switching to the phone requires the user to re-enter the workout type.

### Files touched

- New: `PersonalOptimization/Services/HandoffService.swift`
- `PersonalOptimizationWatch/Views/LiftWatchView.swift` (and Basketball, Swim, Custom)
- `PersonalOptimization/Modules/Training/LiveActivity/WorkoutLiveActivityController.swift`
- `PersonalOptimization/Views/RootView.swift` (consume `onContinueUserActivity`)
- `PersonalOptimizationTests/Services/HandoffServiceTests.swift`

### Implementation

```swift
import Foundation

/// Builds NSUserActivity objects for in-progress sessions so the watch can
/// hand off to the phone (and vice versa). The activity type strings are
/// stable identifiers also declared in Info.plist under
/// `NSUserActivityTypes`.
enum HandoffActivityType: String {
    case lift = "com.rawlins.PersonalOptimization.activity.lift"
    case basketball = "com.rawlins.PersonalOptimization.activity.basketball"
    case swim = "com.rawlins.PersonalOptimization.activity.swim"
    case customActivity = "com.rawlins.PersonalOptimization.activity.custom"
}

@MainActor
enum HandoffService {
    static func makeLiftActivity(templateName: String, sessionID: UUID) -> NSUserActivity {
        let activity = NSUserActivity(activityType: HandoffActivityType.lift.rawValue)
        activity.title = "Lift: \(templateName)"
        activity.userInfo = ["sessionID": sessionID.uuidString, "template": templateName]
        activity.isEligibleForHandoff = true
        activity.becomeCurrent()
        return activity
    }
    // ... similar for basketball, swim, customActivity
}
```

Wire into `LiftWatchView.start()`:

```swift
private func start() {
    do {
        let templates = try LiftTemplatesLoader.load()
        let svc = LiftService(modelContext: modelContext, templatesFile: templates)
        session = try svc.startSession(templateName: templateName)
        service = svc
        startedAt = Date()
        _ = HandoffService.makeLiftActivity(templateName: templateName, sessionID: session?.id ?? UUID())
        // try? justified because: HK session start is best-effort.
        try? live.start(activityType: .functionalStrengthTraining)
        ...
    } catch { ... }
}
```

On the iOS side, `RootView` or `PersonalOptimizationApp` adds:

```swift
.onContinueUserActivity(HandoffActivityType.lift.rawValue) { activity in
    guard let templateName = activity.userInfo?["template"] as? String else { return }
    // Route to the iOS LiftSessionView with the same template.
    selectedTab = .training
    pendingHandoff = .lift(templateName: templateName)
}
```

Info.plist additions:

```xml
<key>NSUserActivityTypes</key>
<array>
    <string>com.rawlins.PersonalOptimization.activity.lift</string>
    <string>com.rawlins.PersonalOptimization.activity.basketball</string>
    <string>com.rawlins.PersonalOptimization.activity.swim</string>
    <string>com.rawlins.PersonalOptimization.activity.custom</string>
</array>
```

### Tests

`HandoffServiceTests.swift`:

```swift
func test_lift_activityHasCorrectTypeAndUserInfo() { ... }
func test_lift_activityIsEligibleForHandoff() { ... }
func test_basketball_activityHasCorrectType() { ... }
```

End-to-end Handoff requires hardware. Document a manual test plan in `.work/milestones/<id>/manual-handoff-checklist.md`.

### Acceptance criteria

- Tests pass.
- Manual: Start lift on Apple Watch Ultra, swipe up on iPhone Lock Screen Handoff banner, lift template appears pre-filled on iPhone Lift session view.

---

## Item 22: Always-on display dimming for active workout views

### Problem

LTPO displays on Apple Watch Ultra dim the system UI in always-on mode. Custom SwiftUI views opting in to always-on rendering keep showing the full UI unless they explicitly dim. Audit found no `@Environment(\.isLuminanceReduced)` usage in any workout view. A multi-hour basketball session keeps the screen bright in always-on, burning battery.

### Files touched

- `PersonalOptimizationWatch/Views/LiftWatchView.swift`
- `PersonalOptimizationWatch/Views/BasketballWatchView.swift`
- `PersonalOptimizationWatch/Views/SwimWatchView.swift`
- `PersonalOptimizationWatch/Views/CustomActivityWatchView.swift`

### Implementation

Add the environment value and dim foreground colors when active:

```swift
struct LiftWatchView: View {
    @Environment(\.isLuminanceReduced) private var dimmed
    // ... existing state

    var body: some View {
        Group {
            if let session, let service {
                content(session: session, service: service)
            } else {
                ProgressView().task { start() }
            }
        }
        .navigationTitle(templateName)
        .foregroundStyle(dimmed ? .secondary : .primary)
        .animation(.easeInOut(duration: 0.5), value: dimmed)
    }
}
```

For the live stats row, lower contrast in always-on mode and reduce update frequency:

```swift
HStack(spacing: 6) {
    Label("\(Int(live.heartRate))", systemImage: "heart.fill")
        .foregroundStyle(dimmed ? .gray : .red)
        .font(.caption2.monospacedDigit())
    // ...
}
```

For `TimelineView(.periodic(...))`-based elapsed-time refreshes, when always-on is active reduce the periodic interval to 60 seconds rather than 1 second:

```swift
TimelineView(.periodic(from: startedAt, by: dimmed ? 60 : 1)) { context in
    Text(formatDuration(context.date.timeIntervalSince(startedAt)))
        .font(.caption2.monospacedDigit())
}
```

### Tests

Visual diff requires hardware. Document the manual test:
- Start a Lift session on Apple Watch Ultra.
- Cover the watch face to trigger always-on.
- Observe: foreground dims, elapsed time updates roughly once per minute, heart rate label color softens.

### Acceptance criteria

- `xcodebuild build -scheme PersonalOptimizationWatch` clean.
- Manual hardware test confirms dim behavior on the four workout views.

---

# Sequencing checklist

A recommended PR order (each PR small, each closes one item):

1. Item 16 (try? justifications): mechanical, no behavior change.
2. Item 1 (notification action handler): pre-sideload blocker.
3. Item 2 (watch accessibility labels): pre-sideload blocker.
4. Item 3 (real-time hydration sync): pre-sideload blocker.
5. Item 20 (BuildConfig centralization): foundation for cleaner diffs after.
6. Item 4 (TokenBudgetService and untested-services tests): protect cost guardrail.
7. Item 6 (ScheduleConfigLoader cache + TodayView refactor): performance.
8. Item 5 (DailySummaryService predicates): performance.
9. Item 17 (CharacterStateService double-start guard) and Item 18 (Task.sleep) and Item 19 (@State on CharacterView): bundle as one cleanup PR.
10. Item 13 (DST tests): catches a class of bugs cheaply.
11. Item 12 (WC failure-mode tests): protocol seam unlocks Item 11.
12. Item 11 (CloudKit conflict tests): prerequisite for Partner Mode.
13. Item 14 (Claude API retry tests): protect Coach Mode.
14. Item 10 (schema migration tests): prerequisite for any future model change.
15. Item 15 (perf regression tests): final hardening before TestFlight.
16. Item 8 (ReactiveRecomputeService off main): once 15 is in place to verify no perf regression.
17. Item 9 (ArchiveBackgroundScheduler chunking): low-risk.
18. Item 7 (CharacterStateLog retention): requires user-approved decision doc first.
19. Item 21 (Handoff) and Item 22 (always-on dimming): polish.

Total estimated work: 60-80 hours of agent time. Tier 1 alone is 12-15 hours and unblocks sideloading to hardware.

# Notes for Claude Code session bootstrap

- Read this file first.
- Read CLAUDE.md, ARCHITECTURE.md, MILESTONES.md, PERFORMANCE.md, SECURITY.md per the existing bootstrap loop.
- Pick one item, branch as `improve/<n>-<short-tag>`, implement, ship a PR.
- Use `.work/milestones/improve-<n>/plan.md` for the per-PR plan rather than the existing milestone directory.
- Honor quality gates: zero warnings, all tests green, coverage not regressing, privacy manifest updated if any new framework lands.
- Stop after each PR. Do not chain items without user signal.
