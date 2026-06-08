import Foundation
import SwiftData
import os

enum StreakServiceError: LocalizedError {
    case noFreezesAvailable
    case alreadyCompletedToday

    var errorDescription: String? {
        switch self {
        case .noFreezesAvailable: return "No streak freezes left this month."
        case .alreadyCompletedToday: return "Today is already completed for this domain."
        }
    }
}

/// Per-domain streak engine with freeze inventory, monthly reset, and travel/sick day grace.
///
/// Day-completion source of truth (per domain), evaluated at recompute time:
/// - workout: a `WorkoutEvent.completed == true` row exists for that day
/// - fasting: `DailyLog.fastEnd != nil` for that day
/// - hydration: `DailyLog.waterOz` >= the day's hydration target minimum
/// - learning: `DailyLog.japaneseMinutes` >= 30 OR `DailyLog.guitarMinutes` >= 20
/// - protocolAdherence: every other domain that was scheduled for that day completed
///
/// Grace mechanisms (any of these also count a day as completed):
/// - `userProfile.sickDayActiveUntil` covers the day
/// - `userProfile.travelModeActiveUntil` covers the day
/// - a `FreezeApplication` exists for the domain on that day
///   (workout domain may instead have `WorkoutEvent` with `source == .freeze|.travel|.sickDay`)
///
/// Auto rest days (workout domain only): any ISO weekday with no training block in the
/// user's schedule template bridges the streak without incrementing it. A missed rest day
/// does not break the chain; a completed workout on a rest day still records a
/// `WorkoutEvent` but the streak count reflects scheduled-training-day adherence.
/// Falls back to Sat/Sun when the schedule is empty (e.g., in tests without seeded data).
@MainActor
final class StreakService {
    static let maxFreezesPerMonth: Int = 2

    private let modelContext: ModelContext
    private let timezone: TimeZone
    private let hydrationTargets: HydrationTargetsOz?
    private let logger = Logger.app

    init(modelContext: ModelContext,
         timezone: TimeZone = TimeZone.current,
         hydrationTargets: HydrationTargetsOz? = nil) {
        self.modelContext = modelContext
        self.timezone = timezone
        self.hydrationTargets = hydrationTargets
    }

    // MARK: - Public API

    /// Recomputes and persists the StreakCounter for `domain`.
    @discardableResult
    func recompute(domain: StreakDomain, asOf: Date = Date()) throws -> StreakCounter {
        let counter = upsertCounter(domain: domain)
        applyMonthlyResetIfNeeded(counter: counter, asOf: asOf)

        let history = try buildCompletionHistory(domain: domain, asOf: asOf)
        let cal = jstCalendar()
        let today = cal.startOfDay(for: asOf)
        let restDays = autoRestDays(domain: domain)

        var current = 0
        if history[today] == true { current = 1 }
        // Today is in-progress: a missed today doesn't break the chain. Past days must be
        // either completed or auto-rest (weekend for workout) to keep the chain alive.
        var cursor = cal.date(byAdding: .day, value: -1, to: today) ?? today
        let maxLookback = 730
        for _ in 0..<maxLookback {
            if history[cursor] == true {
                current += 1
            } else if restDays.contains(isoWeekday(for: cursor)) {
                // rest day bridges the streak without incrementing
            } else {
                break
            }
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }

        let longest = computeLongest(history: history, restDays: restDays, calendar: cal)
        let lastCompleted = mostRecentCompletedDay(history: history)

        counter.currentStreak = current
        counter.longestStreak = max(counter.longestStreak, longest)
        counter.lastCompletedDate = lastCompleted
        try modelContext.save()
        logger.info("Streak \(domain.rawValue, privacy: .public) current=\(current, privacy: .public) longest=\(counter.longestStreak, privacy: .public)")
        return counter
    }

    /// Public read of the completed-day set for `domain` (start-of-day keys in
    /// the user's calendar). Reuses the exact completion rules `recompute` uses
    /// so instrumentation (EngagementMetricsService) never drifts from the
    /// streak engine. Pure read; does not mutate or persist.
    func completedDays(domain: StreakDomain, asOf: Date = Date()) throws -> Set<Date> {
        let history = try buildCompletionHistory(domain: domain, asOf: asOf)
        return Set(history.compactMap { $0.value ? $0.key : nil })
    }

