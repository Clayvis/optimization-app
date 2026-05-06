# DATA_MODELS.md

Complete SwiftData model definitions. Locked. Claude Code implements these exactly. Adding fields, removing fields, or changing types requires a decision record.

Place each `@Model` in its own file under `PersonalOptimization/Models/`.

---

## UserProfile.swift

```swift
import Foundation
import SwiftData

@Model
final class UserProfile {
    var name: String
    var dob: Date
    var sex: String                  // "male" | "female"
    var heightInches: Double
    var weightLbs: Double
    var timezone: String             // IANA, e.g. "Asia/Tokyo"
    var fastWindowStartHour: Int     // 22 = 22:00
    var fastWindowEndHour: Int       // 10 = 10:00
    var bottleSizeOz: Double         // default 32
    var anthropicModel: String       // "claude-sonnet-4-6" | "claude-opus-4-7" | "claude-haiku-4-5-20251001"
    var rolloutPhase: Int            // 1 = weeks 1-2 fast schedule, 2 = weeks 3+
    var notificationBundling: Bool   // false = individual alerts, true = morning summary
    var mascotEnabled: Bool          // M6.5: hide mascot if user prefers
    var reducedMotion: Bool          // App-level override of system reduced-motion

    init(name: String = "", dob: Date = .distantPast, sex: String = "male") {
        self.name = name
        self.dob = dob
        self.sex = sex
        self.heightInches = 74
        self.weightLbs = 205
        self.timezone = "Asia/Tokyo"
        self.fastWindowStartHour = 22
        self.fastWindowEndHour = 10
        self.bottleSizeOz = 32
        self.anthropicModel = "claude-sonnet-4-6"
        self.rolloutPhase = 1
        self.notificationBundling = false
        self.mascotEnabled = true
        self.reducedMotion = false
    }
}
```

---

## ScheduleBlock.swift

```swift
import Foundation
import SwiftData

@Model
final class ScheduleBlock {
    var dayOfWeek: Int               // 1=Mon ... 7=Sun (ISO 8601)
    var startTime: String            // "HH:mm" 24h JST
    var endTime: String              // "HH:mm"
    var activity: String
    var typeRaw: String              // BlockType.rawValue
    var module: String?              // "lift_a", "basketball", "japanese", etc.
    var isOverride: Bool             // true if user customized for this date
    var overrideDate: Date?          // populated when isOverride == true

    var type: BlockType { BlockType(rawValue: typeRaw) ?? .other }

    init(dayOfWeek: Int, startTime: String, endTime: String, activity: String, type: BlockType, module: String? = nil) {
        self.dayOfWeek = dayOfWeek
        self.startTime = startTime
        self.endTime = endTime
        self.activity = activity
        self.typeRaw = type.rawValue
        self.module = module
        self.isOverride = false
        self.overrideDate = nil
    }
}

enum BlockType: String, Codable {
    case transit, training, study, learning, admin, recovery, other
}
```

---

## DailyLog.swift

```swift
import Foundation
import SwiftData

@Model
final class DailyLog {
    @Attribute(.unique) var date: Date     // midnight in user's local TZ
    var fastStart: Date?
    var fastEnd: Date?
    var fastBrokeEarly: Bool
    var fastBreakReason: String?
    var waterOz: Double
    var electrolyteSessions: Int
    var japaneseMinutes: Int
    var guitarMinutes: Int
    var courseworkMinutes: Int
    var subjectiveEnergy: Int?       // 1-10
    var achillesPain: Int?           // 1-10
    var sleepHours: Double?          // from HealthKit
    var restingHR: Int?              // from HealthKit
    var hrvRmssd: Double?            // from HealthKit
    var weightLbs: Double?           // from HealthKit or manual
    var notes: String?

    init(date: Date) {
        self.date = Calendar.current.startOfDay(for: date)
        self.fastBrokeEarly = false
        self.waterOz = 0
        self.electrolyteSessions = 0
        self.japaneseMinutes = 0
        self.guitarMinutes = 0
        self.courseworkMinutes = 0
    }
}
```

---

