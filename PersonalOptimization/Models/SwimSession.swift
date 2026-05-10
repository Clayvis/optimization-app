import Foundation
import SwiftData

enum SwimWaterType: String, Codable, CaseIterable, Sendable {
    case pool
    case beach
    case openWater
    case other

    var displayName: String {
        switch self {
        case .pool:      return "Pool"
        case .beach:     return "Beach"
        case .openWater: return "Open water"
        case .other:     return "Other"
        }
    }

    /// Pool counts laps in pool-length units. Other types count direct meters.
    var laneBased: Bool {
        self == .pool
    }
}

@Model
final class SwimSession {
    var date: Date = Date.distantPast
    var poolLengthMeters: Double = 25
    var laps: Int = 0
    var totalMeters: Double = 0
    var durationMinutes: Int = 0
    var avgHR: Int?
    var location: String?
    var waterTypeRaw: String = SwimWaterType.pool.rawValue

    var waterType: SwimWaterType {
        SwimWaterType(rawValue: waterTypeRaw) ?? .pool
    }

    init(date: Date, poolLengthMeters: Double = 25) {
        self.date = date
        self.poolLengthMeters = poolLengthMeters
    }
}
