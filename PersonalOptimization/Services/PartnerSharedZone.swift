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

    init(userID: String,
         currentStreak: Int,
         masterMetric: Double,
         mascotState: String,
         lastUpdate: Date = Date()) {
        self.userID = userID
        self.currentStreak = currentStreak
        self.masterMetric = masterMetric
        self.mascotState = mascotState
        self.lastUpdate = lastUpdate
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
}
#endif
