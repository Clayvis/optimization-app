import Foundation
import SwiftData

@MainActor
enum InBodyService {
    /// Validates the entire import before mutating. Re-imports by UUID are inert.
    /// Throws validation or persistence errors; existing history is retained.
    static func save(_ values: [InBodyValues], context: ModelContext, editing: InBodyScan? = nil) throws {
        let existing = try context.fetch(FetchDescriptor<InBodyScan>())
        let calendar = UserCalendar.current(modelContext: context)
        var days = Set(existing.filter { $0.id != editing?.id }.map { calendar.startOfDay(for: $0.date) })
        var ids = Set(existing.filter { $0.id != editing?.id }.map(\.id))
        var additions: [InBodyValues] = []
        for value in values {
            try value.validate()
            if ids.contains(value.id) { continue }
            guard days.insert(calendar.startOfDay(for: value.date)).inserted else { throw InBodyError.duplicateDay }
            ids.insert(value.id)
            additions.append(value)
        }
        try context.transaction {
            for value in additions {
                if let editing { editing.apply(value) }
                else { context.insert(InBodyScan(values: value)) }
            }
            try context.save()
        }
    }

    static func focus(profile: UserProfile?) -> HypertrophyFocus {
        profile?.metadata("inbody.focus", as: HypertrophyFocus.self) ?? HypertrophyFocus()
    }

    static func evidence(context: ModelContext, asOf: Date) -> [TrainingSetEvidence] {
        let start = Calendar.current.date(byAdding: .day, value: -42, to: asOf) ?? asOf
        let sessions = context.fetchOrEmpty(FetchDescriptor<LiftSession>(predicate: #Predicate {
            $0.date >= start && $0.date <= asOf && $0.durationMinutes > 0
        }))
        return sessions.flatMap { session in
            (session.exercises ?? []).flatMap { exercise in
                (exercise.sets ?? []).map { set in
                    TrainingSetEvidence(date: session.date, exercise: exercise.name, weight: set.weightLbs,
                                        reps: set.reps, rir: set.repsInReserve)
                }
            }
        }
    }

    static func guidance(context: ModelContext, profile: UserProfile?, asOf: Date) -> [MuscleGuidance] {
        let calendar = UserCalendar.current(modelContext: context)
        let recovery = profile.map { RecoveryGate(modelContext: context, timezone: calendar.timeZone)
            .evaluateDetailed(profile: $0, asOf: asOf) }
        let restricted = profile?.restrictionsCSV.lowercased().contains("achilles") == true
            || (recovery?.reason.lowercased().contains("achilles") == true)
        return HypertrophyRules.guidance(focus: focus(profile: profile), sets: evidence(context: context, asOf: asOf),
                                        asOf: asOf, calendar: calendar,
                                        recoveryLimited: recovery.map { $0.hasData && $0.recommendation != .normal } ?? false,
                                        calfPainConstraint: restricted)
    }

    /// Deterministic observations feed the existing optional AI explanation path.
    /// Never permits AI to infer individual-muscle growth from segmental data.
    static func coachContext(context: ModelContext, profile: UserProfile, asOf: Date) -> String {
        let settings = focus(profile: profile)
        guard settings.enabled else { return "" }
        let scans = context.fetchOrEmpty(FetchDescriptor<InBodyScan>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
            .filter { $0.date <= asOf }
        var lines = ["Controlled hypertrophy. Priority order: \(settings.priorities.joined(separator: ", ")). Maintain chest/back/shoulders/upper arms; reallocate, never stack volume blindly."]
        if scans.count > 1 {
            do {
                let delta = try BodyCompositionComparison(previous: scans[1].values, current: scans[0].values,
                                                          calendar: UserCalendar.current(modelContext: context))
                let assessment = BodyCompositionAssessment(comparison: delta, focus: settings)
                lines.append(String(format: "InBody estimates over %d days: skeletal muscle %+.1f lb; lean mass %+.1f lb; body fat %+.1f lb (%+.1f percentage points); weight %+.2f lb/week.",
                                    delta.days, delta.skeletalMuscle, delta.leanMass, delta.fatMass,
                                    delta.fatPercentagePoints, delta.weeklyWeight))
                lines.append("Rule verdict: \(assessment.headline). Hydration comparability heuristic: \(delta.comparability.rawValue). Lean mass is not muscle. Arm/leg lean mass cannot isolate calves or forearms.")
                if delta.weeklyWeight > settings.weeklyGainMax {
                    lines.append(String(format: "Weight gain is above the chosen %.2f–%.2f lb/week range. Consider a small surplus reduction, preserving protein and training intensity. Do not automatically change calorie targets.",
                                        settings.weeklyGainMin, settings.weeklyGainMax))
                }
            } catch { lines.append("Scan comparison unavailable: \(error.localizedDescription)") }
        }
        lines += guidance(context: context, profile: profile, asOf: asOf).map { "\($0.muscle): \($0.recommendation) \($0.prescription)" }
        lines.append("Explain these rules; do not override recovery/pain restrictions or claim progress without workout evidence. Match exercises and logged RIR before recommending load increases.")
        return lines.joined(separator: "\n")
    }
}
