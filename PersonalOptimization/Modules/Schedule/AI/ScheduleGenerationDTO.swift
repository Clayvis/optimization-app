import Foundation

// MARK: - Intake (form values → Claude prompt)

/// Captured at the top of `ScheduleGenerationView`. Persisted into
/// `ScheduleGenerationRun.intakeJSON` so a discarded proposal can be replayed
/// or debugged without re-prompting the user.
struct ScheduleIntake: Codable, Equatable, Sendable {
    var primaryGoal: PrimaryGoal
    var freeText: String                           // "what does a great week look like for you?"
    var availableDays: Set<Int>                    // ISO weekday set; e.g. {1,3,5}
    var earliestTrainingHour: Int                  // 0-23
    var latestTrainingHour: Int                    // 0-23
    var availableTimeMinutesPerDay: Int            // M4.2: soft cap so AI doesn't over-schedule
    var sleepStartHour: Int                        // 0-23
    var sleepEndHour: Int                          // 0-23 (wraps midnight if end < start)
    var weeklyTrainingTargetSessions: Int          // 1-7
    var equipmentAccess: String                    // mirrors UserProfile.equipmentAccess
    var restrictionsCSV: String                    // "no_running,achilles_flare"
    var anchorEvents: [String]                     // ["after_kid_dropoff", "after_dinner"]
    var motivationStyle: String                    // mirrors UserProfile.motivationStyle
    var optimizationFocusesCSV: String             // M4.2: language, music, etc. — see OptimizationFocus

    enum PrimaryGoal: String, Codable, CaseIterable, Sendable {
        case strength
        case endurance
        case skillBuilding = "skill_building"
        case fastingPriority = "fasting_priority"

        var displayName: String {
            switch self {
            case .strength:         return "Strength"
            case .endurance:        return "Endurance"
            case .skillBuilding:    return "Skill building"
            case .fastingPriority:  return "Fasting priority"
            }
        }
    }
}

extension ScheduleIntake {
    /// Sensible defaults so the form opens populated rather than blank.
    /// Most fields come from the user's existing UserProfile when available;
    /// the form layer is responsible for that wiring.
    static var blank: ScheduleIntake {
        ScheduleIntake(
            primaryGoal: .strength,
            freeText: "",
            availableDays: [1, 2, 3, 4, 5],
            earliestTrainingHour: 17,
            latestTrainingHour: 20,
            availableTimeMinutesPerDay: 120,
            sleepStartHour: 22,
            sleepEndHour: 6,
            weeklyTrainingTargetSessions: 4,
            equipmentAccess: "gym",
            restrictionsCSV: "",
            anchorEvents: [],
            motivationStyle: "balanced",
            optimizationFocusesCSV: ""
        )
    }
}

// MARK: - Draft (Claude output → applied ScheduleBlock)

/// Single block as Claude emits it. Shape-compatible with the validator's
/// `ScheduleValidator.Block` so we can run validation before SwiftData touch.
struct ScheduleBlockDraft: Codable, Equatable, Sendable {
    var dayOfWeek: Int
    var startTime: String                          // "HH:mm"
    var endTime: String                            // "HH:mm"
    var activity: String
    var type: String                               // BlockType raw value
    var module: String?
    var anchorEvent: String?
    var anchorOffsetMinutes: Int?

    /// Convert to a SwiftData `ScheduleBlock` ready for insertion. Caller
    /// inserts into modelContext.
    func toScheduleBlock() -> ScheduleBlock {
        let blockType = BlockType(rawValue: type) ?? .other
        return ScheduleBlock(
            dayOfWeek: dayOfWeek,
            startTime: startTime,
            endTime: endTime,
            activity: activity,
            type: blockType,
            module: module,
            anchorEvent: anchorEvent,
            anchorOffsetMinutes: anchorOffsetMinutes
        )
    }

    /// Lossless view for the validator.
    var asValidatorBlock: ScheduleValidator.Block {
        ScheduleValidator.Block(
            dayOfWeek: dayOfWeek,
            startTime: startTime,
            endTime: endTime,
            type: type,
            module: module,
            anchorEvent: anchorEvent
        )
    }
}

// MARK: - Proposal (full Claude response)

/// Top-level shape Claude returns. `warnings` are soft notes for the user
/// (e.g. "I left Thursday open because you didn't list it as available").
struct GenerationProposal: Codable, Equatable, Sendable {
    var blocks: [ScheduleBlockDraft]
    var rationale: String                          // max 280 chars, identity-framed
    var warnings: [String]                         // soft, do not block apply
}
