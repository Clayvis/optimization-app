import SwiftUI
import SwiftData
import os

@main
struct PersonalOptimizationApp: App {
    let container: ModelContainer = {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.com.rawlins.PersonalOptimization")
        )
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            Task { @MainActor in
                do {
                    try ScheduleSeed.seedIfNeeded(modelContext: container.mainContext)
                } catch {
                    Logger.schedule.error("Seed failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            return container
        } catch {
            Logger.persistence.fault("ModelContainer init failed: \(error.localizedDescription, privacy: .public)")
            fatalError("ModelContainer init failed: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            Text("PersonalOptimization")
        }
        .modelContainer(container)
    }
}
