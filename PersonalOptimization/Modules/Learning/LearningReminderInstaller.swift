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
                                  timezone: TimeZone = TimeZone.current) async throws -> [String] {
        let times = LearningReminderScheduler.plannedTimes(scheduleFile: scheduleFile)
        let upcoming = LearningReminderScheduler.upcomingDates(from: times, startingFrom: asOf, timezone: timezone)
        var ids: [String] = []
        for (time, date) in upcoming {
            let id = try await notification.scheduleLearningReminder(
                at: date,
                moduleName: time.module.displayName,
                targetMinutes: time.module.defaultDailyTargetMinutes
            )
            ids.append(id)
        }
        Logger.app.info("Scheduled \(ids.count, privacy: .public) learning reminders")
        return ids
    }
}
