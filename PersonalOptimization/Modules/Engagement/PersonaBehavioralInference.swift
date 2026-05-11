import Foundation

/// Pure-Swift signal computation for passive persona inference. Value-in, value-out:
/// no I/O, no SwiftData, no Date.init() inside. Tested directly.
///
/// `PersonaService.inferFromBehavior(now:)` fetches the raw records, then
/// calls these helpers to produce `PersonaSignal` proposals the user can accept
/// or dismiss in the TodayView card.
///
/// Each signal must clear a sample-size threshold before being surfaced. Below
/// the threshold we return nil — quiet is better than confidently wrong.
enum PersonaBehavioralInference {

    // MARK: - Public input snapshots

    /// Minimal projection of a completed lift session for peak-alertness inference.
    /// We only need the start hour-of-day in the user's timezone.
    struct LiftStart: Sendable, Equatable {
        let hourOfDay: Int       // 0-23, user-local
    }

    /// One day's recovery-vs-workout snapshot for recovery-sensitivity inference.
    struct RecoveryDay: Sendable, Equatable {
        let hrvRmssd: Double?    // nil = no signal
        let sleepHours: Double?  // nil = no signal
        let trained: Bool        // workout completed on this day
    }

    /// One skip event and what happened the next day for failure-response inference.
    struct SkipDayPair: Sendable, Equatable {
        let trainedNextDay: Bool
        let nextDayDurationMinutes: Int?   // nil if no workout next day
        let typicalDurationMinutes: Int    // baseline for "shorter session" detection
    }

    /// Schedule-suggestion outcome counts for decision-style inference.
    struct SuggestionOutcomes: Sendable, Equatable {
        let accepted: Int
        let dismissed: Int
        let snoozed: Int
        var total: Int { accepted + dismissed + snoozed }
    }

    // MARK: - Public output

    /// A behavior-derived proposal to set or change a single persona field.
    /// The card UI shows `evidence` and `proposedDisplay` to the user; on accept
    /// it writes `proposedRaw` to the field named by `field`.
    struct PersonaSignal: Sendable, Identifiable, Hashable {
        let key: String                  // stable id for dedup ("peakAlertness=morning")
        let field: Field                 // which UserPersona field to update
        let proposedRaw: String          // raw value to store
        let proposedDisplay: String      // short label shown in the card
        let confidence: Int              // 0-100, drives copy + ordering
        let evidence: String             // human-readable rationale shown to user

        var id: String { key }

        enum Field: String, Sendable, Hashable {
            case peakAlertness
            case recoverySensitivity
            case failureResponse
            case decisionStyle
        }
    }

    // MARK: - Peak alertness from lift session start times

    /// Modal hour bucket across recent lifts mapped to a PersonaPeakAlertness.
    /// Requires ≥ 6 sessions and ≥ 40% concentration in the dominant bucket.
    static func inferPeakAlertness(from lifts: [LiftStart]) -> PersonaSignal? {
        guard lifts.count >= 6 else { return nil }

        var bucketCounts: [PersonaPeakAlertness: Int] = [:]
        for lift in lifts {
            bucketCounts[bucket(forHour: lift.hourOfDay), default: 0] += 1
        }

        guard let (top, count) = bucketCounts.max(by: { $0.value < $1.value }) else {
            return nil
        }
        let share = Double(count) / Double(lifts.count)
        guard share >= 0.40 else { return nil }

        let confidence = min(85, Int(share * 100))
        let evidence = "\(count) of your last \(lifts.count) lifts started in the \(top.displayName.lowercased()) window."

        return PersonaSignal(
            key: "peakAlertness=\(top.rawValue)",
            field: .peakAlertness,
            proposedRaw: top.rawValue,
            proposedDisplay: top.displayName,
            confidence: confidence,
            evidence: evidence
        )
    }

    /// Maps an hour-of-day to a `PersonaPeakAlertness` bucket. Matches the
    /// human-facing windows in the enum.
    static func bucket(forHour hour: Int) -> PersonaPeakAlertness {
        switch hour {
        case 5..<7:   return .earlyMorning
        case 7..<11:  return .morning
        case 11..<16: return .afternoon
        case 16..<21: return .evening
        default:      return .lateNight
        }
    }

    // MARK: - Recovery sensitivity from HRV/sleep cross-ref

