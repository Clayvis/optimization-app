import Foundation
import SwiftData

/// SchemaV3 (M3.6). Additive only.
///
/// New entities:
/// - HealthKitWriteFailure (Block 1: persisted record of HK write failures)
/// - HydrationEntry (Block 3: per-bottle log with beverage type)
/// - CoachInsight (Block 4: cached daily Claude insight)
///
/// New fields on existing models:
/// - UserProfile.motivationStyle, customStylePrompt, achillesCheckInEnabled,
///   onboardingCompleted (M4 placeholder), aiQuotesEnabled
/// - ScheduleBlock.isCustom (Block 2)
/// - LiftExercise.isCustom (Block 3)
enum SchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        SchemaV2.models + [
            HealthKitWriteFailure.self,
            HydrationEntry.self,
            CoachInsight.self
        ]
    }
}
