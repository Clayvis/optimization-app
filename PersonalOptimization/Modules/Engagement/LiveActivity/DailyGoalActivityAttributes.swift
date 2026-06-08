import Foundation
import ActivityKit

/// Live Activity attributes for the daily protocol goal (build sheet section 1+2:
/// the goal IS the visual). The completion shape lives on the lock screen and
/// Dynamic Island so the user reads today's state without opening the app or
/// reading a number. `dayStart` identifies the day so the controller can replace
/// a stale prior-day activity.
public struct DailyGoalActivityAttributes: ActivityAttributes {
    public typealias ContentState = State

    public let dayStart: Date

    public struct State: Codable, Hashable, Sendable {
        public let completedDomains: Int
        public let totalDomains: Int
        public let streak: Int

        public init(completedDomains: Int, totalDomains: Int, streak: Int) {
            self.completedDomains = completedDomains
            self.totalDomains = totalDomains
            self.streak = streak
        }

        /// 0...1 completion fraction, guarded against a zero denominator.
        public var progress: Double {
            totalDomains > 0 ? Double(completedDomains) / Double(totalDomains) : 0
        }

        public var isComplete: Bool {
            totalDomains > 0 && completedDomains >= totalDomains
        }
    }

    public init(dayStart: Date) {
        self.dayStart = dayStart
    }
}
