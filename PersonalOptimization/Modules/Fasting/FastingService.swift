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
    case alreadyFasting

    var errorDescription: String? {
        switch self {
        case .noActiveFast: return "No active fast to end"
        case .alreadyFasting: return "A fast is already in progress"
        }
    }
}

@MainActor
final class FastingService {
    private let modelContext: ModelContext
    private let timezone: TimeZone
    private let defaults: FastingDefaults
    private let logger = Logger.app

    init(modelContext: ModelContext, timezone: TimeZone = TimeZone.current, defaults: FastingDefaults) {
        self.modelContext = modelContext
        self.timezone = timezone
        self.defaults = defaults
    }

    /// Gregorian calendar pinned to the user's timezone. Use for day arithmetic
    /// so adding/subtracting a day crosses DST correctly (a calendar day can be
    /// 23 or 25 hours), unlike a raw 86400-second offset.
    private var userCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        return cal
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
        let yesterday = userCalendar.date(byAdding: .day, value: -1, to: date) ?? date
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
        let tomorrow = userCalendar.date(byAdding: .day, value: 1, to: date) ?? date
        return windowStartingOnDay(of: tomorrow, profile: profile)
    }

    /// Honors both scheduled windows and manual fasts. The user's explicit
    /// start/stop takes precedence over the scheduled state.
    func state(at date: Date, profile: UserProfile) -> FastingState {
        activeFastWindow(at: date, profile: profile) == nil ? .eating : .fasting
    }

    /// Time elapsed since the active fast started. Zero when not fasting.
    func elapsedFasting(at date: Date, profile: UserProfile) -> TimeInterval {
        guard let window = activeFastWindow(at: date, profile: profile) else { return 0 }
        return max(0, date.timeIntervalSince(window.start))
    }

    /// Time remaining in the active fast. Nil when not fasting. Manual fasts
    /// return nil because they have no scheduled end.
    func remainingInFast(at date: Date, profile: UserProfile) -> TimeInterval? {
        if openFastLog(asOf: date) != nil { return nil } // manual fast: no fixed end
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

    /// True when an in-progress fast (scheduled or manual) is recorded on a
    /// recent DailyLog (`fastStart` set, `fastEnd` nil). Looks at today and
    /// yesterday so a fast started before midnight stays endable in the
    /// morning.
    func hasManualFastInProgress(asOf date: Date = Date()) -> Bool {
        return openFastLog(asOf: date) != nil
    }

    /// Most-recent DailyLog with an open fast (fastStart set, fastEnd nil).
    /// Looks at today + yesterday so a JST-evening start is endable in the AM.
    private func openFastLog(asOf date: Date) -> DailyLog? {
        if let today = currentDailyLog(for: date),
           today.fastStart != nil, today.fastEnd == nil {
            return today
        }
        let prior = userCalendar.date(byAdding: .day, value: -1, to: date) ?? date
        if let yesterday = currentDailyLog(for: prior),
           yesterday.fastStart != nil, yesterday.fastEnd == nil {
            return yesterday
        }
        return nil
    }

    /// Returns the active fast considering both the scheduled window and any
    /// in-progress manual entry. Manual fasts override the scheduled state so
    /// the user's explicit action is authoritative. Spans midnight by checking
    /// the previous day's log too.
    ///
    /// Also honors explicit "I'm done" intent: if the relevant day's DailyLog
    /// has `fastEnd` set, no fast is active even if the scheduled window
    /// boundary hasn't arrived yet. Without this, manually ending a fast
    /// during the scheduled window would silently re-mark you as fasting.
    func activeFastWindow(at date: Date, profile: UserProfile) -> FastWindow? {
        if let log = openFastLog(asOf: date), let start = log.fastStart {
            return FastWindow(start: start, end: date.addingTimeInterval(3600), label: "manual")
        }
        if let scheduled = currentWindow(at: date, profile: profile) {
            // The day this scheduled window started; that's where the
            // corresponding DailyLog row lives.
            let day = currentDailyLog(for: scheduled.start)
            if let day, day.fastEnd != nil {
                return nil
            }
            return scheduled
        }
        return nil
    }

    /// Manually starts a fast right now. Idempotent: throws `alreadyFasting`
    /// when one is already open.
    @discardableResult
    func startManualFast(at date: Date = Date(), profile: UserProfile) throws -> DailyLog {
        if hasManualFastInProgress(asOf: date) {
            throw FastingError.alreadyFasting
        }
        // Also block when the user is inside a scheduled window that has not
        // been closed; the existing scheduled path covers that case.
        if let scheduled = currentWindow(at: date, profile: profile),
           let log = upsertDailyLog(for: scheduled.start) as DailyLog?,
           log.fastStart != nil, log.fastEnd == nil {
            throw FastingError.alreadyFasting
        }
        let log = upsertDailyLog(for: date)
        log.fastStart = date
        log.fastEnd = nil
        log.fastBrokeEarly = false
        log.fastBreakReason = nil
        try modelContext.save()
        logger.info("Manual fast started at \(date, privacy: .public)")
        return log
    }

    /// Manually ends the open fast right now. Records reason when supplied.
    /// Throws `noActiveFast` when nothing is open. Looks at today and
    /// yesterday so an evening-start fast is endable in the morning.
    @discardableResult
    func endManualFast(at date: Date = Date(), reason: String? = nil) throws -> DailyLog {
        guard let log = openFastLog(asOf: date) else {
            throw FastingError.noActiveFast
        }
        log.fastEnd = date
        if let reason, !reason.isEmpty {
            log.fastBrokeEarly = true
            log.fastBreakReason = reason
        }
        try modelContext.save()
        CompletionHistoryWriter.record(domain: .fasting, at: date, modelContext: modelContext)
        logger.info("Manual fast ended at \(date, privacy: .public) reason=\(reason ?? "nil", privacy: .public)")
        #if os(iOS)
        FastingLiveActivityController.dismissAllSync()
        #endif
        return log
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

    private func currentDailyLog(for date: Date) -> DailyLog? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        let day = cal.startOfDay(for: date)
        let descriptor = FetchDescriptor<DailyLog>(
            predicate: #Predicate<DailyLog> { $0.date == day }
        )
        return modelContext.fetchFirstOrNil(descriptor)
    }

    private func upsertDailyLog(for date: Date) -> DailyLog {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        return DailyLogStore(modelContext: modelContext, calendar: cal).upsert(for: date)
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
