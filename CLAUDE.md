# CLAUDE.md

Project context. Claude Code reads this every session before responding. Treat as authoritative.

## Project

Native iOS 18+ and watchOS 11+ app for daily protocol tracking. Single user (Clay, 31, Okinawa JST). Zero servers, zero accounts, ZERO third-party Swift packages.

## User Communication Preferences (mandatory, every response)

1. **Absolute Mode**: no emojis, no filler, no hype, no soft asks, no conversational transitions, no call-to-action appendixes.
2. **No em dashes ever**. Use commas, periods, parentheses, or restructure.
3. **Show formulas, code, configuration explicitly**. Error-check outputs before presenting.
4. **Verify current data** before answering technical or setup questions. Search docs/web rather than rely on training data for fast-moving topics.
5. **Clarify the actual ask** before responding when ambiguous.
6. **Treat user as co-engineer**, not a customer. High perception assumed.
7. **No unsolicited security warnings, ethics warnings, or "consider consulting a professional" addendums**.
8. **Direct, brief responses preferred**. Long responses only when complexity justifies them.
9. **Quote the spec, do not paraphrase** when asked what the spec says.

## User Profile

- 31 years old, 6'2", 205 lbs, male.
- Marine veteran (2012-2021), former Amazon SDE (2021-2024).
- Student at Embry-Riddle Worldwide (BS Technical Management, ~90 credits, graduating April 2027).
- Located Uruma City, Okinawa, Japan, JST timezone (UTC+9).
- Family: wife active duty Marine E-6, three young children.
- Constraints: Achilles tendonosis (no running). Daily kid drop-off 0900, pickup 1700, Mon-Fri.
- Tech: Java, Python, React, Spring, AWS, CI/CD. Early in Swift but systems-thinking wired.

## Tech Stack (locked, see ARCHITECTURE.md for rationale)

| Layer | Choice |
|-------|--------|
| UI | SwiftUI (iOS + watchOS) |
| Persistence | SwiftData |
| Sync | CloudKit private database |
| Cross-device messaging | WatchConnectivity |
| Health metrics | HealthKit |
| Workouts | HKWorkoutSession + HKLiveWorkoutBuilder |
| Notifications | UserNotifications (local only, no APNs) |
| Live Activities | ActivityKit (M2 fasting timer, M3 workouts) |
| Widgets | WidgetKit (M6 home screen widgets) |
| Secrets | Keychain via custom KeychainService |
| PDF parsing | PDFKit + Vision OCR fallback |
| Optional AI | Anthropic API direct, opt-in only |
| Charts | Swift Charts |
| Animations | Native SwiftUI (transitions, spring, scaleEffect) |
| Mascot character | Static PNG assets in Asset Catalog (M6.5) |

NO third-party packages. No CocoaPods, no Carthage, no SPM dependencies beyond Apple frameworks. Adding ANY new dependency requires writing `.work/decisions/<id>-<topic>.md` first and user approval.

## Concurrency Model

- Swift 6 strict concurrency mode enabled.
- Persistent services are `@MainActor` unless they specifically run in background (e.g., `BiomarkerPDFParser` runs on a parsing actor, `HealthKitService` uses observation actors).
- Use `actor` for shared mutable state across tasks.
- Use `Task` for kicking off async work, `TaskGroup` for parallel work.
- Use `AsyncStream` for HealthKit observation, never NotificationCenter wrappers.
- No completion handlers. Async/await everywhere.
- No Combine for new code. SwiftUI `@Observable` macro replaces it.
- All `@Model` types are Sendable by default in SwiftData.

## Data Retention (load-bearing from M3.7 onward)

SwiftData retention is **permanent**. There is no auto-delete code, no TTL-based cleanup, no "after N days" purge. The full activity history (sessions, daily logs, biomarkers, character state log) is preserved forever in the user's iCloud-backed private database. TrendAnalyticsService and CoachService v2 depend on this guarantee to produce year-plus historical context.

Allowed deletions (explicit user actions only):
- ScheduleEditorView swipe-to-delete on a ScheduleBlock
- ScheduleSeed.resetToDefault (preserves user-marked isCustom blocks)
- JSONImportService.replaceAll (called only when user imports a file)
- KeychainService.deleteApiKey (Settings -> AI -> Remove API key)

ActivityArchive (added M3.7) is an additive rollup; it does not replace or supersede source-of-truth session rows. Source rows remain intact even if archives are corrupted or migrated.

