import Foundation
import SwiftData
@testable import PersonalOptimization

/// In-memory migration harness for SwiftData schema upgrades.
///
/// Pattern: open a file-backed store at the seed schema, seed rows, close,
/// reopen at the target schema with AppMigrationPlan, and let the harness
/// caller fetch the migrated rows for assertions.
///
/// Why file-backed: SwiftData migrations re-open the persistent store, and
/// `isStoredInMemoryOnly` containers don't survive a re-open. The harness
/// uses a temp directory and cleans up via `cleanup(at:)` after the test
/// finishes.
@MainActor
enum SchemaMigrationTestHarness {

    /// Opens a file-backed container at `seedSchema`, runs `seed`, then
    /// reopens at `targetSchema` with the AppMigrationPlan applied. Returns
    /// the migrated container plus the temp URL so the caller can clean up.
    static func migrate<Seed: VersionedSchema, Target: VersionedSchema>(
        seedAt seedSchema: Seed.Type,
        target targetSchema: Target.Type,
        seed: (ModelContext) throws -> Void
    ) throws -> (ModelContainer, URL) {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-test-\(UUID().uuidString).store")

        // Open at seed schema, write the rows, close (let go of reference).
        do {
            let initialSchema = Schema(versionedSchema: seedSchema)
            let initialConfig = ModelConfiguration(schema: initialSchema, url: tempURL)
            let initial = try ModelContainer(for: initialSchema, configurations: [initialConfig])
            try seed(initial.mainContext)
            try initial.mainContext.save()
        }

        // Reopen at the target schema with the migration plan.
        let target = Schema(versionedSchema: targetSchema)
        let migratedConfig = ModelConfiguration(schema: target, url: tempURL)
        let migrated = try ModelContainer(
            for: target,
            migrationPlan: AppMigrationPlan.self,
            configurations: [migratedConfig]
        )
        return (migrated, tempURL)
    }

    static func cleanup(at url: URL) {
        try? FileManager.default.removeItem(at: url)
        // SwiftData also writes auxiliary files; remove the directory parent
        // entries that match the base name.
        let dir = url.deletingLastPathComponent()
        let base = url.lastPathComponent
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            for name in contents where name.hasPrefix(base) {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
            }
        }
    }
}
