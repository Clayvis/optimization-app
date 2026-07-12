import Foundation
import HealthKit
import SwiftData
import os

/// Backend abstraction over HKHealthStore. Tests inject `FakeHKObserverBackend`
/// so `HealthKitObserverService` can be exercised end-to-end without a real
/// HK store (xctest can't grant HK auth and would silently no-op).
@MainActor
protocol HKObserverBackend: AnyObject {
    var isHealthDataAvailable: Bool { get }
    func enableBackgroundDelivery(for type: HKSampleType, frequency: HKUpdateFrequency) async throws
    func disableAllBackgroundDelivery() async throws
    /// Registers an observer for the given sample type. Returns a token so
    /// the caller can stop a specific observer later. The handler is invoked
    /// every time HealthKit detects new samples of `type`.
    @discardableResult
    func startObserver(for type: HKSampleType, handler: @escaping @MainActor () -> Void) -> UUID
    func stopAllObservers()
}

/// Live wrapper around `HKHealthStore`. The observer-query callback may be
/// invoked off the main actor; we hop back before calling the handler so
/// the service's MainActor contract is preserved.
@MainActor
final class LiveHKObserverBackend: HKObserverBackend {
    private let store = HKHealthStore()
    private var queries: [UUID: HKObserverQuery] = [:]
    private let logger = Logger.healthkit

    var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func enableBackgroundDelivery(for type: HKSampleType, frequency: HKUpdateFrequency) async throws {
        try await store.enableBackgroundDelivery(for: type, frequency: frequency)
    }

    func disableAllBackgroundDelivery() async throws {
        try await store.disableAllBackgroundDelivery()
    }

