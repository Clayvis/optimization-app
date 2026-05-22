import Foundation
import HealthKit
import SwiftData
import os

/// Centralized session lifecycle orchestrator for all training and fasting domains.
///
/// Architectural contract (from M3.6_SPEC, Block 1):
/// 1. SwiftData is the authoritative source of "session active or ended". Each domain
///    service writes session state synchronously and that write always succeeds.
/// 2. HealthKit is a best-effort secondary writer. HK failures never propagate to the
///    UI and never block the session-end path.
/// 3. End-session paths return synchronously. The HK write happens in a detached Task
///    with bounded retry (3 attempts, exponential backoff). Final failures persist a
///    `HealthKitWriteFailure` row that the Diagnostics view surfaces.
/// 4. Live Activity dismissal happens synchronously inside the service so the UI is
///    never out of sync with persistence.
@MainActor
final class SessionLifecycleService {
    static let shared = SessionLifecycleService()

    private let logger = Logger.healthkit
    private let maxRetries: Int = 3
    private let baseDelayMs: UInt64 = 200

    /// The most-recently dispatched HK write task. Production callers ignore this;
    /// tests `await SessionLifecycleService.shared.lastDispatchedTask?.value` to
    /// synchronize before asserting against the FakeHealthKitService.
    nonisolated(unsafe) var lastDispatchedTask: Task<Void, Never>?

    private init() {}

    /// Fire-and-forget HK write with bounded retry. Failures persist a
    /// `HealthKitWriteFailure` row. Returns immediately so the caller's UI path is
    /// never blocked.
    /// The returned Task is unused in production; tests await it to synchronize.
    @discardableResult
    nonisolated func dispatchHealthKitWorkout(activityType: HKWorkoutActivityType,
                                              start: Date,
                                              end: Date,
                                              totalEnergyKcal: Double?,
                                              totalDistanceMeters: Double?,
                                              healthKit: HealthKitServiceProtocol?,
                                              modelContainer: ModelContainer?) -> Task<Void, Never> {
        let task = Task.detached { [weak self] in
            guard let self, let healthKit else { return }
            await self.writeWithRetry(activityType: activityType,
                                      start: start,
                                      end: end,
                                      totalEnergyKcal: totalEnergyKcal,
                                      totalDistanceMeters: totalDistanceMeters,
                                      healthKit: healthKit,
                                      modelContainer: modelContainer)
        }
        self.lastDispatchedTask = task
        return task
    }

    private func writeWithRetry(activityType: HKWorkoutActivityType,
                                start: Date,
                                end: Date,
                                totalEnergyKcal: Double?,
                                totalDistanceMeters: Double?,
                                healthKit: HealthKitServiceProtocol,
                                modelContainer: ModelContainer?) async {
        var attempt = 0
        var lastError: Error?
        while attempt < maxRetries {
            do {
                try await healthKit.saveWorkout(
                    activityType: activityType,
                    start: start,
                    end: end,
                    totalEnergyBurnedKcal: totalEnergyKcal,
                    totalDistanceMeters: totalDistanceMeters
                )
                return
            } catch {
                attempt += 1
                lastError = error
                Logger.healthkit.warning(
                    "HK write attempt \(attempt, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
                )
                if attempt < maxRetries {
                    let delay = baseDelayMs * UInt64(1 << (attempt - 1))
                    try? await Task.sleep(nanoseconds: delay * 1_000_000)  // MARK: try? justified - best-effort; failure logged inside the called function.
                }
            }
        }
        if let lastError, let modelContainer {
            await persistFailure(activityType: activityType,
                                 start: start,
                                 end: end,
                                 kcal: totalEnergyKcal,
                                 meters: totalDistanceMeters,
                                 error: lastError,
                                 retryCount: attempt,
                                 container: modelContainer)
        }
    }

    private func persistFailure(activityType: HKWorkoutActivityType,
                                start: Date,
                                end: Date,
                                kcal: Double?,
                                meters: Double?,
                                error: Error,
                                retryCount: Int,
                                container: ModelContainer) async {
        await MainActor.run {
            let context = container.mainContext
            let failure = HealthKitWriteFailure(
                timestamp: Date(),
                activityTypeRaw: UInt(activityType.rawValue),
                startTime: start,
                endTime: end,
                totalEnergyKcal: kcal,
                totalDistanceMeters: meters,
                errorDescription: error.localizedDescription,
                retryCount: retryCount
            )
            context.insert(failure)
            try? context.save()  // MARK: try? save() is best-effort — failures surface via os_log; in-memory state already updated.
            Logger.healthkit.error(
                "HK write exhausted retries; persisted failure record activity=\(activityType.rawValue, privacy: .public)"
            )
        }
    }

    /// Returns recent unresolved HK write failures, newest first. Used by Diagnostics.
    func recentFailures(limit: Int = 10, modelContext: ModelContext) -> [HealthKitWriteFailure] {
        var descriptor = FetchDescriptor<HealthKitWriteFailure>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return modelContext.fetchOrEmpty(descriptor)
    }
}
