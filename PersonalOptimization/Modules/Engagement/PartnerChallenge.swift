import Foundation
import SwiftData

/// Apple-Fitness-style weekly challenge between the paired dyad, scored on
/// protocol points: one point per closed domain per day, using the same
/// rules as the master metric (scheduled-aware workout domain, day-type
/// hydration floor, travel/sick grace). Pure standing logic plus a MainActor
/// scorer; sync rides the `PartnerSharedZone` seam, so everything here works
/// against `MemoryPartnerSharedZone` today and goes live unchanged when the
/// CloudKit zone lands (decision 007).

/// One competitor's week: points per day from week start through "today".
struct ChallengeWeek: Sendable, Equatable {
    let weekStart: Date
    let dailyPoints: [Int]

    var totalPoints: Int { dailyPoints.reduce(0, +) }
}

enum ChallengeLeader: Sendable, Equatable {
    case me(by: Int)
    case partner(by: Int)
    case tied
}

/// My week vs the partner's published total. `partnerPoints` is nil until
/// the partner's snapshot carries points for the SAME week (a stale snapshot
/// from last week never scores against this one).
struct ChallengeStanding: Sendable, Equatable {
    let week: ChallengeWeek
    let partnerPoints: Int?
    /// True when the partner has published challenge data, just not for this
    /// week yet. Lets the UI say "waiting on her week" instead of hiding.
    let partnerStale: Bool
    /// Whole days left in the week including today (1 on the final day).
    let daysRemaining: Int

    var leader: ChallengeLeader? {
        guard let partnerPoints else { return nil }
        if week.totalPoints > partnerPoints { return .me(by: week.totalPoints - partnerPoints) }
        if partnerPoints > week.totalPoints { return .partner(by: partnerPoints - week.totalPoints) }
        return .tied
    }
}

enum ChallengeScoring {

    /// Scores the current week (user calendar) by walking each elapsed day
    /// through `ProtocolGoalSnapshot`, the single source of protocol truth.
    /// History is durable (retention guarantee), so past days re-derive
    /// exactly.
    @MainActor
    static func currentWeek(modelContext: ModelContext,
                            asOf: Date = Date(),
                            calendar: Calendar) -> ChallengeWeek {
        let week = calendar.dateInterval(of: .weekOfYear, for: asOf)
            ?? DateInterval(start: calendar.startOfDay(for: asOf), duration: 7 * 86_400)
        let today = calendar.startOfDay(for: asOf)
        var daily: [Int] = []
        var day = week.start
        while day <= today && day < week.end {
            let snap = ProtocolGoalSnapshot.make(modelContext: modelContext, asOf: day)
            daily.append(snap.completedDomains)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return ChallengeWeek(weekStart: week.start, dailyPoints: daily)
    }

    /// Pure standing combinator; unit-testable without SwiftData or a zone.
    static func standing(week: ChallengeWeek,
                         partner: PartnerSharedRecord?,
                         calendar: Calendar,
                         asOf: Date = Date()) -> ChallengeStanding {
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: week.weekStart)
            ?? week.weekStart
        let daysRemaining = max(0, calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: asOf),
            to: weekEnd
        ).day ?? 0)

        guard let partner,
              let partnerWeekStart = partner.challengeWeekStart,
              let points = partner.challengeWeekPoints else {
            return ChallengeStanding(week: week, partnerPoints: nil,
                                     partnerStale: false, daysRemaining: daysRemaining)
        }
        let sameWeek = calendar.isDate(partnerWeekStart, inSameDayAs: week.weekStart)
        return ChallengeStanding(week: week,
                                 partnerPoints: sameWeek ? points : nil,
                                 partnerStale: !sameWeek,
                                 daysRemaining: daysRemaining)
    }
}
