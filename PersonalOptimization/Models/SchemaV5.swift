import Foundation
import SwiftData

/// SchemaV5 (M3.7 polish pass). Additive only.
///
/// New entities:
/// - CustomActivityTemplate (user-defined activity type)
/// - CustomActivitySession (one logged session against a template)
///
/// New fields on existing models:
/// - PrescribedWorkout.creativeTitle (with default "" so older rows decode cleanly)
///
/// Lightweight migration handles all of these (defaults present everywhere).
enum SchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }

    static var models: [any PersistentModel.Type] {
        SchemaV4.models + [
            CustomActivityTemplate.self,
            CustomActivitySession.self
        ]
    }
}
