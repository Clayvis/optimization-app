import Foundation
import SwiftData

/// Single source of truth for the calendar the app uses for daily boundaries,
/// streak rollovers, and notification scheduling. Reads UserProfile.timezone
/// unless the user has explicitly enabled travel mode, in which case the
/// device's current timezone takes over until they turn it off.
///
/// Use this anywhere app logic depends on a calendar day: DailyLog upserts,
/// streak boundaries, fasting window math, schedule block resolution, sleep
/// window suppression. Do NOT use this for display formatting (use the
/// device's TimeZone.current via DateFormatter directly).
@MainActor
enum UserCalendar {
    static func current(modelContext: ModelContext) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone(modelContext: modelContext)
        return cal
    }

    static func timezone(modelContext: ModelContext) -> TimeZone {
        let profile = modelContext.fetchFirstOrNil(FetchDescriptor<UserProfile>())
        if profile?.travelModeFollowsDevice == true {
            return .current
        }
        if let identifier = profile?.timezone, let tz = TimeZone(identifier: identifier) {
            return tz
        }
        return .current
    }

    /// Convenience for callers that already hold a Calendar: rebuild it with
    /// the user's timezone so date math respects DST and the user's pinned tz.
    static func applying(to calendar: Calendar, modelContext: ModelContext) -> Calendar {
        var out = calendar
        out.timeZone = timezone(modelContext: modelContext)
        return out
    }
}
