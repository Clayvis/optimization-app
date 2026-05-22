import XCTest
import HealthKit
import SwiftData
@testable import PersonalOptimization

/// Exercises `HealthKitObserverService` against a `FakeHKObserverBackend`.
/// xctest can't grant HK authorization, so we never touch a real
/// HKHealthStore — the seam lets us prove the registration, idempotency,
/// and update-dispatch wiring without it.
@MainActor
final class HealthKitObserverServiceTests: XCTestCase {

    func test_startObserving_registersAllDefaultTypes() async throws {
        let fake = FakeHKObserverBackend()
        let service = HealthKitObserverService(backend: fake)
        let container = try InMemoryContainer.make()
        await service.startObserving(modelContainer: container)
        XCTAssertEqual(fake.observedTypes.count, HealthKitObserverService.defaultObservedTypes.count)
        XCTAssertTrue(service.isObserving)
        XCTAssertEqual(service.observedTypes.count, HealthKitObserverService.defaultObservedTypes.count)
    }

    func test_startObserving_enablesImmediateBackgroundDelivery() async throws {
        let fake = FakeHKObserverBackend()
        let service = HealthKitObserverService(backend: fake)
        let container = try InMemoryContainer.make()
        await service.startObserving(modelContainer: container)
        XCTAssertEqual(fake.backgroundDeliveryRequests.count, HealthKitObserverService.defaultObservedTypes.count)
        XCTAssertTrue(fake.backgroundDeliveryRequests.allSatisfy { $0.1 == .immediate })
    }

    func test_startObserving_isIdempotent() async throws {
        let fake = FakeHKObserverBackend()
        let service = HealthKitObserverService(backend: fake)
        let container = try InMemoryContainer.make()
        await service.startObserving(modelContainer: container)
        await service.startObserving(modelContainer: container)
        // Second call must not double-register.
        XCTAssertEqual(fake.observedTypes.count, HealthKitObserverService.defaultObservedTypes.count)
        XCTAssertEqual(fake.backgroundDeliveryRequests.count, HealthKitObserverService.defaultObservedTypes.count)
    }

    func test_startObserving_skipsWhenHealthKitUnavailable() async throws {
        let fake = FakeHKObserverBackend()
        fake.isHealthDataAvailable = false
        let service = HealthKitObserverService(backend: fake)
        let container = try InMemoryContainer.make()
        await service.startObserving(modelContainer: container)
        XCTAssertFalse(service.isObserving)
        XCTAssertTrue(fake.observedTypes.isEmpty)
        XCTAssertTrue(fake.backgroundDeliveryRequests.isEmpty)
    }

    func test_observerFire_routesThroughHandleUpdate() async throws {
        let fake = FakeHKObserverBackend()
        let service = HealthKitObserverService(backend: fake)
        let container = try InMemoryContainer.make()
        await service.startObserving(modelContainer: container)

        let exp = expectation(forNotification: .healthKitObserverDidFire, object: nil)
        fake.fireObserver(for: HKQuantityType(.restingHeartRate))
        await fulfillment(of: [exp], timeout: 3)
    }

    func test_stopObserving_disablesBackgroundDeliveryAndStopsAll() async throws {
        let fake = FakeHKObserverBackend()
        let service = HealthKitObserverService(backend: fake)
        let container = try InMemoryContainer.make()
        await service.startObserving(modelContainer: container)
        await service.stopObserving()
        XCTAssertFalse(service.isObserving)
        XCTAssertEqual(fake.disableAllCalls, 1)
        XCTAssertEqual(fake.stopAllCalls, 1)
        XCTAssertTrue(service.observedTypes.isEmpty)
    }

    func test_startObserving_continuesAfterBackgroundDeliveryError() async throws {
        let fake = FakeHKObserverBackend()
        // First enable-call throws; the service should log and proceed with
        // the remaining types rather than aborting the whole registration.
        fake.backgroundDeliveryError = NSError(domain: "test", code: 1)
        let service = HealthKitObserverService(backend: fake)
        let container = try InMemoryContainer.make()
        await service.startObserving(modelContainer: container)
        XCTAssertTrue(service.isObserving)
        XCTAssertEqual(fake.observedTypes.count, HealthKitObserverService.defaultObservedTypes.count)
    }
}
