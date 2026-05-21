import Foundation
import HealthKit
import Observation
import os

/// Live workout session driver for the watch. Wraps `HKWorkoutSession` +
/// `HKLiveWorkoutBuilder` to surface live HR, elapsed time, and active
/// calories as `@Observable` state the watch session views render directly.
///
/// Battery posture: the builder's data source uses Apple's optimized power
/// profile; we don't run anchored queries on top of it. State updates come
/// through the builder's delegate at the cadence the system picks (typically
/// 1Hz for workout-relevant samples). When the session ends we hand the
/// summary off to whichever Swift module owns the typed session row (Lift /
/// Basketball / Swim / Custom) so it can write the SwiftData record + the
/// shared workout ledger.
#if os(watchOS)
@Observable
@MainActor
final class LiveWorkoutSessionService: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    static let shared = LiveWorkoutSessionService()

    private(set) var isActive: Bool = false
    private(set) var activityType: HKWorkoutActivityType = .other
    private(set) var heartRate: Double = 0           // bpm, latest sample
    private(set) var activeCaloriesKcal: Double = 0  // running total since session start
    private(set) var distanceMeters: Double = 0      // for swim/run/walk activities
    private(set) var elapsedSeconds: TimeInterval = 0
    private(set) var startedAt: Date?

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var elapsedTimer: Timer?
    private let logger = Logger(subsystem: BuildConfig.loggingSubsystem, category: "live-workout")

    private override init() { super.init() }

    /// Begins a live workout session. Throws if HK is unavailable or
    /// configuration fails. The caller is responsible for surfacing this in UI.
    func start(activityType: HKWorkoutActivityType,
               locationType: HKWorkoutSessionLocationType = .indoor) throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.dataNotAvailable
        }
        // Stop any prior session first so re-entering this from a hot view
        // can't accumulate observers.
        stopInternal()

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType
        configuration.locationType = locationType
        if activityType == .swimming {
            configuration.swimmingLocationType = .pool
            configuration.lapLength = HKQuantity(unit: .meter(), doubleValue: 25)
        }

        let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
        session.delegate = self
        builder.delegate = self

        let now = Date()
        session.startActivity(with: now)
        builder.beginCollection(withStart: now) { [weak self] success, error in
            if let error {
                Task { @MainActor in
                    self?.logger.error("beginCollection failed: \(error.localizedDescription, privacy: .public)")
                }
            } else if !success {
                Task { @MainActor in
                    self?.logger.warning("beginCollection returned false")
                }
            }
        }

        self.session = session
        self.builder = builder
        self.activityType = activityType
        self.startedAt = now
        self.isActive = true
        self.heartRate = 0
        self.activeCaloriesKcal = 0
        self.distanceMeters = 0
        self.elapsedSeconds = 0
        startElapsedTicker()

        logger.info("Live session started type=\(activityType.rawValue, privacy: .public)")
    }

    /// Ends the active session. Returns a summary so the typed-session module
    /// can write its SwiftData row with the live numbers. No-op when nothing
    /// is active.
    @discardableResult
    func end() async -> LiveSessionSummary? {
        guard let session, let builder, let startedAt else { return nil }
        let endedAt = Date()
        session.end()

        do {
            try await builder.endCollection(at: endedAt)
            try await builder.finishWorkout()
        } catch {
            logger.warning("Workout finalize failed: \(error.localizedDescription, privacy: .public)")
        }

        let summary = LiveSessionSummary(
            activityType: activityType,
            start: startedAt,
            end: endedAt,
            durationMinutes: Int(endedAt.timeIntervalSince(startedAt) / 60),
            avgHeartRate: heartRate > 0 ? Int(heartRate) : nil,
            activeCaloriesKcal: activeCaloriesKcal > 0 ? activeCaloriesKcal : nil,
            distanceMeters: distanceMeters > 0 ? distanceMeters : nil
        )
        stopInternal()
        return summary
    }

    /// Internal teardown. Resets observable state so a subsequent `start`
    /// renders clean.
    private func stopInternal() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        session = nil
        builder = nil
        isActive = false
        startedAt = nil
        elapsedSeconds = 0
    }

    /// 1Hz UI ticker for elapsed time. Cheaper than asking the builder for a
    /// timestamp — Apple's WorkoutKit examples use a Timer for elapsed display.
    private func startElapsedTicker() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let started = self.startedAt else { return }
                self.elapsedSeconds = Date().timeIntervalSince(started)
            }
        }
    }

    // MARK: - HKWorkoutSessionDelegate

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState,
                                    date: Date) {
        Task { @MainActor in
            self.logger.info("Session state \(fromState.rawValue, privacy: .public) -> \(toState.rawValue, privacy: .public)")
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.logger.error("Session failed: \(error.localizedDescription, privacy: .public)")
            self.stopInternal()
        }
    }

    // MARK: - HKLiveWorkoutBuilderDelegate

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                                    didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType,
                  let stats = workoutBuilder.statistics(for: quantityType) else { continue }
            Task { @MainActor in
                self.handleStatistics(quantityType: quantityType, stats: stats)
            }
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // No-op: events are pause/resume markers; we don't surface them yet.
    }

    private func handleStatistics(quantityType: HKQuantityType, stats: HKStatistics) {
        if quantityType == HKQuantityType(.heartRate) {
            if let hr = stats.mostRecentQuantity()?.doubleValue(for: HKUnit(from: "count/min")) {
                heartRate = hr
            }
        } else if quantityType == HKQuantityType(.activeEnergyBurned) {
            if let kcal = stats.sumQuantity()?.doubleValue(for: .kilocalorie()) {
                activeCaloriesKcal = kcal
            }
        } else if quantityType == HKQuantityType(.distanceWalkingRunning)
                || quantityType == HKQuantityType(.distanceCycling)
                || quantityType == HKQuantityType(.distanceSwimming) {
            if let m = stats.sumQuantity()?.doubleValue(for: .meter()) {
                distanceMeters = m
            }
        }
    }
}

/// What `LiveWorkoutSessionService.end()` returns to the caller. Plain value
/// type so it can cross the watch ↔ SwiftData boundary cleanly and be used in
/// tests without HK at all.
struct LiveSessionSummary: Sendable {
    let activityType: HKWorkoutActivityType
    let start: Date
    let end: Date
    let durationMinutes: Int
    let avgHeartRate: Int?
    let activeCaloriesKcal: Double?
    let distanceMeters: Double?
}
#endif
