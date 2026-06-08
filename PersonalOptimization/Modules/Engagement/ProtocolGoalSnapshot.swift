import Foundation
import SwiftData

/// Single source of truth for today's protocol goal on the glanceable surfaces
/// (watch complication + iOS widget). Mirrors DailySummaryService.todayProtocol's
/// scheduled-domain and travel/sick grace rules so every surface agrees with the
/// in-app master metric and the streak it displays. Both extension targets call
/// this instead of duplicating the logic, so they cannot drift.
struct ProtocolGoalSnapshot: Sendable, Equatable {
    let streak: Int
    let completedDomains: Int
    let totalDomains: Int

    var progress: Double {
        totalDomains > 0 ? Double(completedDomains) / Double(totalDomains) : 0
    }

    @MainActor
    static func make(modelContext: ModelContext, asOf: Date = Date()) -> ProtocolGoalSnapshot {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let day = cal.startOfDay(for: asOf)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: day) ?? day
        let raw = cal.component(.weekday, from: asOf)
        let weekday = raw == 1 ? 7 : raw - 1

        let key = StreakDomain.protocolAdherence.rawValue
        let streak = modelContext.fetchOrEmpty(
            FetchDescriptor<StreakCounter>(predicate: #Predicate { $0.domain == key })
        ).first?.currentStreak ?? 0

        let log = modelContext.fetchOrEmpty(
            FetchDescriptor<DailyLog>(predicate: #Predicate { $0.date == day && $0.supersededAt == nil })
        ).first

        let profile = modelContext.fetchOrEmpty(FetchDescriptor<UserProfile>()).first
        let graceCovered = (profile?.travelModeActiveUntil ?? .distantPast) >= asOf
            || (profile?.sickDayActiveUntil ?? .distantPast) >= asOf

        let blocks = modelContext.fetchOrEmpty(
            FetchDescriptor<ScheduleBlock>(predicate: #Predicate { $0.dayOfWeek == weekday && $0.isOverride == false })
        )
        let workoutScheduled = blocks.contains { $0.type == .training && $0.module != nil }
        let workoutDone = (modelContext.fetchOrEmpty(
            FetchDescriptor<WorkoutEvent>(predicate: #Predicate { $0.date >= day && $0.date < tomorrow && $0.completed })
        ).isEmpty == false) || graceCovered

        let fastingDone = (log?.fastEnd != nil) || graceCovered
        let hydrationDone = ((log?.waterOz ?? 0) >= hydrationTarget(for: asOf, calendar: cal)) || graceCovered
        let learningDone: Bool = {
            let jp = log?.japaneseMinutes ?? 0
            let gtr = log?.guitarMinutes ?? 0
            let mus = log?.musicMinutes ?? 0
            let work = log?.courseworkMinutes ?? 0
            return jp >= 30 || gtr >= 20 || mus >= 20 || work >= 20 || (jp + gtr + mus + work) >= 20 || graceCovered
        }()

        var completed = 0
        var total = 0
        for (scheduled, done) in [(workoutScheduled, workoutDone), (true, fastingDone), (true, hydrationDone), (true, learningDone)] {
            if scheduled {
                total += 1
                if done { completed += 1 }
            }
        }
        return ProtocolGoalSnapshot(streak: streak, completedDomains: completed, totalDomains: total)
    }

    private static func hydrationTarget(for date: Date, calendar: Calendar) -> Double {
        // try? justified - bundled resource; on failure fall back to the 64oz
        // floor so the surface renders rather than breaking.
        guard let targets = try? ScheduleConfigLoader.load().hydrationTargetsOz else { return 64 }
        let raw = calendar.component(.weekday, from: date)
        let weekday = raw == 1 ? 7 : raw - 1
        if targets.basketball.appliesTo.contains(weekday) { return targets.basketball.min }
        if targets.swim.appliesTo.contains(weekday) { return targets.swim.min }
        if targets.lift.appliesTo.contains(weekday) { return targets.lift.min }
        return targets.rest.min
    }
}
