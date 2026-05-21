import Foundation
import SwiftData

/// SchemaV10 (pre-TestFlight P0/P1 hardening pass). Additive only.
///
/// New entities:
/// - TokenUsageEntry: per-day AI token spend tracking (P1-4).
/// - BackgroundTaskLog: diagnostic log of BG task runs (P2-4).
///
/// New UserProfile fields (default-valued, additive — lightweight migration
/// handles them in place): travelModeFollowsDevice, sleepWindowStartHHMM,
/// sleepWindowEndHHMM, dailyTokenBudget, apiKeyICloudSync, metadataBlob.
///
/// New DailyLog field (default-valued): metadataBlob (additive JSON bag for
/// future fields that don't deserve a schema bump on their own).
///
/// All fields default-valued; CloudKit-compatible. AppSchema.current now
/// points at SchemaV10 so phone, watch, and complications agree.
enum SchemaV10: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(10, 0, 0) }

    static var models: [any PersistentModel.Type] {
        SchemaV9.models + [
            TokenUsageEntry.self,
            BackgroundTaskLog.self
        ]
    }
}
