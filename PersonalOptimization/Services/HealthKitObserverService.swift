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

    /// The default initializer wires the live backend. Tests use
    /// `init(backend: FakeHKObserverBackend())` to control the
    /// observer/background-delivery surface without touching HK.
    init(backend: HKObserverBackend = LiveHKObserverBackend()) {
        self.backend = backend
    }

    /// Sample types we observe. Exposed for tests so they can assert
    /// without mirroring the constant.
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

    private func handleUpdate() async {
        guard let container = modelContainer else { return }
        let sync = HealthKitSyncService(modelContext: container.mainContext)
        // 7 day window covers Garmin's typical late-upload behavior plus
        // weekend / travel gaps.
        await sync.syncRange(days: 7)
        // Test hook: fire a notification so tests can assert the observer
        // path reached the sync layer without depending on SwiftData state.
        NotificationCenter.default.post(name: .healthKitObserverDidFire, object: nil)
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
