import Foundation
import SwiftData
import os

struct ProtocolDomainResult: Identifiable, Sendable {
    let id = UUID()
    let domain: StreakDomain
    let label: String
    let scheduled: Bool
    let completed: Bool
    let detail: String
}

struct ProtocolAdherenceTally: Sendable {
    let date: Date
    let domains: [ProtocolDomainResult]

    var completedCount: Int {
        domains.filter { $0.scheduled && $0.completed }.count
    }

    var scheduledCount: Int {
        domains.filter { $0.scheduled }.count
    }

    var displayText: String {
        let total = scheduledCount
        guard total > 0 else { return "Nothing scheduled today." }
        return "\(completedCount)/\(total) of today's protocol complete"
    }

    /// The single scheduled-but-incomplete domain when exactly one remains.
    /// Drives the goal-gradient "one more to close" nudge: motivation rises near
    /// the finish, so the final-stretch prompt names exactly what is left.
    var oneMoreToClose: ProtocolDomainResult? {
        let remaining = domains.filter { $0.scheduled && !$0.completed }
        return remaining.count == 1 ? remaining.first : nil
    }
}

/// Computes "Today's Protocol Adherence" — the single roll-up shown on TodayView.
@MainActor
final class DailySummaryService {
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

    /// Builds today's protocol adherence tally. Domains are evaluated independently and
    /// returned in the natural protocol order: workout, fasting, hydration, learning.
    func todayProtocol(asOf: Date = Date()) -> ProtocolAdherenceTally {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        let day = cal.startOfDay(for: asOf)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: day) ?? day
        let weekday = isoWeekday(for: asOf)

