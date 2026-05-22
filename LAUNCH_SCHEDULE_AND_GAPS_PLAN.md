# LAUNCH_SCHEDULE_AND_GAPS_PLAN.md

Two parts. Hand off to Claude Code one section at a time.

- Part A: launch and schedule re-haul. Fixes the 1800-1900 assumption bug, replaces hardcoded template times with a "shape + your anchors" model, and tightens the daily-launch experience on TodayView.
- Part B: detailed implementation for the six items left open from `IMPROVEMENT_IMPLEMENTATION_PLAN.md`.

All file paths absolute. All diffs grounded in files read before writing this doc. No em dashes. Direct.

---

# Part A: Launch and schedule re-haul

## A0. Root cause of the 1800-1900 assignment

Confirmed by reading `PersonalOptimization/Resources/schedule_balanced.json`:

```json
{
    "version": 1,
    "timezone": "UTC",
    "blocks": [
        { "dayOfWeek": 1, "startTime": "18:00", "endTime": "19:00", "activity": "Lift A", "type": "training", "module": "lift_a" },
        { "dayOfWeek": 2, "startTime": "18:00", "endTime": "19:00", "activity": "Cardio (basketball)", ... },
        { "dayOfWeek": 3, "startTime": "18:00", "endTime": "19:00", "activity": "Lift B", ... },
        { "dayOfWeek": 4, "startTime": "18:00", "endTime": "19:00", "activity": "Cardio (swim)", ... },
        { "dayOfWeek": 5, "startTime": "18:00", "endTime": "19:00", "activity": "Lift A", ... },
        { "dayOfWeek": 7, "startTime": "10:00", "endTime": "10:30", "activity": "Weekly review", ... }
    ]
}
```

Flow that produced your 18:00-19:00 lift:

1. `OnboardingView.swift:308`: `try? ScheduleTemplateApplier.apply(template, modelContext: modelContext)` on tap.
2. `ScheduleTemplateChooserView.swift:148` `ScheduleTemplateApplier.apply` calls `ScheduleSeed.resetToTemplate(resourceName: "schedule_balanced", ...)`.
3. `ScheduleSeed.swift:87` wipes non-custom blocks then inserts JSON blocks verbatim. Times are taken straight from the file.

So the app never asked. The same anchor-time hardcoding lives in `schedule_gym_focused.json`, `schedule_language_focused.json`, and `schedule_fasting_focused.json` (verified via shell). Fasting-focused training rows are 17:00-18:00, language-focused training rows are 18:00-18:30, gym-focused has 17:30-19:00 and 10:00-11:30. None of those anchors were ever chosen by the user.

The AI generation path (`ScheduleAIService.swift`) does take anchor input from `ScheduleIntake`, but the static template path bypasses anchor collection entirely.

## A1. Design: shape plus anchors

Templates describe SHAPE: which days have which kind of block, in what order. Anchors come from the user: wake, training window, learning window, kid drop, kid pickup, bedtime. A planner combines the two into final ScheduleBlocks.

Data model addition (new): `ScheduleAnchorWindow` value type stored on `UserProfile`. Fields:

- `wakeHHMM: String` default `"06:00"`
- `bedtimeHHMM: String` default `"22:00"`
- `kidDropHHMM: String` default `"09:00"` (already on profile via `kidDropoffHHMM`; reuse)
- `kidPickupHHMM: String` default `"17:00"` (already on profile via `kidPickupHHMM`; reuse)
- `trainingWindowStartHHMM: String` default `"06:00"`
- `trainingWindowEndHHMM: String` default `"21:00"`
- `preferredTrainingTimeOfDay: TimeOfDayPreference` enum: `.morning` (`05:30-08:00`), `.midday` (`11:00-13:30`), `.evening` (`17:00-20:00`), `.lateEvening` (`20:00-22:00`)
- `learningWindowStartHHMM: String` default `"19:00"`
- `learningWindowEndHHMM: String` default `"21:00"`

Templates become parametric JSON. Replace hardcoded times with anchor tokens.

## A2. New parametric template JSON format

Rewrite `PersonalOptimization/Resources/schedule_balanced.json` (and the other three) to a v2 schema. Add a `version: 2` discriminator so old code paths break loudly, not silently.

New shape:

```json
{
    "version": 2,
    "description": "Generic balanced template. 3 lift days, 2 cardio days, weekend recovery.",
    "blocks": [
        {
            "dayOfWeek": 1,
            "anchor": "training",
            "durationMinutes": 60,
            "activity": "Lift A",
            "type": "training",
            "module": "lift_a"
        },
        {
            "dayOfWeek": 2,
            "anchor": "training",
            "durationMinutes": 60,
            "activity": "Cardio (basketball)",
            "type": "training",
            "module": "basketball"
        },
        ...
        {
            "dayOfWeek": 7,
            "anchor": "morning",
            "offsetMinutes": 240,
            "durationMinutes": 30,
            "activity": "Weekly review",
            "type": "admin"
        }
    ]
}
```

Anchor vocabulary:

- `training`: starts at the user's `preferredTrainingTimeOfDay` anchor.
- `learning`: starts at `learningWindowStartHHMM`.
- `morning`: starts at `wakeHHMM` plus `offsetMinutes`.
- `pre_kid_drop`: starts at `kidDropHHMM` minus `durationMinutes`.
- `post_kid_pickup`: starts at `kidPickupHHMM` plus `offsetMinutes`.
- `evening`: starts at the slot between `kidPickupHHMM` and `bedtimeHHMM` per template hint.
- `explicit`: same as v1, with literal `startTime`/`endTime`. Reserved for genuinely time-of-day-specific items (e.g., a "Break fast 12:00" block in fasting-focused).

Stacking rule: multiple `anchor: "training"` blocks on the same day stack 30 minutes apart unless an `offsetMinutes` is given.

## A3. New file: `SchedulePlanner.swift`

Create `PersonalOptimization/Modules/Schedule/SchedulePlanner.swift`:

