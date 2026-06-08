import Foundation
import SwiftData
import os

/// 30-day TestFlight instrumentation (engagement build sheet, section 6).
///
/// Computes the six leading indicators that PREDICT long-term retention,
/// entirely from data already persisted on-device. The app is zero-server by
/// design, so "instrumentation" means in-app computed metrics surfaced in a
/// diagnostics screen, never a remote analytics SDK.
///
/// Indicators:
///  1. 7-day streak establishment (PRIMARY): did the master protocol streak
///     reach 7 consecutive completed days, and did that happen within week one.
///  2. Day-over-day return rate (local CURR): P(active tomorrow | active today).
///  3. Grace-day usage: distinct days a forgiveness mechanism protected a streak.
///  4. Joint-streak survival: solo vs joint (min of self + partner) streak.
///  5. Insight engagement: deliberate-interaction rate + helpful:unhelpful ratio.
///  6. Qualitative week-4 check: a one-tap "does this still feel motivating?".
///
/// All reads reuse the streak engine's own completion rules (via
/// `StreakService.completedDays`) so instrumentation never drifts from the
/// number the user actually sees. Pure read; never mutates persisted state.
@MainActor
struct EngagementMetricsService {
    private let modelContext: ModelContext
    private let calendar: Calendar
    private let firstLaunch: Date
    private let hydrationTargets: HydrationTargetsOz?
    private let week4Defaults: UserDefaults

    init(modelContext: ModelContext,
         calendar: Calendar? = nil,
         firstLaunch: Date = FirstLaunchTracker.shared.firstLaunchAt,
         hydrationTargets: HydrationTargetsOz? = nil,
         week4Defaults: UserDefaults = .standard) {
        self.modelContext = modelContext
        self.calendar = calendar ?? UserCalendar.current(modelContext: modelContext)
        self.firstLaunch = firstLaunch
        self.hydrationTargets = hydrationTargets
        self.week4Defaults = week4Defaults
    }

    /// Computes the full instrumentation snapshot. `partnerCurrentStreak` is the
    /// partner's current streak from a fetched `PartnerSharedRecord` snapshot, or
    /// nil when no partner is paired (the single-user reality of v1.0).
    func compute(asOf: Date = Date(), partnerCurrentStreak: Int? = nil) -> EngagementMetrics {
        let today = calendar.startOfDay(for: asOf)
        let firstDay = calendar.startOfDay(for: firstLaunch)
        let daysSinceFirstLaunch = max(0, calendar.dateComponents([.day], from: firstDay, to: today).day ?? 0)

        let streakService = StreakService(
            modelContext: modelContext,
            timezone: calendar.timeZone,
            hydrationTargets: hydrationTargets
        )

        // Indicator 1: establishment.
        let establishment = computeEstablishment(streakService: streakService, firstDay: firstDay, asOf: asOf)
        let perDomainLongest = perDomainLongestStreaks()
        let anyDomainReachedSeven = perDomainLongest.values.contains { $0 >= 7 }

        // Indicator 2: day-over-day return rate (CURR).
        let activeDays = activeDaySet()
        let curr = dayOverDayReturnRate(activeDays: activeDays, today: today)

        // Indicator 3: grace-day usage.
        let grace = graceUsage(since: firstDay)

        // Indicator 4: joint-streak survival.
        let solo = protocolStreakCounter()?.currentStreak ?? 0
        let joint: Int? = partnerCurrentStreak.map { min(solo, $0) }

        // Indicator 5: insight engagement.
        let insight = insightEngagement(since: firstDay)

        // Indicator 6: qualitative week-4 check.
        let week4 = Week4CheckIn.load(from: week4Defaults)

        return EngagementMetrics(
            daysSinceFirstLaunch: daysSinceFirstLaunch,
            establishedSevenDayStreak: establishment.established,
            establishedInWeekOne: establishment.inWeekOne,
            daysToEstablishment: establishment.daysTo,
            anyDomainReachedSeven: anyDomainReachedSeven,
            perDomainLongest: perDomainLongest,
            activeDaysCount: activeDays.count,
            dayOverDayReturnRate: curr,
            graceDaysApplied: grace.total,
            graceBySource: grace.bySource,
            freezesRemainingThisMonth: protocolStreakCounter()?.freezesAvailable ?? StreakService.maxFreezesPerMonth,
            partnerPaired: partnerCurrentStreak != nil,
            soloStreak: solo,
            jointStreak: joint,
            insightsShown: insight.shown,
            insightInteractionRate: insight.rate,
            insightHelpful: insight.helpful,
            insightUnhelpful: insight.unhelpful,
            meetsInsightGate: insight.meets,
            week4Captured: week4.captured,
            week4FeelsMotivating: week4.feelsMotivating
        )
    }

