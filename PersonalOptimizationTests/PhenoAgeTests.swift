import XCTest
@testable import PersonalOptimization

/// Pins the Levine PhenoAge port to hand-computed expectations (independently
/// derived from the reference coefficients). Any drift in a coefficient, a
/// unit conversion, or the mortality transform fails these exactly.
final class PhenoAgeTests: XCTestCase {

    private func values(
        albumin: Double = 4.6,
        creatinine: Double = 1.15,
        glucose: Double = 100,
        crp: Double = 0.5,
        lymph: Double = 37.2,
        mcv: Double = 88.0,
        rdw: Double = 13.9,
        alkPhos: Double = 56,
        wbc: Double = 5.10
    ) -> [String: Double] {
        [
            "albumin": albumin, "creatinine": creatinine, "glucose": glucose,
            "hs_crp": crp, "lymphocyte_pct": lymph, "mcv": mcv, "rdw": rdw,
            "alk_phos": alkPhos, "wbc": wbc
        ]
    }

    func testPhenoAgeMatchesReferenceComputation() {
        let result = PhenoAgeCalculator.phenoAge(values: values(), chronologicalAge: 31.0)
        XCTAssertEqual(result, 30.7)
    }

    func testCRPZeroUsesFloorOfPointZeroOne() {
        let result = PhenoAgeCalculator.phenoAge(values: values(crp: 0), chronologicalAge: 31.0)
        XCTAssertEqual(result, 26.5)
    }

    func testUnhealthyProfileComputesOlderPhenoAge() {
        let unhealthy = values(
            albumin: 3.8, creatinine: 1.3, glucose: 118, crp: 4.2,
            lymph: 22, mcv: 99, rdw: 15.8, alkPhos: 120, wbc: 9.4
        )
        let result = PhenoAgeCalculator.phenoAge(values: unhealthy, chronologicalAge: 55.0)
        XCTAssertEqual(result, 77.1)
    }

    func testMissingMarkerReturnsNil() {
        var incomplete = values()
        incomplete.removeValue(forKey: "hs_crp")
        XCTAssertNil(PhenoAgeCalculator.phenoAge(values: incomplete, chronologicalAge: 31.0))
    }

    func testMissingMarkersListsCanonicalOrder() {
        var incomplete = values()
        incomplete.removeValue(forKey: "hs_crp")
        incomplete.removeValue(forKey: "wbc")
        XCTAssertEqual(PhenoAgeCalculator.missingMarkers(in: incomplete), ["hs_crp", "wbc"])
        XCTAssertEqual(PhenoAgeCalculator.missingMarkers(in: values()), [])
    }

    func testChronologicalAgeUsesJulianYear() throws {
        let cal = Calendar(identifier: .gregorian)
        let dob = try XCTUnwrap(cal.date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"), year: 1994, month: 3, day: 27)))
        let asOf = try XCTUnwrap(cal.date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"), year: 2026, month: 3, day: 27)))
        let age = try XCTUnwrap(PhenoAgeCalculator.chronologicalAge(dob: dob, asOf: asOf))
        XCTAssertEqual(age, 32.0, accuracy: 0.01)
    }

    func testChronologicalAgeRejectsSentinelAndFutureDOB() {
        XCTAssertNil(PhenoAgeCalculator.chronologicalAge(dob: .distantPast))
        XCTAssertNil(PhenoAgeCalculator.chronologicalAge(dob: Date().addingTimeInterval(86_400), asOf: Date()))
    }

    func testHomaIRMatchesReference() {
        XCTAssertEqual(BiomarkerInsights.homaIR(glucose: 100, insulin: 5), 1.23)
        XCTAssertNil(BiomarkerInsights.homaIR(glucose: 100, insulin: nil))
        XCTAssertNil(BiomarkerInsights.homaIR(glucose: nil, insulin: 5))
        XCTAssertNil(BiomarkerInsights.homaIR(glucose: 0, insulin: 5))
    }

    func testWithComputedValuesAddsHomaIROnlyWhenPaired() {
        let paired = BiomarkerInsights.withComputedValues(["glucose": 100, "insulin": 5])
        XCTAssertEqual(paired["homa_ir"], 1.23)
        let unpaired = BiomarkerInsights.withComputedValues(["glucose": 100])
        XCTAssertNil(unpaired["homa_ir"])
    }
}
