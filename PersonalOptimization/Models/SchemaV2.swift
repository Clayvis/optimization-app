import Foundation
import SwiftData

/// SchemaV2 (M3.5). Additive only: no field renames, no deletions.
/// New entities: StreakCounter, WorkoutEvent, CompletionHistory, FreezeApplication.
/// New UserProfile fields: sickDayActiveUntil, travelModeActiveUntil.
enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            UserProfile.self,
            ScheduleBlock.self,
            DailyLog.self,
            LiftSession.self,
            LiftExercise.self,
            LiftSet.self,
            BasketballSession.self,
            SwimSession.self,
            LabDraw.self,
            WearableEntry.self,
            ProtocolEntry.self,
            PomodoroSession.self,
            AdminTask.self,
            LearningStreak.self,
            CharacterStateLog.self,
            StreakCounter.self,
            WorkoutEvent.self,
            CompletionHistory.self,
            FreezeApplication.self
        ]
    }
}

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self),
            .lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self),
            .lightweight(fromVersion: SchemaV3.self, toVersion: SchemaV4.self),
            .lightweight(fromVersion: SchemaV4.self, toVersion: SchemaV5.self)
        ]
    }
}