    /// Spends one freeze on `domain` to mark today completed.
    @discardableResult
    func applyFreeze(domain: StreakDomain, asOf: Date = Date()) throws -> StreakCounter {
        let counter = upsertCounter(domain: domain)
        applyMonthlyResetIfNeeded(counter: counter, asOf: asOf)
        guard counter.freezesAvailable > 0 else {
            throw StreakServiceError.noFreezesAvailable
        }
        let cal = jstCalendar()
        let today = cal.startOfDay(for: asOf)

        if domain == .workout {
            // For workouts use the WorkoutEvent ledger so character/master metric also see it.
            modelContext.insert(WorkoutEvent(date: today, completed: true, source: .freeze))
        } else {
            modelContext.insert(FreezeApplication(domain: domain, date: today))
        }

        counter.freezesAvailable -= 1
        counter.freezesUsedThisMonth += 1
        try modelContext.save()
        return try recompute(domain: domain, asOf: asOf)
    }

    /// Resets the per-month freeze counter when the calendar month changes.
    /// Idempotent within the same month.
    func resetMonthlyFreezes(asOf: Date = Date()) throws {
        let cal = jstCalendar()
        let monthAnchor = cal.date(from: cal.dateComponents([.year, .month], from: asOf)) ?? asOf
        for domain in StreakDomain.allCases {
            let counter = upsertCounter(domain: domain)
            if counter.freezeMonthAnchor != monthAnchor {
                counter.freezesAvailable = StreakService.maxFreezesPerMonth
                counter.freezesUsedThisMonth = 0
                counter.freezeMonthAnchor = monthAnchor
            }
        }
        try modelContext.save()
    }

    /// Marks today's WorkoutEvent ledger so all the workout-related domains read as completed.
    func recordWorkoutLedger(date: Date, source: WorkoutEventSource, sourceID: UUID? = nil) throws {
        let cal = jstCalendar()
        let day = cal.startOfDay(for: date)
        let event = WorkoutEvent(date: day, completed: true, source: source, sourceID: sourceID)
        modelContext.insert(event)
        try modelContext.save()
    }

    /// Activates sick day for today: writes a WorkoutEvent (source=sickDay) plus
    /// FreezeApplication rows for non-workout domains, and sets profile.sickDayActiveUntil
    /// so banners and mascot reason can reflect the state.
    func activateSickDay(asOf: Date = Date()) throws {
        let cal = jstCalendar()
        let day = cal.startOfDay(for: asOf)
        let endOfDay = cal.date(byAdding: DateComponents(day: 1, second: -1), to: day) ?? asOf

        try writeGraceLedger(day: day, source: .sickDay)

        let profile = ensureProfile()
        profile.sickDayActiveUntil = endOfDay
        try modelContext.save()
    }

