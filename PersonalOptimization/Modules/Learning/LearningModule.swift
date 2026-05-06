import Foundation

enum LearningModule: String, Sendable, CaseIterable {
    case japanese
    case guitar

    var defaultDailyTargetMinutes: Int {
        switch self {
        case .japanese: return 30
        case .guitar:   return 20
        }
    }

    var displayName: String {
        switch self {
        case .japanese: return "Japanese"
        case .guitar:   return "Guitar"
        }
    }
}
