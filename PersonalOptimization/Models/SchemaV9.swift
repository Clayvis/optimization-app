import Foundation
import SwiftData

/// SchemaV9 (M4.1, AI Schedule Optimizer). Additive only.
///
/// New entity:
/// - ScheduleGenerationRun (audit trail for AI-generated schedules)
///
/// New fields (lightweight migration, defaults supplied):
/// - ScheduleBlock: anchorEvent, anchorOffsetMinutes
/// - UserProfile: anchorEventsCSV, lastGeneratedAt
///
/// All new fields default-valued; CloudKit-compatible.
enum SchemaV9: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(9, 0, 0) }

    static var models: [any PersistentModel.Type] {
        SchemaV8.models + [
            ScheduleGenerationRun.self
        ]
    }
}
