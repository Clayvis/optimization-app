import Foundation

/// User preference for when they like to train. Drives the `training` anchor
/// in parametric schedule templates so a "Balanced" template can land lifts
/// at the user's chosen window instead of a hardcoded 18:00.
enum TimeOfDayPreference: String, CaseIterable, Sendable, Identifiable {
    case morning
    case midday
    case evening
    case lateEvening = "late_evening"
    /// User-picked wall-clock start. The actual time lives in
    /// `UserProfile.trainingWindowStartHHMM`; `startHHMM` here is only the
    /// fallback for callers without profile access. The planner resolves
    /// `.custom` against the profile (see `SchedulePlanner.AnchorSet.from`).
    case custom

    var id: String { rawValue }

    /// Anchor start time for templates that target this preference.
    /// Templates can layer offsetMinutes on top.
    var startHHMM: String {
        switch self {
        case .morning:     return "06:00"
        case .midday:      return "11:30"
        case .evening:     return "18:00"
        case .lateEvening: return "20:00"
        case .custom:      return "18:00"
        }
    }

    var displayName: String {
        switch self {
        case .morning:     return "Morning (06:00-08:00)"
        case .midday:      return "Midday (11:30-13:00)"
        case .evening:     return "Evening (18:00-20:00)"
        case .lateEvening: return "Late evening (20:00-22:00)"
        case .custom:      return "Custom start time"
        }
    }
}
