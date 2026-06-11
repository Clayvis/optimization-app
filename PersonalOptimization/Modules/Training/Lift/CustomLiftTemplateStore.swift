import Foundation

/// The user-defined lift template ("My Workout"). Persisted as JSON inside
/// `UserProfile.metadataBlob` (the additive escape hatch), so no SwiftData
/// schema bump is needed. First load seeds from the bundled "Lift B" shape so
/// the slot never opens empty; the user reshapes it in `CustomLiftEditorSheet`.
struct CustomLiftTemplateDTO: Codable, Sendable, Equatable {
    struct Exercise: Codable, Sendable, Equatable, Identifiable {
        var id: UUID = UUID()
        var name: String
        var targetSets: Int
        var targetReps: Int
    }

    var focus: String
    var exercises: [Exercise]
}

@MainActor
enum CustomLiftTemplateStore {
    /// Template name written to `LiftSession.template` and shown in nav titles.
    static let templateName = "My Workout"
    static let metadataKey = "customLiftTemplate"

    static func load(profile: UserProfile?) -> CustomLiftTemplateDTO? {
        profile?.metadata(metadataKey, as: CustomLiftTemplateDTO.self)
    }

    static func save(_ dto: CustomLiftTemplateDTO, profile: UserProfile) {
        profile.setMetadata(metadataKey, value: dto)
    }

    /// Returns the stored custom workout, seeding from `seed` (the bundled
    /// Lift B template) on first use.
    static func loadOrSeed(profile: UserProfile?, seed: LiftTemplate?) -> CustomLiftTemplateDTO {
        if let existing = load(profile: profile) {
            return existing
        }
        let dto = CustomLiftTemplateDTO(
            focus: seed?.focus ?? "your workout, your shape",
            exercises: (seed?.exercises ?? [])
                .sorted { $0.orderIndex < $1.orderIndex }
                .map { .init(name: $0.name, targetSets: $0.targetSets, targetReps: $0.targetReps) }
        )
        if let profile {
            save(dto, profile: profile)
        }
        return dto
    }

    /// `LiftTemplate` view of the DTO so LiftService and LiftSessionView keep
    /// one template code path for bundled and custom workouts.
    static func asLiftTemplate(_ dto: CustomLiftTemplateDTO) -> LiftTemplate {
        LiftTemplate(
            name: templateName,
            focus: dto.focus,
            exercises: dto.exercises.enumerated().map { index, entry in
                LiftTemplateExercise(
                    name: entry.name,
                    orderIndex: index,
                    targetSets: entry.targetSets,
                    targetReps: entry.targetReps
                )
            }
        )
    }
}
