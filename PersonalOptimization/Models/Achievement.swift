import Foundation
import SwiftData

/// One unlocked achievement. Sibling to `MilestoneUnlock` — milestones are
/// the heavy "year-of-consistency" markers, achievements are the granular
/// named wins ("First Lift", "Hydration Honest", "Two Weeks Two Disciplines").
/// Append-only ledger; the catalog of available achievements lives in
/// `AchievementRegistry`.
@Model
final class Achievement {
    var identifier: String = ""              // matches AchievementRegistry entry
    var unlockedAt: Date = Date.distantPast
    var celebrationShown: Bool = false       // dedup the toast/animation

    init(identifier: String, unlockedAt: Date = Date()) {
        self.identifier = identifier
        self.unlockedAt = unlockedAt
    }
}
