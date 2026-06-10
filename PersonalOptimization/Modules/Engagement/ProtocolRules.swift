import Foundation

/// THE single definition of the protocol's per-day business rules. Every
/// surface (StreakService, DailySummaryService, ProtocolGoalSnapshot, trend
/// analytics, progress bars, registries, watch complication) delegates here,
/// so a rule change lands everywhere at once and surfaces can never drift
/// (2026-06 audit, Theme 1: one rule, one place).
enum ProtocolRules {

    // MARK: - Weekday

    /// ISO weekday (Mon=1...Sun=7) from a Gregorian calendar component.
    static func isoWeekday(for date: Date, calendar: Calendar) -> Int {
        let raw = calendar.component(.weekday, from: date)
        return raw == 1 ? 7 : raw - 1
    }

    // MARK: - Hydration

    /// The day's minimum hydration target in ounces, by day type: basketball,
    /// swim, and lift days carry higher floors; rest days the base floor.
    /// `nil` targets (config unavailable) fall back to the 64 oz floor so a
    /// surface renders rather than breaks.
    static func hydrationTargetMin(for date: Date, targets: HydrationTargetsOz?, calendar: Calendar) -> Double {
        guard let targets else { return 64 }
        let weekday = isoWeekday(for: date, calendar: calendar)
        if targets.basketball.appliesTo.contains(weekday) { return targets.basketball.min }
        if targets.swim.appliesTo.contains(weekday) { return targets.swim.min }
        if targets.lift.appliesTo.contains(weekday) { return targets.lift.min }
        return targets.rest.min
    }

    // MARK: - Learning

    /// Total tracked learning minutes for a day. Includes ALL four modules;
    /// the registries previously omitted `musicMinutes`, which made milestone
    /// totals disagree with streaks and archives.
    static func learningMinutes(japanese: Int, guitar: Int, coursework: Int, music: Int) -> Int {
        japanese + guitar + coursework + music
    }

    /// Generalized learning-done rule: any tracked module clears its
    /// threshold, OR total tracked minutes reach 20 (so a different
    /// OptimizationFocus still counts its day).
    static func learningDone(japanese: Int, guitar: Int, coursework: Int, music: Int) -> Bool {
        japanese >= 30
            || guitar >= 20
            || coursework >= 20
            || music >= 20
            || learningMinutes(japanese: japanese, guitar: guitar, coursework: coursework, music: music) >= 20
    }
}

extension ProtocolRules {
    /// DailyLog conveniences (nil log = nothing logged today).
    static func learningMinutes(log: DailyLog?) -> Int {
        learningMinutes(
            japanese: log?.japaneseMinutes ?? 0,
            guitar: log?.guitarMinutes ?? 0,
            coursework: log?.courseworkMinutes ?? 0,
            music: log?.musicMinutes ?? 0
        )
    }

    static func learningDone(log: DailyLog?) -> Bool {
        learningDone(
            japanese: log?.japaneseMinutes ?? 0,
            guitar: log?.guitarMinutes ?? 0,
            coursework: log?.courseworkMinutes ?? 0,
            music: log?.musicMinutes ?? 0
        )
    }
}
