import Foundation
import SwiftData

/// SchemaV6 (M4). Additive only.
///
/// New entities:
/// - ImplementationIntention (Block 1: if-then habit plans)
/// - WeeklyReflection (Block 4: Sunday reflection rows)
///
/// All new fields default-valued; CloudKit-compatible (no @Attribute(.unique)).
/// Logical uniqueness on WeeklyReflection.weekStartDate enforced by service.
enum SchemaV6: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(6, 0, 0) }

    static var models: [any PersistentModel.Type] {
        SchemaV5.models + [
            ImplementationIntention.self,
            WeeklyReflection.self
        ]
    }
}
