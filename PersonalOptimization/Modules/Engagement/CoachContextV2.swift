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

    // V1 opportunities pass — Coach memory + continuity (Opp 6).
    /// User-supplied context the Coach should carry across days. Filled by
    /// `CoachMemoryService.summaryForCoach`. Empty when the user hasn't
    /// written any context yet.
    var userMemoryBlock: String = ""
    /// 3-5 most recent CoachInsight rows compressed into bullets so the
    /// Coach can build a thread instead of producing isolated daily notes.
    var recentInsightsBlock: String = ""
    /// Detected lapse state for today, if any. Drives the prompt to tone
    /// the message warmly when the user is returning from a slump.
    var lapseStateNote: String = ""
    /// RecoveryGate verdict for today, if downgraded or rest. Empty when
    /// recovery is normal.
    var recoveryNote: String = ""

    /// M4.2 followup: structured user-persona block — motivation driver,
    /// communication style, accountability preference, identity anchors,
    /// what to avoid re-recommending, etc. Populated by `PersonaService.
    /// promptContextBlock()`. Empty until the user starts answering the
    /// weekly question card or fills in the Settings questionnaire.
    var personaBlock: String = ""

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
        if !userMemoryBlock.isEmpty {
            lines.append("")
            lines.append("=== User-supplied memory ===")
            lines.append(userMemoryBlock)
        }
        if !recentInsightsBlock.isEmpty {
            lines.append("")
            lines.append("=== Recent insights you wrote (build a thread, don't repeat) ===")
            lines.append(recentInsightsBlock)
        }
        if !recoveryNote.isEmpty {
            lines.append("")
            lines.append("=== Recovery state ===")
            lines.append(recoveryNote)
        }
        if !lapseStateNote.isEmpty {
            lines.append("")
            lines.append("=== Lapse state ===")
            lines.append(lapseStateNote)
        }
        if !personaBlock.isEmpty {
            lines.append("")
            lines.append(personaBlock)
        }
        return lines.joined(separator: "\n")
    }
}
