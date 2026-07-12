# TESTING.md

Test strategy for the v1 build. Tests are required for every milestone close per Quality Gates.

## Frameworks

- XCTest for unit tests.
- XCTest with `XCUIApplication` for UI tests (deferred to v0.5+).
- No third-party mocking framework. Hand-rolled test doubles only.

## Coverage Targets

| Layer | Coverage |
|-------|----------|
| Models (SwiftData entities) | 70%+ |
| Services (business logic) | 80%+ |
| Modules (feature logic) | 70%+ |
| Views | 50%+ via Preview validation |
| Parsers (PDF, JSON) | 90%+ |
| Formula calculators (PhenoAge, streaks, adherence) | 95%+ |

Run coverage report: `xcodebuild test -scheme PersonalOptimization -enableCodeCoverage YES`.

## Test File Organization

```
PersonalOptimizationTests/
├── Helpers/
│   ├── InMemoryContainer.swift           # ModelContainer factory for tests
│   ├── TestData.swift                    # Sample data builders
│   └── DateHelpers.swift                 # Date math helpers for fixtures
├── Models/
│   ├── UserProfileTests.swift
│   ├── ScheduleBlockTests.swift
│   └── ... (one per model)
├── Modules/
│   ├── ScheduleServiceTests.swift
│   ├── FastingServiceTests.swift
│   ├── HydrationServiceTests.swift
│   ├── BiomarkerParserTests.swift
│   ├── PhenoAgeTests.swift
│   ├── PatternDetectionTests.swift
│   ├── CharacterStateServiceTests.swift
│   └── ...
├── Services/
│   ├── HealthKitServiceTests.swift
│   ├── KeychainServiceTests.swift
│   └── ...
└── PerformanceTests.swift
```

## In-Memory Container Pattern

All tests use an in-memory ModelContainer to avoid touching disk and CloudKit:

```swift
import SwiftData
@testable import PersonalOptimization

enum InMemoryContainer {
    static func make() throws -> ModelContainer {
        let schema = Schema([
            UserProfile.self, ScheduleBlock.self, DailyLog.self,
            // ... all 13 models
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }
}
```

## Test Data Builders

```swift
enum TestData {
    static func userProfile(name: String = "Test", sex: String = "male") -> UserProfile {
        UserProfile(name: name, dob: Date(timeIntervalSince1970: 764985600), sex: sex)
    }

    static func scheduleBlock(day: Int = 1, start: String = "09:00", end: String = "10:00") -> ScheduleBlock {
        ScheduleBlock(dayOfWeek: day, startTime: start, endTime: end, activity: "Test", type: .training)
    }

    static func liftSession(exerciseCount: Int = 4) -> LiftSession {
        let session = LiftSession(date: Date(), template: "Lift A")
        for i in 0..<exerciseCount {
            let exercise = LiftExercise(name: "Exercise \(i)", orderIndex: i)
            session.exercises.append(exercise)
        }
        return session
    }

    // ... one builder per entity
}
```

## Test Patterns

### Pattern 1: Pure function

```swift
func test_PhenoAge_KnownInputProducesKnownOutput() {
    let values: [String: Double] = [
        "albumin": 4.6, "creatinine": 1.15, "glucose": 100,
        "hs_crp": 0.5, "lymphocyte_pct": 37.2, "mcv": 88.0,
        "rdw": 13.9, "alk_phos": 56, "wbc": 5.10
    ]
    let result = PhenoAge.calculate(values: values, age: 31.5)
    XCTAssertEqual(result ?? 0, 31.2, accuracy: 0.5)
}
```

### Pattern 2: Service with model context

```swift
@MainActor
func test_ScheduleService_CurrentBlockReturnsCorrectBlock() throws {
    let container = try InMemoryContainer.make()
    let context = container.mainContext

    let block = TestData.scheduleBlock(day: 2, start: "10:00", end: "14:00")
    context.insert(block)
    try context.save()

    let service = ScheduleService(modelContext: context)
    let monday11am = Calendar.current.date(/* Monday 11:00 */)!
    let current = service.currentBlock(at: monday11am)

    XCTAssertEqual(current?.activity, "Test")
}
```

### Pattern 3: State machine with overlapping conditions

```swift
@MainActor
func test_CharacterStateService_UrgentBeatsTired() {
    // Set up data: tired AND urgent both true
    // Verify resolved state is .urgent (higher precedence)
}
```

### Pattern 4: Parser regression

```swift
func test_PDFParser_DODPanelExtracts25Markers() throws {
    let url = Bundle(for: type(of: self)).url(forResource: "sample_lab_dod", withExtension: "pdf")!
    let result = try PDFParser.parse(url: url, sex: "male")
    XCTAssertEqual(result.values.count, 25)
    XCTAssertEqual(result.values["glucose"], 100)
    XCTAssertEqual(result.values["tsh"], 0.425)
    XCTAssertEqual(result.values["creatinine"], 1.15)
    // ... all 25 markers
}
```

## What to Test

### Always test

