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
}

/// Computes "Today's Protocol Adherence" — the single roll-up shown on TodayView.
@MainActor
final class DailySummaryService {
    private let modelContext: ModelContext
    private let timezone: TimeZone
    private let hydrationTargets: HydrationTargetsOz?
    private let logger = Logger.app

    init(modelContext: ModelContext,
         timezone: TimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current,
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

        let blocks = (try? modelContext.fetch(FetchDescriptor<ScheduleBlock>())) ?? []
        let weekday = isoWeekday(for: asOf)
        let blocksToday = blocks.filter { $0.dayOfWeek == weekday && !$0.isOverride }
        let workoutScheduled = blocksToday.contains { $0.type == .training && $0.module != nil }

        let log = (try? modelContext.fetch(FetchDescriptor<DailyLog>()))?.first {
            cal.isDate($0.date, inSameDayAs: day)
        }

        let workoutEvents = (try? modelContext.fetch(FetchDescriptor<WorkoutEvent>())) ?? []
        let workoutCompleted = workoutEvents.contains {
            cal.isDate($0.date, inSameDayAs: day) && $0.completed
        }

        let fastingDone = log?.fastEnd != nil
        let waterOz = log?.waterOz ?? 0
        let hydrationTargetMin = hydrationFloor(for: asOf)
        let hydrationDone = waterOz >= hydrationTargetMin

        let japaneseMin = log?.japaneseMinutes ?? 0
        let guitarMin = log?.guitarMinutes ?? 0
        let learningDone = japaneseMin >= 30 || guitarMin >= 20

        // Travel/sick day grace: treat all scheduled domains as completed when active.
        let profile = (try? modelContext.fetch(FetchDescriptor<UserProfile>()))?.first
        let travelOn = (profile?.travelModeActiveUntil ?? .distantPast) >= asOf
        let sickOn = (profile?.sickDayActiveUntil ?? .distantPast) >= asOf
        let graceCovered = travelOn || sickOn

        var domains: [ProtocolDomainResult] = []

        domains.append(ProtocolDomainResult(
            domain: .workout,
            label: "Workout",
            scheduled: workoutScheduled,
            completed: workoutCompleted || graceCovered,
            detail: workoutCompleted ? IdentityCopy.workoutLogged : (workoutScheduled ? "Scheduled" : "Rest day")
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
            detail: "JP \(japaneseMin)m · GTR \(guitarMin)m"
        ))

        return ProtocolAdherenceTally(date: day, domains: domains)
    }

    // MARK: - Helpers

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
