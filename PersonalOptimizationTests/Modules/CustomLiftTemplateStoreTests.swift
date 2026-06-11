import XCTest
@testable import PersonalOptimization

/// Round-trip and seeding behavior for the "My Workout" custom lift template
/// stored in UserProfile.metadataBlob. UserProfile instances work detached
/// from a container for plain property access, so no SwiftData store needed.
@MainActor
final class CustomLiftTemplateStoreTests: XCTestCase {

    private func seedTemplate() -> LiftTemplate {
        LiftTemplate(name: "Lift B", focus: "variation", exercises: [
            LiftTemplateExercise(name: "Hip Thrust", orderIndex: 4, targetSets: 3, targetReps: 10),
            LiftTemplateExercise(name: "Front Squat", orderIndex: 0, targetSets: 4, targetReps: 5)
        ])
    }

    func test_loadOrSeed_firstUse_seedsFromTemplateInOrderAndPersists() {
        let profile = UserProfile(name: "t")
        let dto = CustomLiftTemplateStore.loadOrSeed(profile: profile, seed: seedTemplate())
        XCTAssertEqual(dto.exercises.map(\.name), ["Front Squat", "Hip Thrust"])
        XCTAssertEqual(dto.focus, "variation")

        let reloaded = CustomLiftTemplateStore.load(profile: profile)
        XCTAssertEqual(reloaded, dto)
    }

    func test_loadOrSeed_nilSeed_returnsEmptyTemplate() {
        let profile = UserProfile(name: "t")
        let dto = CustomLiftTemplateStore.loadOrSeed(profile: profile, seed: nil)
        XCTAssertTrue(dto.exercises.isEmpty)
    }

    func test_save_overwritesPriorTemplate() {
        let profile = UserProfile(name: "t")
        var dto = CustomLiftTemplateDTO(focus: "upper", exercises: [
            .init(name: "Curl", targetSets: 3, targetReps: 12)
        ])
        CustomLiftTemplateStore.save(dto, profile: profile)
        dto.exercises[0].targetReps = 15
        CustomLiftTemplateStore.save(dto, profile: profile)
        XCTAssertEqual(CustomLiftTemplateStore.load(profile: profile)?.exercises.first?.targetReps, 15)
    }

    func test_save_coexistsWithOtherMetadataKeys() {
        let profile = UserProfile(name: "t")
        profile.setMetadata("other", value: "kept")
        CustomLiftTemplateStore.save(
            CustomLiftTemplateDTO(focus: "f", exercises: [.init(name: "Row", targetSets: 3, targetReps: 8)]),
            profile: profile
        )
        XCTAssertEqual(profile.metadata("other", as: String.self), "kept")
        XCTAssertNotNil(CustomLiftTemplateStore.load(profile: profile))
    }

    func test_asLiftTemplate_reindexesOrderAndKeepsTargets() {
        let dto = CustomLiftTemplateDTO(focus: "f", exercises: [
            .init(name: "A", targetSets: 4, targetReps: 5),
            .init(name: "B", targetSets: 3, targetReps: 8)
        ])
        let template = CustomLiftTemplateStore.asLiftTemplate(dto)
        XCTAssertEqual(template.name, CustomLiftTemplateStore.templateName)
        XCTAssertEqual(template.exercises.map(\.orderIndex), [0, 1])
        XCTAssertEqual(template.exercises.first?.targetSets, 4)
        XCTAssertEqual(template.exercises.last?.targetReps, 8)
    }
}
