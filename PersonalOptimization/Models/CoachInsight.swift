import Foundation
import SwiftData

/// User interaction with a Coach insight. The day-30 review uses this
/// distribution to decide whether M3.7b prescriptive Coach output is worth
/// building (see `.work/decisions/004-coach-feedback-as-validation-gate.md`).
///
/// Stronger signals overwrite weaker ones: marked_* > acted_on > dismissed >
/// viewed > ignored. Auto-mark "viewed" only writes when the current state is
/// .ignored, so it never demotes a real signal.
enum CoachInsightInteraction: String, Codable, CaseIterable, Sendable {
    case ignored
    case viewed
    case dismissed
    case actedOn = "acted_on"
    case markedHelpful = "marked_helpful"
    case markedUnhelpful = "marked_unhelpful"

    var precedence: Int {
        switch self {
        case .ignored:           return 0
        case .viewed:            return 1
        case .dismissed:         return 2
        case .actedOn:           return 3
        case .markedHelpful, .markedUnhelpful: return 4
        }
    }
}

/// Cached daily insight from CoachService. One row per day; manual refreshes update
/// the existing row and bump refreshCount.
@Model
final class CoachInsight {
    var generatedAt: Date = Date.distantPast
    var insightText: String = ""
    var contextSummary: String = ""    // for debugging
    var tokenUsage: Int = 0
    var refreshCount: Int = 0          // 0 = morning auto, 1+ = manual refreshes

    /// Raw value of `CoachInsightInteraction`. M3.7a additive field.
    /// Default "ignored" so existing rows migrate cleanly without backfill.
    /// SwiftData lightweight migration handles additive default-value fields
    /// in place; see AppSchema.swift for the rule.
    var userInteractionRaw: String = CoachInsightInteraction.ignored.rawValue

    var userInteraction: CoachInsightInteraction {
        get { CoachInsightInteraction(rawValue: userInteractionRaw) ?? .ignored }
        set { userInteractionRaw = newValue.rawValue }
    }

    init(generatedAt: Date,
         insightText: String,
         contextSummary: String = "",
         tokenUsage: Int = 0,
         refreshCount: Int = 0) {
        self.generatedAt = generatedAt
        self.insightText = insightText
        self.contextSummary = contextSummary
        self.tokenUsage = tokenUsage
        self.refreshCount = refreshCount
    }
}