    // MARK: - Indicator 1: 7-day streak establishment

    private func computeEstablishment(
        streakService: StreakService,
        firstDay: Date,
        asOf: Date
    ) -> (established: Bool, inWeekOne: Bool, daysTo: Int?) {
        let protocolDays = (try? streakService.completedDays(domain: .protocolAdherence, asOf: asOf)) ?? []
        guard let establishmentDay = earliestSevenDayRunEnd(protocolDays) else {
            return (false, false, nil)
        }
        let rawDaysTo = calendar.dateComponents([.day], from: firstDay, to: establishmentDay).day
        // Week-one establishment: the seventh consecutive day landed within the
        // first 7 days since first launch (Duolingo optimizes this leading
        // indicator rather than 30-day retention directly). firstDay is day 0,
        // so those days are offsets 0...6; the earliest perfect-start run ends at
        // offset 6. A negative offset means the run predates this install (e.g.
        // imported history): established, but not THIS user's week one.
        let inWeekOne = (rawDaysTo ?? Int.min) >= 0 && (rawDaysTo ?? Int.min) <= 6
        // Clamp the reported offset so imported pre-install history never shows a
        // negative "established on day -N".
        let reportedDaysTo = rawDaysTo.map { max(0, $0) }
        return (true, inWeekOne, reportedDaysTo)
    }

    /// Returns the END date of the earliest 7-consecutive-calendar-day run within
    /// `days`, or nil if no such run exists. Used only for protocolAdherence,
    /// which has no auto rest days, so consecutive calendar days is the correct
    /// model.
    private func earliestSevenDayRunEnd(_ days: Set<Date>) -> Date? {
        guard !days.isEmpty else { return nil }
        for start in days.sorted() {
            var cursor = start
            var complete = true
            for _ in 0..<7 {
                if !days.contains(cursor) { complete = false; break }
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { complete = false; break }
                cursor = next
            }
            if complete {
                return calendar.date(byAdding: .day, value: 6, to: start)
            }
        }
        return nil
    }

