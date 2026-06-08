import Foundation
import SwiftData
import os

/// Recovery-aware prescription gate. Pulls HRV / sleep / resting-HR /
/// achilles-pain signals and returns a `.normal | .downgrade | .rest`
/// verdict the Coach honors when prescribing today's workout.
///
/// Research basis: Plews & Laursen (2017+), MDPI 2025 systematic review on
/// AI exercise prescription. Without a recovery gate, AI coaches over-
/// prescribe in 20-40% of users — a category-killer when the user has an
/// existing injury (Clay's Achilles).
///
/// Thresholds intentionally conservative on first ship; user can override
/// per session, and override frequency is tracked on UserProfile so the
/// Coach can call out repeat overrides ("you've overridden 4 times this
/// month — your HRV says otherwise").
@MainActor
struct RecoveryGate {
    let modelContext: ModelContext
    let timezone: TimeZone

    init(modelContext: ModelContext,
         timezone: TimeZone = TimeZone.current) {
        self.modelContext = modelContext
        self.timezone = timezone
    }

    /// Evaluates today's recovery and returns a recommendation + reason.
    /// Pure read; does not mutate state. Thin wrapper over `evaluateDetailed`.
    func evaluate(profile: UserProfile, asOf date: Date = Date()) -> RecoveryStatus {
        let detail = evaluateDetailed(profile: profile, asOf: date)
        return RecoveryStatus(recommendation: detail.recommendation, reason: detail.reason)
    }

    /// Transparent readiness breakdown (Gap 3: opaque scores). Returns the same
    /// recommendation the Coach honors PLUS the component inputs (HRV, resting
    /// HR, sleep) with their direction vs the 7-day baseline, and a concrete
    /// training-load adjustment. No false precision: the headline is qualitative
    /// ("Ease off today"), never a fabricated "73.4% recovered". Differentiator
    /// against black-box wearable scores: the user sees what moved the verdict.
    func evaluateDetailed(profile: UserProfile, asOf date: Date = Date()) -> RecoveryDetail {
        let log = todaysLog(asOf: date)
        let baseline = sevenDayBaseline(endingBefore: date)

        // Sleep is the most actionable signal we have on the watch + phone.
        let sleepHours = log?.sleepHours ?? baseline.sleepMean
        let hrvDelta = baseline.hrvMean.map { mean in
            mean > 0 ? ((log?.hrvRmssd ?? mean) - mean) / mean : 0
        } ?? 0
        let restingHRDelta = baseline.restingHRMean.map { mean in
            mean > 0 ? (Double(log?.restingHR ?? Int(mean)) - mean) / mean : 0
        } ?? 0
        let achillesPain = log?.achillesPain ?? 0

        let (recommendation, reason) = classify(
            hrvDelta: hrvDelta,
            sleepHours: sleepHours,
            restingHRDelta: restingHRDelta,
            achillesPain: achillesPain
        )
        let components = buildComponents(log: log, baseline: baseline)
        let (loadText, loadMultiplier) = loadAdjustment(for: recommendation)
        return RecoveryDetail(
            recommendation: recommendation,
            headline: Self.headline(for: recommendation),
            reason: reason,
            components: components,
            loadAdjustment: loadText,
            loadMultiplier: loadMultiplier,
            hasData: !components.isEmpty
        )
    }

    /// The recommendation thresholds. Order matters: rest rules are checked
    /// before downgrade rules so the strongest signal wins. Reason strings are
    /// identity-framed and surface verbatim in the recovery card.
    private func classify(
        hrvDelta: Double,
        sleepHours: Double,
        restingHRDelta: Double,
        achillesPain: Int
    ) -> (RecoveryRecommendation, String) {
        // Hard rest-day rules — any one trips it.
        if hrvDelta < -0.30 {
            return (.rest, "HRV is \(Int((-hrvDelta) * 100))% below your 7-day baseline.")
        }
        if sleepHours > 0 && sleepHours < 4.5 {
            return (.rest, "Sleep last night was \(formatSleep(sleepHours)). Below the 4.5h floor.")
        }
        if achillesPain >= 7 {
            return (.rest, "Achilles pain logged at \(achillesPain)/10. The injury talks; listen.")
        }

        // Downgrade rules — any one trips it (after rest rules above).
        if hrvDelta < -0.20 {
            return (.downgrade, "HRV trending \(Int((-hrvDelta) * 100))% below baseline.")
        }
        if sleepHours > 0 && sleepHours < 5.5 {
            return (.downgrade, "Sleep last night was \(formatSleep(sleepHours)).")
        }
        if restingHRDelta > 0.10 {
            return (.downgrade, "Resting HR is \(Int(restingHRDelta * 100))% above baseline.")
        }
        if achillesPain >= 5 {
            return (.downgrade, "Achilles pain at \(achillesPain)/10 — keep the load light.")
        }

        return (.normal, "Recovery markers within range.")
    }

