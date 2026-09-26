import Foundation

struct HypertrophyFocus: Codable, Equatable, Sendable {
    var priorities: [String] = ["Thighs", "Calves", "Forearms"]
    var weeklyGainMin: Double = 0.25
    var weeklyGainMax: Double = 0.5
    var enabled = false
}

struct TrainingSetEvidence: Sendable {
    let date: Date
    let exercise: String
    let weight: Double
    let reps: Int
    let rir: Int?
}

struct MuscleGuidance: Identifiable, Sendable {
    var id: String { muscle }
    let muscle: String
    let directSets: Int
    let effectiveSets: Double
    let averageRIR: Double?
    let recommendation: String
    let prescription: String
    let exercises: String
}

enum HypertrophyRules {
    /// No vacuous success for an empty or unfinished workout.
    static func shouldIncreaseWeight(reps: [Int], plannedSets: Int, upperReps: Int) -> Bool {
        plannedSets > 0 && upperReps > 0 && reps.count >= plannedSets && reps.allSatisfy { $0 >= upperReps }
    }

    static func group(for exercise: String) -> String? {
        let name = exercise.lowercased()
        if ["calf", "calves"].contains(where: name.contains) { return "Calves" }
        if ["hammer curl", "reverse curl", "wrist", "farmer", "dead hang", "heavy hold"].contains(where: name.contains) { return "Forearms" }
        if ["squat", "leg press", "leg extension", "leg curl", "romanian", "adductor", "lunge"].contains(where: name.contains) { return "Thighs" }
        if ["row", "pull-up", "pullup", "pull down", "pulldown", "chin-up"].contains(where: name.contains) { return "Pulling" }
        return nil
    }

    /// Declining performance is only inferred from matched exercises with at
    /// least two dated sessions, using the best estimated 1RM per session.
    static func declining(_ sets: [TrainingSetEvidence]) -> Bool {
        for exerciseSets in Dictionary(grouping: sets, by: \.exercise).values {
            let sessions = Dictionary(grouping: exerciseSets, by: \.date).sorted { $0.key < $1.key }
            guard sessions.count >= 2, let first = sessions.first, let last = sessions.last else { continue }
            func best(_ rows: [TrainingSetEvidence]) -> Double {
                rows.filter { $0.reps > 0 && $0.reps <= 15 }.map { $0.weight * (1 + Double($0.reps) / 30) }.max() ?? 0
            }
            let baseline = best(first.value)
            if baseline > 0 && best(last.value) > 0 && best(last.value) < baseline * 0.95 { return true }
        }
        return false
    }

    static func guidance(focus: HypertrophyFocus, sets: [TrainingSetEvidence], asOf: Date,
                         calendar: Calendar, recoveryLimited: Bool, calfPainConstraint: Bool) -> [MuscleGuidance] {
        let start = calendar.date(byAdding: .day, value: -7, to: asOf) ?? asOf
        let recent = sets.filter { $0.date >= start && $0.date <= asOf && $0.reps > 0 }
        let pulling = recent.filter { group(for: $0.exercise) == "Pulling" }.count
        return focus.priorities.filter { ["Thighs", "Calves", "Forearms"].contains($0) }.map { muscle in
            let rows = recent.filter { group(for: $0.exercise) == muscle }
            let rir = rows.compactMap(\.rir)
            let average = rir.isEmpty ? nil : Double(rir.reduce(0, +)) / Double(rir.count)
            let effective = Double(rows.count) + (muscle == "Forearms" ? Double(pulling) * 0.5 : 0)
            let lower = muscle == "Forearms" ? 8.0 : 12.0
            let upper = muscle == "Thighs" ? 18.0 : muscle == "Calves" ? 16.0 : 15.0
            let message: String
            if recoveryLimited || (muscle == "Calves" && calfPainConstraint) {
                message = "Review recovery. Do not add volume; adapt loading to pain and current restrictions."
            } else if effective >= upper || ((average ?? 10) <= 1 && declining(rows)) {
                message = "Do not add volume. Reduce fatigue and review recovery before progressing."
            } else if rows.isEmpty || average == nil {
                message = "Establish a baseline: log working sets and RIR before increasing volume."
            } else if (average ?? 0) > 3 {
                message = "Improve effort toward 1–3 RIR before adding sets."
            } else if effective < lower {
                message = "Reallocate up to 2 weekly sets from a non-priority muscle, within recovery capacity. Keep total planned volume stable."
            } else {
                message = "Maintain volume and progress reps, then load."
            }
            let prescription = muscle == "Thighs" ? "12–18 working sets/week · 2–3 days · 6–15 reps · 1–3 RIR"
                : muscle == "Calves" ? "12–16 working sets/week · 3–5 days · 8–20 reps · 1–3 RIR"
                : "8–15 effective sets/week · 3 days · 8–20 reps · 1–3 RIR"
            let exercises = muscle == "Thighs" ? "Quads: hack squat, leg press, squat, split squat, leg extension. Hamstrings: Romanian deadlift, leg curl. Adductors: adductor work."
                : muscle == "Calves" ? "Straight-leg raises bias gastrocnemius; bent-knee/seated raises emphasize soleus. Use a comfortable stretch, controlled lowering, no bouncing, and full plantar flexion within tolerance."
                : "Hammer/reverse curls, wrist curls, reverse wrist curls, farmer carries, dead hangs, heavy holds. Pulling contributes 0.5 set per logged set as a planning heuristic."
            return MuscleGuidance(muscle: muscle, directSets: rows.count, effectiveSets: effective,
                                  averageRIR: average, recommendation: message, prescription: prescription, exercises: exercises)
        }
    }
}