        // ScheduleBlock has no date column (weekly recurring), so the
        // unbounded fetch is unavoidable; push the day-of-week filter into
        // the predicate so SwiftData only loads matching rows.
        let blocksDescriptor = FetchDescriptor<ScheduleBlock>(
            predicate: #Predicate<ScheduleBlock> {
                $0.dayOfWeek == weekday && $0.isOverride == false
            }
        )
        let blocksToday = modelContext.fetchOrEmpty(blocksDescriptor)
        let workoutScheduled = blocksToday.contains { $0.type == .training && $0.module != nil }

        // DailyLog: one row for the day. Predicate keyed on equality so
        // SwiftData hits exactly one record instead of streaming the table.
        let logDescriptor = FetchDescriptor<DailyLog>(
            predicate: #Predicate<DailyLog> { $0.date == day && $0.supersededAt == nil }
        )
        let log = modelContext.fetchFirstOrNil(logDescriptor)

        // WorkoutEvent: scoped to today's range with the completed flag.
        let workoutEventsDescriptor = FetchDescriptor<WorkoutEvent>(
            predicate: #Predicate<WorkoutEvent> {
                $0.date >= day && $0.date < tomorrow && $0.completed
            }
        )
        let workoutEvents = modelContext.fetchOrEmpty(workoutEventsDescriptor)
        let workoutCompleted = !workoutEvents.isEmpty

        let fastingDone = log?.fastEnd != nil
        let waterOz = log?.waterOz ?? 0
        let hydrationTargetMin = hydrationFloor(for: asOf)
        let hydrationDone = waterOz >= hydrationTargetMin

        let japaneseMin = log?.japaneseMinutes ?? 0
        let guitarMin = log?.guitarMinutes ?? 0
        let musicMin = log?.musicMinutes ?? 0
        let courseworkMin = log?.courseworkMinutes ?? 0
        let totalLearningMin = japaneseMin + guitarMin + musicMin + courseworkMin
        let learningDone = japaneseMin >= 30
            || guitarMin >= 20
            || musicMin >= 20
            || courseworkMin >= 20
            || totalLearningMin >= 20

        // Travel/sick day grace: treat all scheduled domains as completed when active.
        let profile = modelContext.fetchFirstOrNil(FetchDescriptor<UserProfile>())
        let travelOn = (profile?.travelModeActiveUntil ?? .distantPast) >= asOf
        let sickOn = (profile?.sickDayActiveUntil ?? .distantPast) >= asOf
        let graceCovered = travelOn || sickOn

        var domains: [ProtocolDomainResult] = []

        let workoutDetail: String = {
            if workoutCompleted {
                if let snippet = todaysWorkoutSnippet(for: day) {
                    return snippet
                }
                return IdentityCopy.workoutLogged
            }
            return workoutScheduled ? "Scheduled" : "Rest day"
        }()
        domains.append(ProtocolDomainResult(
            domain: .workout,
            label: "Workout",
            scheduled: workoutScheduled,
            completed: workoutCompleted || graceCovered,
            detail: workoutDetail
        ))

        domains.append(ProtocolDomainResult(
            domain: .fasting,
            label: "Fasting",
            scheduled: true,
            completed: fastingDone || graceCovered,
            detail: fastingDone ? "Window closed" : "Open"
        ))

        domains.append(ProtocolDomainResult(
            domain: .hydration,
            label: "Hydration",
            scheduled: true,
            completed: hydrationDone || graceCovered,
            detail: "\(Int(waterOz)) of \(Int(hydrationTargetMin)) oz"
        ))

        domains.append(ProtocolDomainResult(
            domain: .learning,
            label: "Learning",
            scheduled: true,
            completed: learningDone || graceCovered,
            detail: learningDetail(jp: japaneseMin, gtr: guitarMin, music: musicMin, work: courseworkMin)
        ))

        return ProtocolAdherenceTally(date: day, domains: domains)
    }

    // MARK: - Helpers

    /// M4.2 followup: replace the generic "workout logged" label with the
    /// specific activity surface ("Run · 32 min", "Lift A · 4 sets",
    /// "Cycling · 45 min") when there's a session to point at. Picks the
    /// most-recent session of the day. Returns nil for cleaner workouts
    /// (just a WorkoutEvent ledger entry with no session detail).
    private func todaysWorkoutSnippet(for day: Date) -> String? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        let tomorrow = cal.date(byAdding: .day, value: 1, to: day) ?? day

        // Most-recent CustomActivitySession beats lift/sport sessions since
        // cardio is the M4.2 focus. Predicate pushes the date range and
        // minimum-duration check into SwiftData; fetchLimit = 1 stops at
        // the first row in the descending order.
        var customsDescriptor = FetchDescriptor<CustomActivitySession>(
            predicate: #Predicate<CustomActivitySession> {
                $0.date >= day && $0.date < tomorrow && $0.durationMinutes > 0
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        customsDescriptor.fetchLimit = 1
        if let custom = modelContext.fetchFirstOrNil(customsDescriptor) {
            let name = custom.templateName.isEmpty ? "Cardio" : custom.templateName
            return "\(name) · \(custom.durationMinutes) min"
        }

        var liftsDescriptor = FetchDescriptor<LiftSession>(
            predicate: #Predicate<LiftSession> {
                $0.date >= day && $0.date < tomorrow && $0.durationMinutes > 0
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        liftsDescriptor.fetchLimit = 1
        if let lift = modelContext.fetchFirstOrNil(liftsDescriptor) {
            return "\(lift.template) · \(lift.durationMinutes) min"
        }

        var bballDescriptor = FetchDescriptor<BasketballSession>(
            predicate: #Predicate<BasketballSession> {
                $0.startTime >= day && $0.startTime < tomorrow
            },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        bballDescriptor.fetchLimit = 1
        if let game = modelContext.fetchFirstOrNil(bballDescriptor), game.endTime > game.startTime {
            let minutes = max(1, Int(game.endTime.timeIntervalSince(game.startTime) / 60))
            return "Basketball · \(minutes) min"
        }

        var swimsDescriptor = FetchDescriptor<SwimSession>(
            predicate: #Predicate<SwimSession> {
                $0.date >= day && $0.date < tomorrow && $0.durationMinutes > 0
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        swimsDescriptor.fetchLimit = 1
        if let swim = modelContext.fetchFirstOrNil(swimsDescriptor) {
            return "Swim · \(swim.durationMinutes) min · \(Int(swim.totalMeters))m"
        }

        return nil
    }

    /// Compact one-line learning detail. Surfaces whichever modules had time
    /// logged today, in a stable order. Drops zero-minute modules.
    private func learningDetail(jp: Int, gtr: Int, music: Int, work: Int) -> String {
        var parts: [String] = []
        if jp > 0    { parts.append("JP \(jp)m") }
        if gtr > 0   { parts.append("GTR \(gtr)m") }
        if music > 0 { parts.append("Music \(music)m") }
        if work > 0  { parts.append("Course \(work)m") }
        if parts.isEmpty { return "0 min logged" }
        return parts.joined(separator: " · ")
    }

    private func hydrationFloor(for date: Date) -> Double {
        guard let targets = hydrationTargets else { return 64 }
        let weekday = isoWeekday(for: date)
        if targets.basketball.appliesTo.contains(weekday) { return targets.basketball.min }
        if targets.swim.appliesTo.contains(weekday) { return targets.swim.min }
        if targets.lift.appliesTo.contains(weekday) { return targets.lift.min }
        return targets.rest.min
    }

    private func isoWeekday(for date: Date) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        let raw = cal.component(.weekday, from: date)
        return raw == 1 ? 7 : raw - 1
    }
}
