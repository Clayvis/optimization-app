import Foundation
import SwiftData
import os

/// Granular named-win catalog. Sibling to `MilestoneRegistry`: milestones
/// recognize cross-domain consistency (7/30/100 days, year-of-consistency),
/// achievements recognize specific behaviors ("First Lift", "Hydration
/// Honest", "All Eight" mascot states triggered).
///
/// Per V1_OPPORTUNITIES audit: 20-30 named achievements drive Yu-kai Chou
/// Core Drive 2 (Development & Accomplishment). User-direction this round:
/// skip mascot evolution / alternate art; ship the named-win list + UI.
struct AchievementDefinition: Sendable {
    let id: String
    let name: String
    let description: String
    let category: AchievementCategory
    let glyph: String                       // SF Symbol
}

enum AchievementCategory: String, Codable, CaseIterable, Sendable {
    case firsts          // first time logging X
    case cumulative      // total volume / hours / count
    case combo           // combinations of streaks
    case mastery         // breadth of usage
    case consistency     // streak-related (also covered by milestones, but smaller-grain)

    var displayName: String {
        switch self {
        case .firsts:      return "Firsts"
        case .cumulative:  return "Cumulative"
        case .combo:       return "Combos"
        case .mastery:     return "Mastery"
        case .consistency: return "Consistency"
        }
    }
}

enum AchievementRegistry {
    static let allAchievements: [AchievementDefinition] = [
        // MARK: Firsts
        .init(id: "first_lift", name: "First Lift",
              description: "Logged your first lift session.",
              category: .firsts, glyph: "figure.strengthtraining.traditional"),
        .init(id: "first_basketball", name: "First Game",
              description: "Logged your first basketball session.",
              category: .firsts, glyph: "basketball.fill"),
        .init(id: "first_swim", name: "First Swim",
              description: "Logged your first swim.",
              category: .firsts, glyph: "figure.pool.swim"),
        .init(id: "first_custom_activity", name: "On Your Terms",
              description: "Logged your first custom activity.",
              category: .firsts, glyph: "figure.run"),
        .init(id: "first_hydration", name: "First Sip",
              description: "Logged your first ounce.",
              category: .firsts, glyph: "drop.fill"),
        .init(id: "first_fast_complete", name: "First Fast Closed",
              description: "Closed your first fasting window.",
              category: .firsts, glyph: "timer"),
        .init(id: "first_intention", name: "Plan Maker",
              description: "Created your first implementation intention.",
              category: .firsts, glyph: "arrow.right.circle.fill"),
        .init(id: "first_coach_insight", name: "Counsel",
              description: "Generated your first Coach insight.",
              category: .firsts, glyph: "brain.head.profile"),

        // MARK: Cumulative
        .init(id: "ten_workouts", name: "Ten Sessions",
              description: "Logged 10 total workouts.",
              category: .cumulative, glyph: "10.circle.fill"),
        .init(id: "fifty_workouts", name: "Fifty Sessions",
              description: "Logged 50 total workouts.",
              category: .cumulative, glyph: "50.circle.fill"),
        .init(id: "tonnage_25k", name: "Tonnage I",
              description: "Moved 25,000 lb total.",
              category: .cumulative, glyph: "scalemass.fill"),
        .init(id: "tonnage_100k", name: "Tonnage II",
              description: "Moved 100,000 lb total.",
              category: .cumulative, glyph: "scalemass"),
        .init(id: "pool_2000m", name: "Pool Patience",
              description: "2,000 meters of swim distance.",
              category: .cumulative, glyph: "figure.pool.swim"),
        .init(id: "hydration_30days", name: "Hydration Honest",
              description: "Hit your hydration target on 30 days.",
              category: .cumulative, glyph: "drop.degreesign"),
        .init(id: "fasts_30", name: "Kitchen Discipline I",
              description: "Closed 30 fasting windows.",
              category: .cumulative, glyph: "fork.knife.circle"),
        .init(id: "learning_10h", name: "Ten Hours Learning",
              description: "Logged 10 hours of focused learning.",
              category: .cumulative, glyph: "book.fill"),

        // MARK: Combos
        .init(id: "two_weeks_two_disciplines", name: "Two Weeks, Two Disciplines",
              description: "Workout streak ≥14 and learning streak ≥14 at the same time.",
              category: .combo, glyph: "rectangle.split.2x1.fill"),
        .init(id: "three_disciplines_week", name: "Triple Threat",
              description: "Hit workout, hydration, and learning streaks of 7+ at once.",
              category: .combo, glyph: "circle.grid.3x3.fill"),

        // MARK: Mastery
        .init(id: "all_eight_states", name: "All Eight",
              description: "Triggered all 8 mascot states at least once.",
              category: .mastery, glyph: "person.fill.viewfinder"),
        .init(id: "schedule_customized", name: "Yours, Not Mine",
              description: "Edited or added at least 3 custom schedule blocks.",
              category: .mastery, glyph: "calendar.badge.plus"),
        .init(id: "five_intentions", name: "Architect",
              description: "Have 5 active implementation intentions.",
              category: .mastery, glyph: "list.bullet.rectangle.fill"),
        .init(id: "diagnostics_clean", name: "Diagnostician",
              description: "Opened the Diagnostics view (you peek under the hood).",
              category: .mastery, glyph: "stethoscope"),

        // MARK: Consistency (smaller grain than MilestoneRegistry)
        .init(id: "three_in_a_row", name: "Three In A Row",
              description: "3 consecutive days with master metric ≥ 75%.",
              category: .consistency, glyph: "3.circle.fill"),
        .init(id: "perfect_week", name: "Perfect Week",
              description: "7 days where every scheduled domain was completed.",
              category: .consistency, glyph: "star.fill")
    ]

