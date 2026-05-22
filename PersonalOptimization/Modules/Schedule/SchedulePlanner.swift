import Foundation

/// Resolves parametric template blocks against the user's anchor windows
/// into concrete ScheduleBlock rows. Pure functions; safe to unit test
/// without SwiftData or HealthKit. The planner is the single point that
/// decides what wall-clock time a "training" or "learning" block lands at.
///
/// Templates describe SHAPE (which day, which kind of block, how long).
/// Anchors come from UserProfile (wake, bedtime, kid drop/pickup, training
/// window preference, learning window). The planner combines the two.
struct SchedulePlanner {

    struct AnchorSet: Sendable, Equatable {
        let wakeHHMM: String
        let bedtimeHHMM: String
        let kidDropHHMM: String
        let kidPickupHHMM: String
        /// Resolved from UserProfile.preferredTrainingTimeOfDay.startHHMM.
        let trainingStartHHMM: String
        let learningStartHHMM: String

        @MainActor
        static func from(profile: UserProfile) -> AnchorSet {
            AnchorSet(
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

    /// Resolves one parametric template entry into an absolute (start, end)
    /// pair. `stackedOffsetMinutes` is added when multiple blocks share an
    /// anchor on the same day so they don't collide.
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
            // Evening slot: midpoint between pickup and bedtime. Gives a
            // sensible "after-dinner family time" slot for admin/reflection
            // blocks when no specific anchor fits.
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

    /// Resolves every block in a parametric template. Stacks blocks that
    /// share the same (dayOfWeek, anchor) tuple by adding a 30-minute
    /// offset per additional block so they don't overlap.
    static func resolveAll(
        templateBlocks: [ParametricBlock],
        anchors: AnchorSet
    ) throws -> [ResolvedBlock] {
        // Preserve template ordering within each (day, anchor) bucket so
        // stacking respects the JSON author's intent.
        var stackCounters: [String: Int] = [:]
        var output: [ResolvedBlock] = []
        for block in templateBlocks {
            let key = "\(block.dayOfWeek)-\(block.anchor.rawValue)"
            let index = stackCounters[key, default: 0]
            stackCounters[key] = index + 1
            // Explicit-anchor blocks don't stack: their start times are
            // already wall-clock and should appear at the literal time.
            let stack = block.anchor == .explicit ? 0 : index * 30
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
        return output.sorted { lhs, rhs in
            if lhs.dayOfWeek != rhs.dayOfWeek { return lhs.dayOfWeek < rhs.dayOfWeek }
            return lhs.startHHMM < rhs.startHHMM
        }
    }

    static func parseHHMM(_ s: String) -> Int {
        let parts = s.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return 0 }
        return h * 60 + m
    }

    static func formatHHMM(_ minutes: Int) -> String {
        let safe = max(0, min(minutes, 23 * 60 + 59))
        return String(format: "%02d:%02d", safe / 60, safe % 60)
    }
}

/// One entry in a v2 parametric schedule template JSON file.
struct ParametricBlock: Decodable, Sendable {
    enum Anchor: String, Decodable, Sendable {
        case explicit
        case training
        case learning
        case morning
        case preKidDrop = "pre_kid_drop"
        case postKidPickup = "post_kid_pickup"
        case evening
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

    init(dayOfWeek: Int,
         anchor: Anchor,
         durationMinutes: Int,
         offsetMinutes: Int? = nil,
         activity: String,
         type: String,
         module: String? = nil,
         explicitStartHHMM: String? = nil,
         explicitEndHHMM: String? = nil) {
        self.dayOfWeek = dayOfWeek
        self.anchor = anchor
        self.durationMinutes = durationMinutes
        self.offsetMinutes = offsetMinutes
        self.activity = activity
        self.type = type
        self.module = module
        self.explicitStartHHMM = explicitStartHHMM
        self.explicitEndHHMM = explicitEndHHMM
    }

    enum CodingKeys: String, CodingKey {
        case dayOfWeek, anchor, durationMinutes, offsetMinutes, activity, type, module
        case explicitStartHHMM = "startTime"
        case explicitEndHHMM = "endTime"
    }
}

struct ResolvedBlock: Sendable, Equatable {
    let dayOfWeek: Int
    let startHHMM: String
    let endHHMM: String
    let activity: String
    let type: String
    let module: String?
}

struct ParametricScheduleFile: Decodable, Sendable {
    let version: Int
    let description: String?
    let blocks: [ParametricBlock]
}
