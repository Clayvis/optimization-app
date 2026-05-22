import SwiftUI
import SwiftData
import os

@main
struct PersonalOptimizationApp: App {
    /// True when the process is hosted by the XCTest runner. Set so app
    /// launch can skip CloudKit, HealthKit, BG-task registration, and watch
    /// bridge initialization — those modules touch system-services that fail
    /// or stall under XCTest and the unit tests stub their dependencies
    /// directly anyway.
    private static let isRunningTests: Bool =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    let container: ModelContainer = {
        let schema = AppSchema.schema()
        let config: ModelConfiguration = {
            if PersonalOptimizationApp.isRunningTests {
                return ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
            }
            return ModelConfiguration(
                schema: schema,
                url: AppGroupContainer.storeURL() ?? URL.applicationSupportDirectory.appending(path: "default.store"),
                cloudKitDatabase: .private(BuildConfig.cloudKitContainer)
            )
        }()
        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: AppSchema.migrationPlan,
                configurations: [config]
            )
            // Bail out of the rest of the launch sequence in tests. The unit
            // tests construct their own services with InMemoryContainer.
            if PersonalOptimizationApp.isRunningTests {
                return container
            }
            // M4.2 T0a: Gate the bundled-schedule seed. New users (no profile
            // yet, or onboardingCompleted == false) should NOT get Clay's
            // bundled default_schedule.json — onboarding picks their schedule.
            // Existing users (onboardingCompleted == true) on a fresh device
            // wait for CloudKit to sync their data; seedIfNeeded is a stop-gap
            // only if the sync hasn't populated their schedule.
            Task { @MainActor in
                let context = container.mainContext
                let profile = context.fetchFirstOrNil(FetchDescriptor<UserProfile>())
                let onboardingComplete = profile?.onboardingCompleted ?? false
                if onboardingComplete {
                    do {
                        try ScheduleSeed.seedIfNeeded(modelContext: context)
                    } catch {
                        Logger.schedule.error("Seed failed: \(error.localizedDescription, privacy: .public)")
                    }
                } else {
                    Logger.schedule.info("Skipping auto-seed: new install awaits onboarding choice")
                }
                // One-shot dedupe to repair any DailyLog rows accidentally
                // created with inconsistent timezone keys before DailyLogStore
                // landed. UserDefaults-gated, no-op on subsequent launches.
                DailyLogDedupeOnce.runIfNeeded(modelContext: context)
            }
            DevSecretsBootstrap.bootstrapIfNeeded()
            FirstLaunchTracker.shared.recordIfNeeded()
            // M4.2: one-shot keychain migration. Existing users get their
            // API key moved to the iCloud-synced item so it survives an
            // uninstall + reinstall. Idempotent.
            KeychainService.shared.migrateApiKeyToICloudSynced()
            ArchiveBackgroundScheduler.registerHandler(modelContainer: container)
            ArchiveBackgroundScheduler.runRollupNow(modelContainer: container)
            // M4.2: pull today's HealthKit data into DailyLog on launch.
            // No-op when HK isn't authorized; each fetch returns nil silently.
            Task { @MainActor in
                let service = HealthKitSyncService(modelContext: container.mainContext)
                _ = await service.syncToday()
            }
            // Wire the notification action handler + register categories
            // so the hydration quick-action buttons (8 / 16 / 24 / 32 oz,
            // Skip) actually surface on the lock screen and route taps into
            // HydrationService instead of silently dismissing.
            NotificationActionHandler.shared.attach(modelContainer: container)
            Task { @MainActor in
                do {
                    _ = try await NotificationService.shared.register()
                } catch {
                    Logger.app.warning("Notification register failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            // Activate phone↔watch bridge so the watch can push session events
            // back in real time. Cheap: the WC session activates async and is
            // a no-op on devices without a paired Watch.
            WatchConnectivityService.shared.activateIfPossible()
            // Consume the WC event stream. Each event fans out into a
            // `userStateChanged` notification (mascot + UI rederive). Workout
            // events also kick a HealthKit sync so today's DailyLog reflects
            // what the watch just finished.
            Task { @MainActor in
                for await event in WatchConnectivityService.shared.lastEventStream {
                    NotificationCenter.default.post(name: .userStateChanged, object: event)
                    switch event.kind {
                    case .workoutStarted, .workoutEnded:
                        await HealthKitSyncService(modelContext: container.mainContext).syncToday()
                    case .waterLogged:
                        // Force a HK sync so the daily aggregate refreshes
                        // with whatever the watch added. SwiftData rows
                        // arrive via CloudKit; this accelerates the visible
                        // state on the phone.
                        await HealthKitSyncService(modelContext: container.mainContext).syncToday()
                    default:
                        break
                    }
                }
            }
            // Wire HealthKit observer queries + background delivery so late-
            // arriving samples (Garmin, Strava, Withings) retroactively
            // update past DailyLogs and recompute streaks/character state.
            Task { @MainActor in
                await HealthKitObserverService.shared.startObserving(modelContainer: container)
            }
            // Subscribe to dailyLogsRecomputed so late-arriving samples
            // refresh persistent StreakCounter rows. CharacterStateService
            // already subscribes for its own state; this covers the rollup
            // that doesn't have an in-memory observable surface.
            ReactiveRecomputeService.shared.start(modelContainer: container)
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
