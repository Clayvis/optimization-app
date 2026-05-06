import Foundation
import SwiftData

enum CharacterState: String, Codable, CaseIterable {
    case neutral
    case thirsty
    case fasting
    case urgent
    case proud
    case disappointed
    case tired
    case achievement

    var assetName: String {
        switch self {
        case .neutral: return "MascotNeutral"
        case .thirsty: return "MascotThirsty"
        case .fasting: return "MascotFasting"
        case .urgent: return "MascotUrgent"
        case .proud: return "MascotProud"
        case .disappointed: return "MascotDisappointed"
        case .tired: return "MascotTired"
        case .achievement: return "MascotAchievement"
        }
    }

    static let precedenceOrder: [CharacterState] = [
        .urgent, .achievement, .proud, .disappointed,
        .tired, .thirsty, .fasting, .neutral
    ]
}

@Model
final class CharacterStateLog {
    var timestamp: Date = Date.distantPast
    var stateRaw: String = CharacterState.neutral.rawValue
    var triggerReason: String = "default"
    var durationSeconds: Int?

    init(timestamp: Date, state: CharacterState, triggerReason: String) {
        self.timestamp = timestamp
        self.stateRaw = state.rawValue
        self.triggerReason = triggerReason
    }
}
