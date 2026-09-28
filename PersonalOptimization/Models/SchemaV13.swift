import SwiftData

/// Stable optional lift-session identity (`LiftSession.sessionID`) for linking
/// suggestions to real workouts. Existing rows keep nil; new sessions receive a
/// UUID on creation. V12's workout graph is frozen in SchemaV12.swift.
enum SchemaV13: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(13, 0, 0) }
    static var models: [any PersistentModel.Type] {
        let old = [ObjectIdentifier(SchemaV12.LiftSession.self),
                   ObjectIdentifier(SchemaV12.LiftExercise.self), ObjectIdentifier(SchemaV12.LiftSet.self)]
        return SchemaV12.models.filter { !old.contains(ObjectIdentifier($0)) } + [
            LiftSession.self,
            LiftExercise.self,
            LiftSet.self
        ]
    }
}
