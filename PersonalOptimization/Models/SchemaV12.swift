import SwiftData

/// Additive body-composition scans; all production targets use AppSchema.
enum SchemaV12: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(12, 0, 0) }
    static var models: [any PersistentModel.Type] {
        SchemaV11.models + [
            InBodyScan.self
        ]
    }
}
