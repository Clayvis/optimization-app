import Foundation
import SwiftData

/// "If-then" plan, the load-bearing primitive of the implementation-intentions
/// research (Gollwitzer 1999+). The user pairs a context cue (a trigger) with
/// a concrete action they will take. Trigger types span time, after-event,
/// location, and after-schedule-block so users can anchor habits to whatever
/// feels natural — "after morning coffee", "when I get home from work",
/// "when the basketball block starts".
///
/// Active intentions surface on TodayView under "When you... I will remind
/// you to..." so the cue is visible at the right time.
@Model
final class ImplementationIntention {
    var trigger: String = ""                       // human-readable cue ("After morning coffee")
    var triggerTypeRaw: String = TriggerType.afterEvent.rawValue
    var action: String = ""                        // what the user will do ("Drink 16 oz water")
    var scheduleBlockUUIDString: String?           // optional FK to a ScheduleBlock for after_block triggers
    var triggerTimeMinutes: Int?                   // for time triggers: minutes from midnight in user TZ
    var createdAt: Date = Date.distantPast
    var lastCompletedAt: Date?
    var active: Bool = true

    var triggerType: TriggerType {
        TriggerType(rawValue: triggerTypeRaw) ?? .afterEvent
    }

    var scheduleBlockID: UUID? {
        get { scheduleBlockUUIDString.flatMap(UUID.init(uuidString:)) }
        set { scheduleBlockUUIDString = newValue?.uuidString }
    }

    init(trigger: String,
         triggerType: TriggerType,
         action: String,
         scheduleBlockID: UUID? = nil,
         triggerTimeMinutes: Int? = nil) {
        self.trigger = trigger
        self.triggerTypeRaw = triggerType.rawValue
        self.action = action
        self.scheduleBlockUUIDString = scheduleBlockID?.uuidString
        self.triggerTimeMinutes = triggerTimeMinutes
        self.createdAt = Date()
    }
}

enum TriggerType: String, Codable, CaseIterable, Sendable {
    case time
    case afterEvent = "after_event"
    case location
    case afterBlock = "after_block"

    var displayName: String {
        switch self {
        case .time:       return "At a time"
        case .afterEvent: return "After an event"
        case .location:   return "At a location"
        case .afterBlock: return "After a schedule block"
        }
    }

    var systemImage: String {
        switch self {
        case .time:       return "clock"
        case .afterEvent: return "arrow.right.circle"
        case .location:   return "location"
        case .afterBlock: return "calendar"
        }
    }
}
