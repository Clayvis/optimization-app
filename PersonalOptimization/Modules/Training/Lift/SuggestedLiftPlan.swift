import Foundation

/// Validate the coach's structured exercise plan before any workout is created.
/// Suggested loads remain review information, never completed sets.
struct SuggestedLiftPlan: Decodable {
    struct Exercise: Decodable {
        let name: String
        let sets: Int
        let reps: Int
        let weightLbs: Double?
        let restSec: Int?
        let rir: Int?
    }
    let exercises: [Exercise]

    static func read(_ prescription: PrescribedWorkout) throws -> SuggestedLiftPlan {
        guard prescription.workoutType == .liftA || prescription.workoutType == .liftB,
              let data = prescription.template.data(using: .utf8) else { throw LiftServiceError.invalidPlan }
        let plan: SuggestedLiftPlan
        do { plan = try JSONDecoder().decode(Self.self, from: data) }
        catch { throw LiftServiceError.invalidPlan }
        guard !plan.exercises.isEmpty, plan.exercises.count <= 30,
              plan.exercises.allSatisfy({ exercise in
                  !exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && (1...10).contains(exercise.sets) && (1...40).contains(exercise.reps)
                      && (exercise.weightLbs.map({ $0.isFinite && (0...10_000).contains($0) }) ?? true)
                      && (exercise.restSec.map({ (0...3_600).contains($0) }) ?? true)
                      && (exercise.rir.map({ (0...10).contains($0) }) ?? true)
              }) else { throw LiftServiceError.invalidPlan }
        return plan
    }

    func template(title: String, rationale: String) -> LiftTemplate {
        LiftTemplate(name: title, focus: rationale, exercises: exercises.enumerated().map { index, exercise in
            LiftTemplateExercise(name: exercise.name, orderIndex: index, targetSets: exercise.sets, targetReps: exercise.reps,
                                 suggestedWeightLbs: exercise.weightLbs, restSeconds: exercise.restSec, targetRIR: exercise.rir)
        })
    }
}
