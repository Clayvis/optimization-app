import Foundation
import SwiftData

/// Gap 1 (durability): the meta-analysis is blunt that gamification starts
/// habits but the long-term effect collapses around week 14. The fix is an
/// explicit handoff from extrinsic (the streak number) to intrinsic (identity +
/// self-knowledge). After the bootstrap window this service produces an
/// identity-framed, trend-aware headline so the streak stops being the only
/// thing holding the user. The streak survives as scaffolding, demoted in
/// visual weight, not deleted.
struct DurabilityHeadline: Sendable, Equatable {
    enum Phase: String, Sendable {
        /// Weeks 1-4: the streak count IS the headline (extrinsic bootstrap).
        case bootstrap
        /// Past the bootstrap window: identity + trend lead; streak demoted.
        case established
    }

    let phase: Phase
    let identityLine: String
    let trendLine: String?
    let streakDays: Int
}

@MainActor
struct DurabilityHeadlineService {
    /// Days of use before the extrinsic-to-intrinsic handoff. Matches the build
    /// sheet's "after ~30 days of streak data" and the heavy-weeks-1-4 fade.
    static let bootstrapDays = 30

    private let modelContext: ModelContext
    private let calendar: Calendar
    private let firstLaunch: Date
    private let hydrationTargets: HydrationTargetsOz?

    init(modelContext: ModelContext,
         calendar: Calendar? = nil,
         firstLaunch: Date = FirstLaunchTracker.shared.firstLaunchAt,
         hydrationTargets: HydrationTargetsOz? = nil) {
        self.modelContext = modelContext
        self.calendar = calendar ?? UserCalendar.current(modelContext: modelContext)
        self.firstLaunch = firstLaunch
        self.hydrationTargets = hydrationTargets
    }

    func headline(asOf: Date = Date()) -> DurabilityHeadline {
        let firstDay = calendar.startOfDay(for: firstLaunch)
        let today = calendar.startOfDay(for: asOf)
        let daysSince = max(0, calendar.dateComponents([.day], from: firstDay, to: today).day ?? 0)

        let counters = modelContext.fetchOrEmpty(FetchDescriptor<StreakCounter>())
        let master = counters.first { $0.domain == StreakDomain.protocolAdherence.rawValue }
        let streakDays = master?.currentStreak ?? 0

        let phase: DurabilityHeadline.Phase = daysSince >= Self.bootstrapDays ? .established : .bootstrap
        let topDomain = mostProvenDomain(counters: counters)
        let identityLine = IdentityCopy.identityStatement(topDomain: topDomain)

        // Trend narrative is only surfaced in the established phase, so the
        // bootstrap weeks stay focused on the streak.
        let trendLine: String? = phase == .established
            ? (topTrendSummary(asOf: asOf) ?? IdentityCopy.trendFallback(streakDays: streakDays))
            : nil

        return DurabilityHeadline(
            phase: phase,
            identityLine: identityLine,
            trendLine: trendLine,
            streakDays: streakDays
        )
    }

    /// The domain whose LONGEST streak is greatest is the most-proven identity.
    /// protocolAdherence is excluded so the statement names a concrete behavior
    /// (mover / learner) rather than the abstract rollup. nil when nothing has
    /// been established yet.
    private func mostProvenDomain(counters: [StreakCounter]) -> StreakDomain? {
        let concrete: [StreakDomain] = [.workout, .hydration, .learning, .fasting]
        let ranked = concrete.compactMap { domain -> (StreakDomain, Int)? in
            guard let counter = counters.first(where: { $0.domain == domain.rawValue }) else { return nil }
            return counter.longestStreak > 0 ? (domain, counter.longestStreak) : nil
        }
        return ranked.max { $0.1 < $1.1 }?.0
    }

    /// Highest-confidence detected pattern's one-sentence summary, or nil if no
    /// pattern clears the confidence floor. This is the "you move more on days
    /// you sleep 7+ hours" personal trend narrative.
    private func topTrendSummary(asOf: Date) -> String? {
        let trends = TrendAnalyticsService(
            modelContext: modelContext,
            timezone: calendar.timeZone,
            hydrationTargets: hydrationTargets
        )
        let patterns = trends.patternsDetected(over: .lastNDays(30, asOf: asOf, timezone: calendar.timeZone))
        return patterns.max { $0.confidence < $1.confidence }?.summary
    }
}