## LiftSession.swift

```swift
import Foundation
import SwiftData

@Model
final class LiftSession {
    var date: Date
    var template: String             // "Lift A" | "Lift B"
    @Relationship(deleteRule: .cascade, inverse: \LiftExercise.session)
    var exercises: [LiftExercise]
    var totalVolumeLbs: Double
    var durationMinutes: Int
    var avgHR: Int?
    var notes: String?

    init(date: Date, template: String) {
        self.date = date
        self.template = template
        self.exercises = []
        self.totalVolumeLbs = 0
        self.durationMinutes = 0
    }
}

@Model
final class LiftExercise {
    var name: String
    var orderIndex: Int
    @Relationship(deleteRule: .cascade, inverse: \LiftSet.exercise)
    var sets: [LiftSet]
    var rpe: Int?                    // 1-10 perceived exertion
    var session: LiftSession?

    init(name: String, orderIndex: Int) {
        self.name = name
        self.orderIndex = orderIndex
        self.sets = []
    }
}

@Model
final class LiftSet {
    var weightLbs: Double
    var reps: Int
    var restSeconds: Int?
    var orderIndex: Int
    var exercise: LiftExercise?

    init(weightLbs: Double, reps: Int, orderIndex: Int) {
        self.weightLbs = weightLbs
        self.reps = reps
        self.orderIndex = orderIndex
    }
}
```

---

## BasketballSession.swift

```swift
import Foundation
import SwiftData

@Model
final class BasketballSession {
    var date: Date
    var startTime: Date
    var endTime: Date
    var avgHR: Int?
    var maxHR: Int?
    var hrZoneMinutes: [String: Int] // "zone1": 12, "zone2": 45, ...
    var hydrationOz: Double
    var achillesPostScore: Int?      // 1-10 logged after session
    var notes: String?

    init(date: Date, startTime: Date, endTime: Date) {
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
        self.hrZoneMinutes = [:]
        self.hydrationOz = 0
    }
}
```

---

## SwimSession.swift

```swift
import Foundation
import SwiftData

@Model
final class SwimSession {
    var date: Date
    var poolLengthMeters: Double     // configurable, default 25
    var laps: Int
    var totalMeters: Double
    var durationMinutes: Int
    var avgHR: Int?
    var location: String?            // "McTureous" | "Hansen"

    init(date: Date, poolLengthMeters: Double = 25) {
        self.date = date
        self.poolLengthMeters = poolLengthMeters
        self.laps = 0
        self.totalMeters = 0
        self.durationMinutes = 0
    }
}
```

---

## LabDraw.swift

```swift
import Foundation
import SwiftData

@Model
final class LabDraw {
    @Attribute(.unique) var date: Date
    var notes: String?
    var values: [String: Double]     // key from BiomarkerCatalog
    var sourcePdfFilename: String?   // for re-parsing if alias dictionary updates

    init(date: Date, values: [String: Double] = [:]) {
        self.date = date
        self.values = values
    }
}
```

---

## WearableEntry.swift

```swift
import Foundation
import SwiftData

@Model
final class WearableEntry {
    var date: Date
    var source: String               // "oura" | "whoop" | "garmin" | "apple" | "manual"
    var metrics: [String: Double]    // hrv_rmssd, resting_hr, sleep_score, etc.
    var notes: String?

    init(date: Date, source: String) {
        self.date = date
        self.source = source
        self.metrics = [:]
    }
}
```

---

## ProtocolEntry.swift

```swift
import Foundation
import SwiftData

@Model
final class ProtocolEntry {
    var date: Date
    var category: String             // "supplement", "lifestyle", "retest"
    var title: String
    var notes: String?
    var dose: String?
    var retestDate: Date?
    var completed: Bool
    var completedAt: Date?

    init(date: Date, category: String, title: String) {
        self.date = date
        self.category = category
        self.title = title
        self.completed = false
    }
}
```

---

## PomodoroSession.swift

