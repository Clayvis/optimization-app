import Foundation
import SwiftData
import os

@MainActor
final class LearningService {
    private let modelContext: ModelContext
    private let timezone: TimeZone
    private let logger = Logger.app

    init(modelContext: ModelContext, timezone: TimeZone = TimeZone.current) {
        self.modelContext = modelContext
        self.timezone = timezone
    }

    /// Adds `minutes` to today's DailyLog (Japanese or Guitar field) and recomputes the
    /// LearningStreak entity for the module. Returns the updated streak.
    @discardableResult
    func logMinutes(module: LearningModule, minutes: Int, at date: Date = Date()) throws -> LearningStreak {
        let log = upsertDailyLog(for: date)
        switch module {
        case .japanese: log.japaneseMinutes += minutes
        case .guitar:   log.guitarMinutes += minutes
        case .music:    log.musicMinutes += minutes
        }
        try modelContext.save()
        CompletionHistoryWriter.record(domain: .learning, at: date, modelContext: modelContext)
        return try recomputeStreak(module: module, asOf: date)
    }

    /// Recomputes currentStreak and longestStreak for the module using all DailyLog
    /// rows in the store.
    @discardableResult
    func recomputeStreak(module: LearningModule, asOf: Date = Date()) throws -> LearningStreak {
        let logs = try modelContext.fetch(FetchDescriptor<DailyLog>(predicate: #Predicate<DailyLog> { $0.supersededAt == nil }))
        let history: [DailyMinutes] = logs.map { log in
            let m: Int
            switch module {
            case .japanese: m = log.japaneseMinutes
            case .guitar:   m = log.guitarMinutes
            case .music:    m = log.musicMinutes
            }
            return DailyMinutes(date: log.date, minutes: m)
        }
        let threshold = module.defaultDailyTargetMinutes
        let current = LearningStreakCalculator.currentStreak(history: history, threshold: threshold, asOf: asOf, timezone: timezone)
        let longest = LearningStreakCalculator.longestStreak(history: history, threshold: threshold, timezone: timezone)
        let totalMinutesAllTime = history.reduce(0) { $0 + $1.minutes }

        let streak = upsertStreak(module: module)
        streak.currentStreak = current
        streak.longestStreak = max(streak.longestStreak, longest)
        streak.totalMinutesAllTime = totalMinutesAllTime
        streak.lastCompletedDate = mostRecentQualifyingDay(history: history, threshold: threshold)
        try modelContext.save()
        logger.info("\(module.rawValue, privacy: .public) streak current=\(current, privacy: .public) longest=\(streak.longestStreak, privacy: .public)")
        return streak
    }

    func currentStreak(module: LearningModule) -> LearningStreak {
        upsertStreak(module: module)
    }

    // MARK: - Helpers

    private func upsertDailyLog(for date: Date) -> DailyLog {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        return DailyLogStore(modelContext: modelContext, calendar: cal).upsert(for: date)
    }

    private func upsertStreak(module: LearningModule) -> LearningStreak {
        let key = module.rawValue
        let descriptor = FetchDescriptor<LearningStreak>(
            predicate: #Predicate<LearningStreak> { $0.module == key }
        )
        if let existing = modelContext.fetchFirstOrNil(descriptor) {
            return existing
        }
        let new = LearningStreak(module: module.rawValue)
        modelContext.insert(new)
        return new
    }

    private func mostRecentQualifyingDay(history: [DailyMinutes], threshold: Int) -> Date? {
        history.filter { $0.minutes >= threshold }
            .map { $0.date }
            .max()
    }
}
