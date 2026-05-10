import SwiftUI
import SwiftData
import os

@main
struct PersonalOptimizationWatchApp: App {
    let container: ModelContainer = {
        let schema = Schema(versionedSchema: SchemaV3.self)
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
                    Logger.schedule.error("Watch seed failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            return container
        } catch {
            Logger.persistence.fault("Watch ModelContainer init failed: \(error.localizedDescription, privacy: .public)")
            fatalError("Watch ModelContainer init failed: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