    /// Activates travel mode covering today and the next `days - 1` calendar days.
    func activateTravelMode(days: Int, asOf: Date = Date()) throws {
        precondition(days >= 1, "Travel mode must cover at least one day")
        let cal = jstCalendar()
        let today = cal.startOfDay(for: asOf)
        var cursor = today
        for _ in 0..<days {
            try writeGraceLedger(day: cursor, source: .travel)
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        let lastCovered = cal.date(byAdding: .day, value: days - 1, to: today) ?? today
        let endOfWindow = cal.date(byAdding: DateComponents(day: 1, second: -1), to: lastCovered) ?? lastCovered

        let profile = ensureProfile()
        profile.travelModeActiveUntil = endOfWindow
        try modelContext.save()
    }

    /// Clears travel mode immediately. Existing ledger entries remain (they preserved
    /// past streaks honestly via the source enum).
    func deactivateTravelMode() throws {
        let profile = ensureProfile()
        profile.travelModeActiveUntil = nil
        try modelContext.save()
    }

    private func writeGraceLedger(day: Date, source: WorkoutEventSource) throws {
        // Workout domain: write WorkoutEvent. Avoid duplicates same day same source.
        let dayConst = day
        let sourceRaw = source.rawValue
        let workoutDescriptor = FetchDescriptor<WorkoutEvent>(
            predicate: #Predicate<WorkoutEvent> { $0.date == dayConst && $0.source == sourceRaw }
        )
        // MARK: try? justified - best-effort; nil/empty result is acceptable at this call site.
        if (try? modelContext.fetch(workoutDescriptor))?.isEmpty ?? true {
            modelContext.insert(WorkoutEvent(date: day, completed: true, source: source))
        }

        // Non-workout domains: write FreezeApplication entries. Skip duplicates.
        for domain in StreakDomain.allCases where domain != .workout {
            let domainKey = domain.rawValue
            let descriptor = FetchDescriptor<FreezeApplication>(
                predicate: #Predicate<FreezeApplication> { $0.domain == domainKey && $0.date == dayConst }
            )
            // MARK: try? justified - best-effort; nil/empty result is acceptable at this call site.
            if (try? modelContext.fetch(descriptor))?.isEmpty ?? true {
                modelContext.insert(FreezeApplication(domain: domain, date: day))
            }
        }
    }

    private func ensureProfile() -> UserProfile {
        if let existing = modelContext.fetchFirstOrNil(FetchDescriptor<UserProfile>()) {
            return existing
        }
        let p = UserProfile()
        modelContext.insert(p)
        return p
    }

    // MARK: - History assembly

    private func buildCompletionHistory(domain: StreakDomain, asOf: Date) throws -> [Date: Bool] {
        let cal = jstCalendar()
        let profile = modelContext.fetchFirstOrNil(FetchDescriptor<UserProfile>())
        let today = cal.startOfDay(for: asOf)
        var history: [Date: Bool] = [:]

        // Walk back enough days to cover the longest plausible streak (2 years).
        let lookbackDays = 730
        let earliest = cal.date(byAdding: .day, value: -lookbackDays, to: today) ?? today

        switch domain {
        case .workout:
            for event in try modelContext.fetch(FetchDescriptor<WorkoutEvent>(predicate: #Predicate<WorkoutEvent> { $0.date >= earliest })) {
                let day = cal.startOfDay(for: event.date)
                if event.completed { history[day] = true }
            }
        case .fasting:
            for log in try modelContext.fetch(FetchDescriptor<DailyLog>(predicate: #Predicate<DailyLog> { $0.date >= earliest && $0.supersededAt == nil })) {
                let day = cal.startOfDay(for: log.date)
                if log.fastEnd != nil { history[day] = true }
            }
        case .hydration:
            for log in try modelContext.fetch(FetchDescriptor<DailyLog>(predicate: #Predicate<DailyLog> { $0.date >= earliest && $0.supersededAt == nil })) {
                let day = cal.startOfDay(for: log.date)
                let target = hydrationTargetMin(for: day)
                if log.waterOz >= target { history[day] = true }
            }
        case .learning:
            // M4.2 followup: generalize learning completion. The original rule
            // was Clay-specific (Japanese >= 30 OR Guitar >= 20). Wife / buddy
            // may pick a different OptimizationFocus (language, music, deep
            // work) so we count the day done when ANY tracked learning
            // module clears its threshold OR total tracked minutes >= 20.
            // courseworkMinutes is included since the ScheduleEditor can
            // route generic learning blocks there.
            for log in try modelContext.fetch(FetchDescriptor<DailyLog>(predicate: #Predicate<DailyLog> { $0.date >= earliest && $0.supersededAt == nil })) {
                let day = cal.startOfDay(for: log.date)
                let total = log.japaneseMinutes
                    + log.guitarMinutes
                    + log.courseworkMinutes
                    + log.musicMinutes
                if log.japaneseMinutes >= 30
                    || log.guitarMinutes >= 20
                    || log.courseworkMinutes >= 20
                    || log.musicMinutes >= 20
                    || total >= 20 {
                    history[day] = true
                }
            }
        case .protocolAdherence:
            // protocolAdherence depends on per-day adherence which is computed by
            // DailySummaryService; for now require both fasting and hydration done
            // (workout/learning are not always scheduled). DailySummaryService can
            // refine this once it lands.
            for log in try modelContext.fetch(FetchDescriptor<DailyLog>(predicate: #Predicate<DailyLog> { $0.date >= earliest && $0.supersededAt == nil })) {
                let day = cal.startOfDay(for: log.date)
                let fastingDone = log.fastEnd != nil
                let hydrationDone = log.waterOz >= hydrationTargetMin(for: day)
                if fastingDone && hydrationDone { history[day] = true }
            }
        }

        // Apply freeze applications (non-workout domains write FreezeApplication;
        // workout domain freezes are encoded directly into WorkoutEvent above).
        if domain != .workout {
            for freeze in try modelContext.fetch(FetchDescriptor<FreezeApplication>(predicate: #Predicate<FreezeApplication> { $0.date >= earliest })) where freeze.domain == domain.rawValue {
                history[cal.startOfDay(for: freeze.date)] = true
            }
        }

        // Today-only grace: if the user toggled sick day for today, treat today as completed
        // even if no ledger row exists yet (the view layer writes the ledger via activateSickDay).
        if let until = profile?.sickDayActiveUntil, until >= today {
            history[today] = true
        }
        // Travel mode written ledger covers historical days; the today-fallback handles the
        // current day even before the ledger write commits.
        if let until = profile?.travelModeActiveUntil, until >= today {
            history[today] = true
        }
        _ = earliest
        return history
    }

    private func hydrationTargetMin(for day: Date) -> Double {
        guard let targets = hydrationTargets else { return 64 }
        let weekday = isoWeekday(for: day)
        if targets.basketball.appliesTo.contains(weekday) { return targets.basketball.min }
        if targets.swim.appliesTo.contains(weekday) { return targets.swim.min }
        if targets.lift.appliesTo.contains(weekday) { return targets.lift.min }
        return targets.rest.min
    }

    private func computeLongest(history: [Date: Bool], restDays: Set<Int>, calendar: Calendar) -> Int {
        let days = history.filter { $0.value }.keys.sorted()
        guard !days.isEmpty else { return 0 }
        var longest = 1
        var current = 1
        for i in 1..<days.count {
            let prev = days[i - 1]
            let cur = days[i]
            if daysBridge(from: prev, to: cur, restDays: restDays, calendar: calendar) {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }
        return longest
    }

    /// Returns true when every calendar day strictly between `prev` and `cur` is either absent
    /// (no gap) or an auto rest day. Rest days bridge the chain without incrementing it.
    private func daysBridge(from prev: Date, to cur: Date, restDays: Set<Int>, calendar: Calendar) -> Bool {
        guard var cursor = calendar.date(byAdding: .day, value: 1, to: prev) else { return false }
        while cursor < cur {
            if !restDays.contains(isoWeekday(for: cursor)) { return false }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { return false }
            cursor = next
        }
        return calendar.isDate(cursor, inSameDayAs: cur)
    }

    /// ISO weekdays (Mon=1..Sun=7) that bridge the streak without incrementing it.
    /// Derived from the schedule template for the workout domain: any weekday with no
    /// training block is a rest day. Falls back to Sat/Sun when the schedule is unseeded.
    /// Other domains have no auto rest days.
    private func autoRestDays(domain: StreakDomain) -> Set<Int> {
        guard domain == .workout else { return [] }
        let blocks = modelContext.fetchOrEmpty(FetchDescriptor<ScheduleBlock>())
        let trainingDays = Set(
            blocks.compactMap { block -> Int? in
                guard !block.isOverride, block.type == .training, block.module != nil else { return nil }
                return block.dayOfWeek
            }
        )
        if trainingDays.isEmpty { return [6, 7] }
        return Set(1...7).subtracting(trainingDays)
    }

    private func mostRecentCompletedDay(history: [Date: Bool]) -> Date? {
        history.filter { $0.value }.keys.max()
    }

    private func applyMonthlyResetIfNeeded(counter: StreakCounter, asOf: Date) {
        let cal = jstCalendar()
        let anchor = cal.date(from: cal.dateComponents([.year, .month], from: asOf)) ?? asOf
        if counter.freezeMonthAnchor != anchor {
            counter.freezesAvailable = StreakService.maxFreezesPerMonth
            counter.freezesUsedThisMonth = 0
            counter.freezeMonthAnchor = anchor
        }
    }

    private func upsertCounter(domain: StreakDomain) -> StreakCounter {
        let key = domain.rawValue
        let descriptor = FetchDescriptor<StreakCounter>(
            predicate: #Predicate<StreakCounter> { $0.domain == key }
        )
        if let existing = modelContext.fetchFirstOrNil(descriptor) {
            return existing
        }
        let counter = StreakCounter(domain: domain)
        modelContext.insert(counter)
        return counter
    }

    private func jstCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        return cal
    }

    private func isoWeekday(for date: Date) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        let raw = cal.component(.weekday, from: date)
        return raw == 1 ? 7 : raw - 1
    }
}
