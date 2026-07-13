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

    // Live-session surface — arbitrary interval instead of day bounds, so
    // active workouts can show energy/distance/HR accumulated since start.
    // Defaulted (returns nil) in a protocol extension so existing fakes and
    // any future conformers stay source-compatible.
    func fetchSumQuantity(_ identifier: HKQuantityTypeIdentifier,
                          unit: HKUnit,
                          in interval: DateInterval) async throws -> Double?
    func fetchLatestQuantity(_ identifier: HKQuantityTypeIdentifier,
                             unit: HKUnit,
                             in interval: DateInterval) async throws -> Double?
}

extension HealthKitServiceProtocol {
    func fetchSumQuantity(_ identifier: HKQuantityTypeIdentifier,
                          unit: HKUnit,
                          in interval: DateInterval) async throws -> Double? { nil }
    func fetchLatestQuantity(_ identifier: HKQuantityTypeIdentifier,
                             unit: HKUnit,
                             in interval: DateInterval) async throws -> Double? { nil }
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

        // Workout metadata samples (energy + per-activity distance) need
        // their own share authorization or HKWorkoutBuilder.addSamples
        // throws and the workout lands in Health with no calories/distance.
        let writeTypes: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.dietaryWater),
            HKQuantityType(.bodyMass),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.distanceSwimming),
            HKQuantityType(.distanceCycling)
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
            HKQuantityType(.height),
            HKQuantityType(.distanceSwimming),
            HKQuantityType(.distanceCycling),
            HKCharacteristicType(.dateOfBirth),
            HKCharacteristicType(.biologicalSex),
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
        // Distance samples must use the activity-appropriate type; writing
        // everything as swim meters put basketball/run distance in the wrong
        // Health category. Swimming → distanceSwimming, cycling →
        // distanceCycling, everything else → distanceWalkingRunning.
        if let meters = totalDistanceMeters {
            let distanceIdentifier: HKQuantityTypeIdentifier
            switch activityType {
            case .swimming:
                distanceIdentifier = .distanceSwimming
            case .cycling:
                distanceIdentifier = .distanceCycling
            default:
                distanceIdentifier = .distanceWalkingRunning
            }
            let distanceSample = HKQuantitySample(
                type: HKQuantityType(distanceIdentifier),
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

    // MARK: - Live-session interval fetches

    func fetchSumQuantity(_ identifier: HKQuantityTypeIdentifier,
                          unit: HKUnit,
                          in interval: DateInterval) async throws -> Double? {
        let quantityType = HKQuantityType(identifier)
        let predicate = HKQuery.predicateForSamples(
            withStart: interval.start, end: interval.end, options: .strictStartDate
        )
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

    func fetchLatestQuantity(_ identifier: HKQuantityTypeIdentifier,
                             unit: HKUnit,
                             in interval: DateInterval) async throws -> Double? {
        let quantityType = HKQuantityType(identifier)
        let predicate = HKQuery.predicateForSamples(
            withStart: interval.start, end: interval.end, options: .strictStartDate
        )
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

    // MARK: - Body characteristics (onboarding prefill)

    /// Snapshot of the body data HealthKit already knows, used to prefill
    /// the body-info form instead of making the user type it twice.
    /// Every field is optional: characteristics the user never granted or
    /// never set simply come back nil.
    struct BodyProfileSnapshot: Sendable {
        var dateOfBirth: Date?
        var biologicalSex: String?   // "male" | "female" | nil for other/unset
        var weightLbs: Double?
        var heightInches: Double?
    }

    /// Reads DOB + biological sex characteristics and the most recent body
    /// mass / height samples. Characteristic reads throw when unauthorized;
    /// those are swallowed into nils because prefill is best-effort.
    func fetchBodyProfile() async -> BodyProfileSnapshot {
        var snapshot = BodyProfileSnapshot()

        // MARK: try? justified - characteristics are optional prefill; unauthorized or unset reads mean "no value".
        if let components = try? store.dateOfBirthComponents(),
           let date = Calendar.current.date(from: components) {
            snapshot.dateOfBirth = date
        }
        // MARK: try? justified - same best-effort prefill contract as above.
        if let sexObject = try? store.biologicalSex() {
            switch sexObject.biologicalSex {
            case .male:   snapshot.biologicalSex = "male"
            case .female: snapshot.biologicalSex = "female"
            default:      snapshot.biologicalSex = nil
            }
        }

        let now = Date()
        let lookback = DateInterval(
            start: Calendar.current.date(byAdding: .year, value: -5, to: now) ?? now,
            end: now
        )
        // MARK: try? justified - missing samples mean "no value"; prefill continues with typed defaults.
        if let lbs = try? await fetchLatestQuantity(.bodyMass, unit: .pound(), in: lookback) {
            snapshot.weightLbs = lbs
        }
        // MARK: try? justified - same best-effort prefill contract as above.
        if let inches = try? await fetchLatestQuantity(.height, unit: .inch(), in: lookback) {
            snapshot.heightInches = inches
        }
        return snapshot
    }

    /// Writes a body-mass sample so weight edits made in the app reach the
    /// rest of the Health ecosystem. Fire-and-forget from Settings.
    /// - Throws: HealthKit framework errors (unauthorized, store unavailable).
    func saveBodyMass(lbs: Double, at date: Date = Date()) async throws {
        let sample = HKQuantitySample(
            type: HKQuantityType(.bodyMass),
            quantity: HKQuantity(unit: .pound(), doubleValue: lbs),
            start: date,
            end: date
        )
        try await store.save(sample)
        logger.info("Saved body mass \(lbs, privacy: .private) lbs to HealthKit")
    }

    // MARK: - Helpers

    private func dayBounds(for date: Date) -> (Date, Date) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? date
        return (start, end)
    }
}
