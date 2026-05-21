import Foundation
import SwiftData

/// Diagnostic log of background task runs. Surfaced in Settings > Diagnostics
/// so silent BG failures stop being invisible. Each run writes one row when
/// it finishes (or fails) so the user can see "Background sync: 3 failures
/// in the last week" instead of finding out via stale Journey data.
@Model
final class BackgroundTaskLog {
    /// BGTaskScheduler identifier (e.g. com.rawlins.PersonalOptimization.archiveRollup).
    var taskId: String = ""
    var startedAt: Date = Date.distantPast
    var endedAt: Date?
    /// "success" | "failure" | "expired" | "running"
    var status: String = "running"
    var errorMessage: String?
    /// Optional summary the task can post (e.g. "wrote 7 archives").
    var summary: String?

    init(taskId: String,
         startedAt: Date = Date(),
         endedAt: Date? = nil,
         status: String = "running",
         errorMessage: String? = nil,
         summary: String? = nil) {
        self.taskId = taskId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.errorMessage = errorMessage
        self.summary = summary
    }
}
