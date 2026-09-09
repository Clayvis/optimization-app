import Foundation

/// A value-only projection of recorded activity. Rewards are derived from
/// unique workout days, never app opens, taps, or a mutable XP balance.
struct DailyWorkoutProgress: Equatable, Sendable {
    static let xpPerDay = 50
    static let xpPerLevel = 250

    let movementMinutes: Int
    let goalMinutes: Int
    let weeklyGoal: Int
    let workoutDays: Set<Date>
    let weekDays: [Date]
    let today: Date

    init(workoutDates: [Date], exerciseMinutes: Int, sessionMinutes: Int,
         goalMinutes: Int, weeklyGoal: Int = 3, asOf: Date, calendar: Calendar) {
        today = calendar.startOfDay(for: asOf)
        // Health's exercise total already includes sessions recorded by this
        // app. Taking the larger total avoids counting the same minutes twice.
        movementMinutes = max(0, exerciseMinutes, sessionMinutes)
        self.goalMinutes = max(1, goalMinutes)
        self.weeklyGoal = min(7, max(1, weeklyGoal))
        workoutDays = Set(workoutDates.filter { $0 <= asOf }.map { calendar.startOfDay(for: $0) })
        // The visible week is Monday–Sunday in the user's timezone, including DST.
        let weekday = (calendar.component(.weekday, from: today) + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -weekday, to: today) ?? today
        weekDays = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    var trainedToday: Bool { workoutDays.contains(today) }
    var daysThisWeek: Int { weekDays.filter { workoutDays.contains($0) }.count }
    var totalXP: Int { workoutDays.count * Self.xpPerDay }
    var level: Int { totalXP / Self.xpPerLevel + 1 }
    var xpInLevel: Int { totalXP % Self.xpPerLevel }
    var xpToNextLevel: Int { Self.xpPerLevel - xpInLevel }
    var movementProgress: Double { min(1, Double(movementMinutes) / Double(goalMinutes)) }
    var weeklyProgress: Double { min(1, Double(daysThisWeek) / Double(weeklyGoal)) }
    var lastWorkoutDay: Date? { workoutDays.max() }

    /// Only real exercise sources earn XP. Grace and skips remain separate
    /// from workout completion, even in older stores with completed=true.
    static func earnsWorkoutCredit(source: String) -> Bool {
        ["lift", "basketball", "swim", "custom"].contains(source)
    }

    /// Clips completed sessions to today's elapsed time and merges overlaps.
    /// Unfinished, duplicate, future, and midnight-crossing sessions cannot
    /// inflate the ring. Round once after summing, not once per session.
    static func sessionMinutes(intervals: [DateInterval], asOf: Date, calendar: Calendar) -> Int {
        let day = calendar.startOfDay(for: asOf)
        let clipped = intervals.compactMap { interval -> DateInterval? in
            let start = max(day, interval.start)
            let end = min(asOf, interval.end)
            return end > start ? DateInterval(start: start, end: end) : nil
        }.sorted { $0.start < $1.start }
        var merged: [DateInterval] = []
        for interval in clipped {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        return Int(merged.reduce(0) { $0 + $1.duration } / 60)
    }
}

struct DailyWorkoutCoach: Equatable, Sendable {
    let title: String
    let message: String

    static func make(progress: DailyWorkoutProgress, resting: Bool, easing: Bool,
                     calendar: Calendar) -> DailyWorkoutCoach {
        if resting {
            return .init(title: "Recovery belongs in your week.",
                         message: "Your earned XP stays yours. Take today off and come back when you're ready.")
        }
        if progress.trainedToday {
            return .init(title: "You showed up. That counts.",
                         message: "Today's workout earned 50 XP. More training is optional. Enjoy the win.")
        }
        if easing {
            return .init(title: "Make room for an easier day.",
                         message: "Choose a shorter session if it feels right, or take a rest day. Your progress stays with you.")
        }
        if let last = progress.lastWorkoutDay,
           (calendar.dateComponents([.day], from: last, to: progress.today).day ?? 0) >= 3 {
            return .init(title: "Welcome back. Start small.",
                         message: "You still have \(progress.totalXP) XP. A short session is enough to begin again.")
        }
        if progress.movementMinutes >= progress.goalMinutes {
            return .init(title: "Your movement goal is already closed.",
                         message: "Everyday movement counts too. A workout is here if you want one.")
        }
        let prompts = [
            "A little time for yourself goes a long way. Pick an activity you enjoy.",
            "You don't need a perfect day. Start with the time you have.",
            "Small sessions add up. Your only job right now is to begin.",
            "Make this one yours. Choose the activity and pace that fit today."
        ]
        let index = (calendar.ordinality(of: .day, in: .era, for: progress.today) ?? 0) % prompts.count
        return .init(title: "One small win today.", message: prompts[index])
    }
}
