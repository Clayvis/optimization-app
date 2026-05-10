import Foundation
import SwiftData

/// Persisted record of a HealthKit write that failed after exhausting retries.
/// Diagnostics view surfaces these so the user can see when sync is degraded.
@Model
final class HealthKitWriteFailure {
    var timestamp: Date = Date.distantPast
    var activityTypeRaw: UInt = 0      // HKWorkoutActivityType.rawValue
    var startTime: Date = Date.distantPast
    var endTime: Date = Date.distantPast
    var totalEnergyKcal: Double?
    var totalDistanceMeters: Double?
    var errorDescription: String = ""
    var retryCount: Int = 0
    var resolved: Bool = false

    init(timestamp: Date,
         activityTypeRaw: UInt,
         startTime: Date,
         endTime: Date,
         totalEnergyKcal: Double?,
         totalDistanceMeters: Double?,
         errorDescription: String,
         retryCount: Int) {
        self.timestamp = timestamp
        self.activityTypeRaw = activityTypeRaw
        self.startTime = startTime
        self.endTime = endTime
        self.totalEnergyKcal = totalEnergyKcal
        self.totalDistanceMeters = totalDistanceMeters
        self.errorDescription = errorDescription
        self.retryCount = retryCount
    }
}
