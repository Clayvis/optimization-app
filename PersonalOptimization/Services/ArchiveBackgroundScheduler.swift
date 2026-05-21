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
    static let taskIdentifier = BuildConfig.bgArchiveTaskID
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
    /// the next BG slot. Persists a BackgroundTaskLog row for Diagnostics.
    static func runRollupNow(modelContainer: ModelContainer) {
        Task { @MainActor in
            let context = modelContainer.mainContext
            let log = BackgroundTaskLog(taskId: "\(taskIdentifier).foreground")
            context.insert(log)
            try? context.save()

            let targets = try? ScheduleConfigLoader.loadCached().hydrationTargetsOz
            let service = ActivityArchiveService(
                modelContext: context,
                hydrationTargets: targets
            )
            do {
                let written = try service.backfill(maxDays: 30)
                log.status = "success"
                log.summary = "wrote \(written) archive rows"
                logger.info("Foreground rollup wrote \(written, privacy: .public) archive rows")
            } catch {
                log.status = "failure"
                log.errorMessage = error.localizedDescription
                logger.error("Foreground rollup failed: \(error.localizedDescription, privacy: .public)")
            }
            log.endedAt = Date()
            try? context.save()
            schedule()
        }
    }

    #if canImport(BackgroundTasks)
    private static func handle(task: BGTask, modelContainer: ModelContainer) {
        // Always reschedule next slot even if this run is killed early.
        schedule()
        let taskLog = BackgroundTaskLog(taskId: taskIdentifier)
        Task { @MainActor in
            modelContainer.mainContext.insert(taskLog)
            try? modelContainer.mainContext.save()
        }
        // iOS gives BG app-refresh tasks ~30s. Leave a 5s safety margin so
        // we mark "partial" and persist the log row before the OS yanks us.
        let expirationDeadline = Date().addingTimeInterval(25)
        task.expirationHandler = {
            logger.warning("BG archive task expired before completion")
            Task { @MainActor in
                taskLog.status = "expired"
                taskLog.endedAt = Date()
                try? modelContainer.mainContext.save()
            }
            task.setTaskCompleted(success: false)
        }
        Task { @MainActor in
            let context = modelContainer.mainContext
            let targets = try? ScheduleConfigLoader.loadCached().hydrationTargetsOz
            let service = ActivityArchiveService(
                modelContext: context,
                hydrationTargets: targets
            )
            do {
                let result = try service.backfillChunked(maxDays: 7) {
                    Date() < expirationDeadline
                }
                taskLog.status = result.completed ? "success" : "partial"
                taskLog.summary = "wrote \(result.written) archive rows, completed=\(result.completed)"
                logger.info("BG archive wrote \(result.written, privacy: .public) rows complete=\(result.completed, privacy: .public)")
                task.setTaskCompleted(success: result.completed)
            } catch {
                taskLog.status = "failure"
                taskLog.errorMessage = error.localizedDescription
                logger.error("BG archive failed: \(error.localizedDescription, privacy: .public)")
                task.setTaskCompleted(success: false)
            }
            taskLog.endedAt = Date()
            try? context.save()
        }
    }
    #endif
}