```swift
import Foundation
import SwiftData

@Model
final class PomodoroSession {
    var date: Date
    var courseTag: String            // "PMGT 325"
    var workMinutes: Int             // 25 or 50
    var breakMinutes: Int            // 5 or 10
    var completedCycles: Int
    var notes: String?

    init(date: Date, courseTag: String, workMinutes: Int = 50, breakMinutes: Int = 10) {
        self.date = date
        self.courseTag = courseTag
        self.workMinutes = workMinutes
        self.breakMinutes = breakMinutes
        self.completedCycles = 0
    }
}
```

---

## AdminTask.swift

```swift
import Foundation
import SwiftData

@Model
final class AdminTask {
    var title: String
    var category: String             // "ssdi" | "vre" | "saas" | "other"
    var dueDate: Date?
    var completed: Bool
    var completedAt: Date?
    var notes: String?
    var createdAt: Date

    init(title: String, category: String) {
        self.title = title
        self.category = category
        self.completed = false
        self.createdAt = Date()
    }
}
```

---

## LearningStreak.swift

```swift
import Foundation
import SwiftData

@Model
final class LearningStreak {
    @Attribute(.unique) var module: String   // "japanese" | "guitar"
    var currentStreak: Int
    var longestStreak: Int
    var lastCompletedDate: Date?
    var totalMinutesAllTime: Int

    init(module: String) {
        self.module = module
        self.currentStreak = 0
        self.longestStreak = 0
        self.totalMinutesAllTime = 0
    }
}
```

---

## CharacterStateLog.swift (added at M6.5)

```swift
import Foundation
import SwiftData

@Model
final class CharacterStateLog {
    var timestamp: Date
    var stateRaw: String                 // CharacterState.rawValue
    var triggerReason: String            // human-readable why this state fired
    var durationSeconds: Int?            // populated when state ends

    init(timestamp: Date, state: CharacterState, triggerReason: String) {
        self.timestamp = timestamp
        self.stateRaw = state.rawValue
        self.triggerReason = triggerReason
    }
}

/// 8 character states. Each maps to one PNG asset in Assets.xcassets/Mascot/.
enum CharacterState: String, Codable, CaseIterable {
    case neutral       // default
    case thirsty       // hydration low (intensity scales urgency)
    case fasting       // in fast window
    case urgent        // block starting/late
    case proud         // streak hit milestone
    case disappointed  // streak broken / behind on goals
    case tired         // sleep/recovery low
    case achievement   // PR / weekly review hit all targets

    /// Asset Catalog image name for this state.
    var assetName: String {
        switch self {
        case .neutral: return "MascotNeutral"
        case .thirsty: return "MascotThirsty"
        case .fasting: return "MascotFasting"
        case .urgent: return "MascotUrgent"
        case .proud: return "MascotProud"
        case .disappointed: return "MascotDisappointed"
        case .tired: return "MascotTired"
        case .achievement: return "MascotAchievement"
        }
    }

    /// Precedence order. Earlier index wins when multiple states match.
    static let precedenceOrder: [CharacterState] = [
        .urgent, .achievement, .proud, .disappointed,
        .tired, .thirsty, .fasting, .neutral
    ]
}
```

---

## CharacterStateService.swift (added at M6.5)

`@Observable` service. Recomputes character state from all data sources every 30 seconds and on relevant SwiftData writes. Outputs current state to `currentState` property consumed by `CharacterView`.