    static func definition(forID id: String) -> AchievementDefinition? {
        allAchievements.first { $0.id == id }
    }

    static var groupedByCategory: [(category: AchievementCategory, items: [AchievementDefinition])] {
        AchievementCategory.allCases.map { cat in
            (cat, allAchievements.filter { $0.category == cat })
        }
    }
}

@MainActor
final class AchievementService {
    private let modelContext: ModelContext
    private let timezone: TimeZone
    private let logger = Logger(subsystem: "com.rawlins.PersonalOptimization", category: "achievements")

    init(modelContext: ModelContext,
         timezone: TimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current) {
        self.modelContext = modelContext
        self.timezone = timezone
    }

    /// Walk the registry and unlock anything the user has earned. Returns the
    /// set of achievements unlocked this call.
    @discardableResult
    func evaluate(asOf date: Date = Date()) throws -> [Achievement] {
        let alreadyUnlocked = try modelContext.fetch(FetchDescriptor<Achievement>())
        let alreadyUnlockedIDs = Set(alreadyUnlocked.map(\.identifier))

        let metrics = computeMetrics(asOf: date)
        var unlocked: [Achievement] = []

        for definition in AchievementRegistry.allAchievements where !alreadyUnlockedIDs.contains(definition.id) {
            if isUnlocked(definitionID: definition.id, metrics: metrics) {
                let row = Achievement(identifier: definition.id, unlockedAt: date)
                modelContext.insert(row)
                unlocked.append(row)
                logger.info("Achievement unlocked: \(definition.id, privacy: .public)")
            }
        }
        if !unlocked.isEmpty {
            try modelContext.save()
        }
        return unlocked
    }

    /// Most recent unlock that hasn't fired its toast yet.
    func nextPendingCelebration() -> Achievement? {
        let descriptor = FetchDescriptor<Achievement>(
            sortBy: [SortDescriptor(\.unlockedAt, order: .reverse)]
        )
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return all.first { !$0.celebrationShown }
    }