```swift
import Foundation

/// Resolves parametric template blocks against the user's anchor windows
/// into concrete ScheduleBlock rows. Pure function; safe to unit test
/// without SwiftData.
struct SchedulePlanner {

    struct AnchorSet: Sendable {
        let wakeHHMM: String
        let bedtimeHHMM: String
        let kidDropHHMM: String
        let kidPickupHHMM: String
        let trainingStartHHMM: String   // resolved from preferredTrainingTimeOfDay
        let learningStartHHMM: String

        static func from(profile: UserProfile) -> AnchorSet {
            return AnchorSet(
                wakeHHMM: profile.wakeHHMM,
                bedtimeHHMM: profile.bedtimeHHMM,
                kidDropHHMM: profile.kidDropoffHHMM,
                kidPickupHHMM: profile.kidPickupHHMM,
                trainingStartHHMM: profile.preferredTrainingTimeOfDay.startHHMM,
                learningStartHHMM: profile.learningWindowStartHHMM
            )
        }
    }

    struct PlannerError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Resolves one parametric template entry into an absolute (startTime, endTime) pair.
    /// `stackedOffset` is added when multiple blocks share an anchor on the same day.
    static func resolve(
        block: ParametricBlock,
        anchors: AnchorSet,
        stackedOffsetMinutes: Int
    ) throws -> (startHHMM: String, endHHMM: String) {
        let baseMinutes: Int
        switch block.anchor {
        case .explicit:
            guard let start = block.explicitStartHHMM, let end = block.explicitEndHHMM else {
                throw PlannerError(message: "explicit anchor missing startTime/endTime")
            }
            return (start, end)
        case .training:
            baseMinutes = parseHHMM(anchors.trainingStartHHMM)
        case .learning:
            baseMinutes = parseHHMM(anchors.learningStartHHMM)
        case .morning:
            baseMinutes = parseHHMM(anchors.wakeHHMM)
        case .preKidDrop:
            baseMinutes = parseHHMM(anchors.kidDropHHMM) - block.durationMinutes
        case .postKidPickup:
            baseMinutes = parseHHMM(anchors.kidPickupHHMM)
        case .evening:
            // Evening slot: midpoint between pickup and bedtime, clamped.
            let pickup = parseHHMM(anchors.kidPickupHHMM)
            let bed = parseHHMM(anchors.bedtimeHHMM)
            baseMinutes = (pickup + bed) / 2
        }
        let startMinutes = baseMinutes + (block.offsetMinutes ?? 0) + stackedOffsetMinutes
        let endMinutes = startMinutes + block.durationMinutes

        // Defensive clamps: never start before 00:00, never end after 23:59.
        let safeStart = max(0, min(startMinutes, 23 * 60 + 59))
        let safeEnd = max(safeStart + 1, min(endMinutes, 23 * 60 + 59))
        return (formatHHMM(safeStart), formatHHMM(safeEnd))
    }

    /// Resolves all blocks in a template, handling per-day anchor stacking.
    static func resolveAll(
        templateBlocks: [ParametricBlock],
        anchors: AnchorSet
    ) throws -> [ResolvedBlock] {
        let grouped = Dictionary(grouping: templateBlocks) { "\($0.dayOfWeek)-\($0.anchor.rawValue)" }
        var output: [ResolvedBlock] = []
        for entries in grouped.values {
            for (index, block) in entries.enumerated() {
                let stack = index * 30
                let (start, end) = try resolve(block: block, anchors: anchors, stackedOffsetMinutes: stack)
                output.append(ResolvedBlock(
                    dayOfWeek: block.dayOfWeek,
                    startHHMM: start,
                    endHHMM: end,
                    activity: block.activity,
                    type: block.type,
                    module: block.module
                ))
            }
        }
        return output.sorted { lhs, rhs in
            if lhs.dayOfWeek != rhs.dayOfWeek { return lhs.dayOfWeek < rhs.dayOfWeek }
            return lhs.startHHMM < rhs.startHHMM
        }
    }

    private static func parseHHMM(_ s: String) -> Int {
        let parts = s.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return 0 }
        return h * 60 + m
    }

    private static func formatHHMM(_ minutes: Int) -> String {
        let safe = max(0, min(minutes, 23 * 60 + 59))
        return String(format: "%02d:%02d", safe / 60, safe % 60)
    }
}

struct ParametricBlock: Decodable, Sendable {
    enum Anchor: String, Decodable, Sendable {
        case explicit, training, learning, morning, preKidDrop = "pre_kid_drop",
             postKidPickup = "post_kid_pickup", evening
    }
    let dayOfWeek: Int
    let anchor: Anchor
    let durationMinutes: Int
    let offsetMinutes: Int?
    let activity: String
    let type: String
    let module: String?
    let explicitStartHHMM: String?
    let explicitEndHHMM: String?

    enum CodingKeys: String, CodingKey {
        case dayOfWeek, anchor, durationMinutes, offsetMinutes, activity, type, module
        case explicitStartHHMM = "startTime"
        case explicitEndHHMM = "endTime"
    }
}

struct ResolvedBlock: Sendable {
    let dayOfWeek: Int
    let startHHMM: String
    let endHHMM: String
    let activity: String
    let type: String
    let module: String?
}

struct ParametricScheduleFile: Decodable {
    let version: Int
    let description: String?
    let blocks: [ParametricBlock]
}
```

## A4. Extend `UserProfile`

Add the missing fields. New SwiftData schema version `SchemaV11`. Migration plan defaults preserve existing data:

```swift
@Model
final class UserProfile {
    // existing fields...

    // M5 schedule re-haul anchors.
    var wakeHHMM: String = "06:00"
    var bedtimeHHMM: String = "22:00"
    var trainingWindowStartHHMM: String = "06:00"
    var trainingWindowEndHHMM: String = "21:00"
    var preferredTrainingTimeOfDayRaw: String = TimeOfDayPreference.evening.rawValue
    var learningWindowStartHHMM: String = "19:00"
    var learningWindowEndHHMM: String = "21:00"

    var preferredTrainingTimeOfDay: TimeOfDayPreference {
        get { TimeOfDayPreference(rawValue: preferredTrainingTimeOfDayRaw) ?? .evening }
        set { preferredTrainingTimeOfDayRaw = newValue.rawValue }
    }
}

enum TimeOfDayPreference: String, CaseIterable, Sendable, Identifiable {
    case morning, midday, evening, lateEvening = "late_evening"
    var id: String { rawValue }

    var startHHMM: String {
        switch self {
        case .morning:     return "06:00"
        case .midday:      return "11:30"
        case .evening:     return "18:00"
        case .lateEvening: return "20:00"
        }
    }
    var displayName: String {
        switch self {
        case .morning:     return "Morning (06:00-08:00)"
        case .midday:      return "Midday (11:30-13:00)"
        case .evening:     return "Evening (18:00-20:00)"
        case .lateEvening: return "Late evening (20:00-22:00)"
        }
    }
}
```

Add the migration in `Models/AppSchema.swift` as a lightweight migration (new fields with defaults need no custom stage).

## A5. New onboarding step: "When does your day look like?"

Insert a new screen at index 3 between the existing "goals" (index 2) and "schedule" (index 4, previously 3). All later step indices shift by 1.

Files: `PersonalOptimization/Views/OnboardingView.swift`.

Update step count and `TabView`:

```swift
@State private var step: Int = 0
// existing state
@State private var draftAnchors: ScheduleAnchorDraft = .init()

var body: some View {
    VStack(spacing: 0) {
        ProgressView(value: Double(step + 1), total: 7)
            .tint(.accentColor)
            .padding(.horizontal, 16)
            .padding(.top, 8)

        TabView(selection: $step) {
            welcomeScreen.tag(0)
            permissionsScreen.tag(1)
            goalsScreen.tag(2)
            anchorsScreen.tag(3)      // NEW
            scheduleScreen.tag(4)     // shifted +1
            mascotScreen.tag(5)       // shifted +1
            wrapUpScreen.tag(6)       // shifted +1
        }
        ...
    }
}
```

Update `canAdvance` for step 3 and step 4 (template choice now happens after anchors are set):

```swift
private var canAdvance: Bool {
    switch step {
    case 0, 1, 2: return true
    case 3: return draftAnchors.isValid    // anchors set
    case 4: return hasMadeScheduleChoice   // template applied
    default: return true
    }
}
```

`controls` final-step check: `if step < 6` for Continue, `else` for "Get started" finishing.

New screen:

```swift
@ViewBuilder
private var anchorsScreen: some View {
    Form {
        Section("Daily anchors") {
            DatePicker("Wake time",
                       selection: $draftAnchors.wakeDate,
                       displayedComponents: .hourAndMinute)
            DatePicker("Bedtime",
                       selection: $draftAnchors.bedtimeDate,
                       displayedComponents: .hourAndMinute)
        }
        Section("Kids") {
            DatePicker("Drop off",
                       selection: $draftAnchors.kidDropDate,
                       displayedComponents: .hourAndMinute)
            DatePicker("Pickup",
                       selection: $draftAnchors.kidPickupDate,
                       displayedComponents: .hourAndMinute)
        }
        Section("Training") {
            Picker("Preferred window",
                   selection: $draftAnchors.preferredTrainingTimeOfDay) {
                ForEach(TimeOfDayPreference.allCases) { pref in
                    Text(pref.displayName).tag(pref)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        Section("Learning") {
            DatePicker("Evening learning starts",
                       selection: $draftAnchors.learningStartDate,
                       displayedComponents: .hourAndMinute)
        }
        Section {
            Text("Templates use these as anchors. You can edit any single block after applying. No defaults are assumed — the app will not place a workout at 18:00 unless you choose it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
```

`ScheduleAnchorDraft` value type (private to the view):

```swift
private struct ScheduleAnchorDraft {
    var wakeDate: Date = Self.todayAt(hour: 6, minute: 0)
    var bedtimeDate: Date = Self.todayAt(hour: 22, minute: 0)
    var kidDropDate: Date = Self.todayAt(hour: 9, minute: 0)
    var kidPickupDate: Date = Self.todayAt(hour: 17, minute: 0)
    var learningStartDate: Date = Self.todayAt(hour: 19, minute: 0)
    var preferredTrainingTimeOfDay: TimeOfDayPreference = .evening

    var isValid: Bool { wakeDate < bedtimeDate }

    func writeTo(profile: UserProfile) {
        profile.wakeHHMM = Self.hhmm(wakeDate)
        profile.bedtimeHHMM = Self.hhmm(bedtimeDate)
        profile.kidDropoffHHMM = Self.hhmm(kidDropDate)
        profile.kidPickupHHMM = Self.hhmm(kidPickupDate)
        profile.learningWindowStartHHMM = Self.hhmm(learningStartDate)
        profile.preferredTrainingTimeOfDay = preferredTrainingTimeOfDay
    }

    private static func todayAt(hour: Int, minute: Int) -> Date {
        var cal = Calendar.current
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    private static func hhmm(_ date: Date) -> String {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
    }
}
```

