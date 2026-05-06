import Foundation
import ActivityKit

public struct WorkoutActivityAttributes: ActivityAttributes {
    public typealias ContentState = State

    public let workoutType: String   // "Lift A" | "Lift B" | "Basketball" | "Swim"
    public let startDate: Date

    public struct State: Codable, Hashable, Sendable {
        public let elapsedSeconds: Int
        public let primaryMetric: String   // "12 sets" | "1h 32m" | "20 laps · 500 m"

        public init(elapsedSeconds: Int, primaryMetric: String) {
            self.elapsedSeconds = elapsedSeconds
            self.primaryMetric = primaryMetric
        }
    }

    public init(workoutType: String, startDate: Date) {
        self.workoutType = workoutType
        self.startDate = startDate
    }
}
