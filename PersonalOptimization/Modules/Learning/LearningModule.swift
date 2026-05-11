import Foundation

enum LearningModule: String, Sendable, CaseIterable {
    case japanese
    case guitar
    case music   // M4.2 followup: generic instrument / vocal practice — counts
                 // toward the learning streak when the user picked the `music`
                 // OptimizationFocus. Guitar stays separate for Clay's flow.

    var defaultDailyTargetMinutes: Int {
        switch self {
        case .japanese: return 30
        case .guitar:   return 20
        case .music:    return 20
        }
    }

    var displayName: String {
        switch self {
        case .japanese: return "Japanese"
        case .guitar:   return "Guitar"
        case .music:    return "Music"
        }
    }
}