In `applyScheduleTemplate(_:)`, first flush the draft anchors to the profile, then apply the template with the new planner path:

```swift
private func applyScheduleTemplate(_ template: ScheduleTemplate) {
    scheduleTemplate = template
    if let profile = profile {
        draftAnchors.writeTo(profile: profile)
        try? modelContext.save()  // MARK: - try? justified because anchor write is best-effort; if it fails the planner falls back to defaults.
    }
    _ = try? ScheduleTemplateApplier.apply(
        template,
        modelContext: modelContext,
        anchors: SchedulePlanner.AnchorSet.from(profile: profile ?? UserProfile())
    )
    scheduleChosenInSession = true
}
```

## A6. Update `ScheduleTemplateApplier` to use the planner

File: `PersonalOptimization/Modules/Schedule/Views/ScheduleTemplateChooserView.swift:148`.

```swift
@MainActor
enum ScheduleTemplateApplier {
    static func apply(_ template: ScheduleTemplate,
                      modelContext: ModelContext,
                      anchors: SchedulePlanner.AnchorSet,
                      bundle: Bundle = .main) throws {
        if template == .blank {
            try wipeNonCustom(modelContext: modelContext)
            return
        }
        guard let resourceName = template.resourceName else { return }
        try ScheduleSeed.resetToParametricTemplate(
            resourceName: resourceName,
            anchors: anchors,
            modelContext: modelContext,
            bundle: bundle
        )
    }

    private static func wipeNonCustom(modelContext: ModelContext) throws {
        let descriptor = FetchDescriptor<ScheduleBlock>(
            predicate: #Predicate<ScheduleBlock> { $0.isCustom == false && $0.isOverride == false }
        )
        let toDelete = (try? modelContext.fetch(descriptor)) ?? []
        for block in toDelete { modelContext.delete(block) }
        try modelContext.save()
    }
}
```

Add `ScheduleSeed.resetToParametricTemplate`:

```swift
@MainActor
extension ScheduleSeed {
    static func resetToParametricTemplate(
        resourceName: String,
        anchors: SchedulePlanner.AnchorSet,
        modelContext: ModelContext,
        bundle: Bundle = .main
    ) throws {
        let descriptor = FetchDescriptor<ScheduleBlock>(
            predicate: #Predicate<ScheduleBlock> { $0.isCustom == false && $0.isOverride == false }
        )
        let toDelete = try modelContext.fetch(descriptor)
        for block in toDelete { modelContext.delete(block) }
        try modelContext.save()

        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw ScheduleSeedError.resourceMissing
        }
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(ParametricScheduleFile.self, from: data)

        // Version gate: v2 only via this path; v1 keeps the legacy loader.
        guard file.version == 2 else {
            throw ScheduleSeedError.decodingFailed(
                NSError(domain: "ScheduleSeed", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "expected parametric template version 2, got \(file.version)"])
            )
        }

        let resolved = try SchedulePlanner.resolveAll(templateBlocks: file.blocks, anchors: anchors)
        for r in resolved {
            let blockType = BlockType(rawValue: r.type) ?? .other
            let block = ScheduleBlock(
                dayOfWeek: r.dayOfWeek,
                startTime: r.startHHMM,
                endTime: r.endHHMM,
                activity: r.activity,
                type: blockType,
                module: r.module
            )
            modelContext.insert(block)
        }
        try modelContext.save()
        Logger.schedule.info(
            "Applied parametric template \(resourceName, privacy: .public): wrote \(resolved.count, privacy: .public) blocks against anchors training=\(anchors.trainingStartHHMM, privacy: .public)"
        )
    }
}
```

## A7. Rewrite the four template JSONs

`PersonalOptimization/Resources/schedule_balanced.json`:

```json
{
    "version": 2,
    "description": "Balanced. 3 lift days, 2 cardio days, weekend recovery. Times anchored to your training-window preference.",
    "blocks": [
        { "dayOfWeek": 1, "anchor": "training", "durationMinutes": 60, "activity": "Lift A", "type": "training", "module": "lift_a" },
        { "dayOfWeek": 2, "anchor": "training", "durationMinutes": 60, "activity": "Cardio (basketball)", "type": "training", "module": "basketball" },
        { "dayOfWeek": 3, "anchor": "training", "durationMinutes": 60, "activity": "Lift B", "type": "training", "module": "lift_b" },
        { "dayOfWeek": 4, "anchor": "training", "durationMinutes": 60, "activity": "Cardio (swim)", "type": "training", "module": "swim" },
        { "dayOfWeek": 5, "anchor": "training", "durationMinutes": 60, "activity": "Lift A", "type": "training", "module": "lift_a" },
        { "dayOfWeek": 7, "anchor": "morning", "offsetMinutes": 240, "durationMinutes": 30, "activity": "Weekly review", "type": "admin" }
    ]
}
```

`schedule_gym_focused.json`:

```json
{
    "version": 2,
    "description": "Gym focused. Mon/Wed/Fri heavy lifts, Tue/Thu recovery and mobility.",
    "blocks": [
        { "dayOfWeek": 1, "anchor": "training", "durationMinutes": 90, "activity": "Heavy lift A", "type": "training", "module": "lift_a" },
        { "dayOfWeek": 2, "anchor": "training", "durationMinutes": 30, "activity": "Mobility", "type": "training", "module": null },
        { "dayOfWeek": 3, "anchor": "training", "durationMinutes": 90, "activity": "Heavy lift B", "type": "training", "module": "lift_b" },
        { "dayOfWeek": 4, "anchor": "training", "durationMinutes": 30, "activity": "Light cardio", "type": "training", "module": null },
        { "dayOfWeek": 5, "anchor": "training", "durationMinutes": 90, "activity": "Heavy lift C", "type": "training", "module": "lift_a" },
        { "dayOfWeek": 6, "anchor": "morning", "offsetMinutes": 180, "durationMinutes": 90, "activity": "Long session", "type": "training", "module": "lift_b" }
    ]
}
```

`schedule_language_focused.json`:

```json
{
    "version": 2,
    "description": "Language focused. Daily learning blocks; lighter training cadence.",
    "blocks": [
        { "dayOfWeek": 1, "anchor": "learning", "durationMinutes": 30, "activity": "Language practice", "type": "learning", "module": "japanese" },
        { "dayOfWeek": 2, "anchor": "training", "durationMinutes": 30, "activity": "Light cardio", "type": "training", "module": null },
        { "dayOfWeek": 2, "anchor": "learning", "durationMinutes": 30, "activity": "Language practice", "type": "learning", "module": "japanese" },
        { "dayOfWeek": 3, "anchor": "learning", "durationMinutes": 30, "activity": "Language practice", "type": "learning", "module": "japanese" },
        { "dayOfWeek": 4, "anchor": "training", "durationMinutes": 30, "activity": "Light cardio", "type": "training", "module": null },
        { "dayOfWeek": 4, "anchor": "learning", "durationMinutes": 30, "activity": "Language practice", "type": "learning", "module": "japanese" },
        { "dayOfWeek": 5, "anchor": "learning", "durationMinutes": 30, "activity": "Language practice", "type": "learning", "module": "japanese" },
        { "dayOfWeek": 6, "anchor": "morning", "offsetMinutes": 180, "durationMinutes": 60, "activity": "Extended language study", "type": "learning", "module": "japanese" }
    ]
}
```

`schedule_fasting_focused.json`:

```json
{
    "version": 2,
    "description": "Fasting focused. Built around the eating window; training lands in the fed phase.",
    "blocks": [
        { "dayOfWeek": 1, "anchor": "explicit", "startTime": "12:00", "endTime": "12:30", "durationMinutes": 30, "activity": "Break fast", "type": "fasting" },
        { "dayOfWeek": 2, "anchor": "explicit", "startTime": "12:00", "endTime": "12:30", "durationMinutes": 30, "activity": "Break fast", "type": "fasting" },
        { "dayOfWeek": 2, "anchor": "training", "durationMinutes": 60, "activity": "Lift A", "type": "training", "module": "lift_a" },
        { "dayOfWeek": 3, "anchor": "explicit", "startTime": "12:00", "endTime": "12:30", "durationMinutes": 30, "activity": "Break fast", "type": "fasting" },
        { "dayOfWeek": 4, "anchor": "explicit", "startTime": "12:00", "endTime": "12:30", "durationMinutes": 30, "activity": "Break fast", "type": "fasting" },
        { "dayOfWeek": 4, "anchor": "training", "durationMinutes": 60, "activity": "Cardio", "type": "training", "module": null },
        { "dayOfWeek": 5, "anchor": "explicit", "startTime": "12:00", "endTime": "12:30", "durationMinutes": 30, "activity": "Break fast", "type": "fasting" },
        { "dayOfWeek": 5, "anchor": "training", "durationMinutes": 60, "activity": "Lift B", "type": "training", "module": "lift_b" }
    ]
}
```

