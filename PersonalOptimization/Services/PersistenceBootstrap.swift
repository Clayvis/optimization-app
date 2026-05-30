import Foundation
import SwiftData
import os

/// Degradation state after attempting to open the persistent store.
///
/// The app must never hard-crash at launch because a SwiftData migration, a
/// CloudKit schema-sync race, store corruption, or a lost App Group
/// entitlement failed to open the on-disk store. `PersistenceBootstrap` walks
/// a non-destructive recovery ladder and reports which rung it landed on so
/// the UI can tell the user the truth.
///
/// Retention rule (CLAUDE.md): the on-disk store and its iCloud copy are NEVER
/// deleted by this ladder. Recovery degrades functionality, it does not
/// destroy data.
enum PersistenceMode: Equatable, Sendable {
    /// App Group store opened with schema migration and CloudKit private-DB
    /// sync. Full functionality.
    case full

    /// The on-disk store opened, but CloudKit sync is disabled for this launch
    /// (a CloudKit-specific open failure). Data on disk is intact; sync resumes
    /// on a future launch that opens cleanly. Non-blocking: the user keeps
    /// using the app and a banner explains sync is paused.
    case localOnly(reason: String)

    /// The on-disk store could not be opened at all. The app launches against
    /// a throwaway in-memory store so the user reaches a recovery screen
    /// instead of a crash. The on-disk store and iCloud copy are LEFT
    /// UNTOUCHED. Writes in this mode are not persisted, so the UI must steer
    /// the user to relaunch rather than enter data.
    case recovery(reason: String)

    /// True when the backing store is real and durable (writes persist). Used
    /// to gate the launch side-effect sequence: seeding, HealthKit sync, and
    /// CloudKit/observer wiring must not run against a throwaway store.
    var isDurable: Bool {
        switch self {
        case .full, .localOnly: return true
        case .recovery: return false
        }
    }
}

/// Opens the production `ModelContainer` behind a non-destructive recovery
/// ladder shared by every target (iOS app, Watch app). Replaces the bare
/// `fatalError` on store-open failure: a field build that previously launched
/// can hit a migration, CloudKit, or corruption failure and this degrades to a
/// local-only or recovery launch instead of crashing.
struct PersistenceBootstrap {
    let container: ModelContainer
    let mode: PersistenceMode

    /// Build the production container.
    ///
    /// Ladder (each rung is tried only if the previous one threw):
    /// 1. App Group store + migration + CloudKit private DB   -> `.full`
    /// 2. Same store + migration, CloudKit disabled           -> `.localOnly`
    /// 3. Throwaway in-memory store (on-disk store untouched) -> `.recovery`
    ///
    /// - Note: This ladder relies on `ModelContainer` surfacing open failures
    ///   as thrown errors (its documented behavior). The only `fatalError` in
    ///   this type lives in `inMemory(schema:logger:)` and is reachable solely
    ///   when the compiled `Schema` is structurally invalid: a build-time
    ///   programmer error that fails in dev/CI and cannot occur on a shipped
    ///   build that has launched before. No runtime data condition reaches it.
    @MainActor
    static func makeAppContainer(
        schema: Schema = AppSchema.schema(),
        migrationPlan: (any SchemaMigrationPlan.Type)? = AppSchema.migrationPlan,
        storeURL: URL? = AppGroupContainer.storeURL(),
        cloudKitContainerID: String = BuildConfig.cloudKitContainer,
        logger: Logger = Logger.persistence
    ) -> PersistenceBootstrap {
        let resolvedURL = storeURL
            ?? URL.applicationSupportDirectory.appending(path: "default.store")

        // Rung 1: full configuration (App Group + migration + CloudKit).
        do {
            let config = ModelConfiguration(
                schema: schema,
                url: resolvedURL,
                cloudKitDatabase: .private(cloudKitContainerID)
            )
            let container = try ModelContainer(
                for: schema,
                migrationPlan: migrationPlan,
                configurations: [config]
            )
            return PersistenceBootstrap(container: container, mode: .full)
        } catch {
            logger.fault("Store open failed (full+CloudKit): \(error.localizedDescription, privacy: .public). Retrying CloudKit-disabled.")
        }

        // Rung 2: same on-disk store + migration, CloudKit disabled. Isolates a
        // CloudKit schema-sync failure from a local migration/corruption
        // failure: if the bytes on disk are fine and only CloudKit is unhappy,
        // the app stays fully usable locally and resumes sync next clean launch.
        do {
            let config = ModelConfiguration(
                schema: schema,
                url: resolvedURL,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(
                for: schema,
                migrationPlan: migrationPlan,
                configurations: [config]
            )
            logger.warning("Opened store in local-only mode; CloudKit sync paused this launch.")
            return PersistenceBootstrap(
                container: container,
                mode: .localOnly(reason: "iCloud sync is paused. Your data is saved on this device and will sync the next time you reopen the app.")
            )
        } catch {
            logger.fault("Store open failed (local-only): \(error.localizedDescription, privacy: .public). Falling back to in-memory recovery.")
        }

        // Rung 3: throwaway in-memory store. The on-disk store and its iCloud
        // copy are NOT touched (no delete, no migration write), so a future
        // launch can still recover them. Lets the app reach a recovery screen
        // instead of crashing.
        logger.fault("Launching in recovery mode (in-memory). On-disk store preserved, not opened.")
        let container = PersistenceBootstrap.inMemory(schema: schema, logger: logger)
        return PersistenceBootstrap(
            container: container,
            mode: .recovery(reason: "The database could not be opened this launch. Your saved data has not been changed. Please close the app fully and reopen it.")
        )
    }

    /// Build an in-memory container over the app schema (no disk, no CloudKit,
    /// no migration). Used for the recovery rung and by the test host.
    ///
    /// - Note: The single `fatalError` here is reachable only when the compiled
    ///   `Schema` is structurally invalid. With no disk IO, CloudKit, or
    ///   migration in play there is no runtime/data failure mode, so this is a
    ///   build-time error and crashing is the honest signal.
    @MainActor
    static func inMemory(
        schema: Schema = AppSchema.schema(),
        logger: Logger = Logger.persistence
    ) -> ModelContainer {
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            logger.fault("In-memory container failed; compiled Schema is invalid: \(error.localizedDescription, privacy: .public)")
            fatalError("PersistenceBootstrap.inMemory: compiled Schema is invalid: \(error)")
        }
    }
}
