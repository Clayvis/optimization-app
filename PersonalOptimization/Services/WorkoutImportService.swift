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
    let sourceBundleIdentifier: String?

    init(hkUUID: UUID, source: WorkoutEventSource, start: Date, end: Date,
         sourceBundleIdentifier: String? = nil) {
        self.hkUUID = hkUUID
        self.source = source
        self.start = start
        self.end = end
        self.sourceBundleIdentifier = sourceBundleIdentifier
    }
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
            guard workout.end > workout.start else { continue }
            // The phone ledger is saved before its Health export. Watch data
            // can arrive through Health before CloudKit, so never discard a
            // watch sample unless its matching local completion is present.
            if let bundle = workout.sourceBundleIdentifier {
                if bundle == BuildConfig.bundlePrefix { continue }
                if bundle == "\(BuildConfig.bundlePrefix).watchkitapp",
                   try hasLocalCompletion(matching: workout) { continue }
            }
            let uuid = workout.hkUUID
            if seen.contains(uuid) { continue }
            let existing = try modelContext.fetch(
                FetchDescriptor<WorkoutEvent>(predicate: #Predicate<WorkoutEvent> { $0.hkWorkoutUUID == uuid })
            ).first
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
            modelContext.insert(CompletionHistory(domain: .workout, timestamp: workout.end))
            imported += 1
        }
        if imported > 0 {
            try modelContext.save()
            logger.info("Imported \(imported, privacy: .public) HealthKit workout(s) into the ledger.")
        }
        return imported
    }

    private func hasLocalCompletion(matching workout: ImportedWorkout) throws -> Bool {
        let lower = workout.start.addingTimeInterval(-5)
        let upper = workout.start.addingTimeInterval(5)
        let source = workout.source.rawValue
        let day = calendar.startOfDay(for: workout.start)
        let events = try modelContext.fetch(FetchDescriptor<WorkoutEvent>(predicate: #Predicate {
            $0.date == day && $0.source == source && $0.completed && $0.hkWorkoutUUID == nil
        }))
        guard !events.isEmpty else { return false }
        let durations: [TimeInterval]
        switch workout.source {
        case .lift:
            durations = try modelContext.fetch(FetchDescriptor<LiftSession>(predicate: #Predicate {
                $0.date >= lower && $0.date <= upper && $0.durationMinutes > 0
            })).map { TimeInterval($0.durationMinutes) * 60 }
        case .swim:
            durations = try modelContext.fetch(FetchDescriptor<SwimSession>(predicate: #Predicate {
                $0.date >= lower && $0.date <= upper && $0.durationMinutes > 0
            })).map { TimeInterval($0.durationMinutes) * 60 }
        case .basketball:
            durations = try modelContext.fetch(FetchDescriptor<BasketballSession>(predicate: #Predicate {
                $0.startTime >= lower && $0.startTime <= upper
            })).filter { $0.endTime > $0.startTime }.map { $0.endTime.timeIntervalSince($0.startTime) }
        case .custom:
            durations = try modelContext.fetch(FetchDescriptor<CustomActivitySession>(predicate: #Predicate {
                $0.date >= lower && $0.date <= upper && $0.durationMinutes > 0
            })).map { TimeInterval($0.durationMinutes) * 60 }
        default:
            return false
        }
        return durations.contains { abs($0 - workout.end.timeIntervalSince(workout.start)) < 60 }
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
            end: hkWorkout.endDate,
            sourceBundleIdentifier: hkWorkout.sourceRevision.source.bundleIdentifier
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
