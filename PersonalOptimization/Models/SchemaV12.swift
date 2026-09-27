import SwiftData

/// Body-composition scans and workout progression/RIR fields.
/// All production targets use AppSchema. Keep historical Lift models out of
/// this schema so already-upgraded V12 stores retain their released checksum.
enum SchemaV12: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(12, 0, 0) }
    static var models: [any PersistentModel.Type] {
        let historicalLiftModels = [
            ObjectIdentifier(SchemaV11.LiftSession.self),
            ObjectIdentifier(SchemaV11.LiftExercise.self),
            ObjectIdentifier(SchemaV11.LiftSet.self)
        ]
        return SchemaV11.models.filter { !historicalLiftModels.contains(ObjectIdentifier($0)) } + [
            LiftSession.self,
            LiftExercise.self,
            LiftSet.self,
            InBodyScan.self
        ]
    }
}
