import Foundation
import ActivityKit
import os

/// Live activity facade for the fasting feature. The static methods are
/// the production callsites' surface; internally they delegate to
/// `FastingLiveActivityController.shared`, a closure-injectable class
/// that tests can replace via `init(start:endAll:)` to assert side
/// effects without touching ActivityKit (which is not available in
/// xctest).
@MainActor
final class FastingLiveActivityController {

    typealias StartActivity = @MainActor (FastingActivityAttributes, FastingActivityAttributes.State, Date?) async throws -> String?
    typealias EndAllActivities = @MainActor () async -> Void

    static let shared = FastingLiveActivityController()

    private let _start: StartActivity
    private let _endAll: EndAllActivities
    /// IDs of currently-running fasting activities tracked by this
    /// controller. Lets tests assert idempotent end-on-stop and lets the
    /// live path mirror ActivityKit's own activity registry.
    private var activeIDs: [String] = []

    init(
        start: @escaping StartActivity = FastingLiveActivityController.liveStart,
        endAll: @escaping EndAllActivities = FastingLiveActivityController.liveEndAll
    ) {
        self._start = start
        self._endAll = endAll
    }

    // MARK: - Instance API (testable)

    @discardableResult
    func startInstance(window: FastWindow) async -> String? {
        let attributes = FastingActivityAttributes(
            windowLabel: window.label,
            startDate: window.start,
            endDate: window.end
        )
        let initialState = FastingActivityAttributes.State(isFasting: true)
        let stale = window.end.addingTimeInterval(60)
        do {
            if let id = try await _start(attributes, initialState, stale) {
                activeIDs.append(id)
                return id
            }
            return nil
        } catch {
            Logger.app.error("Failed to start live activity: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func endAllInstance() async {
        await _endAll()
        activeIDs.removeAll()
    }

    var trackedActivityCount: Int { activeIDs.count }

    // MARK: - Static facade (preserves the existing call surface)

    @discardableResult
    static func start(window: FastWindow) async -> String? {
        await shared.startInstance(window: window)
    }

    static func endAll() async {
        await shared.endAllInstance()
    }

    /// Synchronous dismissal helper for service callers. Schedules an end call on
    /// the main actor and returns immediately so the caller's path is never blocked.
    static func dismissAllSync() {
        Task { @MainActor in await FastingLiveActivityController.endAll() }
    }

    // MARK: - Live implementations (default closures)

    private static let liveStart: StartActivity = { attributes, state, stale in
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Logger.app.info("Live activities disabled by system")
            return nil
        }
        let content = ActivityContent(state: state, staleDate: stale)
        let activity = try Activity.request(
            attributes: attributes,
            content: content,
            pushType: nil
        )
        Logger.app.info("Started fast live activity \(activity.id, privacy: .public)")
        return activity.id
    }

    private static let liveEndAll: EndAllActivities = {
        for activity in Activity<FastingActivityAttributes>.activities {
            let finalState = FastingActivityAttributes.State(isFasting: false)
            let content = ActivityContent(state: finalState, staleDate: nil)
            await activity.end(content, dismissalPolicy: .immediate)
        }
    }
}
