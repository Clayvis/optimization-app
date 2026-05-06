import Foundation
import SwiftData
import os

@MainActor
final class SwimService {
    private let modelContext: ModelContext
    private let logger = Logger.app

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Starts a session at the given pool length. Default 25 m matches McTureous pool.
    func startSession(at start: Date, poolLengthMeters: Double = 25, location: String? = nil) throws -> SwimSession {
        let session = SwimSession(date: start, poolLengthMeters: poolLengthMeters)
        session.location = location
        modelContext.insert(session)
        try modelContext.save()
        return session
    }

    /// Adds `count` laps and recomputes totalMeters.
    func logLap(in session: SwimSession, count: Int = 1) throws {
        session.laps += count
        session.totalMeters = Double(session.laps) * session.poolLengthMeters
        try modelContext.save()
    }

    func endSession(_ session: SwimSession, durationMinutes: Int, avgHR: Int? = nil) throws {
        session.durationMinutes = durationMinutes
        session.avgHR = avgHR
        session.totalMeters = Double(session.laps) * session.poolLengthMeters
        try modelContext.save()
        logger.info("Ended swim session laps=\(session.laps, privacy: .public) meters=\(session.totalMeters, privacy: .public)")
    }

    /// Active session = durationMinutes == 0 (placeholder until end).
    func currentSession(at date: Date) -> SwimSession? {
        let descriptor = FetchDescriptor<SwimSession>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let sessions = (try? modelContext.fetch(descriptor)) ?? []
        return sessions.first { $0.durationMinutes == 0 }
    }
}
