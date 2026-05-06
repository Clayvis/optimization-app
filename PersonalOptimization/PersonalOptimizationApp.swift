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
            return try ModelContainer(for: schema, configurations: [config])
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
