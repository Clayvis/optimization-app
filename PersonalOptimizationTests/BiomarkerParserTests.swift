import XCTest
import SwiftData
@testable import PersonalOptimization

/// Text-parsing port tests plus the sample_lab_dod.json regression: the
/// bundled reference export must import losslessly through LabDrawStore.
final class BiomarkerParserTests: XCTestCase {

    // MARK: - DOD MTF stanza format

    func testDODFormatParsesStanzas() {
        let text = """
        Patient: RAWLINS, CLAY
        Collected: 2025-10-24
        Glucose Lvl
        Laboratory
        100 mg/dL
        Hemoglobin
        Laboratory
        14.6 g/dL
        Creatinine Level
        Laboratory
        1.15 mg/dL H
        TSH
        Laboratory
        0.425 uIU/mL L
        """
        let report = BiomarkerPDFParser.parse(text: text, sex: "male")
        XCTAssertEqual(report.values["glucose"], 100)
        XCTAssertEqual(report.values["hemoglobin"], 14.6)
        XCTAssertEqual(report.values["creatinine"], 1.15)
        XCTAssertEqual(report.values["tsh"], 0.425)
        XCTAssertNotNil(report.date)
    }

    func testDODFormatCollectsUnmatchedNames() {
        let text = """
        Mystery Marker Zeta
        Laboratory
        42 units
        Glucose
        Laboratory
        95 mg/dL
        Another Unknown
        Laboratory
        7 things
        """
        let report = BiomarkerPDFParser.parse(text: text, sex: "male")
        XCTAssertEqual(report.values["glucose"], 95)
        XCTAssertTrue(report.unmatched.contains("Mystery Marker Zeta"))
    }

    // MARK: - Generic format

    func testGenericFormatParsesNameValueLines() {
        let text = """
        LabCorp Results — March 3, 2026
        Total Cholesterol 182 mg/dL
        HDL Cholesterol 58 mg/dL
        Triglycerides
        88 mg/dL
        Vitamin B12 642 pg/mL
        """
        let report = BiomarkerPDFParser.parse(text: text, sex: "male")
        XCTAssertEqual(report.values["total_cholesterol"], 182)
        XCTAssertEqual(report.values["hdl_m"], 58)
        XCTAssertEqual(report.values["triglycerides"], 88, "value on the following line must be found")
        XCTAssertEqual(report.values["vit_b12"], 642, "the 12 in B12 must not be taken as the value")
        XCTAssertNotNil(report.date)
    }

    func testGenericFormatLongestAliasWins() {
        // "free t3" must resolve as free_t3, not stop at a shorter prefix.
        let text = """
        Free T3 3.4 pg/mL
        Free T4 1.2 ng/dL
        """
        let report = BiomarkerPDFParser.parse(text: text, sex: "male")
        XCTAssertEqual(report.values["free_t3"], 3.4)
        XCTAssertEqual(report.values["free_t4"], 1.2)
    }

    func testGenericFormatRejectsZeroAndKeepsFirstHit() {
        let text = """
        Glucose 0
        Glucose 92 mg/dL
        Glucose 105 mg/dL
        """
        let report = BiomarkerPDFParser.parse(text: text, sex: "male")
        // Zero is a parse artifact (reference rejects it); first real value sticks.
        XCTAssertEqual(report.values["glucose"], 92)
    }

    func testFemaleSexRemapsHDL() {
        let report = BiomarkerPDFParser.parse(text: "HDL Cholesterol 62 mg/dL", sex: "female")
        XCTAssertEqual(report.values["hdl_f"], 62)
        XCTAssertNil(report.values["hdl_m"])
    }

    // MARK: - Date extraction

    func testDateExtractionAllThreePatterns() throws {
        let utc = TimeZone(identifier: "UTC")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(utc)

        let iso = BiomarkerPDFParser.extractDate(from: ["Collected 2025-10-24 08:12"])
        XCTAssertEqual(iso.map { cal.dateComponents([.year, .month, .day], from: $0) }?.day, 24)

        let monthName = BiomarkerPDFParser.extractDate(from: ["Drawn October 24, 2025"])
        XCTAssertEqual(monthName.map { cal.dateComponents([.year, .month, .day], from: $0) }?.month, 10)

        let slashes = BiomarkerPDFParser.extractDate(from: ["Report date 10/24/2025"])
        XCTAssertEqual(slashes.map { cal.dateComponents([.year, .month, .day], from: $0) }?.year, 2025)

        XCTAssertNil(BiomarkerPDFParser.extractDate(from: ["no dates here"]))
    }

    // MARK: - sample_lab_dod.json regression (round-trip through the store)

