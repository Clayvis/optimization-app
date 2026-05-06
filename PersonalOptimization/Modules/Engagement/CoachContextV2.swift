import Foundation

/// Coach v2 context handed to prompts. Composes the M3.6 daily snapshot
/// (`CoachContext`) with the M3.7 historical summary, the user's stated goals
/// and equipment, today's time-available, and a weather/temperature stub. The
/// `summaryForPrompt` is the single string handed to Claude on every Coach v2
/// call so prompts stay deterministic and budgetable.
struct CoachContextV2: Sendable {
    var today: CoachContext
    var historical: CoachContextHistorical
    var primaryGoal: String?
    var secondaryGoals: [String]
    var equipmentAccess: String
    var weeklyTrainingTargetSessions: Int
    var restrictions: [String]
    var minutesAvailableToday: Int          // open schedule slots, derived
    var temperatureF: Double?               // optional ambient weather (stub)

    var summaryForPrompt: String {
        var lines: [String] = []
        lines.append("=== Today snapshot ===")
        lines.append(today.summaryForPrompt)
        lines.append("")
        lines.append("=== Historical context ===")
        lines.append(historical.summaryForPrompt)
        lines.append("")
        lines.append("=== Identity & constraints ===")
        if let primary = primaryGoal, !primary.isEmpty {
            lines.append("Primary goal: \(primary).")
        }
        if !secondaryGoals.isEmpty {
            lines.append("Secondary goals: \(secondaryGoals.joined(separator: "; ")).")
        }
        lines.append("Equipment access: \(equipmentAccess).")
        lines.append("Weekly training target: \(weeklyTrainingTargetSessions) sessions.")
        if !restrictions.isEmpty {
            lines.append("Restrictions: \(restrictions.joined(separator: "; ")).")
        }
        lines.append("Time available today: \(minutesAvailableToday) min.")
        if let temp = temperatureF {
            lines.append("Ambient: \(Int(temp))F.")
        }
        return lines.joined(separator: "\n")
    }
}
