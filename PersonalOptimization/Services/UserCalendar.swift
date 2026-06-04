import Foundation
import SwiftData

/// Single source of truth for the calendar the app uses for daily boundaries,
/// streak rollovers, and notification scheduling. Follows the device timezone
/// (the user's phone time) so every subsystem agrees with the clock on screen.
///
/// Use this anywhere app logic depends on a calendar day: DailyLog upserts,
/// streak boundaries, fasting window math, schedule block resolution, sleep
/// window suppression. Do NOT use this for display formatting (use the
/// device's TimeZone.current via DateFormatter directly).
///
/// A pinned home timezone (keep home days while travelling) can return later as
/// an explicit opt-in routed through `timezone(modelContext:)`. Until then the
/// device is the source of truth so day math matches the phone everywhere.
@MainActor
enum UserCalendar {
    static func current(modelContext: ModelContext) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone(modelContext: modelContext)
        return cal
    }

    static func timezone(modelContext: ModelContext) -> TimeZone {
        // Follow the device timezone (the user's phone time). Every day boundary
        // in the app keys off this, so fasting windows, streaks, hydration days,
        // and the canonical DailyLog writer all agree with the clock on screen.
        //
        // This previously pinned to UserProfile.timezone (seeded "Asia/Tokyo"),
        // but ~20 day-boundary services already defaulted to TimeZone.current, so
        // the writer (pinned) and its readers (device) disagreed on any non-JST
        // device and every date looked shifted. The home-timezone pin can return
        // as an explicit opt-in setting routed through here. `modelContext` is
        // retained in the signature for that future opt-in and for call-site
        // stability.
        _ = modelContext
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