The "Break fast" rows stay `explicit` because they really are wall-clock anchored to the eating window. Training rows take the user's preferred-training-time anchor.

## A8. Settings: "Adjust my time anchors"

File: `PersonalOptimization/Views/SettingsView.swift`. Add a section that opens a new view `ScheduleAnchorEditorView.swift`. Editing anchors offers a confirmation: "Re-apply current template with new anchors?" If yes, call `ScheduleTemplateApplier.apply(currentTemplate, ...)` with the new anchors and the user's custom blocks survive (the planner only touches non-custom rows).

```swift
// In SettingsView.swift, schedule section:
NavigationLink("Time anchors") { ScheduleAnchorEditorView() }
```

New file `ScheduleAnchorEditorView.swift`:

```swift
@MainActor
struct ScheduleAnchorEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @State private var draft: ScheduleAnchorDraft = .init()
    @State private var showReapplyPrompt = false
    @State private var feedback: String?

    var body: some View {
        Form {
            anchorFields
            Section {
                Button("Save anchors") { save() }
                    .buttonStyle(.borderedProminent)
            }
            if let feedback {
                Section { Text(feedback).font(.footnote).foregroundStyle(.green) }
            }
        }
        .navigationTitle("Time anchors")
        .task { draft.loadFrom(profile: profiles.first) }
        .confirmationDialog("Re-apply current template with new anchors?",
                            isPresented: $showReapplyPrompt) {
            Button("Re-apply (keep custom blocks)", role: .destructive) { reapply() }
            Button("Save anchors only", role: .cancel) { feedback = "Saved." }
        }
    }
}
```

## A9. Validation rules

Add to `ScheduleValidator.swift`:

1. No two blocks overlap on the same day-of-week (already validated for AI path; carry over to seed path).
2. Training blocks must be inside `[trainingWindowStartHHMM, trainingWindowEndHHMM]`.
3. Learning blocks must be inside `[wakeHHMM, bedtimeHHMM]`.
4. Total scheduled minutes per day under 6 hours (sanity cap).
5. Kid-drop and kid-pickup conflicts: any block overlapping `[kidDropoffHHMM-15min, kidDropoffHHMM+30min]` or `[kidPickupHHMM-15min, kidPickupHHMM+15min]` fails validation with a clear error.

When the planner produces a conflict, surface a banner: "Your evening training window overlaps with kid pickup at 17:00. Move training later, or pick a midday window." Do not silently shift.

## A10. Daily launch polish

The "wonky" daily-launch feeling has three sources, each fixable:

1. `TodayView` rebuilds `ScheduleService` and `DailySummaryService` on every body evaluation. Item 6 from `IMPROVEMENT_IMPLEMENTATION_PLAN.md` has a partial fix (cache landed) but the View doesn't gate rebuild yet. See Part B Item 6 below for the remaining refactor.
2. `HealthKitSyncService.syncToday()` runs in `Task` at launch and shows the "Catching up with Apple Health" banner. Replace the unbounded ProgressView with a 4-second timeout that hides the banner and logs a warning if sync hasn't finished.
3. No focused "next thing" indicator. Add a `NextBlockCard` to TodayView that shows what is next (current block if in one, else next block today, else next training day), with a single CTA: "Start" or "Snooze 15 min" or "Reschedule today".

New file `PersonalOptimization/Modules/Schedule/Views/NextBlockCard.swift`:

```swift
struct NextBlockCard: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @State private var refreshTrigger: Int = 0

    var body: some View {
        let service = ScheduleService(modelContext: modelContext)
        let now = Date()
        let current = service.currentBlock(at: now)
        let next = service.nextBlock(after: now)

        VStack(alignment: .leading, spacing: 8) {
            if let current {
                inProgressView(block: current, now: now)
            } else if let next {
                upcomingView(block: next, now: now)
            } else {
                Text("Nothing else scheduled today.").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
```

Insert into `TodayView.swift` before the `streakStrip` section (around line 87).

## A11. Tests

Create `PersonalOptimizationTests/Modules/SchedulePlannerTests.swift`:

```swift
@MainActor
final class SchedulePlannerTests: XCTestCase {

    private func anchors(training: String = "07:00",
                         learning: String = "19:00",
                         wake: String = "06:00",
                         bedtime: String = "22:00",
                         kidDrop: String = "09:00",
                         kidPickup: String = "17:00") -> SchedulePlanner.AnchorSet {
        SchedulePlanner.AnchorSet(
            wakeHHMM: wake, bedtimeHHMM: bedtime,
            kidDropHHMM: kidDrop, kidPickupHHMM: kidPickup,
            trainingStartHHMM: training, learningStartHHMM: learning
        )
    }

    func test_trainingAnchor_morning() throws {
        let block = ParametricBlock(dayOfWeek: 1, anchor: .training, durationMinutes: 60,
                                     offsetMinutes: nil, activity: "Lift A", type: "training",
                                     module: "lift_a", explicitStartHHMM: nil, explicitEndHHMM: nil)
        let (s, e) = try SchedulePlanner.resolve(block: block, anchors: anchors(training: "06:30"), stackedOffsetMinutes: 0)
        XCTAssertEqual(s, "06:30")
        XCTAssertEqual(e, "07:30")
    }

    func test_trainingAnchor_evening_clayDefault() throws {
        let block = ParametricBlock(dayOfWeek: 1, anchor: .training, durationMinutes: 60,
                                     offsetMinutes: nil, activity: "Lift A", type: "training",
                                     module: "lift_a", explicitStartHHMM: nil, explicitEndHHMM: nil)
        let (s, e) = try SchedulePlanner.resolve(block: block, anchors: anchors(training: "20:00"), stackedOffsetMinutes: 0)
        XCTAssertEqual(s, "20:00")
        XCTAssertEqual(e, "21:00")
    }

    func test_stackedTrainingBlocksSameDay_increment30Min() throws {
        let blocks = [
            ParametricBlock(dayOfWeek: 2, anchor: .training, durationMinutes: 30,
                            offsetMinutes: nil, activity: "Warmup", type: "training",
                            module: nil, explicitStartHHMM: nil, explicitEndHHMM: nil),
            ParametricBlock(dayOfWeek: 2, anchor: .training, durationMinutes: 30,
                            offsetMinutes: nil, activity: "Lift", type: "training",
                            module: nil, explicitStartHHMM: nil, explicitEndHHMM: nil)
        ]
        let resolved = try SchedulePlanner.resolveAll(templateBlocks: blocks, anchors: anchors(training: "07:00"))
        XCTAssertEqual(resolved.count, 2)
        XCTAssertEqual(resolved[0].startHHMM, "07:00")
        XCTAssertEqual(resolved[1].startHHMM, "07:30")
    }

    func test_preKidDropAnchor_subtractsDuration() throws { ... }
    func test_eveningAnchor_midpoint() throws { ... }
    func test_explicitAnchor_passesThrough() throws { ... }
    func test_explicitAnchor_missingTimes_throws() throws { ... }
    func test_offsetMinutes_addsToBase() throws { ... }
    func test_balancedTemplate_atEveningAnchor_doesNotProduce1800Unless1800Chosen() throws {
        // Regression test. With training anchor = 06:30, none of the
        // generated blocks should start at 18:00.
        let json = """
        {"version":2,"blocks":[
            {"dayOfWeek":1,"anchor":"training","durationMinutes":60,"activity":"Lift A","type":"training","module":"lift_a"}
        ]}
        """.data(using: .utf8)!
        let file = try JSONDecoder().decode(ParametricScheduleFile.self, from: json)
        let resolved = try SchedulePlanner.resolveAll(
            templateBlocks: file.blocks,
            anchors: anchors(training: "06:30")
        )
        XCTAssertFalse(resolved.contains { $0.startHHMM == "18:00" })
        XCTAssertEqual(resolved.first?.startHHMM, "06:30")
    }
}
```

