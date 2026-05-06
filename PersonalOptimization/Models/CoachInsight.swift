import Foundation
import SwiftData

/// Cached daily insight from CoachService. One row per day; manual refreshes update
/// the existing row and bump refreshCount.
@Model
final class CoachInsight {
    var generatedAt: Date = Date.distantPast
    var insightText: String = ""
    var contextSummary: String = ""    // for debugging
    var tokenUsage: Int = 0
    var refreshCount: Int = 0          // 0 = morning auto, 1+ = manual refreshes

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