    @MainActor
    func testSampleLabImportRoundTripsAllValues() throws {
        let container = try InMemoryContainer.make()
        let context = container.mainContext

        let url = try XCTUnwrap(
            Bundle(for: BiomarkerParserTests.self).url(forResource: "sample_lab_dod", withExtension: "json"),
            "sample_lab_dod.json must be bundled with the test target"
        )
        let data = try Data(contentsOf: url)
        let imported = try LabDrawStore.importReferenceJSON(data, modelContext: context)
        XCTAssertEqual(imported, 1)

        let draw = try XCTUnwrap(LabDrawStore.latest(modelContext: context))
        // Spot-check the documented values plus the full count.
        XCTAssertEqual(draw.values.count, 25)
        XCTAssertEqual(draw.values["glucose"], 100)
        XCTAssertEqual(draw.values["hemoglobin"], 14.6)
        XCTAssertEqual(draw.values["rdw"], 13.9)
        XCTAssertEqual(draw.values["lymphocyte_pct"], 37.2)
        XCTAssertEqual(draw.values["tsh"], 0.425)
        XCTAssertEqual(draw.values["egfr"], 87)

        // Draw date is the file's 2025-10-24 at UTC midnight.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let comps = cal.dateComponents([.year, .month, .day], from: draw.date)
        XCTAssertEqual([comps.year, comps.month, comps.day], [2025, 10, 24])

        // PhenoAge is NOT computable from this panel (hs_crp missing) — the
        // documented property of the sample.
        XCTAssertEqual(PhenoAgeCalculator.missingMarkers(in: draw.values), ["hs_crp"])
        XCTAssertNil(PhenoAgeCalculator.phenoAge(values: draw.values, chronologicalAge: 31))

        // Re-import is idempotent (upsert by day).
        XCTAssertEqual(try LabDrawStore.importReferenceJSON(data, modelContext: context), 1)
        XCTAssertEqual(LabDrawStore.allDraws(modelContext: context).count, 1)
    }

    @MainActor
    func testUpsertMergesAndRecomputesHomaIR() throws {
        let container = try InMemoryContainer.make()
        let context = container.mainContext
        let day = LabDrawStore.dayKey(Date())

        try LabDrawStore.upsert(date: day, values: ["glucose": 100], modelContext: context)
        // Second partial result for the same day brings insulin; HOMA-IR must
        // appear from the merged pair.
        try LabDrawStore.upsert(date: day, values: ["insulin": 5], modelContext: context)

        let draw = try XCTUnwrap(LabDrawStore.latest(modelContext: context))
        XCTAssertEqual(draw.values["glucose"], 100)
        XCTAssertEqual(draw.values["insulin"], 5)
        XCTAssertEqual(draw.values["homa_ir"], 1.23)
        XCTAssertEqual(LabDrawStore.allDraws(modelContext: context).count, 1)
    }

    @MainActor
    func testTrendPercentFirstToLatest() throws {
        let container = try InMemoryContainer.make()
        let context = container.mainContext
        let cal = Calendar(identifier: .gregorian)

        for (offset, value) in [(-180, 92.0), (-90, 96.0), (0, 100.0)] {
            let date = try XCTUnwrap(cal.date(byAdding: .day, value: offset, to: Date()))
            try LabDrawStore.upsert(date: date, values: ["glucose": value], modelContext: context)
        }
        let draws = LabDrawStore.allDraws(modelContext: context)
        // (100 - 92) / 92 * 100 = 8.695… → 8.7 at the reference's 1-decimal rounding.
        XCTAssertEqual(BiomarkerInsights.trendPercent(markerID: "glucose", draws: draws), 8.7)
        XCTAssertNil(BiomarkerInsights.trendPercent(markerID: "tsh", draws: draws))
    }

    func testPatternDetectionThresholds() {
        let patterns = BiomarkerInsights.detectPatterns(
            values: [
                "hba1c": 5.8,
                "glucose": 102, "triglycerides": 160,
                "hdl_m": 40,
                "vit_d": 24,
                "magnesium": 1.7
            ],
            sex: "male"
        )
        let ids = Set(patterns.map(\.id))
        XCTAssertTrue(ids.contains("prediabetic_a1c"))
        XCTAssertTrue(ids.contains("metabolic_cluster"))
        XCTAssertTrue(ids.contains("insulin_resistance_ratio"), "160/40 = 4 ≥ 3")
        XCTAssertTrue(ids.contains("vit_d_deficient"))
        XCTAssertTrue(ids.contains("magnesium_low"))
        XCTAssertFalse(ids.contains("testosterone_low"), "marker absent → no flag")
    }
}
