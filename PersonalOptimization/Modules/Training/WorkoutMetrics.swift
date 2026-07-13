import Foundation
import HealthKit
import Observation
import os

/// Pure workout math + HealthKit mappings shared by the Training surfaces.
/// No UI, no persistence: everything here is deterministic and unit-testable.
enum WorkoutMetrics {

    /// Known activity shapes the app starts from the Training hub.
    enum Activity: String, CaseIterable, Sendable {
        case lift
        case basketball
        case swim
        case custom
    }

    // MARK: - Calories

    /// MET-based calorie estimate: kcal/min = MET × 3.5 × kg / 200.
    /// Used only when HealthKit has no measured active energy for the
    /// session window (phone-only sessions with no watch worn).
    static func estimatedKcal(met: Double, weightLbs: Double, minutes: Double) -> Double {
        guard met > 0, weightLbs > 0, minutes > 0 else { return 0 }
        let kg = weightLbs * 0.45359237
        return met * 3.5 * kg / 200.0 * minutes
    }

    /// Compendium-of-Physical-Activities MET values for the built-in
    /// disciplines. Deliberately mid-range: estimates should undersell,
    /// never flatter.
    static func met(for activity: Activity) -> Double {
        switch activity {
        case .lift:       return 5.0   // resistance training, general
        case .basketball: return 6.5   // game play, non-competitive
        case .swim:       return 7.0   // laps, moderate
        case .custom:     return 5.0   // caller should prefer met(forTemplateNamed:)
        }
    }

    /// MET lookup for user-defined activities by template name keyword.
    /// Falls back to a moderate 5.0 when nothing matches.
    static func met(forTemplateNamed name: String) -> Double {
        let n = name.lowercased()
        if n.contains("run") { return 9.0 }
        if n.contains("walk") { return 3.5 }
        if n.contains("hiit") { return 8.0 }
        if n.contains("yoga") { return 3.0 }
        if n.contains("cycl") || n.contains("bike") { return 7.5 }
        if n.contains("hik") { return 6.0 }
        if n.contains("ruck") { return 6.5 }
        if n.contains("swim") { return 7.0 }
        if n.contains("row") { return 7.0 }
        return 5.0
    }

    // MARK: - HealthKit mappings

    /// Workout activity type for a user-defined template, matched on name.
    static func hkActivityType(forTemplateNamed name: String) -> HKWorkoutActivityType {
        let n = name.lowercased()
        if n.contains("run") { return .running }
        if n.contains("walk") { return .walking }
        if n.contains("hiit") { return .highIntensityIntervalTraining }
        if n.contains("yoga") { return .yoga }
        if n.contains("cycl") || n.contains("bike") { return .cycling }
        if n.contains("hik") || n.contains("ruck") { return .hiking }
        if n.contains("swim") { return .swimming }
        if n.contains("row") { return .rowing }
        return .other
    }

    /// The distance sample type that matches an activity, nil when distance
    /// is meaningless for it (lifting). Keeping this total prevents the
    /// "basketball miles logged as swim meters" class of bug.
    static func distanceIdentifier(for activityType: HKWorkoutActivityType) -> HKQuantityTypeIdentifier? {
        switch activityType {
        case .swimming:
            return .distanceSwimming
        case .cycling:
            return .distanceCycling
        case .traditionalStrengthTraining, .functionalStrengthTraining, .yoga:
            return nil
        default:
            return .distanceWalkingRunning
        }
    }

    // MARK: - Formatting

