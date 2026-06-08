import Foundation

/// Centralized identity-framed copy. Confirmations reinforce who the user is, not
/// what task was ticked. One edit here cascades everywhere.
///
/// Source: PIVOT_SPEC design principle 4 ("identity framing over task framing").
enum IdentityCopy {

    // MARK: - Confirmations after a behavior is logged

    static let workoutLogged = "You showed up."
    static let fastClosed = "That's who you are now."
    static let fastBrokeEarly = "You logged the truth. That counts."
    static let hydrationLogged = "Streak alive."
    static let learningLogged = "Practice in the bank."

    // MARK: - Daily aggregate

    static let dayCompleteAll = "Today belongs to the disciplined."
    static let dayPartial = "You're building a record."

    // MARK: - Notification copy (identity-framed)

    enum Notification {
        static let fastStartTitle = "Window opening"
        static func fastStartBody(label: String) -> String {
            "The \(label) fast window starts now. You've done this before."
        }

        static let fastEndTitle = "Window closed"
        static func fastEndBody(label: String) -> String {
            "The \(label) window is over. Eat with intention."
        }

        static let hydrationTitle = "Stay on it"
        static func hydrationBody(progressOz: Double, targetMaxOz: Double) -> String {
            "\(Int(progressOz)) of \(Int(targetMaxOz)) oz so far. Pick up the next bottle."
        }

        static func learningTitle(moduleName: String) -> String {
            "\(moduleName) on deck"
        }
        static func learningBody(moduleName: String, targetMinutes: Int) -> String {
            "\(targetMinutes) min of \(moduleName.lowercased()). You're someone who does this."
        }
    }

    // MARK: - Banners

    static let travelBanner = "Travel mode active. Streaks paused, not faked."
    static let sickBanner = "Sick day. Today is covered. Rest up."

    // MARK: - Streak mercy (design principle 2: streaks need mercy, made visible)

    /// Reassures the user that missing a day will not erase their streak,
    /// because freezes are available. Identity-framed: protection, not pressure.
    static func streakFreezeAvailable(count: Int) -> String {
        let noun = count == 1 ? "freeze" : "freezes"
        return "\(count) streak \(noun) left this month. A missed day won't erase you."
    }

    /// Shown after the user spends a freeze to protect today. Reassurance, not
    /// pressure: the streak is preserved honestly and the day is covered.
    static let streakProtected = "Streak protected. Rest easy."

    // MARK: - Mascot reasons (display-only, not load-bearing)

    static let mascotProudStreak = "You hit a streak milestone."
    static let mascotAchievementPR = "You set a new personal record."

    // MARK: - Durability handoff (design principle: identity outlasts the streak)

    /// Identity statement for the user's most-proven domain, used once the app
    /// shifts the headline away from a raw streak count (Gap 1 durability). The
    /// frame is "who you are," not "what you did," because identity-based habits
    /// survive a broken streak where goal-based ones do not.
    static func identityStatement(topDomain: StreakDomain?) -> String {
        switch topDomain {
        case .workout:           return "You are a consistent mover."
        case .hydration:         return "Staying hydrated is just who you are now."
        case .learning:          return "You are a daily learner."
        case .fasting:           return "Discipline with food is your default."
        case .protocolAdherence: return "You are someone who keeps their word."
        case nil:                return "You are building who you are, one day at a time."
        }
    }

    /// Fallback trend line when no pattern has been detected yet but the user is
    /// past the bootstrap window. Keeps the headline about the record they are
    /// building rather than a single fragile number.
    static func trendFallback(streakDays: Int) -> String {
        guard streakDays > 0 else { return "Every day you log is a day on the record." }
        return "\(streakDays) days on the record, and the habit is yours now."
    }
}
