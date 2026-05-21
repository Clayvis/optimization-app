import SwiftUI
import SwiftData
import os

@main
struct PersonalOptimizationWatchApp: App {
    let container: ModelContainer = {
        let schema = AppSchema.schema()
        let config = ModelConfiguration(
            schema: schema,
            url: AppGroupContainer.storeURL() ?? URL.applicationSupportDirectory.appending(path: "default.store"),
            cloudKitDatabase: .private("iCloud.com.rawlins.PersonalOptimization")
        )
        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: AppSchema.migrationPlan,
                configurations: [config]
            )
            Task { @MainActor in
                do {
                    try ScheduleSeed.seedIfNeeded(modelContext: container.mainContext)
                } catch {
                    Logger.schedule.error("Watch seed failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            // Activate the WC session and consume events from the phone side.
            // Each event posts userStateChanged so the watch's CharacterState
            // and complications can react in real time (mirroring iOS).
            WatchConnectivityService.shared.activateIfPossible()
            Task { @MainActor in
                for await event in WatchConnectivityService.shared.lastEventStream {
                    NotificationCenter.default.post(name: .userStateChanged, object: event)
                    _ = event
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
