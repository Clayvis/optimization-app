import Foundation
import HealthKit
import os

protocol HealthKitServiceProtocol: AnyObject, Sendable {
    func requestAuthorization() async throws -> Bool
    func saveWorkout(activityType: HKWorkoutActivityType,
                     start: Date,
                     end: Date,
                     totalEnergyBurnedKcal: Double?,
                     totalDistanceMeters: Double?) async throws

    // M4.2 — Fetch surface. Returns nil when unauthorized or no samples.
    // Never throws on missing data; only on HealthKit framework errors.
    func fetchLatestQuantity(_ identifier: HKQuantityTypeIdentifier,
                             unit: HKUnit,
                             on date: Date) async throws -> Double?
    func fetchSumQuantity(_ identifier: HKQuantityTypeIdentifier,
                          unit: HKUnit,
                          for date: Date) async throws -> Double?
    func fetchSleepHours(for date: Date) async throws -> Double?
    func fetchMindfulMinutes(for date: Date) async throws -> Double?
    func fetchWorkouts(in range: DateInterval) async throws -> [HKWorkout]
}

enum HealthKitError: LocalizedError {
    case dataNotAvailable
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .dataNotAvailable: return "HealthKit not available on this device"
        case .authorizationDenied: return "HealthKit authorization was denied"
        }
    }
}

final class LiveHealthKitService: HealthKitServiceProtocol, @unchecked Sendable {

    static let shared = LiveHealthKitService()

    private let store = HKHealthStore()
    private let logger = Logger.healthkit

    private init() {}

    func requestAuthorization() async throws -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.dataNotAvailable
        }

        let writeTypes: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.dietaryWater),
            HKQuantityType(.bodyMass)
        ]

        // M4.2 — expanded read scope. Each addition surfaces a specific
        // signal either to CoachContext (HR recovery, respiratory rate,
        // mindful min, time in daylight) or to TrendAnalyticsService
        // (body comp, dietary intake, ambient noise).
        var readTypes: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.walkingHeartRateAverage),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.basalEnergyBurned),
            HKQuantityType(.stepCount),
            HKQuantityType(.vo2Max),
            HKQuantityType(.bodyMass),
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.respiratoryRate),
            HKQuantityType(.oxygenSaturation),
            HKQuantityType(.bodyFatPercentage),
            HKQuantityType(.leanBodyMass),
            HKQuantityType(.heartRateRecoveryOneMinute),
            HKQuantityType(.appleExerciseTime),
            HKQuantityType(.appleStandTime),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.walkingSpeed),
            HKQuantityType(.environmentalAudioExposure),
            HKQuantityType(.headphoneAudioExposure),
            HKQuantityType(.dietaryEnergyConsumed),
            HKQuantityType(.dietaryProtein),
            HKQuantityType(.dietaryCarbohydrates),
            HKQuantityType(.dietaryFatTotal),
            HKQuantityType(.dietaryCaffeine),
            HKCategoryType(.appleStandHour),
            HKCategoryType(.mindfulSession)
        ]
        if #available(iOS 17.0, *) {
            readTypes.insert(HKQuantityType(.timeInDaylight))
        }
        if #available(iOS 16.0, *) {
            readTypes.insert(HKQuantityType(.appleSleepingWristTemperature))
        }

        try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
        let status = store.authorizationStatus(for: HKObjectType.workoutType())
        return status == .sharingAuthorized
    }

    func saveWorkout(activityType: HKWorkoutActivityType,
                     start: Date,
                     end: Date,
                     totalEnergyBurnedKcal: Double?,
                     totalDistanceMeters: Double?) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType

        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: nil)
        try await builder.beginCollection(at: start)

        var samples: [HKSample] = []
        if let kcal = totalEnergyBurnedKcal {
            let energySample = HKQuantitySample(
                type: HKQuantityType(.activeEnergyBurned),
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                start: start,
                end: end
            )
            samples.append(energySample)
        }
        if let meters = totalDistanceMeters {
            let distanceSample = HKQuantitySample(
                type: HKQuantityType(.distanceSwimming),
                quantity: HKQuantity(unit: .meter(), doubleValue: meters),
                start: start,
                end: end
            )
            samples.append(distanceSample)
        }
        if !samples.isEmpty {
            try await builder.addSamples(samples)
        }

        try await builder.endCollection(at: end)
        _ = try await builder.finishWorkout()
        logger.info("Saved \(activityType.rawValue, privacy: .public) workout to HealthKit")
    }

    // MARK: - Fetch surface (M4.2)

    func fetchLatestQuantity(_ identifier: HKQuantityTypeIdentifier,
                             unit: HKUnit,
                             on date: Date) async throws -> Double? {
        let quantityType = HKQuantityType(identifier)
        let (start, end) = dayBounds(for: date)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: sample.quantity.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    func fetchSumQuantity(_ identifier: HKQuantityTypeIdentifier,
                          unit: HKUnit,
                          for date: Date) async throws -> Double? {
        let quantityType = HKQuantityType(identifier)
        let (start, end) = dayBounds(for: date)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let sum = statistics?.sumQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: sum.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    /// Sum of sleep "asleep" hours for the night ending on the given day.
    /// Window: 16 hours before noon of `date` → noon of `date`.
    func fetchSleepHours(for date: Date) async throws -> Double? {
        let calendar = Calendar.current
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        let start = calendar.date(byAdding: .hour, value: -16, to: noon) ?? date
        let predicate = HKQuery.predicateForSamples(withStart: start, end: noon, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKCategoryType(.sleepAnalysis),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let asleepRaw: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue
                ]
                let categories = (samples as? [HKCategorySample]) ?? []
                let seconds = categories
                    .filter { asleepRaw.contains($0.value) }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                continuation.resume(returning: seconds == 0 ? nil : seconds / 3600.0)
            }
            store.execute(query)
        }
    }

    func fetchMindfulMinutes(for date: Date) async throws -> Double? {
        let (start, end) = dayBounds(for: date)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKCategoryType(.mindfulSession),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let seconds = (samples ?? []).reduce(0.0) {
                    $0 + $1.endDate.timeIntervalSince($1.startDate)
                }
                continuation.resume(returning: seconds == 0 ? nil : seconds / 60.0)
            }
            store.execute(query)
        }
    }

    func fetchWorkouts(in range: DateInterval) async throws -> [HKWorkout] {
        let predicate = HKQuery.predicateForSamples(withStart: range.start, end: range.end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }
    }

    // MARK: - Helpers

    private func dayBounds(for date: Date) -> (Date, Date) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? date
        return (start, end)
    }
}
