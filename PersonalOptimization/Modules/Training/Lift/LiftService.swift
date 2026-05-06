import Foundation
import SwiftData
import os

@MainActor
final class LiftService {
    private let modelContext: ModelContext
    private let templatesFile: LiftTemplatesFile
    private let healthKit: HealthKitServiceProtocol?
    private let logger = Logger.app

    init(modelContext: ModelContext,
         templatesFile: LiftTemplatesFile,
         healthKit: HealthKitServiceProtocol? = nil) {
        self.modelContext = modelContext
        self.templatesFile = templatesFile
        self.healthKit = healthKit
    }

    /// Starts a new LiftSession from the template and pre-populates exercises (no sets yet).
    func startSession(templateName: String, at date: Date = Date()) throws -> LiftSession {
        let template = try LiftTemplatesLoader.template(named: templateName, file: templatesFile)
        let session = LiftSession(date: date, template: template.name)
        modelContext.insert(session)

        var exercises: [LiftExercise] = []
        for entry in template.exercises {
            let exercise = LiftExercise(name: entry.name, orderIndex: entry.orderIndex)
            modelContext.insert(exercise)
            exercises.append(exercise)
        }
        session.exercises = exercises
        try modelContext.save()
        logger.info("Started \(template.name, privacy: .public) with \(exercises.count, privacy: .public) exercises")
        return session
    }

    /// Adds a set to the named exercise inside the session. Returns the new set.
    @discardableResult
    func logSet(in session: LiftSession, exerciseName: String, weightLbs: Double, reps: Int, restSeconds: Int? = nil) throws -> LiftSet {
        guard let exercise = (session.exercises ?? []).first(where: { $0.name == exerciseName }) else {
            throw LiftServiceError.exerciseNotFound(exerciseName)
        }
        let nextIndex = (exercise.sets ?? []).count
        let set = LiftSet(weightLbs: weightLbs, reps: reps, orderIndex: nextIndex)
        set.restSeconds = restSeconds
        modelContext.insert(set)
        var sets = exercise.sets ?? []
        sets.append(set)
        exercise.sets = sets
        try modelContext.save()
        return set
    }

    /// Closes the session, recomputing totalVolumeLbs and writing duration/avgHR.
    /// HealthKit write is dispatched fire-and-forget via SessionLifecycleService;
    /// HK failures never propagate here so the UI can update cleanly.
    func endSession(_ session: LiftSession,
                    durationMinutes: Int,
                    avgHR: Int? = nil,
                    estimatedCalories: Double? = nil) throws {
        session.totalVolumeLbs = LiftService.totalVolume(session: session)
        session.durationMinutes = durationMinutes
        session.avgHR = avgHR
        try modelContext.save()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        let day = cal.startOfDay(for: session.date)
        modelContext.insert(WorkoutEvent(date: day, completed: true, source: .lift))
        try modelContext.save()
        CompletionHistoryWriter.record(domain: .workout, at: session.date, modelContext: modelContext)
        logger.info("Ended \(session.template, privacy: .public) volume=\(session.totalVolumeLbs, privacy: .public) lbs duration=\(durationMinutes, privacy: .public) min")

        let end = session.date.addingTimeInterval(TimeInterval(durationMinutes * 60))
        SessionLifecycleService.shared.dispatchHealthKitWorkout(
            activityType: .functionalStrengthTraining,
            start: session.date,
            end: end,
            totalEnergyKcal: estimatedCalories,
            totalDistanceMeters: nil,
            healthKit: healthKit,
            modelContainer: modelContext.container
        )
    }

    /// Pure volume aggregator: sum of (weightLbs * reps) across all sets in all exercises.
    static func totalVolume(session: LiftSession) -> Double {
        let exercises = session.exercises ?? []
        return exercises.reduce(0.0) { running, exercise in
            let sets = exercise.sets ?? []
            return running + sets.reduce(0.0) { $0 + $1.weightLbs * Double($1.reps) }
        }
    }

    /// Active session is one whose totalVolumeLbs has not yet been finalized (durationMinutes == 0).
    /// Returns nil if none.
    func currentSession(at date: Date) -> LiftSession? {
        let descriptor = FetchDescriptor<LiftSession>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let sessions = (try? modelContext.fetch(descriptor)) ?? []
        return sessions.first { $0.durationMinutes == 0 }
    }
}

enum LiftServiceError: LocalizedError {
    case exerciseNotFound(String)

    var errorDescription: String? {
        switch self {
        case .exerciseNotFound(let name): return "Exercise '\(name)' not found in active session"
        }
    }
}
