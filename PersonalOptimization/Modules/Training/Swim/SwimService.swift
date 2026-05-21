import Foundation
import SwiftData
import os

@MainActor
final class SwimService {
    private let modelContext: ModelContext
    private let healthKit: HealthKitServiceProtocol?
    private let logger = Logger.app

    init(modelContext: ModelContext, healthKit: HealthKitServiceProtocol? = nil) {
        self.modelContext = modelContext
        self.healthKit = healthKit
    }

    /// Starts a session at the given pool length. Default 25 m matches McTureous pool.
    func startSession(at start: Date,
                      poolLengthMeters: Double = 25,
                      location: String? = nil,
                      waterType: SwimWaterType = .pool) throws -> SwimSession {
        let session = SwimSession(date: start, poolLengthMeters: poolLengthMeters)
        session.location = location
        session.waterTypeRaw = waterType.rawValue
        modelContext.insert(session)
        try modelContext.save()
        return session
    }

    /// Adds `count` laps and recomputes totalMeters using poolLengthMeters.
    /// Use this when waterType == .pool.
    func logLap(in session: SwimSession, count: Int = 1) throws {
        session.laps += count
        session.totalMeters = Double(session.laps) * session.poolLengthMeters
        try modelContext.save()
    }

    /// Adds raw meters directly to `totalMeters`. Use when waterType != .pool
    /// (beach / open water) where laps are not meaningful.
    func logMeters(in session: SwimSession, meters: Double) throws {
        guard meters > 0 else { return }
        session.totalMeters += meters
        try modelContext.save()
    }

    /// Sets exact distance overriding any prior accumulated value.
    /// Pool sessions: also recomputes lap count from totalMeters / poolLengthMeters.
    func setExactDistance(in session: SwimSession, meters: Double) throws {
        session.totalMeters = max(0, meters)
        if session.waterType == .pool, session.poolLengthMeters > 0 {
            session.laps = Int((session.totalMeters / session.poolLengthMeters).rounded())
        }
        try modelContext.save()
    }

    /// Sets exact lap count for pool sessions and recomputes totalMeters.
    func setExactLaps(in session: SwimSession, laps: Int) throws {
        session.laps = max(0, laps)
        session.totalMeters = Double(session.laps) * session.poolLengthMeters
        try modelContext.save()
    }

    func endSession(_ session: SwimSession,
                    durationMinutes: Int,
                    avgHR: Int? = nil,
                    estimatedCalories: Double? = nil) throws {
        session.durationMinutes = durationMinutes
        session.avgHR = avgHR
        if session.waterType == .pool {
            session.totalMeters = Double(session.laps) * session.poolLengthMeters
        }
        try modelContext.save()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let day = cal.startOfDay(for: session.date)
        modelContext.insert(WorkoutEvent(date: day, completed: true, source: .swim))
        try modelContext.save()
        CompletionHistoryWriter.record(domain: .workout, at: session.date, modelContext: modelContext)
        logger.info("Ended swim session laps=\(session.laps, privacy: .public) meters=\(session.totalMeters, privacy: .public)")

        let end = session.date.addingTimeInterval(TimeInterval(durationMinutes * 60))
        SessionLifecycleService.shared.dispatchHealthKitWorkout(
            activityType: .swimming,
            start: session.date,
            end: end,
            totalEnergyKcal: estimatedCalories,
            totalDistanceMeters: session.totalMeters,
            healthKit: healthKit,
            modelContainer: modelContext.container
        )
        #if os(iOS)
        WorkoutLiveActivityController.dismissAllSync()
        #endif
    }

    /// Active session = durationMinutes == 0 (placeholder until end).
    func currentSession(at date: Date) -> SwimSession? {
        let descriptor = FetchDescriptor<SwimSession>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let sessions = (try? modelContext.fetch(descriptor)) ?? []
        return sessions.first { $0.durationMinutes == 0 }
    }

    /// Returns the last `limit` distinct, non-empty location names ordered most-recent first.
    func recentLocations(limit: Int = 5) -> [String] {
        var descriptor = FetchDescriptor<SwimSession>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 50
        let sessions = (try? modelContext.fetch(descriptor)) ?? []
        var seen = Set<String>()
        var out: [String] = []
        for s in sessions {
            guard let loc = s.location?.trimmingCharacters(in: .whitespaces),
                  !loc.isEmpty,
                  !seen.contains(loc) else { continue }
            seen.insert(loc)
            out.append(loc)
            if out.count >= limit { break }
        }
        return out
    }
}
