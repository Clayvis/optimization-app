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
         timezone: TimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current) {
        self.modelContext = modelContext
        self.timezone = timezone
    }

    /// Evaluates today's recovery and returns a recommendation + reason.
    /// Pure read; does not mutate state.
    func evaluate(profile: UserProfile, asOf date: Date = Date()) -> RecoveryStatus {
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

        // Hard rest-day rules — any one trips it.
        if hrvDelta < -0.30 {
            return RecoveryStatus(recommendation: .rest,
                                  reason: "HRV is \(Int((-hrvDelta) * 100))% below your 7-day baseline.")
        }
        if sleepHours > 0 && sleepHours < 4.5 {
            return RecoveryStatus(recommendation: .rest,
                                  reason: "Sleep last night was \(formatSleep(sleepHours)). Below the 4.5h floor.")
        }
        if achillesPain >= 7 {
            return RecoveryStatus(recommendation: .rest,
                                  reason: "Achilles pain logged at \(achillesPain)/10. The injury talks; listen.")
        }

        // Downgrade rules — any one trips it (after rest rules above).
        if hrvDelta < -0.20 {
            return RecoveryStatus(recommendation: .downgrade,
                                  reason: "HRV trending \(Int((-hrvDelta) * 100))% below baseline.")
        }
        if sleepHours > 0 && sleepHours < 5.5 {
            return RecoveryStatus(recommendation: .downgrade,
                                  reason: "Sleep last night was \(formatSleep(sleepHours)).")
        }
        if restingHRDelta > 0.10 {
            return RecoveryStatus(recommendation: .downgrade,
                                  reason: "Resting HR is \(Int(restingHRDelta * 100))% above baseline.")
        }
        if achillesPain >= 5 {
            return RecoveryStatus(recommendation: .downgrade,
                                  reason: "Achilles pain at \(achillesPain)/10 — keep the load light.")
        }

        return RecoveryStatus(recommendation: .normal,
                              reason: "Recovery markers within range.")
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
        try? modelContext.save()
    }

    // MARK: - Helpers

    private func todaysLog(asOf date: Date) -> DailyLog? {
        let cal = jstCalendar()
        let day = cal.startOfDay(for: date)
        let descriptor = FetchDescriptor<DailyLog>(
            predicate: #Predicate<DailyLog> { $0.date == day }
        )
        return (try? modelContext.fetch(descriptor))?.first
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
        let all = (try? modelContext.fetch(descriptor)) ?? []
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
