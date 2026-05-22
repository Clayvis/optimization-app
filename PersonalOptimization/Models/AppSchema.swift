import Foundation
import SwiftData

/// Single source of truth for the SwiftData schema version used by every
/// production target (iOS app, Watch app, Watch Complications, App Intents,
/// background extensions). Updating `current` here is the only place that
/// needs to change when a new schema version is added.
///
/// Why this exists: three targets share a CloudKit container. If they declare
/// different schema versions, CloudKit will faithfully replicate records that
/// contain fields one target does not know about, and SwiftData has to decide
/// what to do. The safe answer is "do not let that happen". Funnel everything
/// through AppSchema and the compiler ensures parity.
enum AppSchema {
    /// The current versioned schema. Bump in one place when a new SchemaVN is
    /// added (and add its migration stage in AppMigrationPlan.stages).
    /// Note: the V11 schedule-re-haul (added anchor fields to UserProfile)
    /// did not introduce new entities, so it rides SchemaV10 — SwiftData's
    /// lightweight migration applies the new properties in place when the
    /// stored UserProfile rows are first read.
    static let current: any VersionedSchema.Type = SchemaV10.self

    /// Builds the Schema object for ModelContainer initialisation.
    static func schema() -> Schema {
        Schema(versionedSchema: current)
    }

    /// Migration plan used by every production ModelContainer.
    static var migrationPlan: any SchemaMigrationPlan.Type { AppMigrationPlan.self }
}
