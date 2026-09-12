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
    case training
    case recovering
    case comeback
    case celebrating

    /// Reuse the shipped poses while reactions supply distinct motion and
    /// context. Old state raw values and saved history remain compatible.
    var artworkState: CharacterState {
        switch self {
        case .training, .comeback: return .neutral
        case .recovering: return .fasting
        case .celebrating: return .proud
        default: return self
        }
    }

    var displayName: String {
        switch self {
        case .training: return String(localized: "Training")
        case .recovering: return String(localized: "Recovery day")
        case .comeback: return String(localized: "Welcome back")
        case .celebrating: return String(localized: "Daily win")
        default: return rawValue.capitalized
        }
    }

    var reactionSymbol: String? {
        switch self {
        case .training: return "figure.strengthtraining.functional"
        case .recovering: return "leaf.fill"
        case .comeback: return "hand.wave.fill"
        case .celebrating: return "checkmark.seal.fill"
        default: return nil
        }
    }

    /// Capitalized state suffix used in asset filenames (e.g., "Neutral").
    var suffix: String {
        switch self {
        case .neutral, .training, .comeback: return "Neutral"
        case .thirsty:      return "Thirsty"
        case .fasting, .recovering: return "Fasting"
        case .urgent:       return "Urgent"
        case .proud, .celebrating: return "Proud"
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
        .recovering, .training, .achievement, .proud, .celebrating,
        .tired, .urgent, .comeback, .thirsty, .fasting, .neutral, .disappointed
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
