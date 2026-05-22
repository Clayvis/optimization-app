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
    private let zone: PartnerSharedZone
    private let logger = Logger(subsystem: BuildConfig.loggingSubsystem, category: "partner")

    /// Pairing codes expire 24h after generation per V1 opp 1 spec.
    static let pairingCodeTTL: TimeInterval = 24 * 60 * 60

    /// `zone` defaults to `NoopPartnerSharedZone` so single-user installs
    /// (the V1 reality without a paid Apple Developer account) compile and
    /// run unchanged. Tests pass `MemoryPartnerSharedZone`; the eventual
    /// `CloudKitPartnerSharedZone` wires in once the account lands.
    init(modelContext: ModelContext, zone: PartnerSharedZone = NoopPartnerSharedZone()) {
        self.modelContext = modelContext
        self.zone = zone
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

    /// Async variant of `unpair` that also tears down the shared zone.
    /// Called when the user disables partner mode from Settings. Logs and
    /// re-throws zone failures so the UI can surface a banner rather than
    /// silently leaving stale records in CloudKit.
    func unpairAsync(_ profile: UserProfile) async throws {
        try unpair(profile)
        do {
            try await zone.deleteAll()
        } catch {
            logger.warning("Zone deleteAll failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Writes the user's curated snapshot through the shared zone. No-op
    /// when running against the noop zone (single-user posture). The
    /// snapshot is the only payload that crosses the link — full session
    /// detail and Coach insights stay local.
    func publishSnapshot(_ record: PartnerSharedRecord) async throws {
        try await zone.write(record: record)
        logger.info("Published partner snapshot streak=\(record.currentStreak, privacy: .public) mascot=\(record.mascotState, privacy: .public)")
    }

    /// Reads the partner's latest snapshot, if any. Returns nil for
    /// single-user installs and unlinked accounts.
    func partnerSnapshot() async throws -> PartnerSharedRecord? {
        try await zone.fetchPartnerSnapshot()
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
