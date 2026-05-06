import XCTest
import HealthKit
@testable import PersonalOptimization

/// In-memory test double per TESTING.md (no third-party mocking framework).
final class FakeHealthKitService: HealthKitServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _authorizationCallCount = 0
    private var _savedWorkouts: [(HKWorkoutActivityType, Date, Date, Double?, Double?)] = []
    private var _grantAuthorization = true

    var authorizationCallCount: Int {
        lock.withLock { _authorizationCallCount }
    }
    var savedWorkouts: [(HKWorkoutActivityType, Date, Date, Double?, Double?)] {
        lock.withLock { _savedWorkouts }
    }
    func setGrantAuthorization(_ value: Bool) {
        lock.withLock { _grantAuthorization = value }
    }

    func requestAuthorization() async throws -> Bool {
        lock.withLock {
            _authorizationCallCount += 1
            return _grantAuthorization
        }
    }

    func saveWorkout(activityType: HKWorkoutActivityType,
                     start: Date,
                     end: Date,
                     totalEnergyBurnedKcal: Double?,
                     totalDistanceMeters: Double?) async throws {
        lock.withLock {
            _savedWorkouts.append((activityType, start, end, totalEnergyBurnedKcal, totalDistanceMeters))
        }
    }
}

final class FakeHealthKitServiceTests: XCTestCase {

    func test_fakeService_recordsAuthorizationCall() async throws {
        let fake = FakeHealthKitService()
        let granted = try await fake.requestAuthorization()
        XCTAssertTrue(granted)
        XCTAssertEqual(fake.authorizationCallCount, 1)
    }

    func test_fakeService_returnsFalseWhenDenied() async throws {
        let fake = FakeHealthKitService()
        fake.setGrantAuthorization(false)
        let granted = try await fake.requestAuthorization()
        XCTAssertFalse(granted)
    }

    func test_fakeService_recordsSaveWorkoutCalls() async throws {
        let fake = FakeHealthKitService()
        let start = Date()
        let end = start.addingTimeInterval(3600)
        try await fake.saveWorkout(activityType: .basketball, start: start, end: end, totalEnergyBurnedKcal: 600, totalDistanceMeters: nil)
        try await fake.saveWorkout(activityType: .swimming, start: start, end: end, totalEnergyBurnedKcal: nil, totalDistanceMeters: 800)

        let saved = fake.savedWorkouts
        XCTAssertEqual(saved.count, 2)
        XCTAssertEqual(saved[0].0, .basketball)
        XCTAssertEqual(saved[0].3, 600)
        XCTAssertEqual(saved[1].0, .swimming)
        XCTAssertEqual(saved[1].4, 800)
    }
}