    /// "Low listener" trains on poor-recovery days. "High listener" skips.
    /// Requires ≥ 10 days with either HRV or sleep signal AND a workout
    /// scheduled (proxy = trained-or-not on that day).
    ///
    /// Method:
    ///   Per-user median split on HRV (or sleep where HRV is missing). Below-
    ///   median = "low recovery". Compute training rate on low-recovery days vs
    ///   above-median days. If low/high split is > 80% → low listener; < 20% →
    ///   high listener; otherwise balanced.
    static func inferRecoverySensitivity(from days: [RecoveryDay]) -> PersonaSignal? {
        let scored: [(Double, Bool)] = days.compactMap { day in
            // Prefer HRV; fall back to sleep when HRV missing. Both nil = drop.
            if let h = day.hrvRmssd { return (h, day.trained) }
            if let s = day.sleepHours { return (s, day.trained) }
            return nil
        }
        guard scored.count >= 10 else { return nil }

        let values = scored.map { $0.0 }
        let median = medianOf(values)

        var lowRecoveryTrained = 0
        var lowRecoveryTotal = 0
        var highRecoveryTrained = 0
        var highRecoveryTotal = 0
        for (value, trained) in scored {
            if value < median {
                lowRecoveryTotal += 1
                if trained { lowRecoveryTrained += 1 }
            } else {
                highRecoveryTotal += 1
                if trained { highRecoveryTrained += 1 }
            }
        }
        // Guard pathological splits (all values identical).
        guard lowRecoveryTotal > 0, highRecoveryTotal > 0 else { return nil }

        let lowRate = Double(lowRecoveryTrained) / Double(lowRecoveryTotal)
        let highRate = Double(highRecoveryTrained) / Double(highRecoveryTotal)

        // Override = trains regardless of recovery. Listener = recovery gates work.
        let gap = highRate - lowRate
        let sensitivity: PersonaRecoverySensitivity
        let confidence: Int
        let evidence: String

        if gap > 0.30 {
            sensitivity = .highListener
            confidence = min(80, 50 + Int(gap * 100))
            evidence = "You trained on \(Int(lowRate * 100))% of low-recovery days vs \(Int(highRate * 100))% of high-recovery days — recovery clearly gates your work."
        } else if gap < -0.10 || lowRate >= 0.85 {
            sensitivity = .lowListener
            confidence = min(80, 50 + Int(abs(gap) * 100) + (lowRate >= 0.85 ? 15 : 0))
            evidence = "You trained on \(Int(lowRate * 100))% of low-recovery days — you tend to push through fatigue."
        } else {
            sensitivity = .balanced
            confidence = 55
            evidence = "Training rate on low-recovery days (\(Int(lowRate * 100))%) is close to high-recovery days (\(Int(highRate * 100))%) — you read it day by day."
        }

        return PersonaSignal(
            key: "recoverySensitivity=\(sensitivity.rawValue)",
            field: .recoverySensitivity,
            proposedRaw: sensitivity.rawValue,
            proposedDisplay: sensitivity.displayName,
            confidence: confidence,
            evidence: evidence
        )
    }

    // MARK: - Failure response from post-skip patterns

    /// What happens the day after a missed workout?
    ///   - Trained at typical duration → pushThrough
    ///   - Trained at < 70% typical duration → recalibrate
    ///   - Did not train → rest
    /// Requires ≥ 3 skip events with next-day data.
    /// `talkItOut` is not behaviorally observable — the user has to declare it.
    static func inferFailureResponse(from pairs: [SkipDayPair]) -> PersonaSignal? {
        guard pairs.count >= 3 else { return nil }

        var pushCount = 0
        var recalibrateCount = 0
        var restCount = 0

        for pair in pairs {
            if !pair.trainedNextDay {
                restCount += 1
                continue
            }
            let typical = max(1, pair.typicalDurationMinutes)
            let actual = pair.nextDayDurationMinutes ?? typical
            if Double(actual) < 0.70 * Double(typical) {
                recalibrateCount += 1
            } else {
                pushCount += 1
            }
        }

        let counts: [(PersonaFailureResponse, Int)] = [
            (.pushThrough, pushCount),
            (.recalibrate, recalibrateCount),
            (.rest, restCount)
        ]
        guard let (top, count) = counts.max(by: { $0.1 < $1.1 }), count > 0 else { return nil }

        let share = Double(count) / Double(pairs.count)
        // Need the dominant mode to be > 50% of skip events. Lower threshold
        // would surface noise from a 1-1-1 split.
        guard share >= 0.50 else { return nil }

        let confidence = min(75, Int(share * 90))
        let evidence = "After \(count) of your last \(pairs.count) missed workouts, you \(verbForFailureResponse(top))."

        return PersonaSignal(
            key: "failureResponse=\(top.rawValue)",
            field: .failureResponse,
            proposedRaw: top.rawValue,
            proposedDisplay: top.displayName,
            confidence: confidence,
            evidence: evidence
        )
    }

    private static func verbForFailureResponse(_ r: PersonaFailureResponse) -> String {
        switch r {
        case .pushThrough:  return "trained anyway the next day"
        case .recalibrate:  return "shortened the next session"
        case .rest:         return "took a second rest day"
        case .talkItOut:    return "paused before deciding"
        }
    }

    // MARK: - Decision style from schedule-suggestion acceptance

    /// Accept-heavy → advice. Dismiss-heavy → data (the user reads the data and
    /// disagrees). Mixed or low-volume → no signal.
    /// Requires ≥ 5 suggestions with status (excluding pending).
    static func inferDecisionStyle(from outcomes: SuggestionOutcomes) -> PersonaSignal? {
        let acted = outcomes.accepted + outcomes.dismissed
        guard acted >= 5 else { return nil }

        let acceptRate = Double(outcomes.accepted) / Double(acted)

        if acceptRate >= 0.70 {
            return PersonaSignal(
                key: "decisionStyle=advice",
                field: .decisionStyle,
                proposedRaw: PersonaDecisionStyle.advice.rawValue,
                proposedDisplay: PersonaDecisionStyle.advice.displayName,
                confidence: min(75, Int(acceptRate * 90)),
                evidence: "You accepted \(outcomes.accepted) of \(acted) recent coach suggestions — you take the call when one is offered."
            )
        }
        if acceptRate <= 0.30 {
            return PersonaSignal(
                key: "decisionStyle=data",
                field: .decisionStyle,
                proposedRaw: PersonaDecisionStyle.data.rawValue,
                proposedDisplay: PersonaDecisionStyle.data.displayName,
                confidence: min(75, Int((1 - acceptRate) * 90)),
                evidence: "You dismissed \(outcomes.dismissed) of \(acted) recent coach suggestions — you read the rationale and make your own call."
            )
        }
        return nil
    }

    // MARK: - Helpers

    private static func medianOf(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let n = sorted.count
        if n == 0 { return 0 }
        if n.isMultiple(of: 2) {
            return (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
        }
        return sorted[n / 2]
    }
}
