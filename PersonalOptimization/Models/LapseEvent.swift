import Foundation
import SwiftData

/// One lapse window detected by `LapseDetectionService`. Used to drive the
/// welcome-back flow + crisis-mode threshold. Append-only ledger; resolved
/// gets set when the user re-engages (today's master metric ≥ 30%).
@Model
final class LapseEvent {
    var startedAt: Date = Date.distantPast       // first day with adherence < threshold
    var detectedAt: Date = Date.distantPast      // when the service flagged it
    var severityRaw: String = LapseSeverity.soft.rawValue
    var resolvedAt: Date?                        // first day adherence ≥ 30% after the lapse
    var welcomeBackShown: Bool = false           // dedup the welcome-back card

    var severity: LapseSeverity {
        LapseSeverity(rawValue: severityRaw) ?? .soft
    }

    init(startedAt: Date,
         detectedAt: Date = Date(),
         severity: LapseSeverity) {
        self.startedAt = startedAt
        self.detectedAt = detectedAt
        self.severityRaw = severity.rawValue
    }
}

enum LapseSeverity: String, Codable, CaseIterable, Sendable {
    case soft       // 2 consecutive days < 30% adherence
    case hard       // 5+ consecutive days < 30% OR no app open
    case crisis     // 14+ days persistent
}
