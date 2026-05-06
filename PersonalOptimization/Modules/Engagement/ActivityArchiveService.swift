import Foundation
import SwiftData
import os

/// Builds the daily ActivityArchive rollup. Idempotent per (user, day): a second
/// run for the same day overwrites the row in place. Source-of-truth session and
/// log rows are never deleted; this is purely additive aggregation.
///
/// Runtime entry points:
/// - On app launch: backfill any missing archive days since the last archived date.
/// - On scene foreground: ensure today's row is current.
/// - From BGAppRefreshTask handler (registered via `BackgroundTaskScheduler`): same as launch.
@MainActor
final class ActivityArchiveService {
    private let modelContext: ModelContext
    private let timezone: TimeZone
    private let hydrationTargets: HydrationTargetsOz?
    private let logger = Logger.coach

    init(modelContext: ModelContext,
         timezone: TimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current,
         hydrationTargets: HydrationTargetsOz? = nil) {
        self.modelContext = modelContext
        self.timezone = timezone
        self.hydrationTargets = hydrationTargets
    }

    /// Computes today's rollup. Idempotent: re-runs overwrite the existing row.
    @discardableResult
    func rollupToday(asOf: Date = Date()) throws -> ActivityArchive {
        let day = startOfDay(for: asOf)
        return try rollupDay(day)
    }

    /// Backfills all archive rows from the earliest source-data day up to today.
    /// Caps at `maxDays` to bound the work; the catch-up path on app launch passes
    /// 30 days which is sufficient for normal use. First run will need a longer
    /// window; pass nil for unbounded.
    @discardableResult
    func backfill(maxDays: Int? = 30, asOf: Date = Date()) throws -> Int {
        let earliestSource = earliestSourceDataDate() ?? startOfDay(for: asOf)
        let today = startOfDay(for: asOf)
        let lower: Date = {
            guard let cap = maxDays else { return earliestSource }
            let capDate = calendar().date(byAdding: .day, value: -cap, to: today) ?? earliestSource
            return max(earliestSource, capDate)
        }()
        var cursor = lower
        var written = 0
        while cursor <= today {
            _ = try rollupDay(cursor)
            written += 1
            guard let next = calendar().date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        logger.info("Backfilled \(written, privacy: .public) archive rows from \(lower, privacy: .public) to \(today, privacy: .public)")
        return written
    }

    /// Single-day rollup. Builds the row from current SwiftData state.
    @discardableResult
    func rollupDay(_ day: Date) throws -> ActivityArchive {
        let cal = calendar()
        let dayStart = cal.startOfDay(for: day)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        let archive = upsertArchive(for: dayStart)

        archive.workoutCount = countWorkouts(in: dayStart..<dayEnd)
        archive.workoutVolumeTotal = liftVolumeSum(in: dayStart..<dayEnd)

        if let log = dailyLog(for: dayStart) {
            archive.fastingHours = computeFastingHours(log: log)
            archive.hydrationOz = log.waterOz
            archive.learningMinutes = log.japaneseMinutes + log.guitarMinutes + log.courseworkMinutes
            archive.sleepMinutesHK = log.sleepHours.map { Int($0 * 60) }
            archive.restingHRHK = log.restingHR
            archive.hrvAvgHK = log.hrvRmssd
        } else {
            archive.fastingHours = 0
            archive.hydrationOz = 0
            archive.learningMinutes = 0
            archive.sleepMinutesHK = nil
            archive.restingHRHK = nil
            archive.hrvAvgHK = nil
        }

        archive.dominantMascotState = dominantMascotState(in: dayStart..<dayEnd)
        archive.masterMetric = masterMetricRatio(for: dayStart)

        try modelContext.save()
        return archive
    }

    // MARK: - Aggregations

    private func countWorkouts(in range: Range<Date>) -> Int {
        let events = (try? modelContext.fetch(FetchDescriptor<WorkoutEvent>())) ?? []
        return events.filter { $0.completed && range.contains($0.date) }.count
    }

    private func liftVolumeSum(in range: Range<Date>) -> Double {
        let lifts = (try? modelContext.fetch(FetchDescriptor<LiftSession>())) ?? []
        return lifts.filter { range.contains($0.date) }.reduce(0) { $0 + $1.totalVolumeLbs }
    }

    private func dailyLog(for day: Date) -> DailyLog? {
        let descriptor = FetchDescriptor<DailyLog>(
            predicate: #Predicate<DailyLog> { $0.date == day }
        )
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func computeFastingHours(log: DailyLog) -> Double {
        guard let start = log.fastStart, let end = log.fastEnd else { return 0 }
        return max(0, end.timeIntervalSince(start) / 3600)
    }

    private func dominantMascotState(in range: Range<Date>) -> String {
        let logs = (try? modelContext.fetch(FetchDescriptor<CharacterStateLog>())) ?? []
        let inRange = logs.filter { range.contains($0.timestamp) }
        guard !inRange.isEmpty else { return "neutral" }
        var counts: [String: Int] = [:]
        for log in inRange { counts[log.stateRaw, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key ?? "neutral"
    }

    /// Reuses DailySummaryService logic so the master-metric value matches what
    /// the user saw in the UI on that day.
    private func masterMetricRatio(for day: Date) -> Double {
        let summary = DailySummaryService(
            modelContext: modelContext,
            timezone: timezone,
            hydrationTargets: hydrationTargets
        ).todayProtocol(asOf: day)
        guard summary.scheduledCount > 0 else { return 0 }
        return Double(summary.completedCount) / Double(summary.scheduledCount)
    }

    private func earliestSourceDataDate() -> Date? {
        let cal = calendar()
        var candidates: [Date] = []
        if let firstLog = (try? modelContext.fetch(FetchDescriptor<DailyLog>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )))?.first {
            candidates.append(cal.startOfDay(for: firstLog.date))
        }
        if let firstWorkout = (try? modelContext.fetch(FetchDescriptor<WorkoutEvent>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )))?.first {
            candidates.append(cal.startOfDay(for: firstWorkout.date))
        }
        return candidates.min()
    }

    private func upsertArchive(for day: Date) -> ActivityArchive {
        let descriptor = FetchDescriptor<ActivityArchive>(
            predicate: #Predicate<ActivityArchive> { $0.date == day }
        )
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            return existing
        }
        let archive = ActivityArchive(date: day)
        modelContext.insert(archive)
        return archive
    }

    private func calendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        return cal
    }

    private func startOfDay(for date: Date) -> Date {
        calendar().startOfDay(for: date)
    }
}
