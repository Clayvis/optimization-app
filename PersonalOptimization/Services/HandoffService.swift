import Foundation

/// NSUserActivity-based Handoff between the watch and the phone for
/// in-progress workouts and learning sessions. The watch calls
/// `makeLiftActivity(...).becomeCurrent()` when a lift session starts; the
/// phone receives the activity via `.onContinueUserActivity(...)` on the
/// iOS root view and routes the user to the matching session screen with
/// the same template pre-filled.
///
/// Activity-type strings are stable identifiers also declared in Info.plist
/// under `NSUserActivityTypes`. Renaming requires a coordinated update
/// because in-flight activities reference the old type id.
enum HandoffActivityType: String, Sendable {
    case lift = "com.rawlins.PersonalOptimization.activity.lift"
    case basketball = "com.rawlins.PersonalOptimization.activity.basketball"
    case swim = "com.rawlins.PersonalOptimization.activity.swim"
    case customActivity = "com.rawlins.PersonalOptimization.activity.custom"
    case learning = "com.rawlins.PersonalOptimization.activity.learning"

    /// Human-visible title that appears in the Handoff banner.
    var displayTitle: String {
        switch self {
        case .lift:           return "Lift"
        case .basketball:     return "Basketball"
        case .swim:           return "Swim"
        case .customActivity: return "Workout"
        case .learning:       return "Learning"
        }
    }
}

/// Strongly-typed parsed Handoff payload. The phone receives the raw
/// NSUserActivity and converts it through `Payload(from:)` so the routing
/// code stays simple.
struct HandoffPayload: Sendable, Equatable {
    let type: HandoffActivityType
    let sessionID: UUID?
    let template: String?

    init(type: HandoffActivityType, sessionID: UUID? = nil, template: String? = nil) {
        self.type = type
        self.sessionID = sessionID
        self.template = template
    }

    /// Parses a userInfo dictionary as produced by the watch-side builders.
    /// Returns nil if the type string is unrecognized.
    init?(activityType: String, userInfo: [AnyHashable: Any]?) {
        guard let type = HandoffActivityType(rawValue: activityType) else { return nil }
        self.type = type
        if let raw = userInfo?["sessionID"] as? String {
            self.sessionID = UUID(uuidString: raw)
        } else {
            self.sessionID = nil
        }
        self.template = userInfo?["template"] as? String
    }
}

#if canImport(Foundation)
import Foundation

enum HandoffService {
    /// Build the userInfo dictionary the watch ships in its NSUserActivity.
    /// Exposed as a pure (nonisolated) function so tests can verify the
    /// shape without touching `NSUserActivity.becomeCurrent()` (which
    /// mutates global state and isn't fixture-friendly).
    static func userInfo(for type: HandoffActivityType,
                        sessionID: UUID? = nil,
                        template: String? = nil) -> [String: String] {
        var info: [String: String] = [:]
        if let sessionID { info["sessionID"] = sessionID.uuidString }
        if let template { info["template"] = template }
        return info
    }

    #if canImport(UIKit) || canImport(WatchKit)
    /// Builds and activates an NSUserActivity for a workout in progress.
    /// `becomeCurrent()` registers it with the Handoff subsystem so the
    /// paired device's Lock Screen shows the continuation banner.
    /// MainActor-isolated because NSUserActivity must be touched from main.
    @MainActor
    @discardableResult
    static func startActivity(type: HandoffActivityType,
                              sessionID: UUID? = nil,
                              template: String? = nil) -> NSUserActivity {
        let activity = NSUserActivity(activityType: type.rawValue)
        activity.title = template.map { "\(type.displayTitle): \($0)" } ?? type.displayTitle
        activity.userInfo = userInfo(for: type, sessionID: sessionID, template: template)
        activity.isEligibleForHandoff = true
        activity.becomeCurrent()
        return activity
    }
    #endif
}
#endif
