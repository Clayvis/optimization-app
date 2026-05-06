import Foundation
import SwiftData

enum BeverageType: String, Codable, CaseIterable, Sendable {
    case water
    case coffee
    case tea
    case electrolyte
    case other

    /// Hydration coefficient — multiplied against amountOz to compute effective hydration.
    /// Coffee mildly diuretic; electrolyte enhances retention.
    var hydrationCoefficient: Double {
        switch self {
        case .water:        return 1.0
        case .coffee:       return 0.8
        case .tea:          return 0.95
        case .electrolyte:  return 1.2
        case .other:        return 1.0
        }
    }

    var displayName: String {
        switch self {
        case .water: return "Water"
        case .coffee: return "Coffee"
        case .tea: return "Tea"
        case .electrolyte: return "Electrolyte"
        case .other: return "Other"
        }
    }
}

/// One bottle / mug / cup logged. Per-entry granularity allows beverage-type breakdown
/// and per-day reconciliation. DailyLog.waterOz remains the rolled-up total for legacy
/// callers that only need the day's number.
@Model
final class HydrationEntry {
    var date: Date = Date.distantPast            // logged-at timestamp
    var amountOz: Double = 0
    var beverageTypeRaw: String = BeverageType.water.rawValue
    var note: String?

    var beverageType: BeverageType {
        BeverageType(rawValue: beverageTypeRaw) ?? .other
    }

    /// Amount oz weighted by beverage hydration coefficient.
    var effectiveOz: Double { amountOz * beverageType.hydrationCoefficient }

    init(date: Date, amountOz: Double, beverageType: BeverageType = .water, note: String? = nil) {
        self.date = date
        self.amountOz = amountOz
        self.beverageTypeRaw = beverageType.rawValue
        self.note = note
    }
}