If you find yourself writing `modelContext.delete(...)` inside a service method that runs on a timer, BG task, or any non-user-action path: stop. That violates retention. Add a TODO and surface it.

## Error Handling

- Errors are typed, conform to `LocalizedError`, and thrown.
- Never `try?` without an explicit `// MARK: - try? justified because <reason>` comment.
- All public throwing functions document failure modes in doc comment.
- User-facing errors surface via `ErrorBanner` SwiftUI component (defined M1).
- Logging via `os.Logger`. Never `print()` in production code.
- Subsystem identifier: `com.<YOUR-TEAM>.PersonalOptimization`.

```swift
import os

extension Logger {
    static let schedule = Logger(subsystem: "com.<YOUR-TEAM>.PersonalOptimization", category: "schedule")
    static let healthkit = Logger(subsystem: "com.<YOUR-TEAM>.PersonalOptimization", category: "healthkit")
    static let cloudkit = Logger(subsystem: "com.<YOUR-TEAM>.PersonalOptimization", category: "cloudkit")
    static let parser = Logger(subsystem: "com.<YOUR-TEAM>.PersonalOptimization", category: "parser")
    static let character = Logger(subsystem: "com.<YOUR-TEAM>.PersonalOptimization", category: "character")
    static let api = Logger(subsystem: "com.<YOUR-TEAM>.PersonalOptimization", category: "api")
}
```

Use OSLogPrivacy attributes on user data:

```swift
Logger.parser.info("Parsed \(values.count, privacy: .public) markers from \(filename, privacy: .private) at \(date, privacy: .public)")
```

## File Layout

```
optimization-app/
├── PersonalOptimization.xcodeproj
├── PersonalOptimization/                       # iOS target
│   ├── PersonalOptimizationApp.swift
│   ├── Info.plist
│   ├── PersonalOptimization.entitlements
│   ├── PrivacyInfo.xcprivacy
│   ├── Resources/
│   │   ├── default_schedule.json
│   │   ├── biomarker_catalog.json
│   │   ├── biomarker_aliases.json
│   │   └── Localizable.xcstrings
│   ├── Assets.xcassets/
│   │   ├── AppIcon.appiconset/
│   │   ├── AccentColor.colorset/
│   │   └── Mascot/                             # M6.5: 8 character state PNGs
│   │       ├── neutral.imageset/
│   │       ├── thirsty.imageset/
│   │       ├── fasting.imageset/
│   │       ├── urgent.imageset/
│   │       ├── proud.imageset/
│   │       ├── disappointed.imageset/
│   │       ├── tired.imageset/
│   │       └── achievement.imageset/
│   ├── Models/                                 # SwiftData @Model classes (one per file)
│   ├── Modules/
│   │   ├── Schedule/
│   │   ├── Fasting/
│   │   ├── Hydration/
│   │   ├── Training/
│   │   ├── Learning/
│   │   ├── Coursework/
│   │   ├── Admin/
│   │   ├── Biomarkers/
│   │   ├── Character/                          # M6.5
│   │   └── Analytics/
│   ├── Services/
│   │   ├── HealthKitService.swift
│   │   ├── NotificationService.swift
│   │   ├── WatchConnectivityService.swift
│   │   ├── KeychainService.swift
│   │   ├── CloudKitSyncService.swift
│   │   ├── ClaudeAPIClient.swift
│   │   └── Logger+Categories.swift
│   ├── Views/
│   │   ├── RootView.swift
│   │   ├── TodayView.swift
│   │   ├── HistoryView.swift
│   │   └── SettingsView.swift
│   └── Components/                             # Reusable UI
├── PersonalOptimizationWatch/                  # watchOS target
│   ├── PersonalOptimizationWatchApp.swift
│   ├── Info.plist
│   ├── PersonalOptimizationWatch.entitlements
│   ├── Complications/
│   ├── Workouts/
│   ├── Views/
│   └── ConnectivityHandler.swift
├── PersonalOptimizationWidgets/                # Widget extension (M6)
│   ├── HydrationWidget.swift
│   ├── FastingWidget.swift
│   ├── ScheduleWidget.swift
│   └── PersonalOptimizationWidgetsBundle.swift
├── PersonalOptimizationLiveActivity/           # Live Activity extension (M2, M3)
│   ├── FastingLiveActivity.swift
│   └── WorkoutLiveActivity.swift
└── PersonalOptimizationTests/
    ├── ScheduleTests.swift
    ├── FastingTests.swift
    ├── HydrationTests.swift
    ├── BiomarkerParserTests.swift
    ├── PhenoAgeTests.swift
    ├── PatternDetectionTests.swift
    └── CharacterStateTests.swift
```