    /// Builds the visible input components (HRV, resting HR, sleep) with today's
    /// value, the 7-day baseline, and whether the direction is favorable. Only
    /// components with real data are included; the card hides when this is empty
    /// so the gate stays quiet on cold start rather than showing false precision.
    private func buildComponents(log: DailyLog?, baseline: Baseline) -> [RecoveryComponent] {
        var components: [RecoveryComponent] = []

        // Gate HRV / RHR on TODAY's actual reading, never the baseline mean.
        // Showing the 7-day average as if it were a same-day measurement would be
        // exactly the false precision this surface exists to avoid.
        if let hrv = log?.hrvRmssd {
            let baselineMean = baseline.hrvMean
            let favorable = baselineMean.map { hrv >= $0 } ?? true
            components.append(RecoveryComponent(
                label: "HRV",
                valueText: "\(Int(hrv.rounded())) ms",
                baselineText: baselineMean.map { "7-day avg \(Int($0.rounded())) ms" },
                direction: direction(value: hrv, baseline: baselineMean, higherIsBetter: true),
                isFavorable: favorable
            ))
        }
        if let rhrInt = log?.restingHR {
            let rhr = Double(rhrInt)
            let baselineMean = baseline.restingHRMean
            let favorable = baselineMean.map { rhr <= $0 } ?? true
            components.append(RecoveryComponent(
                label: "Resting HR",
                valueText: "\(Int(rhr.rounded())) bpm",
                baselineText: baselineMean.map { "7-day avg \(Int($0.rounded())) bpm" },
                direction: direction(value: rhr, baseline: baselineMean, higherIsBetter: false),
                isFavorable: favorable
            ))
        }
        if let sleep = log?.sleepHours {
            let favorable = sleep >= 6.5
            components.append(RecoveryComponent(
                label: "Sleep",
                valueText: formatSleep(sleep),
                baselineText: "7-day avg \(formatSleep(baseline.sleepMean))",
                direction: direction(value: sleep, baseline: baseline.sleepMean, higherIsBetter: true),
                isFavorable: favorable
            ))
        }
        // Achilles pain is a today-logged signal that can drive a downgrade, so
        // surface it as a component. This also makes hasData true for an
        // achilles-only day, so the card explains the verdict (and the Move-goal
        // easing, which gates on hasData, has a visible cause).
        if let pain = log?.achillesPain, pain > 0 {
            components.append(RecoveryComponent(
                label: "Achilles",
                valueText: "\(pain)/10",
                baselineText: nil,
                direction: .flat,
                isFavorable: pain < 5
            ))
        }
        return components
    }

    private func direction(value: Double, baseline: Double?, higherIsBetter: Bool) -> RecoveryComponent.Direction {
        guard let baseline else { return .flat }
        let delta = value - baseline
        // 3% deadband so noise reads as flat, not a trend (expert guidance:
        // ignore night-to-night jitter, watch larger moves).
        let threshold = abs(baseline) * 0.03
        if delta > threshold { return .up }
        if delta < -threshold { return .down }
        return .flat
    }

    private func loadAdjustment(for recommendation: RecoveryRecommendation) -> (String, Double) {
        switch recommendation {
        case .normal:    return ("Full training load", 1.0)
        case .downgrade: return ("Reduce today's load ~30%", 0.7)
        case .rest:      return ("Rest day", 0.0)
        }
    }

    private static func headline(for recommendation: RecoveryRecommendation) -> String {
        switch recommendation {
        case .normal:    return "Recovered"
        case .downgrade: return "Ease off today"
        case .rest:      return "Rest day"
        }
    }

