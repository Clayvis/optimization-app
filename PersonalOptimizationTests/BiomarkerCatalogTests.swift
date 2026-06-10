import XCTest
@testable import PersonalOptimization

/// Guards the bundled catalog/alias resources and the evaluation + alias
/// resolution ports. The counts pin the verbatim extraction from the
/// reference implementation (71 markers, 183 aliases).
final class BiomarkerCatalogTests: XCTestCase {

    func testCatalogLoadsAllMarkers() {
        XCTAssertEqual(BiomarkerCatalog.all.count, 71)
        XCTAssertEqual(BiomarkerCatalog.aliases.count, 183)
    }

    func testEveryMarkerHasWellFormedRanges() {
        for (id, def) in BiomarkerCatalog.all {
            XCTAssertEqual(def.optimal.count, 2, "\(id) optimal range malformed")
            XCTAssertEqual(def.normal.count, 2, "\(id) normal range malformed")
            XCTAssertLessThanOrEqual(def.optimal[0], def.optimal[1], id)
            XCTAssertLessThanOrEqual(def.normal[0], def.normal[1], id)
            XCTAssertFalse(def.unit.isEmpty, id)
            XCTAssertTrue(BiomarkerCatalog.categoryOrder.contains(def.category), "\(id) unknown category \(def.category)")
        }
    }

    func testEveryAliasResolvesToACatalogMarker() {
        for (alias, key) in BiomarkerCatalog.aliases {
            XCTAssertNotNil(BiomarkerCatalog.all[key], "alias \(alias) → missing marker \(key)")
        }
    }

    // MARK: - Evaluation boundaries (glucose: optimal 70-89, normal 70-99)

    func testEvaluateClassifiesAgainstRanges() {
        XCTAssertEqual(BiomarkerCatalog.evaluate("glucose", value: 80), .optimal)
        XCTAssertEqual(BiomarkerCatalog.evaluate("glucose", value: 89), .optimal)
        XCTAssertEqual(BiomarkerCatalog.evaluate("glucose", value: 95), .warning)
        XCTAssertEqual(BiomarkerCatalog.evaluate("glucose", value: 100), .high)
        XCTAssertEqual(BiomarkerCatalog.evaluate("glucose", value: 69), .low)
        XCTAssertEqual(BiomarkerCatalog.evaluate("glucose", value: nil), BiomarkerFlag.none)
        XCTAssertEqual(BiomarkerCatalog.evaluate("not_a_marker", value: 50), BiomarkerFlag.none)
    }

    // MARK: - Alias resolution

    func testAliasDirectAndNormalizedLookup() {
        XCTAssertEqual(BiomarkerCatalog.aliasToKey("Glucose Lvl", sex: "male"), "glucose")
        XCTAssertEqual(BiomarkerCatalog.aliasToKey("HEMOGLOBIN A1C", sex: "male"), "hba1c")
        XCTAssertEqual(BiomarkerCatalog.aliasToKey("glucose, fasting", sex: "male"), "glucose")
        XCTAssertNil(BiomarkerCatalog.aliasToKey("definitely not a marker", sex: "male"))
        XCTAssertNil(BiomarkerCatalog.aliasToKey("", sex: "male"))
    }

    func testAliasSexRemapping() {
        let male = BiomarkerCatalog.aliasToKey("HDL Cholesterol", sex: "male")
        let female = BiomarkerCatalog.aliasToKey("HDL Cholesterol", sex: "female")
        XCTAssertEqual(male, "hdl_m")
        XCTAssertEqual(female, "hdl_f")
    }

    func testSexRestrictedMarkerRejectedForOtherSex() {
        XCTAssertEqual(BiomarkerCatalog.aliasToKey("PSA", sex: "male"), "psa")
        XCTAssertNil(BiomarkerCatalog.aliasToKey("PSA", sex: "female"))
    }

    func testNormalizeNameStripsAndCollapses() {
        XCTAssertEqual(BiomarkerCatalog.normalizeName("  Glucose,   Fasting!  "), "glucose fasting")
        XCTAssertEqual(BiomarkerCatalog.normalizeName("Lymphocyte %"), "lymphocyte %")
        XCTAssertEqual(BiomarkerCatalog.normalizeName("Vitamin D (25-OH)"), "vitamin d (25-oh)")
    }

    func testApplicableFiltersBySex() {
        let male = BiomarkerCatalog.applicable(toSex: "male")
        let female = BiomarkerCatalog.applicable(toSex: "female")
        XCTAssertNotNil(male["psa"])
        XCTAssertNil(female["psa"])
        XCTAssertNotNil(female["progesterone_f"])
        XCTAssertNil(male["progesterone_f"])
        XCTAssertNotNil(male["glucose"])
        XCTAssertNotNil(female["glucose"])
    }
}
