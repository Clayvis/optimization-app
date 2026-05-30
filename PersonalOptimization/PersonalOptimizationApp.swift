import SwiftUI
import SwiftData
import os

@main
struct PersonalOptimizationApp: App {
    /// True when the process is hosted by the XCTest runner. Set so app launch
    /// can skip CloudKit, HealthKit, BG-task registration, and watch bridge
    /// initialization. Those modules touch system-services that fail or stall
    /// under XCTest, and the unit tests stub their dependencies directly anyway.
    private static let isRunningTests: Bool =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    let container: ModelContainer

    /// Which rung the persistent store opened on. Drives both the launch
    /// side-effect gating below and the RootView banner / recovery screen.
    let persistenceMode: PersistenceMode

    init() {
        // Tests build their own services against an in-memory container and
        // must not touch CloudKit/HealthKit/BG tasks/the watch bridge.
        if PersonalOptimizationApp.isRunningTests {
            container = PersistenceBootstrap.inMemory()
            persistenceMode = .full
            return
        }

        // Open the store behind the non-destructive recovery ladder. This
        // replaces the previous `fatalError` on store-open failure: a migration,
        // CloudKit, corruption, or App Group entitlement failure now degrades to
        // a local-only or recovery launch instead of crashing.
        let bootstrap = PersistenceBootstrap.makeAppContainer()
        container = bootstrap.container
        persistenceMode = bootstrap.mode

        // Run the full launch sequence only against a durable store. In recovery
        // mode the store is a throwaway in-memory one; seeding, HealthKit sync,
        // and CloudKit/observer wiring would write into it and mask the failure,
        // so skip them and let RootView present the recovery screen.
        guard bootstrap.mode.isDurable else {
            Logger.app.fault("Launching in recovery mode; skipping seed, HealthKit, notifications, and watch-bridge wiring.")
            return
        }

        PersonalOptimizationApp.runLaunchSequence(container: bootstrap.container)
    }

    /// Side effects that previously lived in the container-init closure. Kept
    /// verbatim and in the same order; now invoked only when the store is
    /// durable. Runs on the main actor (App init is main-actor isolated).
    @MainActor
    private static func runLaunchSequence(container: ModelContainer) {
        // M4.2 T0a: Gate the bundled-schedule seed. New users (no profile yet,
        // or onboardingCompleted == false) should NOT get Clay's bundled
        // default_schedule.json (onboarding picks their schedule). Existing
        // users (onboardingCompleted == true) on a fresh device wait for
        // CloudKit to sync their data; seedIfNeeded is a stop-gap only if the
        // sync hasn't populated their schedule.
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
            // One-shot dedupe to repair any DailyLog rows accidentally created
            // with inconsistent timezone keys before DailyLogStore landed.
            // UserDefaults-gated, no-op on subsequent launches.
            DailyLogDedupeOnce.runIfNeeded(modelContext: context)
        }
        DevSecretsBootstrap.bootstrapIfNeeded()
        FirstLaunchTracker.shared.recordIfNeeded()
        // M4.2: one-shot keychain migration. Existing users get their API key
        // moved to the iCloud-synced item so it survives an uninstall +
        // reinstall. Idempotent.
        KeychainService.shared.migrateApiKeyToICloudSynced()
        ArchiveBackgroundScheduler.registerHandler(modelContainer: container)
        ArchiveBackgroundScheduler.runRollupNow(modelContainer: container)
        // M4.2: pull today's HealthKit data into DailyLog on launch. No-op when
        // HK isn't authorized; each fetch returns nil silently.
        Task { @MainActor in
            let service = HealthKitSyncService(modelContext: container.mainContext)
            _ = await service.syncToday()
        }
        // Wire the notification action handler + register categories so the
        // hydration quick-action buttons (8 / 16 / 24 / 32 oz, Skip) actually
        // surface on the lock screen and route taps into HydrationService
        // instead of silently dismissing.
        NotificationActionHandler.shared.attach(modelContainer: container)
        Task { @MainActor in
            do {
                _ = try await NotificationService.shared.register()
                // W1/W4: actually schedule the learning reminders. The installer
                // previously had zero call sites, so learning reminders never
                // fired. Stable per-behavior-per-day ids make this idempotent
                // across launches.
                await PersonalOptimizationApp.runLearningReminderInstall(container: container)
            } catch {
                Logger.app.warning("Notification register failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        // Activate phone↔watch bridge so the watch can push session events back
        // in real time. Cheap: the WC session activates async and is a no-op on
        // devices without a paired Watch.
        WatchConnectivityService.shared.activateIfPossible()
        // Consume the WC event stream. Each event fans out into a
        // `userStateChanged` notification (mascot + UI rederive). Workout events
        // also kick a HealthKit sync so today's DailyLog reflects what the watch
        // just finished.
        Task { @MainActor in
            for await event in WatchConnectivityService.shared.lastEventStream {
                NotificationCenter.default.post(name: .userStateChanged, object: event)
                switch event.kind {
                case .workoutStarted, .workoutEnded:
                    await HealthKitSyncService(modelContext: container.mainContext).syncToday()
                case .waterLogged:
                    // Force a HK sync so the daily aggregate refreshes with
                    // whatever the watch added. SwiftData rows arrive via
                    // CloudKit; this accelerates the visible state on the phone.
                    await HealthKitSyncService(modelContext: container.mainContext).syncToday()
                default:
                    break
                }
            }
        }
        // Wire HealthKit observer queries + background delivery so late-arriving
        // samples (Garmin, Strava, Withings) retroactively update past DailyLogs
        // and recompute streaks/character state.
        Task { @MainActor in
            await HealthKitObserverService.shared.startObserving(modelContainer: container)
        }
        // Subscribe to dailyLogsRecomputed so late-arriving samples refresh
        // persistent StreakCounter rows. CharacterStateService already
        // subscribes for its own state; this covers the rollup that doesn't have
        // an in-memory observable surface.
        ReactiveRecomputeService.shared.start(modelContainer: container)
    }

    /// W1/W4: schedule the next 7 days of learning reminders. Previously the
    /// installer had zero call sites, so learning reminders never fired. Stable
    /// notification ids make this idempotent across launches; history-based
    /// suppression cuts a redundant same-day nudge.
    @MainActor
    private static func runLearningReminderInstall(container: ModelContainer) async {
        do {
            let scheduleFile = try ScheduleSeed.loadDefaultScheduleFile()
            let context = container.mainContext
            let timezone = UserCalendar.timezone(modelContext: context)
            let history = context.fetchOrEmpty(FetchDescriptor<CompletionHistory>())
            _ = try await LearningReminderInstaller.scheduleNext7Days(
                notification: NotificationService.shared,
                scheduleFile: scheduleFile,
                asOf: Date(),
                timezone: timezone,
                history: history
            )
        } catch {
            Logger.app.warning("Learning reminder install failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(persistenceMode: persistenceMode)
        }
        .modelContainer(container)
    }
}
