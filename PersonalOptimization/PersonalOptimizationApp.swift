import SwiftUI
import SwiftData
import os

@main
struct PersonalOptimizationApp: App {
    let container: ModelContainer = {
        let schema = Schema(versionedSchema: SchemaV5.self)
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.com.rawlins.PersonalOptimization")
        )
        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: AppMigrationPlan.self,
                configurations: [config]
            )
            Task { @MainActor in
                do {
                    try ScheduleSeed.seedIfNeeded(modelContext: container.mainContext)
                } catch {
                    Logger.schedule.error("Seed failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            DevSecretsBootstrap.bootstrapIfNeeded()
            ArchiveBackgroundScheduler.registerHandler(modelContainer: container)
            ArchiveBackgroundScheduler.runRollupNow(modelContainer: container)
            return container
        } catch {
            Logger.persistence.fault("ModelContainer init failed: \(error.localizedDescription, privacy: .public)")
            fatalError("ModelContainer init failed: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
