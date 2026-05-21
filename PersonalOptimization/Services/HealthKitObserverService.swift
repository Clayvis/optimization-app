import Foundation
import HealthKit
import SwiftData
import os

/// Wires HealthKit background delivery and observer queries so the app reacts
/// to new samples (live or late-arriving) without the user opening the app.
///
/// Why this is critical: the entitlement
/// `com.apple.developer.healthkit.background-delivery` is on, but without
/// the matching `enableBackgroundDelivery` + `HKObserverQuery` plumbing, the
/// app only updates when the user foregrounds it. Streak counters and
/// character state silently lag whatever Garmin/Withings/Watch finishes
/// uploading later.
@MainActor
final class HealthKitObserverService {
    static let shared = HealthKitObserverService()

    private let store = HKHealthStore()
    private var queries: [HKObserverQuery] = []
    private var modelContainer: ModelContainer?
    private let logger = Logger.healthkit
    private var isObserving: Bool = false

    private init() {}

    /// Begin observing the high-signal HK sample types. Safe to call repeatedly;
    /// no-op if already observing.
    func startObserving(modelContainer: ModelContainer) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard !isObserving else { return }
        self.modelContainer = modelContainer

        let types: [HKSampleType] = [
            HKQuantityType(.bodyMass),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKCategoryType(.sleepAnalysis),
            HKCategoryType(.mindfulSession),
            HKObjectType.workoutType()
        ]

        for type in types {
            do {
                try await store.enableBackgroundDelivery(for: type, frequency: .immediate)
            } catch {
                logger.warning("enableBackgroundDelivery failed for \(type.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }

            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completionHandler, error in
                // Call the completion synchronously to satisfy HK's contract;
                // schedule the actual work on the main actor without sharing
                // the completion handler across actor boundaries (Swift 6
                // strict concurrency does not allow that send).
                defer { completionHandler() }
                guard let self else { return }
                if let error {
                    self.logger.warning("HKObserverQuery for \(type.identifier, privacy: .public) error: \(error.localizedDescription, privacy: .public)")
                    return
                }
                Task { @MainActor in
                    await self.handleUpdate()
                }
            }
            store.execute(query)
            queries.append(query)
        }

        isObserving = true
        logger.info("HKObserverService started for \(self.queries.count, privacy: .public) sample types.")
    }

    /// Stop observing and tear down background delivery. Used by tests; not
    /// invoked in the normal app lifecycle.
    func stopObserving() async {
        for q in queries { store.stop(q) }
        queries.removeAll()
        do {
            try await store.disableAllBackgroundDelivery()
        } catch {
            logger.warning("disableAllBackgroundDelivery failed: \(error.localizedDescription, privacy: .public)")
        }
        isObserving = false
    }

    private func handleUpdate() async {
        guard let container = modelContainer else { return }
        let sync = HealthKitSyncService(modelContext: container.mainContext)
        // 7 day window covers Garmin's typical late-upload behavior plus
        // weekend / travel gaps.
        await sync.syncRange(days: 7)
    }
}
