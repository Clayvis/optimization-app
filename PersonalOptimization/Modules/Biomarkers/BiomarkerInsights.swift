import Foundation

/// Derived values, trends, and rule-based pattern detection over lab draws.
/// All thresholds are a verbatim port of the reference implementation's
/// analysis section (References/biomarker-tracker.html); pattern detection is
/// rule-based by design (no ML).
enum BiomarkerInsights {

    // MARK: - Derived values

    /// HOMA-IR = glucose(mg/dL) * insulin(uIU/mL) / 405, rounded to 2 places.
    /// Nil when either input is absent or non-positive.
    static func homaIR(glucose: Double?, insulin: Double?) -> Double? {
        guard let g = glucose, let i = insulin, g > 0, i > 0 else { return nil }
        return ((g * i / 405) * 100).rounded() / 100
    }

    /// Auto-fill computed markers into a draw's values (currently HOMA-IR),
    /// mirroring the reference's save path.
    static func withComputedValues(_ values: [String: Double]) -> [String: Double] {
        var out = values
        if let homa = homaIR(glucose: values["glucose"], insulin: values["insulin"]) {
            out["homa_ir"] = homa
        }
        return out
    }

    // MARK: - Trends

    /// Percent change of `markerID` from the earliest to the latest draw that
    /// contains it. Nil with fewer than two datapoints or a zero baseline.
    static func trendPercent(markerID: String, draws: [LabDraw]) -> Double? {
        let series = draws
            .compactMap { draw in draw.values[markerID].map { (draw.date, $0) } }
            .sorted { $0.0 < $1.0 }
        guard series.count >= 2 else { return nil }
        let first = series[0].1
        let last = series[series.count - 1].1
        guard first != 0 else { return nil }
        return (((last - first) / first * 100) * 10).rounded() / 10
    }

    // MARK: - Summary counts

    struct DrawSummary: Sendable, Equatable {
        var optimal: Int = 0
        var suboptimal: Int = 0
        var outOfRange: Int = 0     // high + low
        var measured: Int = 0
    }

    static func summarize(values: [String: Double]) -> DrawSummary {
        var s = DrawSummary()
        for (id, v) in values {
            switch BiomarkerCatalog.evaluate(id, value: v) {
            case .optimal: s.optimal += 1; s.measured += 1
            case .warning: s.suboptimal += 1; s.measured += 1
            case .high, .low: s.outOfRange += 1; s.measured += 1
            case .none: break
            }
        }
        return s
    }

    // MARK: - Pattern detection (verbatim thresholds)

    struct Pattern: Sendable, Equatable, Identifiable {
        let id: String
        let title: String
        let detail: String
    }

    /// Rule-based flags over a single draw's values. Sex-specific keys follow
    /// the male profile ids where the reference does (trig/HDL uses hdl_m and
    /// remaps for female profiles upstream via aliasing).
    static func detectPatterns(values: [String: Double], sex: String) -> [Pattern] {
        var found: [Pattern] = []
        let hdlKey = sex == "female" ? "hdl_f" : "hdl_m"
        let ferritinKey = sex == "female" ? "ferritin_f" : "ferritin_m"

        if let a1c = values["hba1c"], a1c >= 5.7 {
            found.append(Pattern(
                id: "prediabetic_a1c",
                title: "HbA1c in prediabetic range",
                detail: "HbA1c \(fmt(a1c))% is at or above 5.7%."
            ))
        }
        if let g = values["glucose"], let a1c = values["hba1c"], let trig = values["triglycerides"],
           g >= 100, a1c >= 5.4, trig >= 150 {
            found.append(Pattern(
                id: "metabolic_cluster",
                title: "Metabolic dysfunction cluster",
                detail: "Fasting glucose ≥ 100, HbA1c ≥ 5.4, and triglycerides ≥ 150 together."
            ))
        }
        if let trig = values["triglycerides"], let hdl = values[hdlKey], hdl > 0, trig / hdl >= 3 {
            found.append(Pattern(
                id: "insulin_resistance_ratio",
                title: "Triglyceride/HDL ratio elevated",
                detail: "Ratio \(fmt(trig / hdl)) (≥ 3 suggests insulin resistance)."
            ))
        }
        if let apob = values["apob"], let lpa = values["lpa"], apob >= 90, lpa >= 75 {
            found.append(Pattern(
                id: "cv_risk_combo",
                title: "Elevated cardiovascular risk pair",
                detail: "ApoB ≥ 90 with Lp(a) ≥ 75 nmol/L."
            ))
        }
        if let ldl = values["ldl"], let crp = values["hs_crp"], ldl >= 130, crp >= 2 {
            found.append(Pattern(
                id: "inflam_dyslipidemia",
                title: "Inflammation plus dyslipidemia",
                detail: "LDL ≥ 130 with hs-CRP ≥ 2."
            ))
        }
        if let d = values["vit_d"], d < 30 {
            found.append(Pattern(
                id: "vit_d_deficient",
                title: "Vitamin D deficient",
                detail: "25-OH vitamin D \(fmt(d)) ng/mL is below 30."
            ))
        }
        if let hcy = values["homocysteine"], hcy >= 10 {
            found.append(Pattern(
                id: "homocysteine_elevated",
                title: "Homocysteine elevated",
                detail: "Homocysteine \(fmt(hcy)) µmol/L is at or above 10."
            ))
        }
        if let mg = values["magnesium"], mg <= 2.0 {
            found.append(Pattern(
                id: "magnesium_low",
                title: "Serum magnesium low-normal",
                detail: "Magnesium \(fmt(mg)) mg/dL is at or below 2.0."
            ))
        }
        if let alb = values["albumin"], alb < 4.0 {
            found.append(Pattern(
                id: "albumin_low",
                title: "Albumin below 4.0",
                detail: "Possible protein intake, inflammation, or liver signal."
            ))
        }
        if let tsh = values["tsh"], tsh < 0.5, values["free_t3"] == nil, values["free_t4"] == nil {
            found.append(Pattern(
                id: "subclinical_hyperthyroid",
                title: "TSH suppressed without free T3/T4",
                detail: "TSH \(fmt(tsh)) with no free hormones measured; retest with free T3/T4."
            ))
        }
        if sex == "male", let t = values["testosterone_total_m"], t < 400 {
            found.append(Pattern(
                id: "testosterone_low",
                title: "Total testosterone below 400",
                detail: "Total T \(fmt(t)) ng/dL is under the longevity-optimal floor."
            ))
        }
        if let crp = values["hs_crp"], let ferr = values[ferritinKey], crp >= 1, ferr >= 200 {
            found.append(Pattern(
                id: "systemic_inflammation",
                title: "Systemic inflammation pair",
                detail: "hs-CRP ≥ 1 with ferritin ≥ 200."
            ))
        }
        return found
    }

    private static func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}
