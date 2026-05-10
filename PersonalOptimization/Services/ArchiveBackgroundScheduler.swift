import Foundation
import SwiftData
import os
#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

/// Registers and schedules the daily activity-archive rollup as a
/// `BGAppRefreshTask`. Apple grants "best-effort" execution windows; the task
/// is opportunistic, so the app additionally calls `runRollupNow` on launch
/// and on scene foreground transitions to keep archives current even when
/// background slots don't fire.
///
/// Task identifier must also appear in Info.plist
/// `BGTaskSchedulerPermittedIdentifiers` (added via project.yml).
@MainActor
enum ArchiveBackgroundScheduler {
    static let taskIdentifier = "com.rawlins.PersonalOptimization.archiveRollup"
    private static let logger = Logger.coach

    /// Call from `application(_:didFinishLaunchingWithOptions:)` or the SwiftUI
    /// app `init`. Registers the BG task handler. Safe to call once per
    /// process; subsequent calls are a no-op.
    static func registerHandler(modelContainer: ModelContainer) {
        #if canImport(BackgroundTasks)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            handle(task: task, modelContainer: modelContainer)
        }
        logger.info("Registered BG archive task handler")
        #endif
    }

    /// Schedules the next BG run roughly 24 hours out. Apple decides the actual
    /// time window. Call once after a successful rollup so the next attempt is
    /// queued.
    static func schedule(after: TimeInterval = 60 * 60 * 22) {
        #if canImport(BackgroundTasks)
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: after)
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Scheduled archive task for \(request.earliestBeginDate?.description ?? "?", privacy: .public)")
        } catch {
            logger.warning("BG archive submit failed: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }

    /// Synchronous-immediate path used on launch/foreground when BG slots are
    /// unreliable. Catches up archives over the last 30 days, then schedules
    /// the next BG slot.
    static func runRollupNow(modelContainer: ModelContainer) {
        Task { @MainActor in
            let context = modelContainer.mainContext
            let targets = try? ScheduleConfigLoader.load().hydrationTargetsOz
            let service = ActivityArchiveService(
                modelContext: context,
                hydrationTargets: targets
            )
            do {
                let written = try service.backfill(maxDays: 30)
                logger.info("Foreground rollup wrote \(written, privacy: .public) archive rows")
            } catch {
                logger.error("Foreground rollup failed: \(error.localizedDescription, privacy: .public)")
            }
            schedule()
        }
    }

    #if canImport(BackgroundTasks)
    private static func handle(task: BGTask, modelContainer: ModelContainer) {
        // Always reschedule next slot even if this run is killed early.
        schedule()
        task.expirationHandler = {
            logger.warning("BG archive task expired before completion")
            task.setTaskCompleted(success: false)
        }
        Task { @MainActor in
            let context = modelContainer.mainContext
            let targets = try? ScheduleConfigLoader.load().hydrationTargetsOz
            let service = ActivityArchiveService(
                modelContext: context,
                hydrationTargets: targets
            )
            do {
                let written = try service.backfill(maxDays: 7)
                logger.info("BG archive wrote \(written, privacy: .public) rows")
                task.setTaskCompleted(success: true)
            } catch {
                logger.error("BG archive failed: \(error.localizedDescription, privacy: .public)")
                task.setTaskCompleted(success: false)
            }
        }
    }
    #endif
}
