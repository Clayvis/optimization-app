import Foundation
import os

struct LearningReminderTime: Sendable, Equatable {
    let module: LearningModule
    let isoWeekday: Int   // 1=Mon ... 7=Sun
    let hour: Int
    let minute: Int
}

@MainActor
enum LearningReminderScheduler {

    /// Builds the canonical week of reminder times: per-day Japanese times pulled from
    /// the bundled schedule, plus 16:00 weekday + 19:00 weekend Guitar slots.
    static func plannedTimes(scheduleFile: DefaultScheduleFile) -> [LearningReminderTime] {
        var result: [LearningReminderTime] = []

        for block in scheduleFile.blocks where block.module == "japanese" {
            let parts = block.startTime.split(separator: ":")
            guard parts.count == 2,
                  let h = Int(parts[0]),
                  let m = Int(parts[1]) else { continue }
            result.append(LearningReminderTime(module: .japanese, isoWeekday: block.dayOfWeek, hour: h, minute: m))
        }

        for weekday in 1...5 {
            result.append(LearningReminderTime(module: .guitar, isoWeekday: weekday, hour: 16, minute: 0))
        }
        for weekday in 6...7 {
            result.append(LearningReminderTime(module: .guitar, isoWeekday: weekday, hour: 19, minute: 0))
        }

        return result
    }

    /// Returns the next 7 days of dates derived from the planned times.
    static func upcomingDates(from plannedTimes: [LearningReminderTime],
                              startingFrom startDate: Date,
                              timezone: TimeZone) -> [(LearningReminderTime, Date)] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone

        var pairs: [(LearningReminderTime, Date)] = []

        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: startDate) else { continue }
            let weekdayRaw = cal.component(.weekday, from: day)
            let isoWeekday = weekdayRaw == 1 ? 7 : weekdayRaw - 1
            let dayStart = cal.startOfDay(for: day)

            for time in plannedTimes where time.isoWeekday == isoWeekday {
                var components = DateComponents()
                components.hour = time.hour
                components.minute = time.minute
                if let scheduled = cal.date(byAdding: components, to: dayStart),
                   scheduled > startDate {
                    pairs.append((time, scheduled))
                }
            }
        }
        return pairs
    }
}
