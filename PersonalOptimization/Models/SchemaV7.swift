import Foundation
import SwiftData

/// SchemaV7 (V1 opportunities pass — landed pre-TestFlight). Additive only.
///
/// New entities:
/// - CoachMemory (Opp 6: user-supplied context the Coach carries across days)
/// - LapseEvent (Opp 4: lapse detection ledger)
/// - MilestoneUnlock (Opp 2: which milestones the user has crossed)
///
/// New fields on existing models:
/// - UserProfile partner-pairing scaffold (Opp 1)
/// - UserProfile recovery-override tracking (Opps 3, 4)
///
/// All new fields default-valued; CloudKit-compatible (no @Attribute(.unique)).
enum SchemaV7: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(7, 0, 0) }

    static var models: [any PersistentModel.Type] {
        SchemaV6.models + [
            CoachMemory.self,
            LapseEvent.self,
            MilestoneUnlock.self
        ]
    }
}
