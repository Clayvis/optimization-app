import Foundation
import SwiftData

@Model
final class WearableEntry {
    var date: Date = Date.distantPast
    var source: String = "manual"
    var metrics: [String: Double] = [:]
    var notes: String?

    init(date: Date, source: String) {
        self.date = date
        self.source = source
    }
}
