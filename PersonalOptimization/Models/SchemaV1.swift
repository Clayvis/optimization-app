import Foundation
import SwiftData

enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

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
            CharacterStateLog.self
        ]
    }
}
