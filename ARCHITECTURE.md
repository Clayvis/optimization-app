# ARCHITECTURE.md

Locked technical decisions. Not open for debate during planning. Changing a decision requires writing `.work/decisions/<id>-<topic>.md` first with rationale, alternatives considered, and impact analysis.

## Platforms

- iOS: 18.0+ minimum.
- watchOS: 11.0+ minimum.
- Mac Catalyst: not supported.
- visionOS: not supported.

iOS 18 baseline gives access to: SwiftData with CloudKit sync, ActivityKit Live Activities (Dynamic Island), App Intents, Control Center widgets, Translation framework, ScreenshotKit. No deployment target lower than iOS 18 supported.

## Language and Framework Versions

- Swift 6.0+ with strict concurrency mode enabled.
- SwiftUI for all UI on both targets.
- Swift Concurrency (async/await, actors). No completion handlers, no Combine for new code.
- `@Observable` macro replaces `ObservableObject` + `@Published`.

## Persistence

- SwiftData for all local persistence.
- All `@Model` classes live in `Models/` directory, one file per model.
- CloudKit sync via SwiftData's built-in CloudKit container support.
- Schema versioning via `VersionedSchema` from day one. Migration plan for every schema change.

## Sync

- CloudKit private database. Single user, no sharing.
- Container ID: `iCloud.com.<YOUR-TEAM>.PersonalOptimization`.
- No CKShare, no public database.
- WatchConnectivity for low-latency phone-to-watch updates (live workout state, immediate logging confirmations).
- Conflict resolution: last-write-wins per record, except for streaks (custom merge: take max of currentStreak).

## HealthKit

- Read: bodyMass, restingHeartRate, heartRateVariabilitySDNN, sleepAnalysis, stepCount, activeEnergyBurned, basalEnergyBurned, walkingHeartRateAverage, vo2Max.
- Write: workouts (.functionalStrengthTraining for lift, .basketball, .swimming), bodyMass on manual entry, dietaryWater on hydration log.
- Background delivery: enabled for sleepAnalysis and bodyMass.
- Privacy manifest entry required for each data type.

## Workouts

- Lift: HKWorkoutSession with .functionalStrengthTraining, indoor location.
- Basketball: HKWorkoutSession with .basketball, configurable indoor/outdoor.
- Swim: HKWorkoutSession with .swimming, pool location, configurable pool length (default 25m for McTureous).
- Live data: HKLiveWorkoutBuilder on watch, mirrored to phone via WatchConnectivity.
- Auto-pause: enabled via WorkoutConfiguration where supported.

## Notifications

