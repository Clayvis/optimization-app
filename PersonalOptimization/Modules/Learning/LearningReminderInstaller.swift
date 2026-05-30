import Foundation
import os

@MainActor
enum LearningReminderInstaller {
    /// Schedules notifications for every upcoming time in the 7-day window via the
    /// app's NotificationService. iOS-only because UserNotifications scheduling is
    /// not present on the watch target's NotificationService surface yet.
    static func scheduleNext7Days(notification: NotificationService,
                                  scheduleFile: DefaultScheduleFile,
                                  asOf: Date = Date(),
                                  timezone: TimeZone = TimeZone.current,
                                  history: [CompletionHistory] = []) async throws -> [String] {
        let times = LearningReminderScheduler.plannedTimes(scheduleFile: scheduleFile)
        let upcoming = LearningReminderScheduler.upcomingDates(from: times, startingFrom: asOf, timezone: timezone)
        var ids: [String] = []
        for (time, date) in upcoming {
            // Design Principle 3 (suppress if logged): skip a reminder for any
            // day the learning domain is already satisfied. For future days the
            // history holds nothing, so only today's redundant nudge is cut.
            if AdaptiveNotificationTiming.shouldSuppressIfAlreadyLogged(
                domain: .learning, history: history, asOf: date, timezone: timezone) {
                continue
            }
            let id = try await notification.scheduleLearningReminder(
                at: date,
                moduleName: time.module.displayName,
                targetMinutes: time.module.defaultDailyTargetMinutes,
                timezone: timezone
            )
            ids.append(id)
        }
        Logger.app.info("Scheduled \(ids.count, privacy: .public) learning reminders")
        return ids
    }
}
