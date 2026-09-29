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
        return try startSession(template: template, at: date)
    }

    /// Creates an explicit user-started workout from a reviewed suggestion.
    /// Targets are preserved; no suggested set is counted as completed.
    func startSession(template: LiftTemplate, at date: Date = Date(), prescription: PrescribedWorkout? = nil) throws -> LiftSession {
        if let prescription, let id = prescription.sessionUUID {
            let sessions = try modelContext.fetch(FetchDescriptor<LiftSession>())
            if let existing = sessions.first(where: { $0.sessionID == id }) { return existing }
            // The linked session may still be arriving through iCloud. Never duplicate it.
            throw LiftServiceError.linkedSessionUnavailable
        }
        guard !template.exercises.isEmpty,
              template.exercises.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  && (1...10).contains($0.targetSets) && (1...40).contains($0.targetReps) }) else {
            throw LiftServiceError.invalidPlan
        }
        let session = LiftSession(date: date, template: template.name)
        try modelContext.transaction {
            modelContext.insert(session)
            session.exercises = template.exercises.map { entry in
                let exercise = LiftExercise(name: entry.name, orderIndex: entry.orderIndex)
                exercise.progressionSets = entry.targetSets
                exercise.progressionLowerReps = entry.targetReps
                exercise.progressionUpperReps = entry.targetReps
                exercise.session = session
                return exercise
            }
            if let prescription {
                prescription.sessionUUID = session.sessionID
                prescription.status = .accepted
            }
            try modelContext.save()
        }
        logger.info("Started \(template.name, privacy: .public) with \(template.exercises.count, privacy: .public) exercises")
        return session
    }

    /// Adds a custom exercise to the session inline. Marks `isCustom = true` so
    /// downstream analytics and history can distinguish ad-hoc additions from template
    /// exercises. Order index is appended after existing exercises.
    @discardableResult
    func addCustomExercise(in session: LiftSession, name: String) throws -> LiftExercise {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw LiftServiceError.invalidExerciseName
        }
        let nextIndex = (session.exercises ?? []).map { $0.orderIndex }.max().map { $0 + 1 } ?? 0
        // Reuse the spelling and targets from the last finished workout with this
        // exercise, so history, prefill and progression stay linked by name.
        let previous = try lastCompletedExercise(named: trimmed, before: session.date)
        let exercise = LiftExercise(name: previous?.name ?? trimmed, orderIndex: nextIndex, isCustom: true)
        if let previous {
            exercise.progressionSets = previous.progressionSets
            exercise.progressionLowerReps = previous.progressionLowerReps
            exercise.progressionUpperReps = previous.progressionUpperReps
        }
        modelContext.insert(exercise)
        var current = session.exercises ?? []
        current.append(exercise)
        session.exercises = current
        try modelContext.save()
        return exercise
    }

    // MARK: - Workouts that change from day to day

    /// Title for a workout built as you go when the user leaves the name blank.
    static let freestyleName = "Workout"

    /// Starts a workout with no exercises; the user adds them as they train.
    func startFreestyleSession(name: String, at date: Date = Date()) throws -> LiftSession {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = LiftSession(date: date, template: trimmed.isEmpty ? Self.freestyleName : trimmed)
        try modelContext.transaction {
            modelContext.insert(session)
            session.exercises = []
            try modelContext.save()
        }
        logger.info("Started \(session.template, privacy: .public) with no exercises")
        return session
    }

    /// Finished workouts with at least one exercise, newest first, one per
    /// title and exercise list so a repeated routine appears once.
    func recentWorkouts(limit: Int = 5, before date: Date = Date()) throws -> [LiftSession] {
        let sessions = try modelContext.fetch(FetchDescriptor<LiftSession>(
            predicate: #Predicate { $0.durationMinutes > 0 && $0.date <= date },
            sortBy: [SortDescriptor(\.date, order: .reverse)]))
        var seen = Set<String>()
        var result: [LiftSession] = []
        for session in sessions {
            let names = (session.exercises ?? []).sorted { $0.orderIndex < $1.orderIndex }.map(\.name)
            guard !names.isEmpty, seen.insert(([session.template] + names).joined(separator: "\u{1F}")).inserted else {
                continue
            }
            result.append(session)
            if result.count == limit { break }
        }
        return result
    }

    /// Exercise names with at least one logged set in a finished workout, most
    /// often trained first, then most recent. Feeds the quick picks.
    func recentExerciseNames(limit: Int = 12, excluding: Set<String> = []) throws -> [String] {
        let exercises = try modelContext.fetch(FetchDescriptor<LiftExercise>())
        var counts: [String: (count: Int, last: Date)] = [:]
        for exercise in exercises where !(exercise.sets ?? []).isEmpty {
            guard let session = exercise.session, session.durationMinutes > 0 else { continue }
            let entry = counts[exercise.name] ?? (0, .distantPast)
            counts[exercise.name] = (entry.count + 1, max(entry.last, session.date))
        }
        let excluded = Set(excluding.map { $0.lowercased() })
        return counts.filter { !excluded.contains($0.key.lowercased()) }
            .sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.value.last > $1.value.last }
            .prefix(limit).map(\.key)
    }

    /// A plan that repeats a finished workout: the same exercises in order,
    /// the number of sets performed and the most common rep count. Loads come
    /// from history when sets are added, so nothing performed is copied as done.
    static func template(repeating session: LiftSession) -> LiftTemplate? {
        let exercises = (session.exercises ?? []).sorted { $0.orderIndex < $1.orderIndex }
        guard !exercises.isEmpty else { return nil }
        var entries: [LiftTemplateExercise] = []
        for (index, exercise) in exercises.enumerated() {
            let sets: [LiftSet] = (exercise.sets ?? []).sorted { $0.orderIndex < $1.orderIndex }
            let performedSets: Int = sets.isEmpty ? exercise.progressionSets : sets.count
            let reps: Int = mostCommon(sets.map(\.reps)) ?? exercise.progressionLowerReps
            entries.append(LiftTemplateExercise(name: exercise.name, orderIndex: index,
                                                targetSets: min(10, max(1, performedSets)),
                                                targetReps: min(40, max(1, reps)),
                                                restSeconds: sets.compactMap(\.restSeconds).last))
        }
        return LiftTemplate(name: session.template, focus: "Repeats your \(session.template) workout.", exercises: entries)
    }

    /// The most frequent value; ties go to the larger one. Nil when empty.
    private static func mostCommon(_ values: [Int]) -> Int? {
        var counts: [Int: Int] = [:]
        for value in values { counts[value, default: 0] += 1 }
        var best: (value: Int, count: Int)?
        for (value, count) in counts {
            if let current = best, current.count > count || (current.count == count && current.value >= value) { continue }
            best = (value, count)
        }
        return best?.value
    }

    /// The newest finished-workout exercise with this name, compared without case.
    private func lastCompletedExercise(named name: String, before date: Date) throws -> LiftExercise? {
        let exercises = try modelContext.fetch(FetchDescriptor<LiftExercise>())
        return exercises
            .filter { $0.name.caseInsensitiveCompare(name) == .orderedSame
                && ($0.session?.durationMinutes ?? 0) > 0 && ($0.session?.date ?? .distantFuture) < date }
            .max { ($0.session?.date ?? .distantPast) < ($1.session?.date ?? .distantPast) }
    }

    /// Adds a set to the named exercise inside the session. Returns the new set.
    @discardableResult
    func logSet(in session: LiftSession, exerciseName: String, weightLbs: Double, reps: Int, restSeconds: Int? = nil, repsInReserve: Int? = nil) throws -> LiftSet {
        let matches = (session.exercises ?? []).filter { $0.name == exerciseName }
        guard matches.count == 1, let exercise = matches.first else {
            throw matches.isEmpty ? LiftServiceError.exerciseNotFound(exerciseName) : LiftServiceError.ambiguousExercise
        }
        return try logSet(in: session, exercise: exercise, weightLbs: weightLbs, reps: reps,
                          restSeconds: restSeconds, repsInReserve: repsInReserve)
    }

    /// Logs against the exact exercise, including repeated exercise names.
    /// Throws for invalid values, foreign exercises, completed sessions or save failures.
    @discardableResult
    func logSet(in session: LiftSession, exercise: LiftExercise, weightLbs: Double, reps: Int,
                restSeconds: Int? = nil, repsInReserve: Int? = nil) throws -> LiftSet {
        try validateSet(weightLbs: weightLbs, reps: reps, restSeconds: restSeconds, rir: repsInReserve)
        guard session.durationMinutes == 0 else { throw LiftServiceError.sessionFinished }
        guard (session.exercises ?? []).contains(where: { $0 === exercise }) else {
            throw LiftServiceError.exerciseNotFound(exercise.name)
        }
        let nextIndex = ((exercise.sets ?? []).map(\.orderIndex).max() ?? -1) + 1
        let set = LiftSet(weightLbs: weightLbs, reps: reps, orderIndex: nextIndex)
        set.restSeconds = restSeconds
        set.repsInReserve = repsInReserve
        try modelContext.transaction {
            modelContext.insert(set)
            set.exercise = exercise
            exercise.sets = (exercise.sets ?? []) + [set]
            try modelContext.save()
        }
        return set
    }

    /// Corrects a logged set in place. Invalid edits leave the original intact.
    func updateSet(_ set: LiftSet, in session: LiftSession, weightLbs: Double, reps: Int,
                   restSeconds: Int?, repsInReserve: Int?) throws {
        try validateSet(weightLbs: weightLbs, reps: reps, restSeconds: restSeconds, rir: repsInReserve)
        guard session.durationMinutes == 0 else { throw LiftServiceError.sessionFinished }
        guard (session.exercises ?? []).contains(where: { ($0.sets ?? []).contains(where: { $0 === set }) }) else {
            throw LiftServiceError.setNotFound
        }
        try modelContext.transaction {
            set.weightLbs = weightLbs
            set.reps = reps
            set.restSeconds = restSeconds
            set.repsInReserve = repsInReserve
            try modelContext.save()
        }
    }

    private func validateSet(weightLbs: Double, reps: Int, restSeconds: Int?, rir: Int?) throws {
        guard weightLbs.isFinite, (0...10_000).contains(weightLbs), (1...1_000).contains(reps),
              restSeconds.map({ (0...3_600).contains($0) }) ?? true,
              rir.map({ (0...10).contains($0) }) ?? true else { throw LiftServiceError.invalidSet }
    }

    /// Prefills the last set in this session, then the latest completed session
    /// for this exercise, then the exercise target. Never treats a suggested set
    /// as performed. Throws fetch errors rather than hiding missing history.
    func suggestedSet(for exercise: LiftExercise, target: LiftTemplateExercise? = nil, before date: Date = Date()) throws -> LiftSetDraft {
        if let previous = (exercise.sets ?? []).max(by: { $0.orderIndex < $1.orderIndex }) {
            return LiftSetDraft(set: previous, source: "Last set")
        }
        let name = exercise.name
        let matches = try modelContext.fetch(FetchDescriptor<LiftExercise>(predicate: #Predicate { $0.name == name }))
        let history = matches.filter { ($0.session?.durationMinutes ?? 0) > 0 && ($0.session?.date ?? .distantFuture) < date }
            .sorted { ($0.session?.date ?? .distantPast) > ($1.session?.date ?? .distantPast) }
        for previousExercise in history {
            if let previous = (previousExercise.sets ?? []).max(by: { $0.orderIndex < $1.orderIndex }) {
                return LiftSetDraft(set: previous, source: "Previous workout")
            }
        }
        return LiftSetDraft(weightLbs: target?.suggestedWeightLbs ?? 0, reps: max(1, exercise.progressionLowerReps),
                            restSeconds: target?.restSeconds ?? 120, repsInReserve: nil,
                            source: target?.suggestedWeightLbs == nil ? "Plan target · enter your weight" : "Coach suggestion · review the load")
    }

    /// Closes the session, recomputing totalVolumeLbs and writing duration/avgHR.
    /// HealthKit write is dispatched fire-and-forget via SessionLifecycleService;
    /// HK failures never propagate here so the UI can update cleanly.
    func endSession(_ session: LiftSession,
                    durationMinutes: Int,
                    avgHR: Int? = nil,
                    estimatedCalories: Double? = nil) throws {
        guard durationMinutes > 0 else { throw LiftServiceError.invalidSet }
        guard session.durationMinutes == 0 else { return }
        let prescriptions = try modelContext.fetch(FetchDescriptor<PrescribedWorkout>())
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let day = cal.startOfDay(for: session.date)
        try modelContext.transaction {
            session.totalVolumeLbs = LiftService.totalVolume(session: session)
            session.durationMinutes = durationMinutes
            session.avgHR = avgHR
            if let id = session.sessionID {
                for prescription in prescriptions where prescription.sessionUUID == id {
                    prescription.status = .completed
                }
            }
            modelContext.insert(WorkoutEvent(date: day, completed: true, source: .lift))
            try modelContext.save()
        }
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
        #if os(iOS)
        WorkoutLiveActivityController.dismissAllSync()
        #endif
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
        let sessions = modelContext.fetchOrEmpty(descriptor)
        return sessions.first { $0.durationMinutes == 0 }
    }
}

enum LiftServiceError: LocalizedError {
    case exerciseNotFound(String)
    case invalidExerciseName
    case ambiguousExercise
    case invalidSet
    case setNotFound
    case sessionFinished
    case invalidPlan
    case linkedSessionUnavailable

    var errorDescription: String? {
        switch self {
        case .exerciseNotFound(let name): return "Exercise '\(name)' not found in active session"
        case .invalidExerciseName: return "Exercise name cannot be empty"
        case .ambiguousExercise: return "Select the exact exercise before logging a set."
        case .invalidSet: return "Enter a valid weight, positive reps, rest time, and RIR between 0 and 10."
        case .setNotFound: return "This set does not belong to the workout."
        case .sessionFinished: return "This workout has already finished."
        case .invalidPlan: return "The workout needs valid exercise names, sets, and rep targets. Generate a new suggestion."
        case .linkedSessionUnavailable: return "This workout is already linked to a session that is not available on this device yet. Let iCloud finish syncing before trying again."
        }
    }
}

/// Volume aggregator surface used by LiftSessionView to render concentric arcs and
/// the identity-framed completion line. Pure value type; computed from the session.
struct LiftVolumeSummary: Sendable {
    var totalLbs: Double
    var setCount: Int
    var repCount: Int

    static func from(session: LiftSession) -> LiftVolumeSummary {
        let exercises = session.exercises ?? []
        var totalLbs: Double = 0
        var setCount = 0
        var repCount = 0
        for ex in exercises {
            let sets = ex.sets ?? []
            setCount += sets.count
            for s in sets {
                totalLbs += s.weightLbs * Double(s.reps)
                repCount += s.reps
            }
        }
        return LiftVolumeSummary(totalLbs: totalLbs, setCount: setCount, repCount: repCount)
    }

    /// Identity-framed completion line. Spec: "12,400 lb moved. That's the work."
    var completionLine: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let pretty = formatter.string(from: NSNumber(value: totalLbs)) ?? "\(Int(totalLbs))"
        return "\(pretty) lb moved. That's the work."
    }
}

/// Editable values only, not a logged performance or a prescription to lift a load.
struct LiftSetDraft {
    var weightLbs: Double
    var reps: Int
    var restSeconds: Int
    var repsInReserve: Int?
    var source: String

    init(weightLbs: Double, reps: Int, restSeconds: Int, repsInReserve: Int?, source: String) {
        self.weightLbs = weightLbs
        self.reps = reps
        self.restSeconds = restSeconds
        self.repsInReserve = repsInReserve
        self.source = source
    }

    init(set: LiftSet, source: String) {
        self.init(weightLbs: set.weightLbs, reps: set.reps, restSeconds: set.restSeconds ?? 0,
                  repsInReserve: set.repsInReserve, source: source)
    }
}