    @discardableResult
    func startObserver(for type: HKSampleType, handler: @escaping @MainActor () -> Void) -> UUID {
        let token = UUID()
        let logger = self.logger
        let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completionHandler, error in
            defer { completionHandler() }
            if let error {
                logger.warning("HKObserverQuery for \(type.identifier, privacy: .public) error: \(error.localizedDescription, privacy: .public)")
                return
            }
            Task { @MainActor in handler() }
        }
        store.execute(query)
        queries[token] = query
        return token
    }

    func stopAllObservers() {
        for (_, query) in queries { store.stop(query) }
        queries.removeAll()
    }
}

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

    private let backend: HKObserverBackend
    private(set) var observedTypes: Set<String> = []
    private var modelContainer: ModelContainer?
    private let logger = Logger.healthkit
    private(set) var isObserving: Bool = false
    private let skipsDataSync: Bool

    /// The default initializer wires the live backend and performs data syncs.
    /// Observer-routing tests can inject a fake backend and skip the separate
    /// HealthKit query pipeline so they remain deterministic in XCTest.
    init(
        backend: HKObserverBackend = LiveHKObserverBackend(),
        skipsDataSync: Bool = false
    ) {
        self.backend = backend
        self.skipsDataSync = skipsDataSync
    }

    /// Sample types we observe with the full 7-day resync + workout import.
    /// Exposed for tests so they can assert without mirroring the constant.
    static var defaultObservedTypes: [HKSampleType] {
        [
            HKQuantityType(.bodyMass),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKCategoryType(.sleepAnalysis),
            HKCategoryType(.mindfulSession),
            HKObjectType.workoutType()
        ]
    }

    /// High-frequency activity types (the Apple Fitness Move/Exercise inputs).
    /// These fire constantly during movement, so they get a debounced
    /// today-only sync instead of the heavy 7-day resync. Without them the
    /// Move number only refreshed at launch and pull-to-refresh.
    static var fastObservedTypes: [HKSampleType] {
        [
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.appleExerciseTime),
            HKQuantityType(.stepCount)
        ]
    }

    /// Every type registered with the backend (heavy + fast paths).
    static var allObservedTypes: [HKSampleType] {
        defaultObservedTypes + fastObservedTypes
    }

    /// Minimum spacing between fast-path syncs. Active energy can fire every
    /// few seconds during a workout; one today-sync per interval is plenty.
    static let fastSyncDebounce: TimeInterval = 60
    private var lastFastSyncAt: Date?

    /// Begin observing the high-signal HK sample types. Safe to call repeatedly;
    /// no-op if already observing.
    func startObserving(modelContainer: ModelContainer) async {
        guard backend.isHealthDataAvailable else { return }
        guard !isObserving else { return }
        self.modelContainer = modelContainer

        for type in Self.defaultObservedTypes {
            do {
                try await backend.enableBackgroundDelivery(for: type, frequency: .immediate)
            } catch {
                logger.warning("enableBackgroundDelivery failed for \(type.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }

            backend.startObserver(for: type) { [weak self] in
                Task { @MainActor in
                    await self?.handleUpdate()
                }
            }
            observedTypes.insert(type.identifier)
        }

        for type in Self.fastObservedTypes {
            do {
                try await backend.enableBackgroundDelivery(for: type, frequency: .immediate)
            } catch {
                logger.warning("enableBackgroundDelivery failed for \(type.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }

            backend.startObserver(for: type) { [weak self] in
                Task { @MainActor in
                    await self?.handleFastUpdate()
                }
            }
            observedTypes.insert(type.identifier)
        }

        isObserving = true
        logger.info("HKObserverService started for \(self.observedTypes.count, privacy: .public) sample types.")
    }

    /// Stop observing and tear down background delivery. Used by tests; not
    /// invoked in the normal app lifecycle.
    func stopObserving() async {
        backend.stopAllObservers()
        observedTypes.removeAll()
        do {
            try await backend.disableAllBackgroundDelivery()
        } catch {
            logger.warning("disableAllBackgroundDelivery failed: \(error.localizedDescription, privacy: .public)")
        }
        isObserving = false
    }

    /// Fast path for Move/Exercise/steps: refresh today's DailyLog only,
    /// debounced. No 7-day range walk, no workout import; the heavy types
    /// keep covering those.
    private func handleFastUpdate() async {
        guard let container = modelContainer else { return }
        if let last = lastFastSyncAt, Date().timeIntervalSince(last) < Self.fastSyncDebounce {
            return
        }
        lastFastSyncAt = Date()
        if !skipsDataSync {
            await HealthKitSyncService(modelContext: container.mainContext).refreshToday()
        }
        NotificationCenter.default.post(name: .healthKitObserverDidFire, object: nil)
    }

    private func handleUpdate() async {
        guard let container = modelContainer else { return }
        if !skipsDataSync {
            let context = container.mainContext
            let sync = HealthKitSyncService(modelContext: context)
            // 7 day window covers Garmin's typical late-upload behavior plus
            // weekend / travel gaps.
            await sync.syncRange(days: 7)
            // Import any workouts the Watch or a third-party app recorded so the
            // app realizes the user trained without them opening it and starting a
            // manual timer. Deduped by HealthKit UUID, so it is safe on every fire.
            await importRecentWorkouts(modelContext: context)
        }
        // Test hook: fire a notification so tests can assert the observer
        // path reached the sync layer without depending on SwiftData state.
        NotificationCenter.default.post(name: .healthKitObserverDidFire, object: nil)
    }

    /// Pull the last 7 days of HKWorkout samples and import any not already in
    /// the ledger. No-op when HealthKit is unauthorized (fetch returns empty).
    private func importRecentWorkouts(modelContext: ModelContext) async {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -7, to: end) ?? end
        do {
            let workouts = try await LiveHealthKitService.shared
                .fetchWorkouts(in: DateInterval(start: start, end: end))
            let imported = workouts.compactMap { ImportedWorkout(hkWorkout: $0) }
            let count = try WorkoutImportService.forUser(modelContext: modelContext)
                .importWorkouts(imported)
            if count > 0 {
                // Rederive streaks + character state now that new workouts landed.
                NotificationCenter.default.post(name: .dailyLogsRecomputed, object: nil)
            }
        } catch {
            logger.warning("Workout import failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension Notification.Name {
    /// Posted after `HealthKitObserverService` finishes a syncRange call
    /// in response to an HK observer fire. Used by `HealthKitObserverServiceTests`
    /// to verify the observer wiring without depending on SwiftData state.
    static let healthKitObserverDidFire = Notification.Name("HealthKitObserverDidFire")
}

#if DEBUG
/// In-memory observer backend for tests. Records calls and lets the test
/// fire observers synthetically via `fireObserver(for:)`.
@MainActor
final class FakeHKObserverBackend: HKObserverBackend {
    var isHealthDataAvailable: Bool = true
    var backgroundDeliveryRequests: [(HKSampleType, HKUpdateFrequency)] = []
    var backgroundDeliveryError: Error?
    var disableAllCalls: Int = 0
    private(set) var observedTypes: [HKSampleType] = []
    private var handlers: [(typeID: String, token: UUID, handler: @MainActor () -> Void)] = []
    var stopAllCalls: Int = 0

    func enableBackgroundDelivery(for type: HKSampleType, frequency: HKUpdateFrequency) async throws {
        backgroundDeliveryRequests.append((type, frequency))
        if let error = backgroundDeliveryError {
            backgroundDeliveryError = nil
            throw error
        }
    }

    func disableAllBackgroundDelivery() async throws {
        disableAllCalls += 1
    }

    @discardableResult
    func startObserver(for type: HKSampleType, handler: @escaping @MainActor () -> Void) -> UUID {
        let token = UUID()
        observedTypes.append(type)
        handlers.append((typeID: type.identifier, token: token, handler: handler))
        return token
    }

    func stopAllObservers() {
        stopAllCalls += 1
        handlers.removeAll()
    }

    /// Synthetic observer fire. Triggers every handler registered for the
    /// matching sample-type identifier.
    func fireObserver(for type: HKSampleType) {
        for entry in handlers where entry.typeID == type.identifier {
            entry.handler()
        }
    }
}
#endif
