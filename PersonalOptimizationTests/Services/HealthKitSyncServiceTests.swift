import XCTest
import HealthKit
import SwiftData
@testable import PersonalOptimization

@MainActor
final class HealthKitSyncServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var fake: FakeHealthKitService!

    override func setUp() async throws {
        try await super.setUp()
        container = try InMemoryContainer.make()
        context = container.mainContext
        fake = FakeHealthKitService()
    }

    override func tearDown() async throws {
        fake = nil
        context = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: - Empty HealthKit case

    func test_syncToday_emptyHealthKit_leavesDailyLogEmpty() async throws {
        let service = HealthKitSyncService(modelContext: context, healthKit: fake)
        let log = await service.syncToday()

        XCTAssertNil(log.respiratoryRate)
        XCTAssertNil(log.oxygenSaturationPercent)
        XCTAssertNil(log.heartRateRecovery1minBpm)
        XCTAssertNil(log.stepCount)
        XCTAssertNil(log.dietaryKcal)
        XCTAssertNotNil(log.healthKitSyncedAt, "Sync timestamp should record even when no data")
    }

    // MARK: - Populated HealthKit case

    func test_syncToday_populatedHealthKit_writesAllFields() async throws {
        // Stub a realistic spread of values.
        fake.stubLatest(.respiratoryRate, value: 14.5)
        fake.stubLatest(.oxygenSaturation, value: 0.97)        // 97%
        fake.stubLatest(.bodyFatPercentage, value: 0.18)       // 18%
        fake.stubLatest(.heartRateRecoveryOneMinute, value: 32)
        fake.stubLatest(.restingHeartRate, value: 58)
        fake.stubLatest(.heartRateVariabilitySDNN, value: 65.2)
        fake.stubLatest(.bodyMass, value: 175)
        fake.stubLatest(.environmentalAudioExposure, value: 62)
        fake.stubSum(.stepCount, value: 8420)
        fake.stubSum(.appleExerciseTime, value: 35)
        fake.stubSum(.distanceWalkingRunning, value: 5400)
        fake.stubSum(.dietaryEnergyConsumed, value: 2100)
        fake.stubSum(.dietaryProtein, value: 165)
        fake.stubSum(.dietaryCarbohydrates, value: 220)
        fake.stubSum(.dietaryFatTotal, value: 70)
        fake.stubSum(.dietaryCaffeine, value: 180)
        fake.stubSleepHours(7.4)
        fake.stubMindfulMinutes(12)

        let service = HealthKitSyncService(modelContext: context, healthKit: fake)
        let log = await service.syncToday()

        XCTAssertEqual(log.respiratoryRate, 14.5)
        XCTAssertEqual(log.oxygenSaturationPercent ?? 0, 97, accuracy: 0.001)
        XCTAssertEqual(log.bodyFatPercentage ?? 0, 18, accuracy: 0.001)
        XCTAssertEqual(log.heartRateRecovery1minBpm, 32)
        XCTAssertEqual(log.restingHR, 58)
        XCTAssertEqual(log.hrvRmssd, 65.2)
        XCTAssertEqual(log.weightLbs, 175)
        XCTAssertEqual(log.environmentalAudioDb, 62)
        XCTAssertEqual(log.stepCount, 8420)
        XCTAssertEqual(log.appleExerciseMinutes, 35)
        XCTAssertEqual(log.distanceMeters, 5400)
        XCTAssertEqual(log.dietaryKcal, 2100)
        XCTAssertEqual(log.dietaryProteinG, 165)
        XCTAssertEqual(log.dietaryCarbsG, 220)
        XCTAssertEqual(log.dietaryFatG, 70)
        XCTAssertEqual(log.caffeineMg, 180)
        XCTAssertEqual(log.sleepHours, 7.4)
        XCTAssertEqual(log.mindfulMinutes, 12)
    }

    // MARK: - Idempotency

    func test_syncToday_runTwice_sameDataProducesNoChanges() async throws {
        fake.stubLatest(.respiratoryRate, value: 14.5)
        fake.stubSum(.stepCount, value: 5000)
        fake.stubSleepHours(7.0)

        let service = HealthKitSyncService(modelContext: context, healthKit: fake)
        _ = await service.syncToday()
        _ = await service.syncToday()

        // Only one DailyLog row should exist, with the same values.
        let logs = try context.fetch(FetchDescriptor<DailyLog>())
        XCTAssertEqual(logs.count, 1, "Two syncs must reuse the same DailyLog row")
        XCTAssertEqual(logs.first?.respiratoryRate, 14.5)
        XCTAssertEqual(logs.first?.stepCount, 5000)
        XCTAssertEqual(logs.first?.sleepHours, 7.0)
    }

    // MARK: - Partial data

    func test_syncToday_partialData_writesOnlyAvailableFields() async throws {
        // Only sleep is stubbed; everything else absent.
        fake.stubSleepHours(8.1)

        let service = HealthKitSyncService(modelContext: context, healthKit: fake)
        let log = await service.syncToday()

        XCTAssertEqual(log.sleepHours, 8.1)
        XCTAssertNil(log.respiratoryRate)
        XCTAssertNil(log.stepCount)
        XCTAssertNil(log.dietaryKcal)
    }

    // MARK: - Preserves user-entered data when HK has nil

    func test_syncToday_preservesExistingValuesWhenHKReturnsNil() async throws {
        // User manually entered a sleep value; HK has none for today.
        let log = DailyLog(date: Date())
        log.sleepHours = 6.5
        log.notes = "manual entry"
        context.insert(log)
        try context.save()

        let service = HealthKitSyncService(modelContext: context, healthKit: fake)
        _ = await service.syncToday()

        let logs = try context.fetch(FetchDescriptor<DailyLog>())
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.notes, "manual entry")
        // Sleep was nil-stubbed → manual value preserved (sync doesn't clobber
        // with nil).
        XCTAssertEqual(logs.first?.sleepHours, 6.5)
    }
}
