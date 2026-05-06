import Foundation
import ActivityKit
import os

@MainActor
enum FastingLiveActivityController {

    /// Starts a Lock Screen + Dynamic Island live activity for the given fast window.
    /// No-op when the OS reports activities are disabled.
    @discardableResult
    static func start(window: FastWindow) async -> Activity<FastingActivityAttributes>? {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Logger.app.info("Live activities disabled by system")
            return nil
        }
        let attributes = FastingActivityAttributes(
            windowLabel: window.label,
            startDate: window.start,
            endDate: window.end
        )
        let initialState = FastingActivityAttributes.State(isFasting: true)
        let content = ActivityContent(state: initialState, staleDate: window.end.addingTimeInterval(60))
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            Logger.app.info("Started fast live activity \(activity.id, privacy: .public)")
            return activity
        } catch {
            Logger.app.error("Failed to start live activity: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Ends all running fast live activities immediately.
    static func endAll() async {
        for activity in Activity<FastingActivityAttributes>.activities {
            let finalState = FastingActivityAttributes.State(isFasting: false)
            let content = ActivityContent(state: finalState, staleDate: nil)
            await activity.end(content, dismissalPolicy: .immediate)
        }
    }
}
