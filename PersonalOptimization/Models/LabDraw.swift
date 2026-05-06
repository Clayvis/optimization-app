import Foundation
import SwiftData

@Model
final class LabDraw {
    var date: Date = Date.distantPast
    var notes: String?
    var values: [String: Double] = [:]
    var sourcePdfFilename: String?

    init(date: Date, values: [String: Double] = [:]) {
        self.date = date
        self.values = values
    }
}