    func markCelebrationShown(_ achievement: Achievement) {
        achievement.celebrationShown = true
        try? modelContext.save()
    }

    /// Returns the unlocked subset for UI rendering (id → unlock date).
    func unlockedByID() -> [String: Date] {
        let rows = (try? modelContext.fetch(FetchDescriptor<Achievement>())) ?? []
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.identifier, $0.unlockedAt) })
    }

    // MARK: - Metric harvest

    private struct Metrics {
        let liftSessionCount: Int
        let basketballSessionCount: Int
        let swimSessionCount: Int
        let customSessionCount: Int
        let liftTotalVolume: Double
        let swimTotalMeters: Double
        let totalWorkouts: Int
        let hydrationLogCount: Int
        let hydrationDaysHit: Int
        let fastingDaysCompleted: Int
        let learningMinutesTotal: Int
        let workoutStreak: Int
        let hydrationStreak: Int
        let learningStreak: Int
        let activeIntentionCount: Int
        let totalIntentionCount: Int
        let coachInsightCount: Int
        let customScheduleBlockCount: Int
        let mascotStatesTriggered: Set<String>
        let highAdherenceDays: Int
        let perfectDays: Int
    }

    private func computeMetrics(asOf date: Date) -> Metrics {
        let lifts = (try? modelContext.fetch(FetchDescriptor<LiftSession>())) ?? []
        let bball = (try? modelContext.fetch(FetchDescriptor<BasketballSession>())) ?? []
        let swims = (try? modelContext.fetch(FetchDescriptor<SwimSession>())) ?? []
        let customs = (try? modelContext.fetch(FetchDescriptor<CustomActivitySession>())) ?? []
        let workouts = (try? modelContext.fetch(FetchDescriptor<WorkoutEvent>())) ?? []
        let logs = (try? modelContext.fetch(FetchDescriptor<DailyLog>())) ?? []
        let hydrationEntries = (try? modelContext.fetch(FetchDescriptor<HydrationEntry>())) ?? []
        let intentions = (try? modelContext.fetch(FetchDescriptor<ImplementationIntention>())) ?? []
        let coachInsights = (try? modelContext.fetch(FetchDescriptor<CoachInsight>())) ?? []
        let blocks = (try? modelContext.fetch(FetchDescriptor<ScheduleBlock>())) ?? []
        let mascotLogs = (try? modelContext.fetch(FetchDescriptor<CharacterStateLog>())) ?? []
        let archives = (try? modelContext.fetch(FetchDescriptor<ActivityArchive>())) ?? []
        let counters = (try? modelContext.fetch(FetchDescriptor<StreakCounter>())) ?? []

        let workoutStreak = counters.first { $0.domain == StreakDomain.workout.rawValue }?.currentStreak ?? 0
        let hydrationStreak = counters.first { $0.domain == StreakDomain.hydration.rawValue }?.currentStreak ?? 0
        let learningStreak = counters.first { $0.domain == StreakDomain.learning.rawValue }?.currentStreak ?? 0

        let liftTotalVolume = lifts.reduce(0) { $0 + $1.totalVolumeLbs }
        let swimTotalMeters = swims.reduce(0) { $0 + $1.totalMeters }

        let hydrationDaysHit = logs.filter { $0.waterOz >= 64 }.count
        let fastingDaysCompleted = logs.filter { $0.fastEnd != nil }.count
        let learningMinutesTotal = logs.reduce(0) { $0 + $1.japaneseMinutes + $1.guitarMinutes + $1.courseworkMinutes }

        let mascotStatesTriggered = Set(mascotLogs.map(\.stateRaw))

        // High-adherence runs: count contiguous trailing archives ≥ 0.75.
        let sortedArchives = archives.sorted { $0.date > $1.date }
        var trailingHigh = 0
        for archive in sortedArchives {
            if archive.masterMetric >= 0.75 { trailingHigh += 1 } else { break }
        }
        // Perfect days = archives at 1.0 master metric.
        let perfectDays = archives.filter { $0.masterMetric >= 0.999 }.count

        return Metrics(
            liftSessionCount: lifts.count,
            basketballSessionCount: bball.count,
            swimSessionCount: swims.count,
            customSessionCount: customs.count,
            liftTotalVolume: liftTotalVolume,
            swimTotalMeters: swimTotalMeters,
            totalWorkouts: workouts.filter(\.completed).count,
            hydrationLogCount: hydrationEntries.count,
            hydrationDaysHit: hydrationDaysHit,
            fastingDaysCompleted: fastingDaysCompleted,
            learningMinutesTotal: learningMinutesTotal,
            workoutStreak: workoutStreak,
            hydrationStreak: hydrationStreak,
            learningStreak: learningStreak,
            activeIntentionCount: intentions.filter(\.active).count,
            totalIntentionCount: intentions.count,
            coachInsightCount: coachInsights.count,
            customScheduleBlockCount: blocks.filter(\.isCustom).count,
            mascotStatesTriggered: mascotStatesTriggered,
            highAdherenceDays: trailingHigh,
            perfectDays: perfectDays
        )
    }

    private func isUnlocked(definitionID: String, metrics: Metrics) -> Bool {
        switch definitionID {
        case "first_lift":             return metrics.liftSessionCount >= 1
        case "first_basketball":       return metrics.basketballSessionCount >= 1
        case "first_swim":             return metrics.swimSessionCount >= 1
        case "first_custom_activity":  return metrics.customSessionCount >= 1
        case "first_hydration":        return metrics.hydrationLogCount >= 1
        case "first_fast_complete":    return metrics.fastingDaysCompleted >= 1
        case "first_intention":        return metrics.totalIntentionCount >= 1
        case "first_coach_insight":    return metrics.coachInsightCount >= 1

        case "ten_workouts":           return metrics.totalWorkouts >= 10
        case "fifty_workouts":         return metrics.totalWorkouts >= 50
        case "tonnage_25k":            return metrics.liftTotalVolume >= 25_000
        case "tonnage_100k":           return metrics.liftTotalVolume >= 100_000
        case "pool_2000m":             return metrics.swimTotalMeters >= 2_000
        case "hydration_30days":       return metrics.hydrationDaysHit >= 30
        case "fasts_30":               return metrics.fastingDaysCompleted >= 30
        case "learning_10h":           return metrics.learningMinutesTotal >= 10 * 60

        case "two_weeks_two_disciplines":
            return metrics.workoutStreak >= 14 && metrics.learningStreak >= 14
        case "three_disciplines_week":
            return metrics.workoutStreak >= 7 && metrics.hydrationStreak >= 7 && metrics.learningStreak >= 7

        case "all_eight_states":
            // CharacterState has 8 cases; check that we've seen ≥ 8 distinct raws.
            return metrics.mascotStatesTriggered.count >= 8
        case "schedule_customized":    return metrics.customScheduleBlockCount >= 3
        case "five_intentions":        return metrics.activeIntentionCount >= 5
        case "diagnostics_clean":      return false  // unlocked imperatively when DiagnosticsView appears

        case "three_in_a_row":         return metrics.highAdherenceDays >= 3
        case "perfect_week":           return metrics.perfectDays >= 7

        default: return false
        }
    }

    /// Imperative unlock used by views that don't fit a metric (e.g. opened
    /// the Diagnostics view). Idempotent — won't double-insert.
    func unlockImperative(_ id: String) throws {
        let descriptor = FetchDescriptor<Achievement>(
            predicate: #Predicate<Achievement> { $0.identifier == id }
        )
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        guard existing.isEmpty else { return }
        let row = Achievement(identifier: id)
        modelContext.insert(row)
        try modelContext.save()
        logger.info("Achievement unlocked imperatively: \(id, privacy: .public)")
    }
}
