import SwiftUI
import SwiftData
import os

@main
struct PersonalOptimizationApp: App {
    let container: ModelContainer = {
        let schema = Schema(versionedSchema: SchemaV9.self)
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
            // M4.2 T0a: Gate the bundled-schedule seed. New users (no profile
            // yet, or onboardingCompleted == false) should NOT get Clay's
            // bundled default_schedule.json — onboarding picks their schedule.
            // Existing users (onboardingCompleted == true) on a fresh device
            // wait for CloudKit to sync their data; seedIfNeeded is a stop-gap
            // only if the sync hasn't populated their schedule.
            Task { @MainActor in
                let context = container.mainContext
                let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first
                let onboardingComplete = profile?.onboardingCompleted ?? false
                guard onboardingComplete else {
                    Logger.schedule.info("Skipping auto-seed: new install awaits onboarding choice")
                    return
                }
                do {
                    try ScheduleSeed.seedIfNeeded(modelContext: context)
                } catch {
                    Logger.schedule.error("Seed failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            DevSecretsBootstrap.bootstrapIfNeeded()
            FirstLaunchTracker.shared.recordIfNeeded()
            ArchiveBackgroundScheduler.registerHandler(modelContainer: container)
            ArchiveBackgroundScheduler.runRollupNow(modelContainer: container)
            // Activate phone↔watch bridge so the watch can push session events
            // back in real time. Cheap: the WC session activates async and is
            // a no-op on devices without a paired Watch.
            WatchConnectivityService.shared.activateIfPossible()
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
