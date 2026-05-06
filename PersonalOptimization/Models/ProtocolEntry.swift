import Foundation
import SwiftData

@Model
final class ProtocolEntry {
    var date: Date = Date.distantPast
    var category: String = "supplement"
    var title: String = ""
    var notes: String?
    var dose: String?
    var retestDate: Date?
    var completed: Bool = false
    var completedAt: Date?

    init(date: Date, category: String, title: String) {
        self.date = date
        self.category = category
        self.title = title
    }
}
