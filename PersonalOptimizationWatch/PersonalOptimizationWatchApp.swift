import SwiftUI
import SwiftData
import os

@main
struct PersonalOptimizationWatchApp: App {
    let container: ModelContainer
    let persistenceMode: PersistenceMode

    init() {
        // Open the shared App Group store behind the same non-destructive
        // recovery ladder the phone uses. Replaces the previous `fatalError`:
        // the watch launches independently and can hit a mid-migration or
        // entitlement state the phone has not, so a failure degrades instead of
        // crashing on wrist-raise.
        let bootstrap = PersistenceBootstrap.makeAppContainer()
        container = bootstrap.container
        persistenceMode = bootstrap.mode

        // Seed only against a durable store. In recovery mode the store is a
        // throwaway; seeding it would write data that never persists.
        if bootstrap.mode.isDurable {
            let container = bootstrap.container
            Task { @MainActor in
                do {
                    try ScheduleSeed.seedIfNeeded(modelContext: container.mainContext)
                } catch {
                    Logger.schedule.error("Watch seed failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        } else {
            Logger.persistence.fault("Watch launching in recovery mode; skipping seed.")
        }

        // Activate the WC session and consume events from the phone side. Each
        // event posts userStateChanged so the watch's CharacterState and
        // complications can react in real time (mirroring iOS). WC writes no
        // store rows here, so it is safe in any persistence mode.
        WatchConnectivityService.shared.activateIfPossible()
        Task { @MainActor in
            for await event in WatchConnectivityService.shared.lastEventStream {
                NotificationCenter.default.post(name: .userStateChanged, object: event)
                _ = event
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
