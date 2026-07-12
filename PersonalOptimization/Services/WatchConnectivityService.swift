import Foundation
import Observation
import os
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Protocol seam over WCSession so the service-level decisions (drop when
/// unreachable, drop when not activated, log on error) can be tested without
/// a paired Watch + WCSession.activate roundtrip. Production code uses
/// LiveWCSessionTransport; tests use a FakeWCSessionTransport.
protocol WCSessionTransport: AnyObject, Sendable {
    var isActivated: Bool { get }
    var isReachable: Bool { get }
    func sendMessage(_ message: [String: Any],
                     replyHandler: (([String: Any]) -> Void)?,
                     errorHandler: ((Error) -> Void)?)
}

#if canImport(WatchConnectivity)
/// Production transport adapter. WCSession itself can't conform directly
/// because activationState exposes the WCSessionActivationState enum which
/// is platform-gated; the adapter normalizes the surface.
final class LiveWCSessionTransport: WCSessionTransport, @unchecked Sendable {
    static let shared = LiveWCSessionTransport()
    private init() {}

    var isActivated: Bool { WCSession.default.activationState == .activated }
    var isReachable: Bool { WCSession.default.isReachable }
    func sendMessage(_ message: [String: Any],
                     replyHandler: (([String: Any]) -> Void)?,
                     errorHandler: ((Error) -> Void)?) {
        WCSession.default.sendMessage(message, replyHandler: replyHandler, errorHandler: errorHandler)
    }
}
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

    private let logger = Logger.wc

    /// Replaced by tests via `setTransportForTesting` to inject a fake.
    /// Production reads `LiveWCSessionTransport.shared` lazily so unit tests
    /// can swap it before the first send().
    private var transportOverride: WCSessionTransport?
    private var transport: WCSessionTransport? {
        if let transportOverride { return transportOverride }
        #if canImport(WatchConnectivity)
        return LiveWCSessionTransport.shared
        #else
        return nil
        #endif
    }

    #if DEBUG
    func setTransportForTesting(_ transport: WCSessionTransport?) {
        self.transportOverride = transport
    }

    /// Push an event directly into the lastEventStream as if it had been
    /// received via WCSession. Lets tests verify the consumer chain
    /// without a live peer.
    func injectIncomingEventForTesting(_ event: WatchConnectivityEvent) {
        continuation?.yield(event)
    }
    #endif

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
        guard let transport else { return }
        guard transport.isActivated else { return }
        guard transport.isReachable else {
            logger.info("Peer unreachable; skipping event \(event.kind.rawValue, privacy: .public)")
            return
        }
        do {
            let payload = try JSONEncoder().encode(event)
            guard let dict = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return }
            transport.sendMessage(dict, replyHandler: nil) { [weak self] error in
                self?.logger.warning("sendMessage error: \(error.localizedDescription, privacy: .public)")
            }
        } catch {
            logger.warning("Encoding event failed: \(error.localizedDescription, privacy: .public)")
        }
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

/// Lightweight, privacy-safe presence signal for an in-progress workout.
/// Kept beside the connectivity bridge so the committed Xcode project always
/// compiles the type even when `project.yml` has not yet been regenerated.
@MainActor
@Observable
final class WorkoutPresenceService {
    static let shared = WorkoutPresenceService()

    private(set) var isActive = false
    private(set) var workoutType: String?
    private(set) var startedAt: Date?

    private let defaults: UserDefaults
    private let activeKey = "workoutPresence.active"
    private let typeKey = "workoutPresence.type"
    private let startKey = "workoutPresence.startedAt"
    private let staleAfter: TimeInterval = 6 * 60 * 60

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedStart = defaults.object(forKey: startKey) as? Date
        if defaults.bool(forKey: activeKey),
           let savedStart,
           Date().timeIntervalSince(savedStart) < staleAfter {
            isActive = true
            workoutType = defaults.string(forKey: typeKey)
            startedAt = savedStart
        } else {
            clear()
        }
    }

    func handle(_ event: WatchConnectivityEvent) {
        switch event.kind {
        case .workoutStarted:
            start(type: event.payload["template"] ?? event.payload["type"] ?? "workout")
        case .workoutEnded:
            end()
        default:
            break
        }
    }

    func start(type: String, at date: Date = Date()) {
        isActive = true
        workoutType = type
        startedAt = date
        defaults.set(true, forKey: activeKey)
        defaults.set(type, forKey: typeKey)
        defaults.set(date, forKey: startKey)
        NotificationCenter.default.post(name: .workoutPresenceChanged, object: nil)
    }

    func end() {
        clear()
        NotificationCenter.default.post(name: .workoutPresenceChanged, object: nil)
    }

    var coachSummary: String {
        guard isActive else { return "No live workout signal." }
        let type = workoutType ?? "workout"
        let elapsed = startedAt.map { max(0, Int(Date().timeIntervalSince($0) / 60)) } ?? 0
        return "Workout in progress: \(type), approximately \(elapsed) minutes elapsed. Do not prescribe a second workout; coach the current session, hydration, pacing, or recovery."
    }

    private func clear() {
        isActive = false
        workoutType = nil
        startedAt = nil
        defaults.removeObject(forKey: activeKey)
        defaults.removeObject(forKey: typeKey)
        defaults.removeObject(forKey: startKey)
    }
}