    private func perDomainLongestStreaks() -> [String: Int] {
        var result: [String: Int] = [:]
        for domain in StreakDomain.allCases {
            let key = domain.rawValue
            let counter = modelContext.fetchFirstOrNil(
                FetchDescriptor<StreakCounter>(predicate: #Predicate<StreakCounter> { $0.domain == key })
            )
            result[key] = counter?.longestStreak ?? 0
        }
        return result
    }

    // MARK: - Indicator 2: day-over-day return rate (CURR)

    /// A calendar day is "active" when the user genuinely engaged: a DailyLog with
    /// any logged field, or a completed non-grace workout. Grace days (freeze /
    /// travel / sick / manual skip) are NOT engagement and are excluded so the
    /// return rate measures real returns, not protection tokens.
    private func activeDaySet() -> Set<Date> {
        var set: Set<Date> = []
        let logs = modelContext.fetchOrEmpty(
            FetchDescriptor<DailyLog>(predicate: #Predicate<DailyLog> { $0.supersededAt == nil })
        )
        for log in logs {
            let active = log.waterOz > 0
                || log.japaneseMinutes > 0
                || log.guitarMinutes > 0
                || log.courseworkMinutes > 0
                || log.musicMinutes > 0
                || log.electrolyteSessions > 0
                || log.fastStart != nil
                || log.fastEnd != nil
                || log.subjectiveEnergy != nil
            if active { set.insert(calendar.startOfDay(for: log.date)) }
        }
        let graceSources = Self.graceWorkoutSources
        for event in modelContext.fetchOrEmpty(FetchDescriptor<WorkoutEvent>()) {
            guard event.completed, !graceSources.contains(event.source) else { continue }
            set.insert(calendar.startOfDay(for: event.date))
        }
        return set
    }

    /// P(active tomorrow | active today). A day is eligible only when its
    /// "tomorrow" is a fully past, observable day (strictly before today).
    /// Yesterday's tomorrow is today, still in progress, so counting it would
    /// depress the rate every morning before the user logs anything. nil when no
    /// eligible day.
    private func dayOverDayReturnRate(activeDays: Set<Date>, today: Date) -> Double? {
        let eligible = activeDays.filter {
            guard let next = calendar.date(byAdding: .day, value: 1, to: $0) else { return false }
            return next < today
        }
        guard !eligible.isEmpty else { return nil }
        var returned = 0
        for day in eligible {
            if let next = calendar.date(byAdding: .day, value: 1, to: day), activeDays.contains(next) {
                returned += 1
            }
        }
        return Double(returned) / Double(eligible.count)
    }

    // MARK: - Indicator 3: grace-day usage

    private static let graceWorkoutSources: Set<String> = [
        WorkoutEventSource.freeze.rawValue,
        WorkoutEventSource.travel.rawValue,
        WorkoutEventSource.sickDay.rawValue,
        WorkoutEventSource.manualSkip.rawValue
    ]

    /// Counts DISTINCT calendar days a grace mechanism protected a streak since
    /// `since`. Grace ledger rows fan out (sick day writes one row per non-workout
    /// domain), so days are deduped to avoid 4x overcount. Categorized by the
    /// clearest available source label.
    private func graceUsage(since: Date) -> (total: Int, bySource: [String: Int]) {
        var sickDays: Set<Date> = []
        var travelDays: Set<Date> = []
        var freezeDays: Set<Date> = []

        let events = modelContext.fetchOrEmpty(
            FetchDescriptor<WorkoutEvent>(predicate: #Predicate<WorkoutEvent> { $0.date >= since })
        )
        for event in events {
            let day = calendar.startOfDay(for: event.date)
            switch event.source {
            case WorkoutEventSource.sickDay.rawValue: sickDays.insert(day)
            case WorkoutEventSource.travel.rawValue: travelDays.insert(day)
            case WorkoutEventSource.freeze.rawValue: freezeDays.insert(day)
            default: break
            }
        }
        // FreezeApplication rows cover manual single-domain freezes (no workout
        // event). Treat their days as "freeze" unless already labeled sick/travel.
        let freezeApps = modelContext.fetchOrEmpty(
            FetchDescriptor<FreezeApplication>(predicate: #Predicate<FreezeApplication> { $0.date >= since })
        )
        for app in freezeApps {
            let day = calendar.startOfDay(for: app.date)
            if !sickDays.contains(day) && !travelDays.contains(day) {
                freezeDays.insert(day)
            }
        }

        let allGraceDays = sickDays.union(travelDays).union(freezeDays)
        var bySource: [String: Int] = [:]
        if !sickDays.isEmpty { bySource["sick day"] = sickDays.count }
        if !travelDays.isEmpty { bySource["travel"] = travelDays.count }
        if !freezeDays.isEmpty { bySource["freeze"] = freezeDays.count }
        return (allGraceDays.count, bySource)
    }

    private func protocolStreakCounter() -> StreakCounter? {
        let key = StreakDomain.protocolAdherence.rawValue
        return modelContext.fetchFirstOrNil(
            FetchDescriptor<StreakCounter>(predicate: #Predicate<StreakCounter> { $0.domain == key })
        )
    }

    // MARK: - Indicator 5: insight engagement

    /// Aggregates CoachInsight interactions since `since`. "Interaction" is a
    /// DELIBERATE action (dismissed / acted-on / marked), excluding auto-"viewed"
    /// and "ignored", so the rate reflects real reading, not mere display. The
    /// day-30 gate (decision 004) is >=40% interaction AND >=3:1 helpful:unhelpful.
    private func insightEngagement(since: Date) -> (shown: Int, rate: Double?, helpful: Int, unhelpful: Int, meets: Bool) {
        let insights = modelContext.fetchOrEmpty(
            FetchDescriptor<CoachInsight>(predicate: #Predicate<CoachInsight> { $0.generatedAt >= since })
        )
        let shown = insights.count
        guard shown > 0 else { return (0, nil, 0, 0, false) }
        let deliberate = CoachInsightInteraction.dismissed.precedence
        let interacted = insights.filter { $0.userInteraction.precedence >= deliberate }.count
        let helpful = insights.filter { $0.userInteraction == .markedHelpful }.count
        let unhelpful = insights.filter { $0.userInteraction == .markedUnhelpful }.count
        let rate = Double(interacted) / Double(shown)
        let ratioOK = unhelpful == 0 ? helpful > 0 : (Double(helpful) / Double(unhelpful)) >= 3.0
        let meets = rate >= 0.40 && ratioOK
        return (shown, rate, helpful, unhelpful, meets)
    }
}

/// Immutable snapshot of the six leading indicators. Value type so it can cross
/// actors and be diffed in tests.
struct EngagementMetrics: Sendable, Equatable {
    var daysSinceFirstLaunch: Int

    // 1. 7-day streak establishment (primary success metric).
    var establishedSevenDayStreak: Bool
    var establishedInWeekOne: Bool
    var daysToEstablishment: Int?
    var anyDomainReachedSeven: Bool
    var perDomainLongest: [String: Int]

    // 2. Day-over-day return rate (CURR).
    var activeDaysCount: Int
    var dayOverDayReturnRate: Double?

    // 3. Grace-day usage.
    var graceDaysApplied: Int
    var graceBySource: [String: Int]
    var freezesRemainingThisMonth: Int

    // 4. Joint-streak survival.
    var partnerPaired: Bool
    var soloStreak: Int
    var jointStreak: Int?

    // 5. Insight engagement.
    var insightsShown: Int
    var insightInteractionRate: Double?
    var insightHelpful: Int
    var insightUnhelpful: Int
    var meetsInsightGate: Bool

    // 6. Qualitative week-4 check.
    var week4Captured: Bool
    var week4FeelsMotivating: Bool?
}

/// One-tap qualitative week-4 self-check ("does this still feel motivating, or
/// like an obligation?"). Stored in UserDefaults rather than SwiftData because
/// it is test-period instrumentation metadata, not user activity history, and
/// must not trigger a schema migration. Injectable defaults keep it testable.
enum Week4CheckIn {
    private static let dateKey = "\(BuildConfig.bundlePrefix).week4CheckIn.capturedAt"
    private static let valueKey = "\(BuildConfig.bundlePrefix).week4CheckIn.feelsMotivating"

    static func load(from defaults: UserDefaults = .standard) -> (captured: Bool, feelsMotivating: Bool?) {
        guard defaults.object(forKey: dateKey) != nil else { return (false, nil) }
        return (true, defaults.bool(forKey: valueKey))
    }

    static func record(feelsMotivating: Bool, at date: Date = Date(), into defaults: UserDefaults = .standard) {
        defaults.set(date, forKey: dateKey)
        defaults.set(feelsMotivating, forKey: valueKey)
    }

    static func reset(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: dateKey)
        defaults.removeObject(forKey: valueKey)
    }
}