Add a migration test `SchemaV11Tests.swift` ensuring existing profiles get the new fields with defaults.

Add `ScheduleAnchorEditorViewTests.swift` for the reapply path.

## A12. Sequencing for Part A

1. SwiftData schema V11 with the new UserProfile fields. Migration test.
2. `SchedulePlanner.swift` and tests.
3. Rewrite the four template JSONs to v2.
4. `ScheduleSeed.resetToParametricTemplate` and update `ScheduleTemplateApplier`.
5. New onboarding anchor screen.
6. `ScheduleAnchorEditorView` in Settings.
7. `ScheduleValidator` new rules.
8. `NextBlockCard` and TodayView integration.

Total estimate: 14-20 hours.

## A13. Acceptance criteria for Part A

- Fresh install, walking through onboarding, picking Morning training preference, selecting Balanced template: every training block lands at the chosen morning anchor (e.g., 06:30-07:30), not 18:00.
- Re-running onboarding flow with Evening preference produces 18:00 blocks. The app respects choice, never assumes.
- Settings > Time anchors > change preferredTrainingTimeOfDay to Midday, accept re-apply: all training blocks shift to 11:30. Custom blocks untouched.
- `SchedulePlannerTests` 10+ tests green. `test_balancedTemplate_atEveningAnchor_doesNotProduce1800Unless1800Chosen` green.
- `xcodebuild build` zero warnings.
- TodayView shows `NextBlockCard` at the top of the master-metric area.
- Daily launch on hardware: time from cold launch to first interactive frame under 1.5s (matches PERFORMANCE.md).

---

# Part B: Detailed breakdown for the six remaining gaps

Listed by commit-history order. Each item has: current state, what is missing, files to touch, the diffs, tests, acceptance.

## Item 4 remaining: HealthKitObserverService, FastingLiveActivityController, WorkoutLiveActivityController tests

### Current state

`TokenBudgetService` and `ProfileService` tests landed. The three below still lack tests because each needs a protocol seam before it can be tested without live system services.

### Files to touch

- `PersonalOptimization/Services/HealthKitObserverService.swift` (add `HKStoreObserving` protocol)
- New: `PersonalOptimizationTests/Services/HealthKitObserverServiceTests.swift`
- `PersonalOptimization/Modules/Fasting/LiveActivity/FastingLiveActivityController.swift` (add `ActivityRequester` protocol)
- New: `PersonalOptimizationTests/Modules/FastingLiveActivityControllerTests.swift`
- `PersonalOptimization/Modules/Training/LiveActivity/WorkoutLiveActivityController.swift` (same protocol)
- New: `PersonalOptimizationTests/Modules/WorkoutLiveActivityControllerTests.swift`

### Implementation

Step 1. HealthKit observer seam.

```swift
protocol HKStoreObserving: Sendable {
    func executeObserverQuery(
        for type: HKQuantityTypeIdentifier,
        handler: @escaping @Sendable (Error?) -> Void
    ) async
    func enableBackgroundDelivery(
        for type: HKQuantityTypeIdentifier,
        frequency: HKUpdateFrequency
    ) async throws
}

@MainActor
final class HealthKitObserverService {
    static let shared = HealthKitObserverService(store: LiveHKStoreObserver())

    private let store: HKStoreObserving
    private var observedTypes: Set<HKQuantityTypeIdentifier> = []

    init(store: HKStoreObserving) {
        self.store = store
    }

    func startObserving(modelContainer: ModelContainer) async {
        let types: [HKQuantityTypeIdentifier] = [
            .activeEnergyBurned, .stepCount, .heartRateVariabilitySDNN, .restingHeartRate
        ]
        for type in types {
            guard !observedTypes.contains(type) else { continue }
            observedTypes.insert(type)
            try? await store.enableBackgroundDelivery(for: type, frequency: .hourly)
            await store.executeObserverQuery(for: type) { [weak self] _ in
                Task { @MainActor in
                    NotificationCenter.default.post(name: .dailyLogsRecomputed, object: type.rawValue)
                    _ = await HealthKitSyncService(modelContext: modelContainer.mainContext).syncToday()
                }
            }
        }
    }
}
```

`LiveHKStoreObserver` wraps `HKHealthStore.execute(HKObserverQuery)` and `enableBackgroundDelivery`. `FakeHKStoreObserver` for tests records calls and lets the test fire the handler synthetically.

```swift
final class FakeHKStoreObserver: HKStoreObserving {
    var observedTypes: [HKQuantityTypeIdentifier] = []
    var backgroundDeliveryRequests: [(HKQuantityTypeIdentifier, HKUpdateFrequency)] = []
    var pendingHandlers: [(HKQuantityTypeIdentifier, @Sendable (Error?) -> Void)] = []

    func executeObserverQuery(for type: HKQuantityTypeIdentifier,
                              handler: @escaping @Sendable (Error?) -> Void) async {
        observedTypes.append(type)
        pendingHandlers.append((type, handler))
    }

    func enableBackgroundDelivery(for type: HKQuantityTypeIdentifier,
                                   frequency: HKUpdateFrequency) async throws {
        backgroundDeliveryRequests.append((type, frequency))
    }

    func fireObserver(for type: HKQuantityTypeIdentifier, error: Error? = nil) {
        for (queryType, handler) in pendingHandlers where queryType == type {
            handler(error)
        }
    }
}
```

Tests:

```swift
@MainActor
final class HealthKitObserverServiceTests: XCTestCase {

    func test_startObserving_registersAllFourTypes() async throws {
        let fake = FakeHKStoreObserver()
        let service = HealthKitObserverService(store: fake)
        let container = try InMemoryContainer.make()
        await service.startObserving(modelContainer: container)
        XCTAssertEqual(Set(fake.observedTypes), [.activeEnergyBurned, .stepCount, .heartRateVariabilitySDNN, .restingHeartRate])
    }

    func test_startObserving_enablesBackgroundDelivery() async throws {
        let fake = FakeHKStoreObserver()
        let service = HealthKitObserverService(store: fake)
        let container = try InMemoryContainer.make()
        await service.startObserving(modelContainer: container)
        XCTAssertEqual(fake.backgroundDeliveryRequests.count, 4)
        XCTAssertTrue(fake.backgroundDeliveryRequests.allSatisfy { $0.1 == .hourly })
    }

    func test_startObserving_isIdempotent() async throws {
        let fake = FakeHKStoreObserver()
        let service = HealthKitObserverService(store: fake)
        let container = try InMemoryContainer.make()
        await service.startObserving(modelContainer: container)
        await service.startObserving(modelContainer: container)
        XCTAssertEqual(fake.observedTypes.count, 4)  // not 8
    }

    func test_observerFire_postsDailyLogsRecomputed() async throws {
        let fake = FakeHKStoreObserver()
        let service = HealthKitObserverService(store: fake)
        let container = try InMemoryContainer.make()
        await service.startObserving(modelContainer: container)

        let exp = expectation(forNotification: .dailyLogsRecomputed, object: nil)
        fake.fireObserver(for: .stepCount)
        await fulfillment(of: [exp], timeout: 2)
    }
}
```

Step 2. Live Activity protocol seam.

```swift
protocol ActivityRequesting: Sendable {
    associatedtype Attrs: ActivityAttributes
    func request(attributes: Attrs, content: ActivityContent<Attrs.ContentState>) throws -> any FakeOrRealActivity
    func update(token: String, content: ActivityContent<Attrs.ContentState>) async
    func end(token: String, dismissalPolicy: ActivityUIDismissalPolicy) async
}
```

This is verbose because `Activity<T>` is generic. Easier pattern: wrap the controller's interaction in a closure-based interface.

