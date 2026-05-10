import Foundation

/// Records the first-ever launch timestamp in UserDefaults so the About screen
/// can show "days since first launch" without depending on a SwiftData model.
/// Set once on the first call to `recordIfNeeded()`; never overwritten. The
/// 30-day TestFlight review (per `.work/decisions/004-coach-feedback-as-validation-gate.md`)
/// uses this as the baseline for filtering early-onboarding noise.
final class FirstLaunchTracker: @unchecked Sendable {
    static let shared = FirstLaunchTracker()

    private let key = "com.rawlins.PersonalOptimization.firstLaunchAt"

    var firstLaunchAt: Date {
        if let stored = UserDefaults.standard.object(forKey: key) as? Date {
            return stored
        }
        let now = Date()
        UserDefaults.standard.set(now, forKey: key)
        return now
    }

    /// Idempotent. Call once at app startup so the first-launch timestamp is
    /// pinned even if the user never opens About.
    func recordIfNeeded() {
        _ = firstLaunchAt
    }
}
