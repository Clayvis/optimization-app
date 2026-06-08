import Foundation
import SwiftData

/// Variable / unpredictable reward (build sheet section 2): an OCCASIONAL surprise
/// insight that appears off the fixed daily-insight schedule. The power of a
/// variable-ratio reward is the unpredictable TIMING, so the trigger is a stable
/// per-day pseudo-random roll (same day yields the same decision across app
/// restarts, but the user cannot predict which days) gated by a cooldown.
///
/// Cost-safe: the content is drawn from the top already-computed DetectedPattern
/// (e.g. "you move more on days you sleep 7+ hours") or a streak reflection, so a
/// surprise never makes an extra Anthropic API call. The daily CoachInsight
/// remains the API-generated reflection; this is the bonus on top.
struct SurpriseInsight: Sendable, Equatable {
    let body: String
}

@MainActor
struct SurpriseInsightService {
    /// Minimum days between surprises so they stay rare and special.
    static let cooldownDays = 3
    /// Fraction of eligible days that surface a surprise (~1 in 3).
    static let dailyProbability = 0.30
    /// Days of use before surprises begin (need real history to be notable).
    static let minDataDays = 7

    private let modelContext: ModelContext
    private let calendar: Calendar
    private let firstLaunch: Date
    private let hydrationTargets: HydrationTargetsOz?
    private let defaults: UserDefaults

    private static let lastShownKey = "\(BuildConfig.bundlePrefix).surpriseInsight.lastShownAt"
    private static let lastShownBodyKey = "\(BuildConfig.bundlePrefix).surpriseInsight.lastShownBody"

    init(modelContext: ModelContext,
         calendar: Calendar? = nil,
         firstLaunch: Date = FirstLaunchTracker.shared.firstLaunchAt,
         hydrationTargets: HydrationTargetsOz? = nil,
         defaults: UserDefaults = .standard) {
        self.modelContext = modelContext
        self.calendar = calendar ?? UserCalendar.current(modelContext: modelContext)
        self.firstLaunch = firstLaunch
        self.hydrationTargets = hydrationTargets
        self.defaults = defaults
    }

    /// The surprise for today on a variable schedule, or nil. Idempotent within a
    /// day: once surfaced today it keeps returning today's surprise so the card is
    /// stable across re-renders. `rollOverride` is for tests; production uses the
    /// stable per-day roll.
    func surpriseForToday(asOf: Date = Date(), rollOverride: Double? = nil) -> SurpriseInsight? {
        let today = calendar.startOfDay(for: asOf)
        let firstDay = calendar.startOfDay(for: firstLaunch)
        let daysSinceLaunch = calendar.dateComponents([.day], from: firstDay, to: today).day ?? 0
        guard daysSinceLaunch >= Self.minDataDays else { return nil }

        if let last = lastShown() {
            let lastDay = calendar.startOfDay(for: last)
            if lastDay == today {
                // Already surfaced today: keep showing the SAME surprise (cached
                // body), so the card is stable even if data shifts mid-day.
                if let cached = defaults.string(forKey: Self.lastShownBodyKey) {
                    return SurpriseInsight(body: cached)
                }
                return makeBody(asOf: asOf).map(SurpriseInsight.init)
            }
            let gap = calendar.dateComponents([.day], from: lastDay, to: today).day ?? Int.max
            if gap < Self.cooldownDays { return nil }
        }

        let roll = rollOverride ?? dailyRoll(for: today)
        guard roll < Self.dailyProbability else { return nil }
        return makeBody(asOf: asOf).map(SurpriseInsight.init)
    }

    /// Records that today's surprise was surfaced, caching its body so the
    /// shown-today path returns the identical text on later renders.
    func markShown(asOf: Date = Date(), body: String) {
        defaults.set(asOf, forKey: Self.lastShownKey)
        defaults.set(body, forKey: Self.lastShownBodyKey)
    }

    func lastShown() -> Date? {
        defaults.object(forKey: Self.lastShownKey) as? Date
    }

    // MARK: - Helpers

    /// The surprise body: the highest-confidence detected pattern, else a streak
    /// reflection. Returns nil when nothing is notable enough to be a reward.
    private func makeBody(asOf: Date) -> String? {
        let trends = TrendAnalyticsService(
            modelContext: modelContext,
            timezone: calendar.timeZone,
            hydrationTargets: hydrationTargets
        )
        let patterns = trends.patternsDetected(over: .lastNDays(30, asOf: asOf, timezone: calendar.timeZone))
        if let top = patterns.max(by: { $0.confidence < $1.confidence }) {
            return top.summary
        }
        let counters = modelContext.fetchOrEmpty(FetchDescriptor<StreakCounter>())
        let longest = counters.map(\.longestStreak).max() ?? 0
        if longest >= 7 {
            return "Your longest streak is \(longest) days. That consistency is who you are now."
        }
        return nil
    }

    /// Stable per-day pseudo-random value in [0, 1). Same calendar day always
    /// yields the same value (so the decision survives app restarts), but the
    /// user cannot predict which days clear the probability bar. Deterministic
    /// integer hash (not Swift's per-process-randomized Hasher).
    private func dailyRoll(for day: Date) -> Double {
        let comps = calendar.dateComponents([.year, .month, .day], from: day)
        let seed = Int64((comps.year ?? 0) * 10_000 + (comps.month ?? 0) * 100 + (comps.day ?? 0))
        var x = UInt64(bitPattern: seed) &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        x ^= x >> 33
        return Double(x % 10_000) / 10_000.0
    }
}
