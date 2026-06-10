import Foundation
import SwiftData
import os

/// Catalog of milestones the user can reach. Static — adding/removing is a
/// code change, not a runtime decision. Each milestone has an evaluator that
/// returns true when the user has crossed the threshold today; the runtime
/// service writes a `MilestoneUnlock` row and triggers the celebration sheet.
///
/// Density is engineered for the day 30-90 retention window per the
/// V1_OPPORTUNITIES doc / Opportunity 2 research basis.
struct Milestone: Sendable {
    let id: String
    let dayThreshold: Int                  // # of consecutive engaged days, or absolute day-count milestone
    let type: MilestoneType
    let displayName: String
    let unlockTitle: String                // identity-framed celebration line
    let unlockBody: String                 // optional second line
    let mascotState: CharacterState        // which mascot pose accompanies the celebration
}

enum MilestoneRegistry {
    /// Twelve+ named milestones across the first year. Day numbers chosen to
    /// front-load reward density in the day 30-90 window where novelty fades.
    static let allMilestones: [Milestone] = [
        Milestone(id: "first_week",
                  dayThreshold: 7, type: .streakDays,
                  displayName: "First Week Done",
                  unlockTitle: "Seven days. The first ridge.",
                  unlockBody: "You did the work no one else can do for you.",
                  mascotState: .achievement),

        Milestone(id: "two_weeks_steady",
                  dayThreshold: 14, type: .streakDays,
                  displayName: "Two Weeks Steady",
                  unlockTitle: "Fourteen days. Pattern, not luck.",
                  unlockBody: "The body remembers; the mind catches up.",
                  mascotState: .proud),

        Milestone(id: "three_weeks_real",
                  dayThreshold: 21, type: .streakDays,
                  displayName: "Three Weeks Real",
                  unlockTitle: "Twenty-one. This is who you are now.",
                  unlockBody: "Identity, not effort.",
                  mascotState: .achievement),

        Milestone(id: "first_month",
                  dayThreshold: 30, type: .streakDays,
                  displayName: "First Month",
                  unlockTitle: "Thirty days. Stoic mode unlocked.",
                  unlockBody: "Marcus Aurelius pull-quotes are now in rotation.",
                  mascotState: .proud),

        Milestone(id: "past_halfway",
                  dayThreshold: 45, type: .streakDays,
                  displayName: "Past Halfway",
                  unlockTitle: "Forty-five. The middle is the work.",
                  unlockBody: "Most people stop here. You're not most people.",
                  mascotState: .achievement),

        Milestone(id: "sustained",
                  dayThreshold: 60, type: .streakDays,
                  displayName: "Sustained",
                  unlockTitle: "Sixty days. Sustained.",
                  unlockBody: "Philosopher mode unlocked in Coach.",
                  mascotState: .proud),

        Milestone(id: "habit_locked",
                  dayThreshold: 90, type: .streakDays,
                  displayName: "Habit Locked",
                  unlockTitle: "Ninety days. The habit is yours.",
                  unlockBody: "What you do now is what you'll do at sixty.",
                  mascotState: .achievement),

        Milestone(id: "centurion",
                  dayThreshold: 100, type: .streakDays,
                  displayName: "Centurion",
                  unlockTitle: "One hundred. Centurion.",
                  unlockBody: "The headband stays gold for seven days.",
                  mascotState: .achievement),

        // Cumulative-volume milestones don't depend on a streak; they recognize
        // the work itself, regardless of pace.
        Milestone(id: "fifty_workouts",
                  dayThreshold: 50, type: .totalWorkouts,
                  displayName: "Fifty Workouts",
                  unlockTitle: "Fifty sessions logged.",
                  unlockBody: "That's the body of work.",
                  mascotState: .proud),

        Milestone(id: "tonnage_50k",
                  dayThreshold: 50_000, type: .totalVolume,
                  displayName: "Tonnage",
                  unlockTitle: "Fifty thousand pounds moved.",
                  unlockBody: "That's the work no one sees.",
                  mascotState: .achievement),

        Milestone(id: "fasting_90",
                  dayThreshold: 90, type: .fastingDays,
                  displayName: "Kitchen Discipline",
                  unlockTitle: "Ninety completed fasting windows.",
                  unlockBody: "The kitchen knows who's in charge.",
                  mascotState: .proud),

        Milestone(id: "learning_30h",
                  dayThreshold: 30 * 60, type: .learningMinutes,
                  displayName: "Thirty Hours of Learning",
                  unlockTitle: "Thirty hours of focused learning.",
                  unlockBody: "Compound interest of attention.",
                  mascotState: .proud),

        Milestone(id: "year_of_consistency",
                  dayThreshold: 365, type: .streakDays,
                  displayName: "Year of Consistency",
                  unlockTitle: "Three hundred sixty-five.",
                  unlockBody: "You are the kind of person you set out to become.",
                  mascotState: .achievement)
    ]

