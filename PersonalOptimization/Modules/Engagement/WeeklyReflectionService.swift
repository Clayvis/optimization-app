import Foundation
import SwiftData
import os

/// Generates `WeeklyReflection` rows from `ActivityArchive` aggregates.
/// Idempotent per ISO-week (Monday-anchored). On Sundays the TodayView
/// surfaces "this week's reflection" — `current()` returns it; if absent the
/// service generates and persists one.
@MainActor
final class WeeklyReflectionService {
    private let modelContext: ModelContext
    private let timezone: TimeZone
    private let logger = Logger(subsystem: BuildConfig.loggingSubsystem, category: "weekly")

    init(modelContext: ModelContext,
         timezone: TimeZone = TimeZone.current) {
        self.modelContext = modelContext
        self.timezone = timezone
    }

    /// Returns the reflection for the week containing `date`, generating it
    /// on demand when not already persisted.
    @discardableResult
    func currentOrGenerate(asOf date: Date = Date()) throws -> WeeklyReflection {
        let weekStart = mondayOfWeek(containing: date)
        let descriptor = FetchDescriptor<WeeklyReflection>(
            predicate: #Predicate<WeeklyReflection> { $0.weekStartDate == weekStart }
        )
        if let existing = modelContext.fetchFirstOrNil(descriptor) {
            return existing
        }
        return try generate(weekStartDate: weekStart)
    }

    /// Force-regenerates the reflection for the week containing `date`. Used
    /// when the user adds late-day data and wants a fresh take.
    @discardableResult
    func regenerate(asOf date: Date = Date()) throws -> WeeklyReflection {
        let weekStart = mondayOfWeek(containing: date)
        let descriptor = FetchDescriptor<WeeklyReflection>(
            predicate: #Predicate<WeeklyReflection> { $0.weekStartDate == weekStart }
        )
        if let existing = modelContext.fetchFirstOrNil(descriptor) {
            modelContext.delete(existing)
        }
        return try generate(weekStartDate: weekStart)
    }

    /// Pure: generate from ActivityArchive rows in [weekStart, weekStart+7d).
    private func generate(weekStartDate: Date) throws -> WeeklyReflection {
        let cal = jstCalendar()
        let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStartDate) ?? weekStartDate

        let archivesDescriptor = FetchDescriptor<ActivityArchive>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let allArchives = modelContext.fetchOrEmpty(archivesDescriptor)
        let archives = allArchives.filter { $0.date >= weekStartDate && $0.date < weekEnd }

        let adherenceMean: Double = {
            guard !archives.isEmpty else { return 0 }
            return archives.reduce(0) { $0 + $1.masterMetric } / Double(archives.count)
        }()
        let bestArchive = archives.max(by: { $0.masterMetric < $1.masterMetric })
        let bestDay: Int = bestArchive.map { isoWeekday(for: $0.date) } ?? 1

        let workoutCount = archives.reduce(0) { $0 + $1.workoutCount }
        let hydrationDaysMet = archives.filter { $0.hydrationOz >= 64 }.count
        let fastingDaysCompleted = archives.filter { $0.fastingHours >= 14 }.count
        let learningMinutesTotal = archives.reduce(0) { $0 + $1.learningMinutes }

        // Best/weakest domain by which made the most/fewest threshold hits.
        let domainHits: [(domain: String, hits: Int)] = [
            ("workout", workoutCount),
            ("hydration", hydrationDaysMet),
            ("fasting", fastingDaysCompleted),
            ("learning", learningMinutesTotal / 30) // crude conversion to "days hit"
        ]
        let bestDomain = domainHits.max { $0.hits < $1.hits }?.domain ?? "workout"
        let weakestDomain = domainHits.min { $0.hits < $1.hits }?.domain ?? "hydration"

        let dominantState: String = {
            var counts: [String: Int] = [:]
            for a in archives { counts[a.dominantMascotState, default: 0] += 1 }
            return counts.max(by: { $0.value < $1.value })?.key ?? "neutral"
        }()

        let coachMessage = Self.composeCoachMessage(
            adherence: adherenceMean,
            workouts: workoutCount,
            bestDomain: bestDomain
        )

        let reflection = WeeklyReflection(
            weekStartDate: weekStartDate,
            generatedAt: Date(),
            adherencePercent: adherenceMean,
            bestDomain: bestDomain,
            weakestDomain: weakestDomain,
            bestDayOfWeek: bestDay,
            workoutCount: workoutCount,
            hydrationDaysMet: hydrationDaysMet,
            fastingDaysCompleted: fastingDaysCompleted,
            learningMinutesTotal: learningMinutesTotal,
            dominantMascotState: dominantState,
            coachMessage: coachMessage
        )
        modelContext.insert(reflection)
        try modelContext.save()
        logger.info("Generated reflection for week \(weekStartDate, privacy: .public)")
        return reflection
    }

    /// Pure helper for the identity-framed coach message. Stays as a static
    /// function so it's easy to unit-test without a model container.
    static func composeCoachMessage(adherence: Double,
                                    workouts: Int,
                                    bestDomain: String) -> String {
        let pct = Int((adherence * 100).rounded())
        if pct >= 85 {
            return "You showed up \(pct)% this week. That's the standard, not the exception."
        }
        if pct >= 60 {
            return "Solid week — \(pct)% adherence with \(workouts) workout\(workouts == 1 ? "" : "s") logged. Build on the \(bestDomain) base."
        }
        if pct >= 30 {
            return "A few hits, a few misses. \(pct)% week. The pattern matters more than any single day."
        }
        return "Tough week. \(pct)% adherence. Show up next week and the streak resets cleanly."
    }

    // MARK: - Helpers

    func mondayOfWeek(containing date: Date) -> Date {
        let cal = jstCalendar()
        let weekday = isoWeekday(for: date)
        let delta = -(weekday - 1)
        let day = cal.startOfDay(for: date)
        return cal.date(byAdding: .day, value: delta, to: day) ?? day
    }

    private func isoWeekday(for date: Date) -> Int {
        let raw = jstCalendar().component(.weekday, from: date)
        return raw == 1 ? 7 : raw - 1
    }

    private func jstCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        return cal
    }
}
