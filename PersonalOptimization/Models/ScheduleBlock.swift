import Foundation
import SwiftData

enum BlockType: String, Codable, CaseIterable, Sendable {
    case transit, training, study, learning, admin, recovery, family, other

    /// Family blocks represent intentionally protected time (kid drop-off,
    /// family dinner, weekends). NotificationService treats them like quiet
    /// hours, and the master metric doesn't fault the user for "missing" a
    /// scheduled domain during a family block.
    var isFamilyTime: Bool { self == .family }

    var displayName: String {
        switch self {
        case .transit:   return "Transit"
        case .training:  return "Training"
        case .study:     return "Study"
        case .learning:  return "Learning"
        case .admin:     return "Admin"
        case .recovery:  return "Recovery"
        case .family:    return "Family"
        case .other:     return "Other"
        }
    }
}

@Model
final class ScheduleBlock {
    var dayOfWeek: Int = 1
    var startTime: String = "00:00"
    var endTime: String = "00:00"
    var activity: String = ""
    var typeRaw: String = BlockType.other.rawValue
    var module: String?
    var isOverride: Bool = false
    var overrideDate: Date?
    var isCustom: Bool = false

    // M4.1 — Implementation-intention authoring. When set, the block is
    // anchored to a user-declared trigger event ("after_kid_dropoff",
    // "after_coffee", etc.). startTime/endTime remain authoritative for time
    // math; anchorEvent is display-only at v1 ("Lift A — 30 min after
    // drop-off") and a hint for adaptation prompts that this block prefers
    // a trigger over a clock.
    var anchorEvent: String?
    var anchorOffsetMinutes: Int?

    var type: BlockType { BlockType(rawValue: typeRaw) ?? .other }

    init(dayOfWeek: Int,
         startTime: String,
         endTime: String,
         activity: String,
         type: BlockType,
         module: String? = nil,
         anchorEvent: String? = nil,
         anchorOffsetMinutes: Int? = nil) {
        self.dayOfWeek = dayOfWeek
        self.startTime = startTime
        self.endTime = endTime
        self.activity = activity
        self.typeRaw = type.rawValue
        self.module = module
        self.anchorEvent = anchorEvent
        self.anchorOffsetMinutes = anchorOffsetMinutes
    }
}