## Bundle ID Configuration

- iOS bundle ID: `com.<YOUR-TEAM>.PersonalOptimization`
- Watch bundle ID: `com.<YOUR-TEAM>.PersonalOptimization.watchkitapp`
- Widget extension: `com.<YOUR-TEAM>.PersonalOptimization.widgets`
- Live Activity extension: `com.<YOUR-TEAM>.PersonalOptimization.liveactivity`
- App Group: `group.com.<YOUR-TEAM>.PersonalOptimization`
- CloudKit container: `iCloud.com.<YOUR-TEAM>.PersonalOptimization`

The agent prompts user for `<YOUR-TEAM>` value at bootstrap and replaces all occurrences before first build.

## Coding Conventions

- Indent: 4 spaces (Apple default).
- Line length: 120 characters soft limit, 140 hard.
- Naming: PascalCase types, camelCase functions/properties, SCREAMING_SNAKE for compile-time constants.
- One public type per file; file name matches type name.
- Service classes: singletons accessed via static `shared`.
- All views have `#Preview` macro with seeded sample data via in-memory ModelContainer.
- All async functions use `throws`. Return `Result` only when caller specifically needs synchronous error handling.
- No force unwraps in production code. `// swiftlint:disable force_unwrapping` permitted only in tests and `#Preview`.
- Localization: en-US baseline. All user-facing strings in `Localizable.xcstrings` from day one. Use `String(localized:)`.
- Accessibility: `.accessibilityLabel()` on every custom control. `@ScaledMetric` for sizing. `@Environment(\.accessibilityReduceMotion)` for animations.
- Date math: always use `Calendar.current` with explicit timezone, never raw `Date` arithmetic.
- All times stored as UTC, converted to user timezone (`UserProfile.timezone`) only at display.

## Bootstrap Sequence (every session)

1. Read CLAUDE.md (this file), README.md, PROJECT_BRIEF.md, ARCHITECTURE.md, DATA_MODELS.md, MILESTONES.md, PERFORMANCE.md, TESTING.md, SECURITY.md.
2. Confirm understanding by listing user's top 3 communication preferences and the current milestone's Definition of Done.
3. If `.work/state.json` exists, read it and resume the active milestone.
4. If not, ask user for the 3 bootstrap inputs from BOOTSTRAP.md.
5. Begin execution.

## Execution Loop (per milestone)

For each milestone in MILESTONES.md:

1. **Plan**. Read milestone tasks, identify dependencies, parallelizable work, token budget. Write plan to `.work/milestones/<id>/plan.md`.
2. **Surface unknowns**. If any task requires user input, ask now. Do not guess.
3. **Execute**. Implement tasks in dependency order. After each task, run tests and commit.
4. **Verify**. Confirm Definition of Done items pass. Run performance benchmarks per PERFORMANCE.md.
5. **Close**. Open PR, merge to main, tag commit `m<id>-complete`. Update `.work/state.json`.
6. **Stop**. Do not start next milestone without user signal.

## Workspace Conventions

- `.work/` directory: agent state, plans, logs (gitignored).
- `.work/state.json`: active milestone, last task, last commit.
- `.work/decisions/`: architectural decisions with rationale.
- `.work/milestones/<id>/`: per-milestone plans, scratch notes, completion artifacts.

## Quality Gates

Each milestone closes only when ALL pass:

1. `xcodebuild -scheme PersonalOptimization build` succeeds with zero warnings on Xcode 16.
2. `xcodebuild test -scheme PersonalOptimizationTests` passes.
3. Watch target builds: `xcodebuild -scheme PersonalOptimizationWatch build`.
4. Widget extension builds (after M6 introduces it).
5. Performance benchmarks for the milestone pass per PERFORMANCE.md.
6. New code has unit tests; coverage stays above 70% on Models/Services.
7. Privacy manifest (`PrivacyInfo.xcprivacy`) updated if new HealthKit/CloudKit/Network usage added.
8. PR created, reviewed by user, merged to main.
9. Git tag `m<id>-complete` pushed.

## Failure Recovery

If a milestone fails Quality Gate:

1. Do not move to next milestone.
2. Log failure in `.work/milestones/<id>/failures.md` with reproduction steps.
3. Decompose failing item into smaller sub-tasks.
4. Implement sub-tasks one at a time, each with its own quality gate.
5. Resume normal execution only after original Quality Gate passes.

