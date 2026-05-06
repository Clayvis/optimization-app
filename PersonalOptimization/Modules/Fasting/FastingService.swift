import Foundation
import SwiftData
import os

enum FastingState: String, Sendable, Equatable {
    case fasting
    case eating
}

struct FastWindow: Sendable, Equatable {
    let start: Date
    let end: Date
    let label: String  // "training" | "other" | "all"
}

enum FastingError: LocalizedError {
    case noActiveFast

    var errorDescription: String? {
        switch self {
        case .noActiveFast: return "No active fast window to break"
        }
    }
}

@MainActor
final class FastingService {
    private let modelContext: ModelContext
    private let timezone: TimeZone
    private let defaults: FastingDefaults
    private let logger = Logger.app

    init(modelContext: ModelContext, timezone: TimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current, defaults: FastingDefaults) {
        self.modelContext = modelContext
        self.timezone = timezone
        self.defaults = defaults
    }

    /// Computes the fast window that begins on the day of `date` based on profile phase.
    func windowStartingOnDay(of date: Date, profile: UserProfile) -> FastWindow {
        let weekday = isoWeekday(for: date)
        let phase = profile.rolloutPhase

        let startTime: String
        let endTime: String
        let label: String

        if phase == 1 {
            if defaults.weeks_1_2.trainingDayNumbers.contains(weekday) {
                startTime = defaults.weeks_1_2.trainingDays.start
                endTime = defaults.weeks_1_2.trainingDays.end
                label = "training"
            } else {
                startTime = defaults.weeks_1_2.otherDays.start
                endTime = defaults.weeks_1_2.otherDays.end
                label = "other"
            }
        } else {
            startTime = defaults.weeks_3_plus.all.start
            endTime = defaults.weeks_3_plus.all.end
            label = "all"
        }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone

        let dayStart = cal.startOfDay(for: date)
        let startDateTime = applyTime(startTime, to: dayStart, calendar: cal)
        // The fast crosses midnight: end is on the next calendar day.
        let nextDay = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let endDateTime = applyTime(endTime, to: nextDay, calendar: cal)

        return FastWindow(start: startDateTime, end: endDateTime, label: label)
    }

    /// Returns the fast window currently in effect (containing `date`), if any.
    func currentWindow(at date: Date, profile: UserProfile) -> FastWindow? {
        let today = windowStartingOnDay(of: date, profile: profile)
        if (today.start...today.end).contains(date) {
            return today
        }
        let yesterday = date.addingTimeInterval(-86400)
        let prior = windowStartingOnDay(of: yesterday, profile: profile)
        if (prior.start...prior.end).contains(date) {
            return prior
        }
        return nil
    }

    /// Returns the next fast window starting strictly after `date`.
    func nextWindow(after date: Date, profile: UserProfile) -> FastWindow {
        let today = windowStartingOnDay(of: date, profile: profile)
        if today.start > date {
            return today
        }
        let tomorrow = date.addingTimeInterval(86400)
        return windowStartingOnDay(of: tomorrow, profile: profile)
    }

    func state(at date: Date, profile: UserProfile) -> FastingState {
        currentWindow(at: date, profile: profile) == nil ? .eating : .fasting
    }

    /// Time elapsed since the active fast started. Zero when not fasting.
    func elapsedFasting(at date: Date, profile: UserProfile) -> TimeInterval {
        guard let window = currentWindow(at: date, profile: profile) else { return 0 }
        return max(0, date.timeIntervalSince(window.start))
    }

    /// Time remaining in the active fast. Nil when not fasting.
    func remainingInFast(at date: Date, profile: UserProfile) -> TimeInterval? {
        guard let window = currentWindow(at: date, profile: profile) else { return nil }
        return max(0, window.end.timeIntervalSince(date))
    }

    /// Logs an early break of the current fast. Updates today's DailyLog.
    func logEarlyBreak(at date: Date, reason: String, profile: UserProfile) throws {
        guard let window = currentWindow(at: date, profile: profile) else {
            throw FastingError.noActiveFast
        }
        let log = upsertDailyLog(for: window.start)
        log.fastStart = window.start
        log.fastEnd = date
        log.fastBrokeEarly = true
        log.fastBreakReason = reason
        try modelContext.save()
        CompletionHistoryWriter.record(domain: .fasting, at: date, modelContext: modelContext)
        logger.info("Logged early fast break at \(date, privacy: .public), reason length=\(reason.count, privacy: .public)")
        #if os(iOS)
        FastingLiveActivityController.dismissAllSync()
        #endif
    }

    /// Records a successful fast end at the scheduled boundary.
    func logScheduledFastEnd(at date: Date, profile: UserProfile) throws {
        guard let window = currentWindow(at: date, profile: profile) else {
            throw FastingError.noActiveFast
        }
        let log = upsertDailyLog(for: window.start)
        log.fastStart = window.start
        log.fastEnd = window.end
        log.fastBrokeEarly = false
        try modelContext.save()
        CompletionHistoryWriter.record(domain: .fasting, at: date, modelContext: modelContext)
        #if os(iOS)
        FastingLiveActivityController.dismissAllSync()
        #endif
    }

    // MARK: - Helpers

    private func upsertDailyLog(for date: Date) -> DailyLog {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        let day = cal.startOfDay(for: date)

        let descriptor = FetchDescriptor<DailyLog>(
            predicate: #Predicate<DailyLog> { $0.date == day }
        )
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            return existing
        }
        let log = DailyLog(date: day)
        modelContext.insert(log)
        return log
    }

    private func isoWeekday(for date: Date) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        let raw = cal.component(.weekday, from: date)
        return raw == 1 ? 7 : raw - 1
    }

    private func applyTime(_ hhmm: String, to dayStart: Date, calendar: Calendar) -> Date {
        let parts = hhmm.split(separator: ":")
        let hour = Int(parts.first ?? "0") ?? 0
        let minute = parts.count >= 2 ? (Int(parts[1]) ?? 0) : 0
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        return calendar.date(byAdding: components, to: dayStart) ?? dayStart
    }
}