- UserNotifications framework, local only.
- No remote push, no APNs, no notification service extension.
- Categories registered at app launch in `NotificationService.shared.register()`.
- Smart suppression rules implemented as filters before scheduling.
- Critical alerts entitlement NOT requested (Achilles pain doesn't qualify).

## Live Activities (M2 onward)

- ActivityKit framework.
- Active activities: fasting timer, current workout, study Pomodoro.
- Dynamic Island presentations: compact, expanded, minimal.
- Lock screen presentation included.
- Activity attributes use ContentState pattern with start/end dates so OS can compute progress without app updates.

## Widgets (M6 onward)

- WidgetKit framework.
- Home screen sizes: small, medium, large.
- Lock screen sizes: circular, rectangular, inline.
- Smart Stack ranking via TimelineProvider relevance scores.
- Configuration via App Intents (iOS 17+ pattern).
- Widget kinds: hydration progress, fast countdown, today's schedule, current streaks.

## Secrets

- Keychain via custom `KeychainService` wrapper.
- Stored items: Anthropic API key (single string).
- Access via `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (no iCloud sync of keys).
- Never log keys, never write to UserDefaults, never include in JSON export.

## PDF Parsing

- Primary: PDFKit `PDFDocument.string` for text-based PDFs.
- Fallback: Vision `VNRecognizeTextRequest` for scanned PDFs (detected when text extraction yields fewer than 50 lines).
- Algorithm: see `References/biomarker-tracker.html` `parseLines()`. Port directly.
- DOD MTF detection: count of "Laboratory" sentinel lines >= 3 triggers DOD pair extraction.

## Anthropic API

- Endpoint: `https://api.anthropic.com/v1/messages`.
- Models: `claude-opus-4-7`, `claude-sonnet-4-6` (default), `claude-haiku-4-5-20251001`.
- API version header: `2023-06-01`.
- API calls only on explicit user action (never automatic, never silent).
- Network calls in dedicated `ClaudeAPIClient` actor. URLSession with default configuration plus custom timeoutInterval=60s.
- Errors surfaced to UI via ErrorBanner component with user-readable message.

## Charts

- Swift Charts framework.
- iPhone: trend visualizations, biomarker overlays, weekly review aggregates.
- Watch: simple gauges and progress bars only (Swift Charts support on watchOS limited).

## Animations

- All animations native SwiftUI: `.animation`, `.transition`, `.scaleEffect`, `.opacity`, `.offset`, `withAnimation`.
- Mascot character: static PNGs with cross-fade transitions, subtle breathing scale animation, alert-triggered scale pulse.
- Reduced motion: `@Environment(\.accessibilityReduceMotion)` toggles all decorative animations.
- No third-party animation libraries.

## Project Structure

```
PersonalOptimization.xcodeproj
├── PersonalOptimization (iOS app target, deployment iOS 18.0)
├── PersonalOptimizationWatch (watchOS app target, deployment watchOS 11.0)
├── PersonalOptimizationWidgets (widget extension, M6)
├── PersonalOptimizationLiveActivity (Live Activity extension, M2)
└── PersonalOptimizationTests (unit test target)
```

## Code Organization

```
PersonalOptimization/
├── PersonalOptimizationApp.swift             # @main, ModelContainer setup
├── Resources/                                 # Bundled JSON seed data
├── Assets.xcassets/                           # Images, colors, mascot PNGs
├── Models/                                    # SwiftData @Model classes
├── Modules/                                   # Feature modules
│   └── <ModuleName>/
│       ├── <ModuleName>Service.swift         # Business logic singleton
│       ├── <ModuleName>View.swift            # Top-level view
│       └── Components/                        # Module-specific subviews
├── Services/                                  # Cross-cutting services
├── Views/                                     # Top-level navigation
└── Components/                                # Reusable UI
```

## SwiftData Models (final list, see DATA_MODELS.md)

13 models total:

1. UserProfile
2. ScheduleBlock
3. DailyLog
4. LiftSession + LiftExercise + LiftSet (3 related)
5. BasketballSession
6. SwimSession
7. LabDraw
8. WearableEntry
9. ProtocolEntry
10. PomodoroSession
11. AdminTask
12. LearningStreak
13. CharacterStateLog (added at M6.5)

Adding any model requires writing a decision record.

## Testing

- XCTest for unit tests.
- No mocking framework. Hand-rolled test doubles only.
- Snapshot tests deferred until v0.5+.
- CI: GitHub Actions on push to main and PR. Build, test, lint.
- See TESTING.md for full strategy.

## Linting

- SwiftLint via SPM build plugin (Apple-supported pattern, not third-party runtime).
- If SwiftLint causes friction, drop it. Code style enforced by review.

## Localization

- Base: en-US. All user-facing strings in `Localizable.xcstrings` from day one.
- No additional locales for v1.

## Accessibility

- VoiceOver labels on all custom controls.
- Dynamic Type respected via `@ScaledMetric`.
- Reduced motion variants for all decorative animations.
- Color contrast: AA minimum, AAA for primary text.

## CI / Build

- Xcode 16.0+ for development.
- `xcodebuild` from CLI for headless builds.
- Build commands run by Claude Code:
  - `xcodebuild -scheme PersonalOptimization -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build`
  - `xcodebuild test -scheme PersonalOptimizationTests -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
- Watch builds: `-scheme PersonalOptimizationWatch -destination 'platform=watchOS Simulator,name=Apple Watch Ultra 2 (49mm)'`
- Widget builds: `-scheme PersonalOptimizationWidgets`

## Apple Developer Account

- Free personal team works for development and 7-day device installs.
- Paid Apple Developer Program ($99/year) required for:
  - HealthKit background delivery
  - Push notifications (not used in v1)
  - TestFlight distribution
  - App Store submission
- Decision required before M7. Default assumption: paid account by M7.

## Privacy Manifest

`PrivacyInfo.xcprivacy` required from M1. Updated as features land:

| Milestone | Privacy entries added |
|-----------|----------------------|
| M1 | NSUserTrackingUsageDescription (none, set to N/A) |
| M2 | NSHealthShareUsageDescription, NSHealthUpdateUsageDescription |
| M3 | Workout types added to HealthKit usage |
| M5 | Camera/Photo access if PDF photo capture added (DEFER, file picker only for v1) |
| M6 | Widget timeline data |
| M7 | Notification authorization rationale |

## Dependencies

ZERO. All Apple frameworks. If any third-party need arises, write a decision record first and pause for user approval.

## What's Different from a Generic iOS App

1. **Privacy-first by default**: no analytics, no crash reporting third-party SDKs, no marketing pixels. Use MetricKit for crash data, OSLog for diagnostics.
2. **Watch-first UX**: phone is for configuration and review, watch is for daily interaction. Optimize watch performance over phone.
3. **Offline-first**: app fully functional without internet. Anthropic API calls are the only network operations and are explicitly opt-in.
4. **Single user**: no auth flow, no user switching, no profiles beyond UserProfile entity.
5. **Mascot as retention**: character emotional state is core UX, not decoration. Drives behavior.
