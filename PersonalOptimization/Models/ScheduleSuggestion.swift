import Foundation
import SwiftData

/// Coach-generated schedule optimization suggestion. Stored in inbox until user
/// accepts (applies the change) or dismisses. Snoozable.
@Model
final class ScheduleSuggestion {
    var generatedAt: Date = Date.distantPast
    var summary: String = ""                          // human-readable headline (one-line)
    var detail: String = ""                           // multi-sentence explanation
    var changeTypeRaw: String = ScheduleSuggestionChangeType.shiftBlock.rawValue
    var changePayload: String = "{}"                  // JSON of the proposed change (model-specific)
    var statusRaw: String = ScheduleSuggestionStatus.pending.rawValue
    var rationaleData: String = ""                    // pattern data backing the suggestion
    var snoozedUntil: Date?

    var changeType: ScheduleSuggestionChangeType {
        ScheduleSuggestionChangeType(rawValue: changeTypeRaw) ?? .shiftBlock
    }

    var status: ScheduleSuggestionStatus {
        get { ScheduleSuggestionStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    init(generatedAt: Date,
         summary: String,
         detail: String,
         changeType: ScheduleSuggestionChangeType,
         changePayload: String = "{}",
         rationaleData: String = "") {
        self.generatedAt = generatedAt
        self.summary = summary
        self.detail = detail
        self.changeTypeRaw = changeType.rawValue
        self.changePayload = changePayload
        self.rationaleData = rationaleData
    }
}

enum ScheduleSuggestionChangeType: String, Codable, CaseIterable, Sendable {
    case shiftBlock
    case addBlock
    case removeBlock
    case mergeBlocks
    case splitBlock
}

enum ScheduleSuggestionStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case accepted
    case dismissed
    case snoozed
}
