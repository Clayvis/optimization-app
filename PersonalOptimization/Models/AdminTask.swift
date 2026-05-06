import Foundation
import SwiftData

@Model
final class AdminTask {
    var title: String = ""
    var category: String = "other"
    var dueDate: Date?
    var completed: Bool = false
    var completedAt: Date?
    var notes: String?
    var createdAt: Date = Date.distantPast

    init(title: String, category: String) {
        self.title = title
        self.category = category
        self.createdAt = Date()
    }
}