```swift
@MainActor
final class FastingLiveActivityController {
    static let shared = FastingLiveActivityController()

    typealias StartActivity = @MainActor (FastingActivityAttributes, FastingActivityAttributes.ContentState, Date?) async throws -> String?
    typealias UpdateActivity = @MainActor (String, FastingActivityAttributes.ContentState, Date?) async -> Void
    typealias EndActivity = @MainActor (String) async -> Void

    private let start: StartActivity
    private let update: UpdateActivity
    private let end: EndActivity
    private var activeToken: String?

    init(
        start: @escaping StartActivity = FastingLiveActivityController.liveStart,
        update: @escaping UpdateActivity = FastingLiveActivityController.liveUpdate,
        end: @escaping EndActivity = FastingLiveActivityController.liveEnd
    ) {
        self.start = start
        self.update = update
        self.end = end
    }

    func startFasting(window: FastingWindow) async throws {
        let attrs = FastingActivityAttributes(windowStart: window.start, windowEnd: window.end)
        let state = FastingActivityAttributes.ContentState(isFasting: true)
        activeToken = try await start(attrs, state, window.end.addingTimeInterval(60))
    }

    func endFasting() async {
        guard let token = activeToken else { return }
        await end(token)
        activeToken = nil
    }

    // Live implementations call ActivityKit; failures throw or no-op.
    @MainActor
    private static func liveStart(...) async throws -> String? { ... }
}
```

Tests inject fakes:

```swift
@MainActor
final class FastingLiveActivityControllerTests: XCTestCase {

    func test_startFasting_callsStartWithCorrectAttributes() async throws {
        var capturedAttrs: FastingActivityAttributes?
        var capturedState: FastingActivityAttributes.ContentState?
        var capturedStale: Date?
        let controller = FastingLiveActivityController(
            start: { attrs, state, stale in
                capturedAttrs = attrs
                capturedState = state
                capturedStale = stale
                return "token-1"
            },
            update: { _, _, _ in },
            end: { _ in }
        )
        let window = FastingWindow(start: Date(), end: Date().addingTimeInterval(16 * 3600))
        try await controller.startFasting(window: window)
        XCTAssertNotNil(capturedAttrs)
        XCTAssertEqual(capturedState?.isFasting, true)
        XCTAssertNotNil(capturedStale)
        XCTAssertEqual(capturedStale, window.end.addingTimeInterval(60))
    }

    func test_endFasting_noOpWhenNotStarted() async {
        var endCallCount = 0
        let controller = FastingLiveActivityController(
            start: { _, _, _ in "x" },
            update: { _, _, _ in },
            end: { _ in endCallCount += 1 }
        )
        await controller.endFasting()
        XCTAssertEqual(endCallCount, 0)
    }

    func test_endFasting_callsEndOnceAfterStart() async throws {
        var endCallCount = 0
        let controller = FastingLiveActivityController(
            start: { _, _, _ in "token-x" },
            update: { _, _, _ in },
            end: { _ in endCallCount += 1 }
        )
        try await controller.startFasting(window: FastingWindow(start: Date(), end: Date().addingTimeInterval(3600)))
        await controller.endFasting()
        await controller.endFasting()  // second call should no-op
        XCTAssertEqual(endCallCount, 1)
    }

    func test_startFasting_throwsWhenActivityKitRefuses() async {
        let controller = FastingLiveActivityController(
            start: { _, _, _ in throw FakeError.activitiesDisabled },
            update: { _, _, _ in },
            end: { _ in }
        )
        do {
            try await controller.startFasting(window: FastingWindow(start: Date(), end: Date().addingTimeInterval(3600)))
            XCTFail("expected throw")
        } catch {
            XCTAssertTrue(error is FakeError)
        }
    }
}

private enum FakeError: Error { case activitiesDisabled }
```

Mirror for `WorkoutLiveActivityController`: start/update/end injection, tests for state-transitions and end-on-stop semantics.

### Acceptance

- Three new test files compile and pass.
- `xccov` Models/Services coverage at or above 70%.
- Live behavior on hardware unchanged (the live-implementation closures are static functions called by default; no behavior change for prod callers).

---

## Item 6 remaining: TodayView `bootstrapServices()` refactor

### Current state

`ScheduleConfigLoader.loadCached()` landed. `TodayView.swift:16-23` still uses computed properties that allocate `ScheduleService` and `DailySummaryService` on every body evaluation. Now that the JSON parse is cheap, the dominant cost is `ModelContext`-bound service init plus the `DailySummaryService.init(hydrationTargets:)` flow.

### Files to touch

- `PersonalOptimization/Views/TodayView.swift`

### Implementation

Replace lines 4-25 of `TodayView.swift`:

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

    // Services held in @State so they survive across body evaluations. Init
    // happens once in .task; subsequent body renders read these directly.
    @State private var scheduleService: ScheduleService?
    @State private var summaryService: DailySummaryService?

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            // Render content only when services exist. Pre-bootstrap shows
            // a thin loading state instead of allocating per-render.
            if let scheduleService, let summaryService {
                listContent(schedule: scheduleService, summary: summaryService)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await bootstrapServices()
        }
        // Other modifiers unchanged
    }

    private func bootstrapServices() async {
        if scheduleService == nil {
            scheduleService = ScheduleService(modelContext: modelContext)
        }
        if summaryService == nil {
            // try? justified because: ScheduleConfig is a bundled resource.
            // Falling back to nil targets keeps DailySummaryService working
            // with its default 64 oz hydration floor.
            let config = try? ScheduleConfigLoader.loadCached()
            summaryService = DailySummaryService(
                modelContext: modelContext,
                hydrationTargets: config?.hydrationTargetsOz
            )
        }
        if hkSyncService == nil {
            hkSyncService = HealthKitSyncService(modelContext: modelContext)
        }
    }

    @ViewBuilder
    private func listContent(schedule: ScheduleService, summary: DailySummaryService) -> some View {
        // Move the existing List body here. Replace `service.*` with `schedule.*`
        // and `summaryService.*` with `summary.*`. Everything that was inside
        // the original NavigationStack { List { ... } } moves into this builder.
        List {
            // existing sections
        }
    }
}
```

Add a refresh path: when the user pulls to refresh or returns from a sheet that may have changed schedule blocks, call `bootstrapServices(reset: true)`:

```swift
private func bootstrapServices(reset: Bool = false) async {
    if reset {
        scheduleService = nil
        summaryService = nil
    }
    // ...existing init logic
}
```

### Tests

`TodayViewBootstrapTests.swift` is hard to write because SwiftUI body inspection is brittle. Pragmatic test: extract `bootstrapServices` into a free function or service helper and test that. Skip if the cost is too high; the existing `DailySummaryServiceTests` already cover the underlying behavior.

### Acceptance

- Instruments cold launch: `DailySummaryService.init` called exactly once per app session (not per body evaluation).
- No visual regression. The pre-bootstrap ProgressView is gone within one frame.

---

## Item 11: CloudKit shared-zone tests (deferred until paid Apple Developer)

### Current state

Decision record exists; tests are deferred until a paid Developer account is available and the shared zone is actually created. The protocol seam from Item 11 in the original plan can be added now to unlock test-writing later.

### What to do now (without paid account)

Implement the protocol seam so when the account lands, the test suite is one PR away.

Files:

- `PersonalOptimization/Modules/Engagement/PartnerService.swift`
- New: `PersonalOptimization/Services/PartnerSharedZone.swift`

```swift
import Foundation

protocol PartnerSharedZone: Sendable {
    func write(record: PartnerSharedRecord) async throws
    func deleteAll() async throws
    func fetchPartnerSnapshot() async throws -> PartnerSharedRecord?
}

struct PartnerSharedRecord: Codable, Sendable {
    let userID: String
    let currentStreak: Int
    let masterMetric: Double
    let mascotState: String
    let lastUpdate: Date
}

/// No-op implementation used until CloudKit shared zones are wired in. Lets
/// the rest of the app compile and tests can pass `MemoryPartnerSharedZone`.
final class NoopPartnerSharedZone: PartnerSharedZone {
    func write(record: PartnerSharedRecord) async throws {}
    func deleteAll() async throws {}
    func fetchPartnerSnapshot() async throws -> PartnerSharedRecord? { nil }
}

#if DEBUG
final class MemoryPartnerSharedZone: PartnerSharedZone {
    var records: [String: PartnerSharedRecord] = [:]
    var writeCalls = 0
    var deleteAllCalls = 0
    var failNextWrite: Error?

    func write(record: PartnerSharedRecord) async throws {
        writeCalls += 1
        if let error = failNextWrite {
            failNextWrite = nil
            throw error
        }
        records[record.userID] = record
    }
    func deleteAll() async throws {
        deleteAllCalls += 1
        records.removeAll()
    }
    func fetchPartnerSnapshot() async throws -> PartnerSharedRecord? {
        records.values.first
    }
}
#endif
```

Refactor `PartnerService` to take the seam:

```swift
@MainActor
final class PartnerService {
    private let zone: PartnerSharedZone
    init(zone: PartnerSharedZone = NoopPartnerSharedZone()) {
        self.zone = zone
    }