```swift
import Foundation
import SwiftData
import Observation
import os

@Observable
@MainActor
final class CharacterStateService {
    static let shared = CharacterStateService()

    private(set) var currentState: CharacterState = .neutral
    private(set) var triggerReason: String = "default"

    private var modelContext: ModelContext?
    private var timer: Timer?
    private let logger = Logger.character

    private init() {}

    func start(modelContext: ModelContext) {
        self.modelContext = modelContext
        recompute()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recompute() }
        }
    }

    func recompute() {
        guard let ctx = modelContext else { return }
        let candidates = evaluateAllStates(context: ctx)
        let resolved = resolvePrecedence(candidates)
        if resolved.state != currentState {
            logger.info("State transition: \(self.currentState.rawValue) -> \(resolved.state.rawValue) reason=\(resolved.reason, privacy: .public)")
            logTransition(to: resolved.state, reason: resolved.reason, context: ctx)
            currentState = resolved.state
            triggerReason = resolved.reason
        }
    }

    /// Evaluate all 8 states. Return all that match; resolvePrecedence picks winner.
    private func evaluateAllStates(context: ModelContext) -> [(state: CharacterState, reason: String)] {
        var results: [(CharacterState, String)] = []
        let now = Date()

        // Implementation queries SwiftData for:
        // - Today's DailyLog (water, fast times, sleep, HRV)
        // - Active ScheduleBlock (current block, next block timing)
        // - LearningStreak (Japanese, Guitar) for proud/disappointed
        // - LiftSession + SwimSession latest for achievement
        // - BasketballSession for Achilles concern (rolled into disappointed)
        // - UserProfile for fast window times
        //
        // Rules:
        // - urgent: nextBlock.start - now < 5 min AND nextBlock.module != nil
        //          OR currentBlock.end < now AND currentBlock not logged complete
        // - achievement: lift volume PR OR swim distance PR set today
        //                OR weekly review hit all 7 targets
        // - proud: any streak hit 7/30/100 milestone today
        // - disappointed: any streak broken in last 24h
        //                 OR Achilles pain >= 6 logged in last 48h
        //                 OR <50% hydration past 18:00
        // - tired: sleep_hours < 6 OR hrv down 20% from 7-day rolling avg
        // - thirsty: water_oz / expected_oz_for_time < 0.6
        //            (intensity: <0.3 increases visual urgency via state.intensity property)
        // - fasting: now in fast window
        // - neutral: fallback

        return results
    }

    private func resolvePrecedence(_ candidates: [(CharacterState, String)]) -> (state: CharacterState, reason: String) {
        for state in CharacterState.precedenceOrder {
            if let match = candidates.first(where: { $0.0 == state }) {
                return (state, match.1)
            }
        }
        return (.neutral, "default")
    }

    private func logTransition(to new: CharacterState, reason: String, context: ModelContext) {
        let log = CharacterStateLog(timestamp: Date(), state: new, triggerReason: reason)
        context.insert(log)
        try? context.save()
    }
}
```

---

## ModelContainer Setup

In `PersonalOptimizationApp.swift`:

```swift
import SwiftUI
import SwiftData

@main
struct PersonalOptimizationApp: App {
    let container: ModelContainer = {
        let schema = Schema([
            UserProfile.self,
            ScheduleBlock.self,
            DailyLog.self,
            LiftSession.self, LiftExercise.self, LiftSet.self,
            BasketballSession.self,
            SwimSession.self,
            LabDraw.self,
            WearableEntry.self,
            ProtocolEntry.self,
            PomodoroSession.self,
            AdminTask.self,
            LearningStreak.self,
            CharacterStateLog.self,
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.com.<YOUR-TEAM>.PersonalOptimization")
        )
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
```

Replace `<YOUR-TEAM>` with Apple Developer reverse-domain identifier on first build.

## Schema Versioning

From M1, all schemas use `VersionedSchema`:

```swift
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [UserProfile.self, ...] }
}
```

When a schema change is needed, create `SchemaV2`, `SchemaV3`, etc. and a `MigrationPlan`.

## Notes for Claude Code

1. All Date fields default to UTC. Convert to `UserProfile.timezone` only at display.
2. `[String: Double]` and `[String: Int]` dictionary fields require SwiftData Codable transformation. Use `@Attribute(.transformable(by: ...))` if SwiftData rejects them on first build, otherwise let SwiftData auto-handle.
3. `@Relationship(deleteRule: .cascade)` is critical for `LiftSession.exercises` and `LiftExercise.sets`. Inverse keypaths required.
4. `DailyLog.date`, `LabDraw.date`, and `LearningStreak.module` are uniqued. Inserting duplicates is a programmer error.
5. CloudKit requires all relationships to be optional or have a default. Verify with build.
6. `CharacterStateLog` is append-only. Never edit, only insert.
7. All models conform to Sendable automatically via SwiftData macros.
