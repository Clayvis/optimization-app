import Foundation

/// Values read from a scan, never inferred from weight or a photograph.
struct InBodyValues: Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var date: Date = Date()
    var heightInches: Double = 0
    var weightLb: Double = 0
    var skeletalMuscleMassLb: Double = 0
    var leanBodyMassLb: Double = 0
    var bodyFatMassLb: Double = 0
    var bodyFatPercent: Double = 0
    var visceralFatAreaCm2: Double? = nil
    var totalBodyWaterLb: Double? = nil
    var ecwTbwRatio: Double? = nil
    var basalMetabolicRateKcal: Double? = nil
    var rightArmLb: Double? = nil
    var leftArmLb: Double? = nil
    var trunkLb: Double? = nil
    var rightLegLb: Double? = nil
    var leftLegLb: Double? = nil

    func validate() throws {
        let positive = [heightInches, weightLb, skeletalMuscleMassLb, leanBodyMassLb]
        let optional = [visceralFatAreaCm2, totalBodyWaterLb, basalMetabolicRateKcal,
                        rightArmLb, leftArmLb, trunkLb, rightLegLb, leftLegLb].compactMap { $0 }
        guard date.timeIntervalSince1970.isFinite, positive.allSatisfy({ $0.isFinite && $0 > 0 }),
              optional.allSatisfy({ $0.isFinite && $0 >= 0 }),
              bodyFatMassLb.isFinite, bodyFatMassLb >= 0, bodyFatMassLb <= weightLb,
              bodyFatPercent.isFinite, (0...100).contains(bodyFatPercent),
              skeletalMuscleMassLb <= leanBodyMassLb, leanBodyMassLb <= weightLb,
              ecwTbwRatio.map({ $0.isFinite && $0 > 0 && $0 < 1 }) ?? true,
              totalBodyWaterLb.map({ $0 <= leanBodyMassLb }) ?? true else {
            throw InBodyError.invalidValues
        }
    }
}

enum InBodyError: LocalizedError {
    case invalidValues, invalidDates, duplicateDay
    var errorDescription: String? {
        switch self {
        case .invalidValues: return "Check scan values: use positive weights, a body-fat percentage from 0 to 100, and an ECW/TBW ratio between 0 and 1."
        case .invalidDates: return "Choose scans from two different days, with the newer scan last."
        case .duplicateDay: return "A scan already exists for that day. Edit that scan instead."
        }
    }
}

struct BodyCompositionComparison: Equatable, Sendable {
    enum Comparability: String, Sendable { case high, moderate, low, unknown }
    let days: Int
    let weight: Double
    let skeletalMuscle: Double
    let leanMass: Double
    let fatMass: Double
    let fatPercentagePoints: Double
    let visceralFat: Double?
    let water: Double?
    let ecw: Double?
    let segments: [String: Double]
    let comparability: Comparability
    var weeks: Double { Double(days) / 7 }
    var weeklyWeight: Double { weight / weeks }

    init(previous: InBodyValues, current: InBodyValues, calendar: Calendar) throws {
        try previous.validate()
        try current.validate()
        days = calendar.dateComponents([.day], from: calendar.startOfDay(for: previous.date),
                                       to: calendar.startOfDay(for: current.date)).day ?? 0
        guard days > 0 else { throw InBodyError.invalidDates }
        weight = current.weightLb - previous.weightLb
        skeletalMuscle = current.skeletalMuscleMassLb - previous.skeletalMuscleMassLb
        leanMass = current.leanBodyMassLb - previous.leanBodyMassLb
        fatMass = current.bodyFatMassLb - previous.bodyFatMassLb
        fatPercentagePoints = current.bodyFatPercent - previous.bodyFatPercent
        func delta(_ a: Double?, _ b: Double?) -> Double? {
            guard let a, let b else { return nil }
            return b - a
        }
        visceralFat = delta(previous.visceralFatAreaCm2, current.visceralFatAreaCm2)
        water = delta(previous.totalBodyWaterLb, current.totalBodyWaterLb)
        ecw = delta(previous.ecwTbwRatio, current.ecwTbwRatio)
        // Thresholds are a configurable product heuristic, not a validated clinical score.
        if let ecw {
            let magnitude = abs(ecw)
            comparability = magnitude <= 0.003 + 1e-10 ? .high : magnitude <= 0.007 + 1e-10 ? .moderate : .low
        } else { comparability = .unknown }
        segments = ["Right arm": delta(previous.rightArmLb, current.rightArmLb),
                    "Left arm": delta(previous.leftArmLb, current.leftArmLb),
                    "Trunk": delta(previous.trunkLb, current.trunkLb),
                    "Right leg": delta(previous.rightLegLb, current.rightLegLb),
                    "Left leg": delta(previous.leftLegLb, current.leftLegLb)].compactMapValues { $0 }
    }
}