    func unpair() async throws {
        try await zone.deleteAll()
    }

    func updateSnapshot(...) async throws {
        try await zone.write(record: ...)
    }
}
```

### Tests (against the in-memory zone)

`PartnerServiceZoneTests.swift`:

```swift
@MainActor
final class PartnerServiceZoneTests: XCTestCase {

    func test_unpair_callsDeleteAllOnZone() async throws {
        let zone = MemoryPartnerSharedZone()
        let service = PartnerService(zone: zone)
        try await service.unpair()
        XCTAssertEqual(zone.deleteAllCalls, 1)
    }

    func test_updateSnapshot_writesRecord() async throws { ... }

    func test_updateSnapshot_propagatesWriteFailure() async throws {
        let zone = MemoryPartnerSharedZone()
        zone.failNextWrite = NSError(domain: "test", code: 1)
        let service = PartnerService(zone: zone)
        do {
            try await service.updateSnapshot(...)
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual((error as NSError).domain, "test")
        }
    }
}
```

When the paid account lands, write `CloudKitPartnerSharedZone` conforming to the protocol and integration-test against a sandboxed CK environment.

### Acceptance

- Protocol seam shipped on main.
- `PartnerServiceZoneTests` green against `MemoryPartnerSharedZone`.
- No live CloudKit calls in tests (verified by network-stub assertion or by inspection).
- Decision record updated noting the seam is in place pending paid-account integration.

---

## Item 16 remaining: 241 unjustified `try?` calls

### Current state

The strict literal reading of CLAUDE.md requires every `try?` to carry a justification comment. Most of the 241 calls follow the same fail-soft pattern: `try? modelContext.fetch(FetchDescriptor<X>())` where the failure path returns an empty array because the consumer treats nil and empty the same.

### Two-track fix

Track A: bulk-annotate via a shared helper that encodes the justification in code, not comments.

Create `PersonalOptimization/Services/SwiftDataHelpers.swift`:

```swift
import SwiftData

extension ModelContext {

