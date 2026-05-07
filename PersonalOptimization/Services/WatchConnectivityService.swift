import Foundation
import os
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Phone↔watch real-time bridge. Two-way: phone pushes profile/state to the
/// watch on demand; watch pushes session events back as soon as they happen.
///
/// Battery posture: messages only when both apps are reachable. When the
/// peer isn't reachable, we don't queue retries — CloudKit handles eventual
/// consistency for the persisted SwiftData rows. This service exists for
/// *real-time* signaling (workout started, fast ended, water logged) so the
/// other device's UI updates within seconds rather than tens of seconds.
///
/// Message shape is JSON via `applicationContext` (delivered automatically
/// when peer becomes reachable) for state, and `sendMessage` for live events.
final class WatchConnectivityService: NSObject, @unchecked Sendable {
    static let shared = WatchConnectivityService()

    /// Most recently received event from the peer. UI can observe via
    /// `lastEventStream` (an AsyncStream) so SwiftUI views can react.
    private var continuation: AsyncStream<WatchConnectivityEvent>.Continuation?
    /// Public stream — views subscribe with `for await event in lastEventStream`.
    let lastEventStream: AsyncStream<WatchConnectivityEvent>

    private let logger = Logger(subsystem: "com.rawlins.PersonalOptimization", category: "wc")

    override init() {
        var localContinuation: AsyncStream<WatchConnectivityEvent>.Continuation!
        self.lastEventStream = AsyncStream { continuation in
            localContinuation = continuation
        }
        super.init()
        self.continuation = localContinuation
        activateIfPossible()
    }

    /// Activates the WCSession singleton if the platform supports it. Safe to
    /// call multiple times (subsequent calls no-op).
    func activateIfPossible() {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.activationState == .notActivated {
            session.delegate = self
            session.activate()
        }
        #endif
    }

    /// Send a live event to the peer. Drops silently if the peer isn't
    /// reachable; CloudKit will reconcile the underlying SwiftData rows when
    /// the peer comes back online.
    func send(_ event: WatchConnectivityEvent) {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        guard session.isReachable else {
            logger.info("Peer unreachable; skipping event \(event.kind.rawValue, privacy: .public)")
            return
        }
        do {
            let payload = try JSONEncoder().encode(event)
            guard let dict = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return }
            session.sendMessage(dict, replyHandler: nil) { [weak self] error in
                self?.logger.warning("sendMessage error: \(error.localizedDescription, privacy: .public)")
            }
        } catch {
            logger.warning("Encoding event failed: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }
}

#if canImport(WatchConnectivity)
extension WatchConnectivityService: WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        if let error {
            logger.warning("WCSession activation error: \(error.localizedDescription, privacy: .public)")
            return
        }
        logger.info("WCSession activated state=\(activationState.rawValue, privacy: .public)")
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        // iOS apps need to reactivate after a deactivate.
        WCSession.default.activate()
    }
    #endif

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        do {
            let data = try JSONSerialization.data(withJSONObject: message)
            let event = try JSONDecoder().decode(WatchConnectivityEvent.self, from: data)
            continuation?.yield(event)
            logger.info("Received event \(event.kind.rawValue, privacy: .public)")
        } catch {
            logger.warning("didReceiveMessage decode failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
#endif

/// Cross-device event payloads. Keep small and dumb — they're hints, not
/// state. The persisted SwiftData rows are still the truth via CloudKit.
struct WatchConnectivityEvent: Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case workoutStarted
        case workoutEnded
        case waterLogged
        case fastStarted
        case fastEnded
        case learningLogged
    }

    let kind: Kind
    /// Free-form context. Caller decides keys; receiver tolerates absence.
    let payload: [String: String]
    let timestamp: Date

    init(kind: Kind, payload: [String: String] = [:], timestamp: Date = Date()) {
        self.kind = kind
        self.payload = payload
        self.timestamp = timestamp
    }
}
