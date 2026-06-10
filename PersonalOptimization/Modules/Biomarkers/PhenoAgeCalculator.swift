import Foundation

/// Levine 2018 PhenoAge, ported verbatim from the validated reference
/// implementation (References/biomarker-tracker.html). Every coefficient and
/// unit conversion matches the reference; PhenoAgeTests pins the output so the
/// port cannot drift.
enum PhenoAgeCalculator {

    /// Marker ids required for the calculation. All nine must be present.
    static let requiredMarkers: [String] = [
        "albumin", "creatinine", "glucose", "hs_crp", "lymphocyte_pct",
        "mcv", "rdw", "alk_phos", "wbc"
    ]

    /// Markers missing from `values`, in canonical order. Empty when computable.
    static func missingMarkers(in values: [String: Double]) -> [String] {
        requiredMarkers.filter { values[$0] == nil }
    }

    /// PhenoAge in years, or nil when any input is missing or the mortality
    /// score falls outside (0, 1). `chronologicalAge` is in years.
    ///
    /// Reference formula (quoted):
    ///   xb = -19.907 - 0.0336*albumin_gL + 0.0095*creatinine_umolL
    ///        + 0.1953*glucose_mmolL + 0.0954*ln(CRP) - 0.0120*lymph%
    ///        + 0.0268*MCV + 0.3306*RDW + 0.00188*ALP + 0.0554*WBC
    ///        + 0.0804*chronoAge
    ///   M = 1 - exp(-exp(xb) * (exp(120*0.0076927) - 1) / 0.0076927)
    ///   PhenoAge = 141.50225 + ln(-0.00553 * ln(1 - M)) / 0.090165
    static func phenoAge(values: [String: Double], chronologicalAge: Double) -> Double? {
        guard
            let albumin = values["albumin"],
            let creatinine = values["creatinine"],
            let glucose = values["glucose"],
            let crp = values["hs_crp"],
            let lymphocytePct = values["lymphocyte_pct"],
            let mcv = values["mcv"],
            let rdw = values["rdw"],
            let alkPhos = values["alk_phos"],
            let wbc = values["wbc"]
        else { return nil }

        // Unit conversions exactly as the reference applies them.
        let albuminGL = albumin * 10            // g/dL -> g/L
        let creatinineUmolL = creatinine * 88.4 // mg/dL -> µmol/L
        let glucoseMmolL = glucose / 18.018     // mg/dL -> mmol/L
        let lnCRP = log(max(crp, 0.01))         // ln(mg/L), floored at 0.01

        let xb = -19.907
            + (-0.0336 * albuminGL)
            + (0.0095 * creatinineUmolL)
            + (0.1953 * glucoseMmolL)
            + (0.0954 * lnCRP)
            + (-0.0120 * lymphocytePct)
            + (0.0268 * mcv)
            + (0.3306 * rdw)
            + (0.00188 * alkPhos)
            + (0.0554 * wbc)
            + (0.0804 * chronologicalAge)

        let m = 1 - exp(-exp(xb) * (exp(120 * 0.0076927) - 1) / 0.0076927)
        guard m > 0, m < 1 else { return nil }

        let pheno = 141.50225 + log(-0.00553 * log(1 - m)) / 0.090165
        // Reference rounds to one decimal via toFixed(1).
        return (pheno * 10).rounded() / 10
    }

    /// Chronological age in years at `asOf` for a profile date of birth,
    /// using the reference's 365.25-day year.
    static func chronologicalAge(dob: Date, asOf: Date = Date()) -> Double? {
        guard dob != .distantPast, dob < asOf else { return nil }
        return asOf.timeIntervalSince(dob) / (86_400 * 365.25)
    }
}
