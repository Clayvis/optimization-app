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

        let readTypes: Set<HKObjectType> = [
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
            HKCategoryType(.sleepAnalysis)
        ]

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
}
