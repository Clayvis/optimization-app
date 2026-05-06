import Foundation
import SwiftData

/// SchemaV4 (M3.7). Additive only.
///
/// New entities:
/// - ActivityArchive (Block 1: daily rolled-up metrics)
/// - DetectedPattern (Block 1: pattern-detector output)
/// - PrescribedWorkout (Block 2: Coach v2 daily prescription)
/// - ScheduleSuggestion (Block 2: Coach v2 schedule optimization inbox)
/// - WeeklyProgram (Block 2: Coach v2 weekly programming pass)
///
/// New fields on existing models:
/// - UserProfile.mascotVariant (Block 3)
/// - UserProfile.primaryGoal, secondaryGoalsCSV, equipmentAccess,
///   weeklyTrainingTargetSessions, restrictionsCSV (Block 4)
///
/// All additions have defaults so SwiftData lightweight migration applies.
enum SchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    static var models: [any PersistentModel.Type] {
        SchemaV3.models + [
            ActivityArchive.self,
            DetectedPattern.self,
            PrescribedWorkout.self,
            ScheduleSuggestion.self,
            WeeklyProgram.self
        ]
    }
}
