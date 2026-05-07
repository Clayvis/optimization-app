import Foundation
import SwiftData

/// SchemaV8 (Tier 2 V1 opportunities pass). Additive only.
///
/// New entities:
/// - Achievement (Opp 7: granular named wins, sibling to MilestoneUnlock)
///
/// All new fields default-valued; CloudKit-compatible.
enum SchemaV8: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(8, 0, 0) }

    static var models: [any PersistentModel.Type] {
        SchemaV7.models + [
            Achievement.self
        ]
    }
}