    /// One-line session recap: "42 min · 310 kcal · 2.1 mi". Segments with
    /// no data are dropped; returns nil when nothing is worth showing.
    static func recapLine(durationMinutes: Int?, kcal: Double?, distanceMeters: Double?) -> String? {
        var parts: [String] = []
        if let minutes = durationMinutes, minutes > 0 {
            parts.append("\(minutes) min")
        }
        if let kcal, kcal >= 1 {
            parts.append("\(Int(kcal.rounded())) kcal")
        }
        if let meters = distanceMeters, meters > 0 {
            parts.append(milesText(meters: meters))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Meters → miles, one decimal ("2.1 mi"). Sub-0.05 mi distances read
    /// as noise and are shown in yards instead.
    static func milesText(meters: Double) -> String {
        let miles = meters / 1609.344
        if miles < 0.05 {
            let yards = meters * 1.0936133
            return "\(Int(yards.rounded())) yd"
        }
        return String(format: "%.1f mi", miles)
    }
}

// MARK: - Last-workout recap

/// Compact summary of a completed HealthKit workout, used on the Training
/// hub tiles ("last: 42 min · 310 kcal · 2.1 mi").
struct WorkoutRecap: Sendable {
    let endDate: Date
    let durationMinutes: Int
    let kcal: Double?
    let distanceMeters: Double?

    var line: String? {
        WorkoutMetrics.recapLine(durationMinutes: durationMinutes, kcal: kcal, distanceMeters: distanceMeters)
    }

    /// Extracts the recap from an `HKWorkout` using the statistics API
    /// (the `totalEnergyBurned` / `totalDistance` properties are deprecated).
    static func from(workout: HKWorkout) -> WorkoutRecap {
        let kcal = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?
            .doubleValue(for: .kilocalorie())

        var distance: Double?
        for identifier: HKQuantityTypeIdentifier in [.distanceWalkingRunning, .distanceSwimming, .distanceCycling] {
            if let meters = workout.statistics(for: HKQuantityType(identifier))?
                .sumQuantity()?
                .doubleValue(for: .meter()), meters > 0 {
                distance = meters
                break
            }
        }

        return WorkoutRecap(
            endDate: workout.endDate,
            durationMinutes: Int((workout.duration / 60).rounded()),
            kcal: kcal,
            distanceMeters: distance
        )
    }
}

// MARK: - Live in-session metrics

/// Polls HealthKit for the metrics accumulated since a session started:
/// active energy, activity-appropriate distance, and the latest heart rate.
/// Watch-worn sessions surface real sensor data; phone-only sessions surface
/// whatever the phone recorded (steps-derived distance, usually no energy).
///
/// The session views own one instance for the life of an active session and
/// read `activeKcal` / `distanceMeters` / `heartRateBPM` reactively.
@Observable
@MainActor
final class LiveWorkoutMetrics {
    private(set) var activeKcal: Double?
    private(set) var distanceMeters: Double?
    private(set) var heartRateBPM: Double?
    private(set) var lastUpdatedAt: Date?

    private let healthKit: HealthKitServiceProtocol?
    private let sessionStart: Date
    private let distanceIdentifier: HKQuantityTypeIdentifier?
    private var pollTask: Task<Void, Never>?
    private let pollInterval: Duration

    /// True when at least one metric has real data — the views hide the
    /// HealthKit strip entirely until then instead of rendering placeholders.
    var hasAnyData: Bool {
        activeKcal != nil || distanceMeters != nil || heartRateBPM != nil
    }

    init(healthKit: HealthKitServiceProtocol?,
         sessionStart: Date,
         activityType: HKWorkoutActivityType,
         pollInterval: Duration = .seconds(20)) {
        self.healthKit = healthKit
        self.sessionStart = sessionStart
        self.distanceIdentifier = WorkoutMetrics.distanceIdentifier(for: activityType)
        self.pollInterval = pollInterval
    }

    /// Starts the poll loop. Idempotent; safe to call from `.task`.
    func begin() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshOnce()
                guard let interval = self?.pollInterval else { return }
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return // cancelled
                }
            }
        }
    }

    func end() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// One fetch pass over the session window. Failures are logged and the
    /// prior values are kept: transient HealthKit errors must never blank an
    /// on-screen metric mid-workout.
    func refreshOnce() async {
        guard let healthKit else { return }
        let interval = DateInterval(start: sessionStart, end: Date())
        guard interval.duration > 0 else { return }

        do {
            if let kcal = try await healthKit.fetchSumQuantity(
                .activeEnergyBurned, unit: .kilocalorie(), in: interval
            ) {
                activeKcal = kcal
            }
            if let distanceIdentifier,
               let meters = try await healthKit.fetchSumQuantity(
                   distanceIdentifier, unit: .meter(), in: interval
               ) {
                distanceMeters = meters
            }
            if let bpm = try await healthKit.fetchLatestQuantity(
                .heartRate, unit: HKUnit.count().unitDivided(by: .minute()), in: interval
            ) {
                heartRateBPM = bpm
            }
            lastUpdatedAt = Date()
        } catch {
            Logger.healthkit.info("Live workout metrics fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Best available calorie figure for closing out the session: measured
    /// active energy when HealthKit has it, MET estimate from body weight
    /// otherwise. Returns nil when neither source can produce a number.
    func closingKcal(met: Double, weightLbs: Double?, elapsedMinutes: Double) -> Double? {
        if let measured = activeKcal, measured >= 1 { return measured }
        guard let weightLbs, weightLbs > 0 else { return nil }
        let estimate = WorkoutMetrics.estimatedKcal(met: met, weightLbs: weightLbs, minutes: elapsedMinutes)
        return estimate >= 1 ? estimate : nil
    }
}
