import Foundation
import SwiftData

/// Per-day record of Anthropic API token spend. Aggregates input + output
/// tokens for a single calendar day so Diagnostics can show "Today: 12,400 /
/// 50,000" and TokenBudgetService can enforce caps.
@Model
final class TokenUsageEntry {
    var date: Date = Date.distantPast
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var callCount: Int = 0
    var lastCallAt: Date?

    init(date: Date,
         inputTokens: Int = 0,
         outputTokens: Int = 0,
         callCount: Int = 0,
         lastCallAt: Date? = nil) {
        self.date = date
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.callCount = callCount
        self.lastCallAt = lastCallAt
    }

    var totalTokens: Int { inputTokens + outputTokens }
}
