import Foundation
import ActivityKit
import os

@MainActor
enum WorkoutLiveActivityController {

    @discardableResult
    static func start(workoutType: String, startDate: Date = Date()) async -> Activity<WorkoutActivityAttributes>? {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return nil }
        let attributes = WorkoutActivityAttributes(workoutType: workoutType, startDate: startDate)
        let initial = WorkoutActivityAttributes.State(elapsedSeconds: 0, primaryMetric: "—")
        let content = ActivityContent(state: initial, staleDate: startDate.addingTimeInterval(6 * 3600))
        do {
            return try Activity.request(attributes: attributes, content: content, pushType: nil)
        } catch {
            Logger.app.error("Workout live activity start failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func update(elapsedSeconds: Int, primaryMetric: String) async {
        for activity in Activity<WorkoutActivityAttributes>.activities {
            let next = WorkoutActivityAttributes.State(elapsedSeconds: elapsedSeconds, primaryMetric: primaryMetric)
            await activity.update(ActivityContent(state: next, staleDate: nil))
        }
    }

    static func endAll() async {
        for activity in Activity<WorkoutActivityAttributes>.activities {
            let final = WorkoutActivityAttributes.State(elapsedSeconds: 0, primaryMetric: "—")
            await activity.end(ActivityContent(state: final, staleDate: nil), dismissalPolicy: .immediate)
        }
    }
}
