import Foundation
import SwiftData

enum BlockType: String, Codable {
    case transit, training, study, learning, admin, recovery, other
}

@Model
final class ScheduleBlock {
    var dayOfWeek: Int = 1
    var startTime: String = "00:00"
    var endTime: String = "00:00"
    var activity: String = ""
    var typeRaw: String = BlockType.other.rawValue
    var module: String?
    var isOverride: Bool = false
    var overrideDate: Date?

    var type: BlockType { BlockType(rawValue: typeRaw) ?? .other }

    init(dayOfWeek: Int, startTime: String, endTime: String, activity: String, type: BlockType, module: String? = nil) {
        self.dayOfWeek = dayOfWeek
        self.startTime = startTime
        self.endTime = endTime
        self.activity = activity
        self.typeRaw = type.rawValue
        self.module = module
    }
}