- Pure functions (formulas, parsers, validators).
- State machines (Pomodoro, Fasting, Character).
- Date math (timezone conversions, day-of-week, fast windows).
- JSON serialization/deserialization round-trips.
- SwiftData @Model relationships and cascade deletes.
- Streak calculators with edge cases (gap day, midnight rollover, timezone change).
- Pattern detection rules with known biomarker fixtures.
- Notification suppression rules.

### Test where reasonable

- Services with model context (use InMemoryContainer).
- Views via `#Preview` rendering (manual verification, not automated assertion).
- Watch complication rendering.

### Skip in v1

- HealthKit integration (test on device manually, requires real data).
- CloudKit sync (test manually across simulators).
- Notification delivery (test on device).
- Anthropic API calls (mock the URLSession instead of hitting live API).
- Live Activities (test on device).
- Widget timeline updates (test in simulator with widget gallery).

## Test Doubles

No mocking framework. Build hand-rolled doubles when needed:

```swift
// Test double for HealthKitService that returns canned data
final class FakeHealthKitService: HealthKitServiceProtocol {
    var stubbedSleepHours: Double = 7.5
    var stubbedHRV: Double = 45.0
    var stubbedRHR: Int = 58

    func fetchSleepHours(date: Date) async throws -> Double { stubbedSleepHours }
    func fetchHRV(date: Date) async throws -> Double { stubbedHRV }
    func fetchRestingHR(date: Date) async throws -> Int { stubbedRHR }
}
```

This requires defining `HealthKitServiceProtocol` so production code can accept either real or fake. Use protocols for any service that does network or device I/O.

## Test Naming

`test_<UnitUnderTest>_<Scenario>_<ExpectedOutcome>`

Examples:
- `test_PhenoAge_AllRequiredMarkersPresent_ReturnsCalculatedAge`
- `test_PhenoAge_MissingHsCRP_ReturnsNil`
- `test_FastingService_DuringFastWindow_ReturnsFasting`
- `test_FastingService_OutsideFastWindow_ReturnsEating`
- `test_StreakCalculator_GapDay_ResetsStreak`
- `test_StreakCalculator_ConsecutiveDays_IncrementsStreak`

## Snapshot Testing

Deferred to v0.5+. Adding snapshot testing requires either:
- Custom hand-rolled image diff (expensive, error-prone).
- Adopting `swift-snapshot-testing` SPM package (requires architecture decision record).

For v1, use `#Preview` macros with seeded data and visually verify on simulator.

## CI Integration

GitHub Actions runs `.github/workflows/ios-ci.yml` on every pull request to
`main`, every push to `main`, and manual dispatch. The workflow pins the
generally available `macos-26` runner to Xcode 26.4.1 and tests against the
iPhone 17 Pro / iOS 26.4.1 simulator. It runs schema parity, asset validation,
the full unit suite, code coverage, and the repository's zero-warning policy.
The `.xcresult` bundle and complete build log are retained for 14 days.

Date-sensitive tests inject their calendar/timezone explicitly. Tests must not
depend on the developer Mac or hosted simulator's `TimeZone.current` value.

TestFlight delivery remains in Xcode Cloud because it owns the Apple signing
configuration. Protect `main` with the `Build and test` status check so Xcode
Cloud only sees commits that passed GitHub CI before merge.

The local pre-push hook runs the same core checks before code leaves a Mac.

Install once per clone:

```sh
sh scripts/install_git_hooks.sh
```

`scripts/pre_push_test_gate.sh` then runs on every `git push`: schema-parity
guard, asset guard, the full unit suite, and a zero-warning check. A red suite
or any build warning blocks the push.

- Bypass once (use sparingly): `git push --no-verify`
- Fast push, parity guards only: `SKIP_TESTS=1 git push`
- Override the simulator: `TEST_SIM='platform=iOS Simulator,name=iPhone 17 Pro' git push`

If a self-hosted macOS runner with the matching Xcode becomes available, the
same `xcodebuild ... test` invocation can move into a GitHub Actions job
verbatim; until then the pre-push hook is the source of truth.

## Manual Test Checklist (per milestone)

In addition to automated tests, run these manually before closing each milestone:

- M1: Boot phone simulator, boot watch simulator, modify on phone, see change on watch.
- M2: Start fast, see Live Activity. Tap watch to log water, see phone update.
- M3: Start lift workout from watch, log 5 sets, end workout, see in Apple Health.
- M4: Run Pomodoro on watch, hear haptic at break.
- M5: Drop sample DOD PDF, parse, see 25 markers extracted.
- M6: Wait until Sunday simulated time, see weekly review notification.
- M6.5: Cycle through all 8 character states by manipulating data, verify each PNG renders.
- M7: Run 7-day simulator test, verify zero crashes.

## Test Independence

- Every test creates a fresh InMemoryContainer.
- Tests must not depend on order.
- Tests must not depend on external state (filesystem, network, current time without `Date(timeIntervalSinceReferenceDate:)`).
- Time-dependent tests inject a `() -> Date` clock function.
