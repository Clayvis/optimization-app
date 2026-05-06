import Foundation
import ActivityKit

public struct FastingActivityAttributes: ActivityAttributes {
    public typealias ContentState = State

    public let windowLabel: String  // "training" | "other" | "all"
    public let startDate: Date
    public let endDate: Date

    public struct State: Codable, Hashable, Sendable {
        public let isFasting: Bool

        public init(isFasting: Bool) {
            self.isFasting = isFasting
        }
    }

    public init(windowLabel: String, startDate: Date, endDate: Date) {
        self.windowLabel = windowLabel
        self.startDate = startDate
        self.endDate = endDate
    }
}
