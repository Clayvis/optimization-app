import Foundation
import SwiftData
import os

/// Partner Mode foundation. v1 ships pairing-code generation + acceptance UI
/// + the data model for a linked partner; the CloudKit shared zone that
/// actually moves data between two Apple IDs is deferred until paid Apple
/// Developer membership lands. Once the shared zone wires up, this service
/// is the single point that publishes the curated subset (current streak,
/// today's master metric, mascot state, last workout type).
///
/// The design choice: privacy-preserving by default. Specific lift weights,
/// hydration amounts, fasting windows, Coach insights, and free-text notes
/// stay private even when paired. Only the lighter signals cross.
@MainActor
final class PartnerService {
    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.rawlins.PersonalOptimization", category: "partner")

    /// Pairing codes expire 24h after generation per V1 opp 1 spec.
    static let pairingCodeTTL: TimeInterval = 24 * 60 * 60

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Generates a fresh 6-character pairing code and persists it on the
    /// user's profile. Replaces any previous unexpired code.
    @discardableResult
    func generatePairingCode(for profile: UserProfile, at date: Date = Date()) throws -> String {
        let code = Self.makeCode()
        profile.partnerPairingCode = code
        profile.partnerPairingCodeExpiresAt = date.addingTimeInterval(Self.pairingCodeTTL)
        try modelContext.save()
        logger.info("Generated pairing code for user")
        return code
    }

    /// Returns the active code if present and not expired.
    func activeCode(for profile: UserProfile, asOf date: Date = Date()) -> String? {
        guard let code = profile.partnerPairingCode,
              let expires = profile.partnerPairingCodeExpiresAt,
              expires > date else { return nil }
        return code
    }

    /// Records that the user accepted a code from their partner. CloudKit
    /// shared zone integration lands later; for now we just persist the link
    /// so the UI can flip to "paired" state.
    func acceptCode(_ code: String,
                    partnerRecordID: String,
                    on profile: UserProfile,
                    at date: Date = Date()) throws {
        let cleaned = code.uppercased().trimmingCharacters(in: .whitespaces)
        guard cleaned.count == 6 else {
            throw PartnerError.invalidCode
        }
        profile.partnerRecordID = partnerRecordID
        profile.partnerLinkedAt = date
        profile.partnerPairingCode = nil
        profile.partnerPairingCodeExpiresAt = nil
        try modelContext.save()
        logger.info("Accepted partner pairing code")
    }

    /// Removes the partner link and any shared data on this device. CloudKit
    /// cleanup happens on the cloud side once shared-zone wiring exists.
    func unpair(_ profile: UserProfile) throws {
        profile.partnerRecordID = nil
        profile.partnerLinkedAt = nil
        try modelContext.save()
    }

    /// Generates a 6-character alphanumeric code. Excludes 0/O/1/I to avoid
    /// confusion when typing on a phone keyboard.
    static func makeCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in alphabet.randomElement()! })
    }
}

enum PartnerError: LocalizedError {
    case invalidCode

    var errorDescription: String? {
        switch self {
        case .invalidCode: return "Pairing codes are six characters."
        }
    }
}
