import Foundation

/// Protocol seam for the CloudKit shared zone that will eventually move
/// the curated partner snapshot (current streak, master metric, mascot
/// state, last update) between two Apple IDs. The live implementation
/// (`CloudKitPartnerSharedZone`) lands when the paid Apple Developer
/// account is in place; until then `NoopPartnerSharedZone` keeps the
/// rest of the app compiling and `MemoryPartnerSharedZone` powers the
/// test suite.
///
/// Why bring the seam in now: PartnerService already exists and the
/// callers want to call "write a snapshot" / "fetch the partner's
/// snapshot" / "tear it all down" without knowing whether the CloudKit
/// container is real or a stub. Shipping the seam unblocks the test
/// suite and reduces the integration PR to a single file once the
/// account lands.
@MainActor
protocol PartnerSharedZone: Sendable {
    /// Writes the user's own snapshot so the partner can read it.
    func write(record: PartnerSharedRecord) async throws
    /// Removes all snapshots in the zone. Used at unpair time.
    func deleteAll() async throws
    /// Fetches the most recent snapshot written by the partner (not the
    /// caller). Returns nil if the partner hasn't published one yet or
    /// the link is broken.
    func fetchPartnerSnapshot() async throws -> PartnerSharedRecord?
    /// Sends a gentle nudge to the partner. Single tap, no feed: the
    /// cooperative-dyad version of Strava kudos at n=2.
    func sendNudge(_ nudge: PartnerNudge) async throws
    /// Fetches the most recent nudge the partner sent, if any.
    func fetchPendingNudge() async throws -> PartnerNudge?
}

/// A one-tap "thinking of you, close your day" prompt. At n=2 the sender is
/// implicit (the only partner), so no identity field is needed.
struct PartnerNudge: Codable, Sendable, Equatable {
    let message: String
    let sentAt: Date

    init(message: String, sentAt: Date = Date()) {
        self.message = message
        self.sentAt = sentAt
    }
}

/// Lightweight record passed through the zone. Codable so the live
/// implementation can serialize it through `CKRecord` fields without a
/// custom encoder.
struct PartnerSharedRecord: Codable, Sendable, Equatable {
    let userID: String
    let currentStreak: Int
    let masterMetric: Double
    let mascotState: String
    let lastUpdate: Date
    /// Weekly challenge payload (additive, optional so records written by
    /// older builds keep decoding). `challengeWeekStart` anchors the points
    /// to a week so a stale snapshot never scores against the current one.
    let challengeWeekStart: Date?
    let challengeWeekPoints: Int?

    init(userID: String,
         currentStreak: Int,
         masterMetric: Double,
         mascotState: String,
         lastUpdate: Date = Date(),
         challengeWeekStart: Date? = nil,
         challengeWeekPoints: Int? = nil) {
        self.userID = userID
        self.currentStreak = currentStreak
        self.masterMetric = masterMetric
        self.mascotState = mascotState
        self.lastUpdate = lastUpdate
        self.challengeWeekStart = challengeWeekStart
        self.challengeWeekPoints = challengeWeekPoints
    }
}

/// Default zone implementation used when no paid-developer CloudKit
/// container is wired. All operations succeed silently and the fetch
/// returns nil. Keeps `PartnerService` working in single-user mode
/// without conditional branches at the call site.
@MainActor
final class NoopPartnerSharedZone: PartnerSharedZone {
    func write(record: PartnerSharedRecord) async throws { /* no-op */ }
    func deleteAll() async throws { /* no-op */ }
    func fetchPartnerSnapshot() async throws -> PartnerSharedRecord? { nil }
    func sendNudge(_ nudge: PartnerNudge) async throws { /* no-op */ }
    func fetchPendingNudge() async throws -> PartnerNudge? { nil }
}

#if DEBUG
/// In-memory implementation for tests. Records call counts and
/// optionally fails the next write to exercise error paths.
@MainActor
final class MemoryPartnerSharedZone: PartnerSharedZone {
    /// Snapshots keyed by `record.userID`. Both the caller's own and
    /// any synthetic partner snapshot the test stuffs in are stored
    /// here; `fetchPartnerSnapshot` returns the latest by `lastUpdate`.
    private(set) var records: [String: PartnerSharedRecord] = [:]
    private(set) var writeCalls = 0
    private(set) var deleteAllCalls = 0
    private(set) var fetchCalls = 0
    private(set) var nudgeCalls = 0
    private(set) var sentNudges: [PartnerNudge] = []
    var pendingNudge: PartnerNudge?
    var failNextWrite: Error?
    var failNextDeleteAll: Error?
    var failNextFetch: Error?
    /// Used by `fetchPartnerSnapshot` to filter out the caller's own
    /// record so it returns the partner's view of the world. The test
    /// sets this before calling `fetchPartnerSnapshot`.
    var callerUserID: String?

    func write(record: PartnerSharedRecord) async throws {
        writeCalls += 1
        if let error = failNextWrite {
            failNextWrite = nil
            throw error
        }
        records[record.userID] = record
    }

    func deleteAll() async throws {
        deleteAllCalls += 1
        if let error = failNextDeleteAll {
            failNextDeleteAll = nil
            throw error
        }
        records.removeAll()
    }

    func fetchPartnerSnapshot() async throws -> PartnerSharedRecord? {
        fetchCalls += 1
        if let error = failNextFetch {
            failNextFetch = nil
            throw error
        }
        return records.values
            .filter { $0.userID != callerUserID }
            .max(by: { $0.lastUpdate < $1.lastUpdate })
    }

    func sendNudge(_ nudge: PartnerNudge) async throws {
        nudgeCalls += 1
        sentNudges.append(nudge)
    }

    func fetchPendingNudge() async throws -> PartnerNudge? {
        pendingNudge
    }

    /// Synchronous seeding for previews and tests that cannot await `write`.
    func preloadPartner(_ record: PartnerSharedRecord) {
        records[record.userID] = record
    }
}
#endif
