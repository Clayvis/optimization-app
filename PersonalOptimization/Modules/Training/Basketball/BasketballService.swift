import Foundation
import SwiftData
import os

@MainActor
final class BasketballService {
    private let modelContext: ModelContext
    private let healthKit: HealthKitServiceProtocol?
    private let logger = Logger.app

    init(modelContext: ModelContext, healthKit: HealthKitServiceProtocol? = nil) {
        self.modelContext = modelContext
        self.healthKit = healthKit
    }

    /// Starts a session at `start`, with a placeholder endTime equal to start.
    func startSession(at start: Date) throws -> BasketballSession {
        let session = BasketballSession(date: start, startTime: start, endTime: start)
        modelContext.insert(session)
        try modelContext.save()
        return session
    }

    /// Adds one minute to the zone bucket for the given heart rate.
    func logMinute(in session: BasketballSession, bpm: Int, maxHR: Int) throws {
        let zone = BasketballService.zone(for: bpm, maxHR: maxHR)
        var zones = session.hrZoneMinutes
        zones[zone, default: 0] += 1
        session.hrZoneMinutes = zones
        try modelContext.save()
    }

    /// Closes the session and writes check-in fields. Also stamps the DailyLog with
    /// today's Achilles score so the cross-pillar dashboard surfaces it.
    /// HealthKit write is dispatched fire-and-forget via SessionLifecycleService.
    func endSession(_ session: BasketballSession,
                    endTime: Date,
                    achillesPostScore: Int?,
                    hydrationOz: Double,
                    estimatedCalories: Double? = nil) throws {
        session.endTime = endTime
        session.achillesPostScore = achillesPostScore
        session.hydrationOz = hydrationOz

        let dayStart = Calendar.current.startOfDay(for: session.date)
        let descriptor = FetchDescriptor<DailyLog>(
            predicate: #Predicate<DailyLog> { $0.date == dayStart }
        )
        let dailyLog: DailyLog
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            dailyLog = existing
        } else {
            dailyLog = DailyLog(date: session.date)
            modelContext.insert(dailyLog)
        }
        if let achillesPostScore { dailyLog.achillesPain = achillesPostScore }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        let day = cal.startOfDay(for: session.date)
        modelContext.insert(WorkoutEvent(date: day, completed: true, source: .basketball))
        try modelContext.save()
        CompletionHistoryWriter.record(domain: .workout, at: session.date, modelContext: modelContext)
        logger.info("Ended basketball session, achilles=\(achillesPostScore ?? -1, privacy: .public)")

        SessionLifecycleService.shared.dispatchHealthKitWorkout(
            activityType: .basketball,
            start: session.startTime,
            end: endTime,
            totalEnergyKcal: estimatedCalories,
            totalDistanceMeters: nil,
            healthKit: healthKit,
            modelContainer: modelContext.container
        )
    }

    /// Active session = endTime equals startTime (placeholder set by startSession).
    func currentSession(at date: Date) -> BasketballSession? {
        let descriptor = FetchDescriptor<BasketballSession>(
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        let sessions = (try? modelContext.fetch(descriptor)) ?? []
        return sessions.first { $0.startTime == $0.endTime }
    }

    // MARK: - Pure helpers

    /// Maps a heart rate to one of zone1..zone5 by % of max HR.
    /// <60% = zone1, 60-70% = zone2, 70-80% = zone3, 80-90% = zone4, >=90% = zone5.
    static func zone(for bpm: Int, maxHR: Int) -> String {
        guard maxHR > 0 else { return "zone1" }
        let pct = Double(bpm) / Double(maxHR)
        switch pct {
        case ..<0.6: return "zone1"
        case ..<0.7: return "zone2"
        case ..<0.8: return "zone3"
        case ..<0.9: return "zone4"
        default:     return "zone5"
        }
    }

    /// Should we prompt the user to drink? Cadence is 30 min from start, only re-prompts
    /// after the previous prompt rolls past another 30-minute multiple.
    static func shouldPromptHydration(elapsed: TimeInterval, lastPromptElapsed: TimeInterval?) -> Bool {
        let cadence: TimeInterval = 30 * 60
        let nextDue = ((lastPromptElapsed ?? 0) / cadence + 1) * cadence
        return elapsed >= nextDue
    }
}
