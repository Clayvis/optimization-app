import XCTest
@testable import PersonalOptimization

@MainActor
final class MascotVariantTests: XCTestCase {

    func test_assetName_ninja_male_returns_NinjaMale_prefix() {
        XCTAssertEqual(CharacterState.neutral.assetName(for: "ninja_male"), "NinjaMale_Neutral")
        XCTAssertEqual(CharacterState.urgent.assetName(for: "ninja_male"), "NinjaMale_Urgent")
    }

    func test_assetName_ninja_female_returns_NinjaFemale_prefix() {
        XCTAssertEqual(CharacterState.neutral.assetName(for: "ninja_female"), "NinjaFemale_Neutral")
        XCTAssertEqual(CharacterState.achievement.assetName(for: "ninja_female"), "NinjaFemale_Achievement")
    }

    func test_assetName_unknown_variant_falls_back_to_male() {
        XCTAssertEqual(CharacterState.neutral.assetName(for: "alien"), "NinjaMale_Neutral")
    }

    func test_legacy_assetName_uses_male_default() {
        XCTAssertEqual(CharacterState.neutral.assetName, "NinjaMale_Neutral")
    }

    func test_requiredAssetNames_count_is_eight() {
        XCTAssertEqual(MascotVariant.ninjaMale.requiredAssetNames.count, 8)
        XCTAssertEqual(MascotVariant.ninjaFemale.requiredAssetNames.count, 8)
    }

    func test_preflight_male_assets_present_in_bundle() {
        // The shipped app catalog has all 8 NinjaMale_* imagesets. Preflight returns nil.
        let missing = MascotVariantPreflight.missingAssets(for: .ninjaMale)
        XCTAssertNil(missing, "All NinjaMale_* assets must be present after Block 3 rename")
    }

    func test_preflight_female_assets_present_in_bundle() {
        let missing = MascotVariantPreflight.missingAssets(for: .ninjaFemale)
        XCTAssertNil(missing, "All NinjaFemale_* assets must be present in the bundle")
    }
}
