import Foundation
import ActivityKit
import os

/// Live activity facade for in-progress workouts (lift/basketball/swim/
/// custom). Mirrors the FastingLiveActivityController pattern: a static
/// surface area for callers, backed by a closure-injectable class so
/// tests can stub ActivityKit (unavailable in xctest).
@MainActor
final class WorkoutLiveActivityController {

    typealias StartActivity = @MainActor (WorkoutActivityAttributes, WorkoutActivityAttributes.State, Date?) async throws -> String?
    typealias UpdateActivities = @MainActor (Int, String) async -> Void
    typealias EndAllActivities = @MainActor () async -> Void

    static let shared = WorkoutLiveActivityController()

    private let _start: StartActivity
    private let _update: UpdateActivities
    private let _endAll: EndAllActivities
    private var activeIDs: [String] = []

    init(
        start: @escaping StartActivity = WorkoutLiveActivityController.liveStart,
        update: @escaping UpdateActivities = WorkoutLiveActivityController.liveUpdate,
        endAll: @escaping EndAllActivities = WorkoutLiveActivityController.liveEndAll
    ) {
        self._start = start
        self._update = update
        self._endAll = endAll
    }

    // MARK: - Instance API (testable)

    @discardableResult
    func startInstance(workoutType: String, startDate: Date = Date()) async -> String? {
        let attributes = WorkoutActivityAttributes(workoutType: workoutType, startDate: startDate)
        let initial = WorkoutActivityAttributes.State(elapsedSeconds: 0, primaryMetric: "—")
        let stale = startDate.addingTimeInterval(6 * 3600)
        do {
            if let id = try await _start(attributes, initial, stale) {
                activeIDs.append(id)
                return id
            }
            return nil
        } catch {
            Logger.app.error("Workout live activity start failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func updateInstance(elapsedSeconds: Int, primaryMetric: String) async {
        await _update(elapsedSeconds, primaryMetric)
    }

    func endAllInstance() async {
        await _endAll()
        activeIDs.removeAll()
    }

    var trackedActivityCount: Int { activeIDs.count }

    // MARK: - Static facade

    @discardableResult
    static func start(workoutType: String, startDate: Date = Date()) async -> String? {
        await shared.startInstance(workoutType: workoutType, startDate: startDate)
    }

    static func update(elapsedSeconds: Int, primaryMetric: String) async {
        await shared.updateInstance(elapsedSeconds: elapsedSeconds, primaryMetric: primaryMetric)
    }

    static func endAll() async {
        await shared.endAllInstance()
    }

    /// Synchronous dismissal helper for service callers.
    static func dismissAllSync() {
        Task { @MainActor in await WorkoutLiveActivityController.endAll() }
    }

    // MARK: - Live implementations

    private static let liveStart: StartActivity = { attributes, state, stale in
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return nil }
        let content = ActivityContent(state: state, staleDate: stale)
        let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
        return activity.id
    }

    private static let liveUpdate: UpdateActivities = { elapsedSeconds, primaryMetric in
        for activity in Activity<WorkoutActivityAttributes>.activities {
            let next = WorkoutActivityAttributes.State(elapsedSeconds: elapsedSeconds, primaryMetric: primaryMetric)
            await activity.update(ActivityContent(state: next, staleDate: nil))
        }
    }

    private static let liveEndAll: EndAllActivities = {
        for activity in Activity<WorkoutActivityAttributes>.activities {
            let final = WorkoutActivityAttributes.State(elapsedSeconds: 0, primaryMetric: "—")
            await activity.end(ActivityContent(state: final, staleDate: nil), dismissalPolicy: .immediate)
        }
    }
}
