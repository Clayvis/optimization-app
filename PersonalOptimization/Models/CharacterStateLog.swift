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

    /// Capitalized state suffix used in asset filenames (e.g., "Neutral").
    var suffix: String {
        switch self {
        case .neutral:      return "Neutral"
        case .thirsty:      return "Thirsty"
        case .fasting:      return "Fasting"
        case .urgent:       return "Urgent"
        case .proud:        return "Proud"
        case .disappointed: return "Disappointed"
        case .tired:        return "Tired"
        case .achievement:  return "Achievement"
        }
    }

    /// Returns the Asset Catalog name for this state under the given variant.
    /// Defaults to ninja_male when variant is unknown.
    func assetName(for variant: String) -> String {
        switch variant {
        case "ninja_male":   return "NinjaMale_\(suffix)"
        case "ninja_female": return "NinjaFemale_\(suffix)"
        default:             return "NinjaMale_\(suffix)"
        }
    }

    /// Backward-compatible default that maps to the ninja_male variant.
    /// Prefer `assetName(for:)` so user-selected variant can take effect.
    var assetName: String { assetName(for: "ninja_male") }

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
