import Foundation

/// Domains that maintain a streak independently. `protocolAdherence` is the rolled-up
/// daily metric and avoids colliding with the Swift `protocol` keyword.
enum StreakDomain: String, Codable, CaseIterable, Sendable {
    case workout
    case fasting
    case hydration
    case learning
    case protocolAdherence = "protocol"
}
