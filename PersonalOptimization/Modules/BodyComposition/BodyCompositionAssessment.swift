import Foundation

/// Deterministic verdict on a scan comparison: the dashboard's coach analysis.
/// Rules decide; the optional AI Coach only explains their output.
///
/// A change inside a stable band reads as "stable". Back-to-back BIA scans can
/// differ by about this much from hydration, food and time of day alone, so a
/// smaller change is not evidence of a trend. The bands are product
/// heuristics, shown in the UI, not clinical thresholds.
struct BodyCompositionAssessment: Equatable, Sendable {
    enum Trend: String, Sendable {
        case rising = "Rising"
        case stable = "Stable"
        case falling = "Falling"
    }

    enum GainRate: String, Sendable {
        case below = "Below your range"
        case within = "Within your range"
        case above = "Above your range"
    }

    static let muscleBandLb = 0.5
    static let fatMassBandLb = 0.5
    static let bodyFatBandPoints = 0.5

    let muscle: Trend
    let fatMass: Trend
    let bodyFatPercent: Trend
    let gainRate: GainRate
    let comparability: BodyCompositionComparison.Comparability
    let headline: String
    let recommendations: [String]

    init(comparison: BodyCompositionComparison, focus: HypertrophyFocus) {
        muscle = Self.trend(comparison.skeletalMuscle, band: Self.muscleBandLb)
        fatMass = Self.trend(comparison.fatMass, band: Self.fatMassBandLb)
        bodyFatPercent = Self.trend(comparison.fatPercentagePoints, band: Self.bodyFatBandPoints)
        gainRate = comparison.weeklyWeight > focus.weeklyGainMax ? .above
            : comparison.weeklyWeight < focus.weeklyGainMin ? .below : .within
        comparability = comparison.comparability

        switch (muscle, bodyFatPercent) {
        case (.rising, .rising): headline = "Gaining muscle, body fat rising"
        case (.rising, _): headline = "Productive muscle-gaining phase"
        case (.falling, _): headline = "Estimated muscle trending down"
        case (.stable, .rising): headline = "Body fat rising without measurable muscle gain"
        case (.stable, .falling): headline = "Leaning out, muscle holding"
        case (.stable, .stable): headline = "Holding steady"
        }

        let range = "\(Self.pounds(focus.weeklyGainMin))–\(Self.pounds(focus.weeklyGainMax)) lb/week"
        var advice: [String] = []
        switch gainRate {
        case .above:
            advice.append("Weight is rising faster than your \(range) range. Trim the calorie surplus slightly; keep protein and training intensity.")
        case .below where muscle == .rising:
            advice.append("Muscle is rising at less than your \(range) range. No calorie change is needed.")
        case .below:
            advice.append("Weight is below your \(range) range without clear muscle gain. Review intake, progression and recovery before changing calories.")
        case .within:
            advice.append("The rate of gain fits your \(range) range. Keep the current intake.")
        }
        if focus.enabled {
            let priorities = ListFormatter.localizedString(byJoining: focus.priorities.map { $0.lowercased() })
            advice.append("Direct extra recoverable volume to \(priorities); keep other muscles at maintenance.")
        }
        if comparability == .low || comparability == .unknown {
            advice.append("Hydration differs between these scans or was not measured. Treat lean-mass changes cautiously and repeat under matched conditions.")
        }
        recommendations = advice
    }

    private static func trend(_ change: Double, band: Double) -> Trend {
        change > band ? .rising : change < -band ? .falling : .stable
    }

    private static func pounds(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}
