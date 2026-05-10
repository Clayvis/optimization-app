import Foundation
import SwiftData

/// User-supplied context the Coach can carry across days. Pulled into
/// `CoachService.gatherFullContext` so prompts can reference what the user
/// shared instead of starting cold every call. Expiry handles ephemeral
/// context ("sick kid this week" auto-clears in 7 days); persistent context
/// (achilles flare-up, equipment change) lives until the user removes it.
@Model
final class CoachMemory {
    var key: String = ""                    // optional deduper, e.g. "achilles_flare"
    var value: String = ""                  // free text from the user
    var importance: Int = 3                 // 1-5; high importance survives prompt-budget trims first
    var expiresAt: Date?                    // optional auto-clear
    var createdAt: Date = Date.distantPast

    init(key: String = "",
         value: String,
         importance: Int = 3,
         expiresAt: Date? = nil) {
        self.key = key
        self.value = value
        self.importance = max(1, min(5, importance))
        self.expiresAt = expiresAt
        self.createdAt = Date()
    }
}
