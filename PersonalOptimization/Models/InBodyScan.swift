import Foundation
import SwiftData

@Model
final class InBodyScan {
    var id: UUID = UUID()
    var date: Date = Date.distantPast
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

    init(values: InBodyValues) { apply(values) }
    func apply(_ values: InBodyValues) {
        id = values.id
        date = values.date
        heightInches = values.heightInches
        weightLb = values.weightLb
        skeletalMuscleMassLb = values.skeletalMuscleMassLb
        leanBodyMassLb = values.leanBodyMassLb
        bodyFatMassLb = values.bodyFatMassLb
        bodyFatPercent = values.bodyFatPercent
        visceralFatAreaCm2 = values.visceralFatAreaCm2
        totalBodyWaterLb = values.totalBodyWaterLb
        ecwTbwRatio = values.ecwTbwRatio
        basalMetabolicRateKcal = values.basalMetabolicRateKcal
        rightArmLb = values.rightArmLb
        leftArmLb = values.leftArmLb
        trunkLb = values.trunkLb
        rightLegLb = values.rightLegLb
        leftLegLb = values.leftLegLb
    }
    var values: InBodyValues {
        var result = InBodyValues()
        result.id = id
        result.date = date
        result.heightInches = heightInches
        result.weightLb = weightLb
        result.skeletalMuscleMassLb = skeletalMuscleMassLb
        result.leanBodyMassLb = leanBodyMassLb
        result.bodyFatMassLb = bodyFatMassLb
        result.bodyFatPercent = bodyFatPercent
        result.visceralFatAreaCm2 = visceralFatAreaCm2
        result.totalBodyWaterLb = totalBodyWaterLb
        result.ecwTbwRatio = ecwTbwRatio
        result.basalMetabolicRateKcal = basalMetabolicRateKcal
        result.rightArmLb = rightArmLb
        result.leftArmLb = leftArmLb
        result.trunkLb = trunkLb
        result.rightLegLb = rightLegLb
        result.leftLegLb = leftLegLb
        return result
    }
}