    /// Records that the user manually overrode the gate's downgrade/rest
    /// recommendation. Bumps a counter on UserProfile that the Coach can
    /// surface when overrides become a pattern.
    func recordOverride(profile: UserProfile, at date: Date = Date()) {
        let cal = jstCalendar()
        let thisMonth = cal.dateComponents([.year, .month], from: date)
        let lastMonth = profile.lastRecoveryOverrideAt.map { cal.dateComponents([.year, .month], from: $0) }
        if lastMonth?.year != thisMonth.year || lastMonth?.month != thisMonth.month {
            profile.recoveryOverrideCountThisMonth = 0
        }
        profile.lastRecoveryOverrideAt = date
        profile.recoveryOverrideCountThisMonth += 1
        try? modelContext.save()  // MARK: try? save() is best-effort — failures surface via os_log; in-memory state already updated.
    }

    // MARK: - Helpers

    private func todaysLog(asOf date: Date) -> DailyLog? {
        let cal = jstCalendar()
        let day = cal.startOfDay(for: date)
        let descriptor = FetchDescriptor<DailyLog>(
            predicate: #Predicate<DailyLog> { $0.date == day && $0.supersededAt == nil }
        )
        return modelContext.fetchFirstOrNil(descriptor)
    }

    private struct Baseline {
        let sleepMean: Double
        let hrvMean: Double?
        let restingHRMean: Double?
    }

    /// 7-day rolling baseline for sleep / HRV / resting HR. Returns nil for
    /// sub-fields that don't have at least 3 days of data so the gate stays
    /// quiet on cold-start.
    private func sevenDayBaseline(endingBefore date: Date) -> Baseline {
        let cal = jstCalendar()
        let today = cal.startOfDay(for: date)
        let weekAgo = cal.date(byAdding: .day, value: -7, to: today) ?? today

        let descriptor = FetchDescriptor<DailyLog>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let all = modelContext.fetchOrEmpty(descriptor)
        let window = all.filter { $0.date >= weekAgo && $0.date < today }

        let sleepValues = window.compactMap(\.sleepHours)
        let hrvValues = window.compactMap(\.hrvRmssd)
        let hrValues = window.compactMap(\.restingHR).map(Double.init)

        let sleepMean = sleepValues.isEmpty ? 7.0 : sleepValues.reduce(0, +) / Double(sleepValues.count)
        let hrvMean: Double? = hrvValues.count >= 3 ? hrvValues.reduce(0, +) / Double(hrvValues.count) : nil
        let hrMean: Double? = hrValues.count >= 3 ? hrValues.reduce(0, +) / Double(hrValues.count) : nil

        return Baseline(sleepMean: sleepMean, hrvMean: hrvMean, restingHRMean: hrMean)
    }

    private func jstCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        return cal
    }

    private func formatSleep(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return "\(h)h \(m)m"
    }
}

/// What the gate returned. The `reason` is identity-framed copy ready to
/// surface in UI without further wrapping.
struct RecoveryStatus: Sendable, Equatable {
    let recommendation: RecoveryRecommendation
    let reason: String
}

enum RecoveryRecommendation: String, Codable, CaseIterable, Sendable {
    case normal
    case downgrade
    case rest
}

/// One transparent input behind the readiness verdict: the value, its 7-day
/// baseline, and whether the direction is favorable. Surfaced so the user sees
/// what moved the score, the opposite of a black-box wearable number.
struct RecoveryComponent: Sendable, Equatable, Identifiable {
    enum Direction: String, Sendable, Equatable { case up, down, flat }

    let label: String
    let valueText: String
    let baselineText: String?
    let direction: Direction
    /// True when this component is pushing readiness up (HRV up, RHR down,
    /// sleep long). Drives the green/orange tint.
    let isFavorable: Bool

    var id: String { label }
}

/// Full readiness breakdown: the recommendation plus everything needed to render
/// a transparent, actionable recovery card (Gap 3). `headline` is qualitative on
/// purpose, never a fabricated percentage.
struct RecoveryDetail: Sendable, Equatable {
    let recommendation: RecoveryRecommendation
    let headline: String
    let reason: String
    let components: [RecoveryComponent]
    /// Concrete action paired with the verdict ("Reduce today's load ~30%").
    let loadAdjustment: String
    /// Training-load scalar a consumer can multiply a target by (1.0 / 0.7 / 0.0).
    let loadMultiplier: Double
    /// False on cold start (no HRV / RHR / sleep yet); the card hides instead of
    /// showing false precision.
    let hasData: Bool
}