    /// Look up a milestone by id, or nil.
    static func milestone(forID id: String) -> Milestone? {
        allMilestones.first { $0.id == id }
    }
}

/// Runtime detector + persister. Run on app launch / day rollover; writes a
/// `MilestoneUnlock` row when the user crosses a threshold for the first
/// time. Idempotent: existing unlock rows aren't duplicated.
@MainActor
final class MilestoneService {
    private let modelContext: ModelContext
    private let timezone: TimeZone
    private let logger = Logger(subsystem: BuildConfig.loggingSubsystem, category: "milestones")

    init(modelContext: ModelContext,
         timezone: TimeZone = TimeZone.current) {
        self.modelContext = modelContext
        self.timezone = timezone
    }

    /// Walk the registry and unlock anything the user has now earned.
    /// Returns the list of milestones unlocked this call (empty when none).
    @discardableResult
    func evaluate(asOf date: Date = Date()) throws -> [MilestoneUnlock] {
        let alreadyUnlocked = try modelContext.fetch(FetchDescriptor<MilestoneUnlock>())
        let alreadyUnlockedIDs = Set(alreadyUnlocked.map(\.identifier))

        let metrics = computeMetrics(asOf: date)
        var newlyUnlocked: [MilestoneUnlock] = []

        for milestone in MilestoneRegistry.allMilestones where !alreadyUnlockedIDs.contains(milestone.id) {
            let value = metrics.value(for: milestone.type)
            if value >= milestone.dayThreshold {
                let unlock = MilestoneUnlock(
                    identifier: milestone.id,
                    milestoneType: milestone.type,
                    unlockedAt: date
                )
                modelContext.insert(unlock)
                newlyUnlocked.append(unlock)
                logger.info("Milestone unlocked: \(milestone.id, privacy: .public)")
            }
        }
        if !newlyUnlocked.isEmpty {
            try modelContext.save()
        }
        return newlyUnlocked
    }

    /// Most recent unlock that hasn't fired its celebration sheet yet.
    func nextPendingCelebration() -> MilestoneUnlock? {
        let descriptor = FetchDescriptor<MilestoneUnlock>(
            sortBy: [SortDescriptor(\.unlockedAt, order: .reverse)]
        )
        let all = modelContext.fetchOrEmpty(descriptor)
        return all.first { !$0.celebrationShown }
    }

    func markCelebrationShown(_ unlock: MilestoneUnlock) {
        unlock.celebrationShown = true
        try? modelContext.save()  // MARK: try? save() is best-effort — failures surface via os_log; in-memory state already updated.
    }

    // MARK: - Metric computation

    private struct Metrics {
        let streakDays: Int
        let totalWorkouts: Int
        let totalVolume: Int
        let fastingDays: Int
        let learningMinutes: Int
        let appUsageDays: Int

        func value(for type: MilestoneType) -> Int {
            switch type {
            case .streakDays:        return streakDays
            case .totalWorkouts:     return totalWorkouts
            case .totalVolume:       return totalVolume
            case .fastingDays:       return fastingDays
            case .learningMinutes:   return learningMinutes
            case .appUsageDays:      return appUsageDays
            case .allMascotStates:   return 0   // computed elsewhere; not in basic metrics
            }
        }
    }

    private func computeMetrics(asOf date: Date) -> Metrics {
        let counters = modelContext.fetchOrEmpty(FetchDescriptor<StreakCounter>())
        let workoutStreak = counters.first { $0.domain == StreakDomain.workout.rawValue }?.currentStreak ?? 0
        let hydrationStreak = counters.first { $0.domain == StreakDomain.hydration.rawValue }?.currentStreak ?? 0
        let learningStreak = counters.first { $0.domain == StreakDomain.learning.rawValue }?.currentStreak ?? 0
        // Use the longest active streak as the "consistency" metric.
        let streakDays = max(workoutStreak, max(hydrationStreak, learningStreak))

        let workouts = modelContext.fetchOrEmpty(FetchDescriptor<WorkoutEvent>())
        let totalWorkouts = workouts.filter { $0.completed }.count

        let lifts = modelContext.fetchOrEmpty(FetchDescriptor<LiftSession>())
        let totalVolume = lifts.reduce(0) { $0 + Int($1.totalVolumeLbs) }

        let logs = modelContext.fetchOrEmpty(FetchDescriptor<DailyLog>())
        let fastingDays = logs.filter { $0.fastEnd != nil }.count
        let learningMinutes = logs.reduce(0) { $0 + ProtocolRules.learningMinutes(log: $1) }

        // App usage = number of distinct DailyLog rows or ActivityArchive rows.
        let archives = modelContext.fetchOrEmpty(FetchDescriptor<ActivityArchive>())
        let appUsageDays = max(logs.count, archives.count)

        return Metrics(
            streakDays: streakDays,
            totalWorkouts: totalWorkouts,
            totalVolume: totalVolume,
            fastingDays: fastingDays,
            learningMinutes: learningMinutes,
            appUsageDays: appUsageDays
        )
    }
}
