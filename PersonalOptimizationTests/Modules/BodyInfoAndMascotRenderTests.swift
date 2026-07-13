import XCTest
@testable import PersonalOptimization

/// Coverage for the body-info helpers and the mascot render-resolution layer
/// (PNG override vs built-in vector illustration).
@MainActor
final class BodyInfoAndMascotRenderTests: XCTestCase {

    // MARK: - Age math

    func test_age_computesWholeYears() {
        let cal = Calendar.current
        let dob = cal.date(from: DateComponents(year: 1995, month: 3, day: 14))!
        let reference = cal.date(from: DateComponents(year: 2026, month: 7, day: 13))!
        XCTAssertEqual(BodyInfoForm.age(dob: dob, at: reference), 31)
    }

    func test_age_birthdayNotYetReachedThisYear() {
        let cal = Calendar.current
        let dob = cal.date(from: DateComponents(year: 1995, month: 12, day: 25))!
        let reference = cal.date(from: DateComponents(year: 2026, month: 7, day: 13))!
        XCTAssertEqual(BodyInfoForm.age(dob: dob, at: reference), 30)
    }

    func test_age_unsetSentinelReturnsNil() {
        XCTAssertNil(BodyInfoForm.age(dob: .distantPast))
        XCTAssertNil(BodyInfoForm.age(dob: Date().addingTimeInterval(86_400)))
    }

    // MARK: - Mascot render resolution

    func test_assetExists_findsInstalledArtAndRejectsUnknown() {
        // The shipped MascotAssets.xcassets carries all 16 imagesets.
        XCTAssertTrue(MascotView.assetExists(named: "NinjaMale_Neutral"))
        XCTAssertTrue(MascotView.assetExists(named: "NinjaFemale_Achievement"))
        XCTAssertFalse(MascotView.assetExists(named: "NinjaRaccoon_Neutral"))
    }

    func test_palette_variantMapping() {
        // Raw profile values and asset-name prefixes both resolve.
        XCTAssertEqual(
            MascotIllustration.Palette.forVariant("ninja_female").accent,
            MascotIllustration.Palette.ninjaFemale.accent
        )
        XCTAssertEqual(
            MascotIllustration.Palette.forVariant("NinjaFemale_Proud").accent,
            MascotIllustration.Palette.ninjaFemale.accent
        )
        XCTAssertEqual(
            MascotIllustration.Palette.forVariant("ninja_male").accent,
            MascotIllustration.Palette.ninjaMale.accent
        )
        XCTAssertEqual(
            MascotIllustration.Palette.forVariant("unknown-variant").accent,
            MascotIllustration.Palette.ninjaMale.accent
        )
    }
}
