import Foundation
import SwiftData

/// Append-only ledger of every behavior log. Powers adaptive notification timing
/// after day 14.
@Model
final class CompletionHistory {
    var domain: String = StreakDomain.workout.rawValue
    var timestamp: Date = Date.distantPast

    init(domain: StreakDomain, timestamp: Date) {
        self.domain = domain.rawValue
        self.timestamp = timestamp
    }
}
