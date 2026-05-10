import Foundation
import SwiftData

/// Pattern detected by TrendAnalyticsService over rolling windows. Append-only;
/// dismissed flag toggles UI surfacing. Confidence is a heuristic 0.0-1.0.
@Model
final class DetectedPattern {
    var detectedAt: Date = Date.distantPast
    var patternTypeRaw: String = PatternType.scheduleDrift.rawValue
    var confidence: Double = 0          // 0.0-1.0
    var summary: String = ""            // headline, one sentence
    var detail: String = ""             // longer explanation, used by Coach prompts
    var actionableSuggestion: String?
    var dismissed: Bool = false
    var snoozedUntil: Date?

    var patternType: PatternType {
        PatternType(rawValue: patternTypeRaw) ?? .scheduleDrift
    }

    init(detectedAt: Date,
         patternType: PatternType,
         confidence: Double,
         summary: String,
         detail: String,
         actionableSuggestion: String? = nil) {
        self.detectedAt = detectedAt
        self.patternTypeRaw = patternType.rawValue
        self.confidence = max(0, min(1, confidence))
        self.summary = summary
        self.detail = detail
        self.actionableSuggestion = actionableSuggestion
    }
}

enum PatternType: String, Codable, CaseIterable, Sendable {
    case scheduleDrift              // user has shifted blocks consistently for N weeks
    case volumeDecline              // lift volume trending down vs prior month
    case hydrationCorrelation       // performance correlates with hydration met
    case sleepImpact                // low-sleep nights precede missed sessions
    case fastingConsistency         // fasting completion consistency increasing/decreasing
    case learningStreakDecay        // learning minutes declining vs prior month

    var displayName: String {
        switch self {
        case .scheduleDrift: return "Schedule drift"
        case .volumeDecline: return "Volume decline"
        case .hydrationCorrelation: return "Hydration correlation"
        case .sleepImpact: return "Sleep impact"
        case .fastingConsistency: return "Fasting consistency"
        case .learningStreakDecay: return "Learning decay"
        }
    }
}