## Token Efficiency

Token costs add up over a 100-hour build. Apply these patterns:

1. **Read files once per session**. Cache in agent memory; do not re-read unchanged files.
2. **Quote, do not paraphrase**. When user asks "what does the spec say about X", quote directly.
3. **Use grep before viewing**. Locate symbols with grep, view only matching range.
4. **Stream large outputs**. For files over 200 lines, stream rather than load entire file as context.
5. **Defer reference docs**. References/ files load only when corresponding milestone is active.
6. **Batch tool calls**. Multiple Read calls fit in one tool turn.

## When to Ask vs Proceed

**Ask the user**:
- Decision affecting multiple milestones (architecture change, dependency addition).
- Asset acquisition required (mascot PNGs, app icon).
- Apple Developer account, certificates, signing required.
- Ambiguous spec admitting multiple valid interpretations.
- Cost-impacting choice (TestFlight vs simulator-only, Opus vs Sonnet).

**Proceed without asking**:
- Implementation details within a defined module.
- Naming a private helper.
- Choosing between two equivalent SwiftUI patterns.
- Refactoring code style for clarity.
- Adding tests for existing code.

When in doubt, ask. User prefers one extra clarifying question over wrong work.

## Reference Files

- `References/biomarker-tracker.html`: validated logic for biomarker module. Port to Swift, do not redesign. Used at M5.
- `References/default_schedule.json`: schedule seed data, copy into Resources/ at M1.
- `References/sample_lab_dod.json`: parser regression target at M5. Original PDF dropped at `References/sample_lab_dod.pdf` by user before M5 starts.
- `References/character_brief.md`: mascot aesthetic and 8-state spec for M6.5.
- `References/gemini_workflow.md`: step-by-step Gemini web prompts for character art generation at M6.5.

## What NOT to Build

1. Multi-user, accounts, authentication.
2. Server backend, web service, REST API.
3. Brand-specific wearable integrations (Whoop, Oura, Garmin all funnel through Apple Health).
4. ML model training. Pattern detection is rule-based by design.
5. Anki integration (deferred to day-90 trigger).
6. Apple Health Records direct VA pull. Manual lab PDF upload is v1 path.
7. Sharing, social, leaderboards.
8. Cross-platform (Android, web). iOS + watchOS only.
9. visionOS or Mac Catalyst.
10. Rive integration. Static PNG mascot at M6.5; defer Rive to v1.5+ if user asks.

## Definition of "Done" for the Whole Project

v1.0 ships when:

1. All 8 milestones (M1, M2, M3, M4, M5, M6, M6.5, M7) close cleanly.
2. App runs on iPhone 16 Pro and Apple Watch Ultra 2 hardware.
3. 7-day end-to-end usability test on simulator passes (manual time advancement, no crashes, all reminders fire correctly, all data round-trips).
4. Performance targets in PERFORMANCE.md met on real hardware.
5. Privacy manifest filed; nutrition labels prepared per SECURITY.md.
6. App icon and watch face complications shipped.
7. Either: TestFlight build deployed (paid Apple Developer) OR sideloaded to user's hardware via free dev cert.
8. README updated with screenshots and final feature list.
9. Git tag `v1.0` pushed.

## Design Principles for Engagement Decisions (load-bearing from M3.5 onward)

These principles override any prior copy-design or notification choice when in conflict. Source: 2024-2025 systematic reviews on habit formation app design (see PIVOT_SPEC.md for citations).

1. Implementation intentions over reminders. Anchor every notification and prompt to a trigger event (after coffee, after dinner, on block start), not a clock time, when feasible.
2. Streaks need mercy. Always honor freezes, sick day, and travel mode. Never fake completion to preserve a streak; preserve it via explicit pause.
3. Notification minimum effective dose. One nudge per behavior per day max. Suppress if logged. Personalize timing from history after day 14.
4. Identity framing over task framing. Confirmation copy reinforces who the user is, not what task is done.
5. Friction reduction first. Tap-to-log beats motivational copy. Multi-step logging kills habits.
6. One master metric. Foreground today's protocol adherence as a single number. Sub-metrics one tap away.
7. Mascot reflects state, never theater. Sad mascot must mean a real miss. Achievement is rare and earned.

Apply these principles to every UI/copy/notification decision from M3.5 forward. When in doubt, choose the option that respects the user's autonomy and reduces friction.
