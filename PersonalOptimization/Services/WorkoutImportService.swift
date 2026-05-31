import Foundation
import SwiftData
import HealthKit
import os

/// A workout observed from HealthKit (Apple Watch or a third-party app), reduced
/// to the fields the app needs to log it. Value type so the persistence logic is
/// unit-testable without constructing HKWorkout objects.
struct ImportedWorkout: Sendable, Equatable {
    let hkUUID: UUID
    let source: WorkoutEventSource
    let start: Date
    let end: Date
}

/// Imports workouts recorded outside the app (the Apple Watch Workout app,
/// Strava, Nike, etc.) into the app's ledger so the user does not have to open
/// the app and run a manual timer to get credit. This closes the "the app does
/// not realize I am working out" gap.
///
/// Append-only and idempotent: every imported workout is deduped by its
/// HealthKit UUID, so re-firing the observer, or importing a workout this app
/// itself wrote to Health, never double-counts. Never deletes (retention).
@MainActor
final class WorkoutImportService {
    private let modelContext: ModelContext
    private let calendar: Calendar
    private let logger = Logger.healthkit

    init(modelContext: ModelContext, calendar: Calendar) {
        self.modelContext = modelContext
        self.calendar = calendar
    }

    /// Builds the service with the user's timezone calendar so the day key
    /// matches every other workout-logging path.
    static func forUser(modelContext: ModelContext) -> WorkoutImportService {
        WorkoutImportService(
            modelContext: modelContext,
            calendar: UserCalendar.current(modelContext: modelContext)
        )
    }

    /// Insert a WorkoutEvent (and a CompletionHistory row) for each imported
    /// workout that is not already present, deduped by HealthKit UUID. Returns
    /// the number of newly imported workouts.
    @discardableResult
    func importWorkouts(_ workouts: [ImportedWorkout]) throws -> Int {
        var imported = 0
        // Dedupe within the batch too: a predicate fetch may not see rows
        // inserted-but-not-yet-saved earlier in this same loop.
        var seen = Set<UUID>()
        for workout in workouts {
            let uuid = workout.hkUUID
            if seen.contains(uuid) { continue }
            let existing = modelContext.fetchFirstOrNil(
                FetchDescriptor<WorkoutEvent>(predicate: #Predicate<WorkoutEvent> { $0.hkWorkoutUUID == uuid })
            )
            if existing != nil { continue }

            seen.insert(uuid)
            let day = calendar.startOfDay(for: workout.start)
            let event = WorkoutEvent(
                date: day,
                completed: true,
                source: workout.source,
                hkWorkoutUUID: workout.hkUUID
            )
            modelContext.insert(event)
            CompletionHistoryWriter.record(domain: .workout, at: workout.end, modelContext: modelContext)
            imported += 1
        }
        if imported > 0 {
            try modelContext.save()
            logger.info("Imported \(imported, privacy: .public) HealthKit workout(s) into the ledger.")
        }
        return imported
    }
}

extension ImportedWorkout {
    /// Map a HealthKit workout to the app's import value. Returns nil for a
    /// zero- or negative-length sample (defensive). Reads only stable,
    /// non-deprecated HKWorkout properties.
    init?(hkWorkout: HKWorkout) {
        guard hkWorkout.endDate > hkWorkout.startDate else { return nil }
        self.init(
            hkUUID: hkWorkout.uuid,
            source: WorkoutEventSource.from(hkWorkout.workoutActivityType),
            start: hkWorkout.startDate,
            end: hkWorkout.endDate
        )
    }
}

extension WorkoutEventSource {
    /// Map a HealthKit activity type onto the app's coarse workout sources.
    /// Unmapped activities fall back to `.custom`, which the app already uses
    /// for user-defined activities (running, HIIT, yoga, etc.).
    static func from(_ activityType: HKWorkoutActivityType) -> WorkoutEventSource {
        switch activityType {
        case .traditionalStrengthTraining, .functionalStrengthTraining, .crossTraining:
            return .lift
        case .basketball:
            return .basketball
        case .swimming, .waterFitness:
            return .swim
        default:
            return .custom
        }
    }
}
