import Foundation
import SwiftData

/// One milestone the user has reached. The full milestone catalog lives in
/// `MilestoneRegistry` (static); this row records that the user crossed the
/// threshold and what they unlocked. Append-only.
@Model
final class MilestoneUnlock {
    var identifier: String = ""              // matches MilestoneRegistry.allMilestones[i].id
    var unlockedAt: Date = Date.distantPast
    var celebrationShown: Bool = false       // dedup the one-time celebration sheet
    var milestoneTypeRaw: String = MilestoneType.streakDays.rawValue

    var milestoneType: MilestoneType {
        MilestoneType(rawValue: milestoneTypeRaw) ?? .streakDays
    }

    init(identifier: String,
         milestoneType: MilestoneType,
         unlockedAt: Date = Date()) {
        self.identifier = identifier
        self.milestoneTypeRaw = milestoneType.rawValue
        self.unlockedAt = unlockedAt
    }
}

enum MilestoneType: String, Codable, CaseIterable, Sendable {
    case streakDays                  // consecutive days of any-domain adherence
    case totalWorkouts               // cumulative workout count
    case totalVolume                 // cumulative lift volume
    case fastingDays                 // cumulative fast completion
    case learningMinutes             // cumulative learning minutes
    case appUsageDays                // distinct days the user opened the app
    case allMascotStates             // all 8 mascot states triggered
}