    /// Fail-soft fetch. Returns an empty array if the fetch throws. Used for
    /// read paths where a nil and an empty result are semantically identical
    /// and a fetch failure is unrecoverable from the call site (the SwiftData
    /// store is in-process; failure means data-corruption-level events that
    /// the user can't act on inline). All such failures are logged via
    /// Logger.persistence at the catch site.
    func fetchOrEmpty<T>(_ descriptor: FetchDescriptor<T>,
                          logger: Logger = .persistence,
                          file: String = #fileID,
                          line: Int = #line) -> [T] where T: PersistentModel {
        do {
            return try fetch(descriptor)
        } catch {
            logger.error("fetchOrEmpty failed at \(file, privacy: .public):\(line, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Fail-soft single-result fetch. Returns nil on error or no rows.
    func fetchFirstOrNil<T>(_ descriptor: FetchDescriptor<T>,
                             logger: Logger = .persistence,
                             file: String = #fileID,
                             line: Int = #line) -> T? where T: PersistentModel {
        fetchOrEmpty(descriptor, logger: logger, file: file, line: line).first
    }
}
```

Then sweep the codebase: replace `(try? modelContext.fetch(...)) ?? []` with `modelContext.fetchOrEmpty(...)` and `(try? modelContext.fetch(...))?.first` with `modelContext.fetchFirstOrNil(...)`. The pattern is mechanical; a regex-based codemod handles 90% of it:

```bash
# Search-and-replace template (apply manually with review):
# (try? \w+\.fetch\((\w+(?:\<.+?\>)?\([^\)]*\))\)\)\s*\?\?\s*\[\]
# -> $1.fetchOrEmpty($2)
```

This eliminates 200+ of the 241 `try?` calls and replaces them with a single auditable helper. The remaining 30-40 `try?` calls (mostly `try? ctx.save()`, `try? FileManager...`, `try? URL...`) get explicit MARK comments per CLAUDE.md.

Track B: for the remaining genuine `try?` calls (saves, file IO), bulk-annotate with a script. Pattern:

```swift
// MARK: - try? justified because: SwiftData local save; failure is logged
// via Logger.persistence elsewhere and the in-memory state already
// reflects the intended change.
try? modelContext.save()
```

### Tests

Add `SwiftDataHelpersTests.swift`:

```swift
@MainActor
final class SwiftDataHelpersTests: XCTestCase {

    func test_fetchOrEmpty_returnsEmptyOnError() throws { ... }
    func test_fetchOrEmpty_returnsResults() throws { ... }
    func test_fetchFirstOrNil_returnsNilWhenEmpty() throws { ... }
    func test_fetchFirstOrNil_returnsFirstWhenPresent() throws { ... }
}
```

### Acceptance

- `grep -rn "try?" PersonalOptimization | grep -v "MARK" | grep -v "SwiftDataHelpers"` returns under 20 hits (only legitimate, MARKed `try?`).
- Coverage of read paths via `fetchOrEmpty` shows up in Logger output when a SwiftData read fails (manual canary test by passing a malformed predicate).

---

## Item 21 remaining: Handoff wiring for Basketball / Swim / Custom

### Current state

`LiftWatchView` wires `HandoffService.makeLiftActivity(...)` on `start()`. `BasketballWatchView`, `SwimWatchView`, `CustomActivityWatchView` do not yet call `HandoffService` at all. `HandoffActivityType` enum already has `.basketball`, `.swim`, `.customActivity` cases. `RootView.swift:28-39` already subscribes to `onContinueUserActivity` for all three.

### Files to touch

- `PersonalOptimizationWatch/Views/BasketballWatchView.swift`
- `PersonalOptimizationWatch/Views/SwimWatchView.swift`
- `PersonalOptimizationWatch/Views/CustomActivityWatchView.swift`
- `PersonalOptimization/Services/HandoffService.swift` (add factory helpers if missing)

### Implementation

In `HandoffService.swift`, ensure these factories exist (mirror `makeLiftActivity`):

```swift
@MainActor
enum HandoffService {

    static func makeLiftActivity(templateName: String, sessionID: UUID) -> NSUserActivity { ... }

    static func makeBasketballActivity(sessionID: UUID) -> NSUserActivity {
        let activity = NSUserActivity(activityType: HandoffActivityType.basketball.rawValue)
        activity.title = "Basketball"
        activity.userInfo = ["sessionID": sessionID.uuidString]
        activity.isEligibleForHandoff = true
        activity.becomeCurrent()
        return activity
    }

    static func makeSwimActivity(sessionID: UUID) -> NSUserActivity {
        let activity = NSUserActivity(activityType: HandoffActivityType.swim.rawValue)
        activity.title = "Swim"
        activity.userInfo = ["sessionID": sessionID.uuidString]
        activity.isEligibleForHandoff = true
        activity.becomeCurrent()
        return activity
    }

    static func makeCustomActivity(templateName: String, sessionID: UUID) -> NSUserActivity {
        let activity = NSUserActivity(activityType: HandoffActivityType.customActivity.rawValue)
        activity.title = templateName
        activity.userInfo = [
            "sessionID": sessionID.uuidString,
            "templateName": templateName
        ]
        activity.isEligibleForHandoff = true
        activity.becomeCurrent()
        return activity
    }

    /// Resign the active handoff activity. Call on session end so the banner
    /// disappears from the paired device. Idempotent.
    static func endActivity() {
        NSUserActivity.deleteAllSavedUserActivities {}
    }
}
```

In each watch view's `start()`:

```swift
// BasketballWatchView.start():
session = try service.startSession(...)
_ = HandoffService.makeBasketballActivity(sessionID: session?.id ?? UUID())

// BasketballWatchView.end():
await live.end()
HandoffService.endActivity()
```

Same pattern for Swim and CustomActivity. Wire on `start()` after the SwiftData session row is created.

For Custom, the iOS-side handler in `RootView.swift:34` (or wherever the Notification is consumed) needs to read both `sessionID` and `templateName` from `userInfo`. Update `HandoffPayload` if needed:

```swift
enum HandoffPayload {
    case lift(templateName: String, sessionID: UUID?)
    case basketball(sessionID: UUID?)
    case swim(sessionID: UUID?)
    case customActivity(templateName: String, sessionID: UUID?)
    case learning(...)

    init?(activityType: String, userInfo: [AnyHashable: Any]?) {
        let sessionID = (userInfo?["sessionID"] as? String).flatMap(UUID.init)
        switch activityType {
        case HandoffActivityType.lift.rawValue:
            guard let name = userInfo?["template"] as? String else { return nil }
            self = .lift(templateName: name, sessionID: sessionID)
        case HandoffActivityType.basketball.rawValue:
            self = .basketball(sessionID: sessionID)
        case HandoffActivityType.swim.rawValue:
            self = .swim(sessionID: sessionID)
        case HandoffActivityType.customActivity.rawValue:
            guard let name = userInfo?["templateName"] as? String else { return nil }
            self = .customActivity(templateName: name, sessionID: sessionID)
        case HandoffActivityType.learning.rawValue:
            ...
        default:
            return nil
        }
    }
}
```

iOS-side routing in `TrainingHubView` (or RootView via Notification):

```swift
.onReceive(NotificationCenter.default.publisher(for: .handoffActivityContinued)) { note in
    guard let payload = note.object as? HandoffPayload else { return }
    switch payload {
    case .basketball:
        pendingHandoff = .basketball
    case .swim:
        pendingHandoff = .swim
    case .customActivity(let templateName, _):
        pendingHandoff = .customActivity(templateName: templateName)
    default:
        break
    }
}
```

### Tests

Extend `HandoffServiceTests.swift`:

```swift
func test_basketball_activityHasCorrectType() {
    let activity = HandoffService.makeBasketballActivity(sessionID: UUID())
    XCTAssertEqual(activity.activityType, HandoffActivityType.basketball.rawValue)
    XCTAssertTrue(activity.isEligibleForHandoff)
}

func test_swim_activityIncludesSessionID() {
    let id = UUID()
    let activity = HandoffService.makeSwimActivity(sessionID: id)
    XCTAssertEqual(activity.userInfo?["sessionID"] as? String, id.uuidString)
}

func test_customActivity_carriesTemplateName() {
    let activity = HandoffService.makeCustomActivity(templateName: "Run", sessionID: UUID())
    XCTAssertEqual(activity.userInfo?["templateName"] as? String, "Run")
}

func test_handoffPayload_parsesBasketball() { ... }
func test_handoffPayload_parsesCustomActivity_rejectsMissingTemplate() { ... }
```

E2E verification (manual, requires paired hardware):

1. Start basketball on Apple Watch Ultra.
2. Lock the iPhone, unlock it.
3. Lock screen shows a Handoff banner with the basketball icon.
4. Swipe up: iOS opens to `TrainingHubView` with Basketball session pre-routed.
5. End basketball on watch: Handoff banner disappears within a few seconds.

Document in `.work/milestones/improve-21/manual-handoff-checklist.md`.

### Acceptance

- Three watch views now call `HandoffService.make*` on session start and `HandoffService.endActivity` on session end.
- New `HandoffServiceTests` pass.
- Manual hardware checklist signed off.

---

## Item 22: TimelineView refresh 1s -> 60s when dimmed

### Current state

`@Environment(\.isLuminanceReduced)` is wired in the workout views' foreground style, but the TimelineView refresh interval still ticks at 1Hz in always-on, burning battery.

### Files to touch

- `PersonalOptimizationWatch/Views/LiftWatchView.swift`
- `PersonalOptimizationWatch/Views/BasketballWatchView.swift`
- `PersonalOptimizationWatch/Views/SwimWatchView.swift`
- `PersonalOptimizationWatch/Views/CustomActivityWatchView.swift`

### Implementation

Find any `TimelineView(.periodic(from: ..., by: 1))` and wrap with a dim-aware refresh interval. If the workout views currently use `live.elapsedSeconds` derived from a Combine-style timer on the controller, that timer also needs to dial back. Pattern:

```swift
struct LiftWatchView: View {
    @Environment(\.isLuminanceReduced) private var dimmed
    // ...

    var body: some View {
        Group {
            if let session, let service {
                TimelineView(.periodic(from: startedAt, by: dimmed ? 60 : 1)) { context in
                    content(session: session, service: service, now: context.date)
                }
            } else {
                ProgressView().task { start() }
            }
        }
        .navigationTitle(templateName)
    }
}
```

For the live-stats row, surface the relative elapsed time from the `context.date` parameter instead of polling `live.elapsedSeconds`:

```swift
@ViewBuilder
private var liveStatsRow: some View {
    if live.isActive {
        TimelineView(.periodic(from: startedAt, by: dimmed ? 60 : 1)) { context in
            HStack(spacing: 6) {
                Label("\(Int(live.heartRate))", systemImage: "heart.fill")
                    .foregroundStyle(dimmed ? .gray : .red)
                    .font(.caption2.monospacedDigit())
                Spacer()
                Label("\(Int(live.activeCaloriesKcal))", systemImage: "flame.fill")
                    .foregroundStyle(dimmed ? .gray : .orange)
                    .font(.caption2.monospacedDigit())
                Spacer()
                Text(formatDuration(context.date.timeIntervalSince(startedAt)))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            // ...
        }
    }
}
```

If `LiveWorkoutSessionService.heartRate` updates more often than the dimmed cadence, that is fine. SwiftUI will only re-render at the TimelineView cadence regardless; observed reads outside a TimelineView trigger normal SwiftUI invalidation, but inside the TimelineView the snapshot is taken at the cadence interval.

For HKWorkoutBuilder data collection, do NOT reduce the underlying sampling interval. Sampling continues at 1Hz from HealthKit; only the UI repaint is throttled.

### Tests

The check is visual. Add a manual test entry to the hardware checklist:

```
- [ ] Start lift session, cover wrist for 5s to trigger always-on.
- [ ] Observe HR text dims to gray, elapsed time stops counting visibly per-second.
- [ ] Uncover wrist: HR text returns to red, elapsed time resumes 1Hz updates.
```

Unit test for the modifier expression (not for visual behavior):

```swift
@MainActor
final class WatchDimmedRefreshTests: XCTestCase {

    func test_refreshInterval_60sWhenDimmed_1sOtherwise() {
        // Construct via direct value comparison. No runtime check possible
        // without snapshotting; lint-style guard.
        let lit = TimelineSchedule.periodic(from: Date(), by: 1)
        let dim = TimelineSchedule.periodic(from: Date(), by: 60)
        XCTAssertNotNil(lit)
        XCTAssertNotNil(dim)
    }
}
```

### Acceptance

- Build green.
- Manual hardware test confirms dim-mode TimelineView no longer ticks per second.
- Battery posture improvement: a 90-minute lift in always-on mode no longer drains the watch significantly faster than active mode.

---

# Suggested next-PR sequence

If you want one PR at a time:

1. Part A.1 (schema V11), Part A.2 (template JSON v2 schema), Part A.3 (`SchedulePlanner` + tests).
2. Part A.7 (rewrite four template JSONs).
3. Part A.4 + A.5 (extend `UserProfile`, new onboarding anchor screen).
4. Part A.6 (`ScheduleTemplateApplier` uses planner) + Part A.8 (`ScheduleAnchorEditorView`).
5. Part A.9 (validator rules) + Part A.10 (`NextBlockCard`).
6. Part B Item 16 sweep (helpers + bulk migration).
7. Part B Item 6 (TodayView bootstrap refactor).
8. Part B Item 4 (three service tests).
9. Part B Item 11 (protocol seam, fake zone, tests).
10. Part B Item 21 (Basketball/Swim/Custom Handoff wiring).
11. Part B Item 22 (TimelineView dim-aware refresh).

Total estimated work: 28-38 hours of agent time. Part A is the heavier lift (14-20 hours) because it touches data model, onboarding, settings, and templates. Part B items are smaller (1-4 hours each).

# Bootstrap reminder for Claude Code

- Read CLAUDE.md, MILESTONES.md, ARCHITECTURE.md, PERFORMANCE.md, SECURITY.md first.
- Pick one item, branch as `improve/<short-tag>`, ship a PR, stop.
- Honor the absolute-mode user preferences and the no-em-dashes rule on all code, comments, commit messages, and any user-facing copy you write.
- Schema V11 must include a migration test before any new field is read at runtime.
- The 1800-1900 regression test (`test_balancedTemplate_atEveningAnchor_doesNotProduce1800Unless1800Chosen`) is the canary: if it ever fails, the planner has regressed.
